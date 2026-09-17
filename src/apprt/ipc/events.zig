//! Asynchronous event stream for the agent IPC surface (`events.subscribe`).
//!
//! Design constraints that shaped this file:
//!
//!   * Events must be copyable and allocation-free, because they are queued per
//!     subscriber and dropped-oldest on overflow. Every payload therefore uses
//!     fixed inline buffers (`TitleBuf`) rather than owned slices.
//!   * A slow subscriber must never block the terminal. `publish` never waits on
//!     a subscriber; overflow is recorded and reported to that subscriber as a
//!     synthetic `events_dropped` event so loss is visible, never silent.
//!   * Ordering is per broker: sequence numbers are assigned at publish time, so
//!     a client can detect gaps caused by drops.
//!
//! Thread safety: every entry point takes `std.Io.Mutex` and an `std.Io`.
//!
//!     zig test src/apprt/ipc/events.zig

const std = @import("std");
const Allocator = std.mem.Allocator;
const protocol = @import("protocol.zig");

const EventKind = protocol.EventKind;
const EventMask = protocol.EventMask;
const PaneId = protocol.PaneId;
const Obj = protocol.Obj;
const WriteError = protocol.WriteError;

/// Number of events a single subscriber may queue before drops begin.
pub const default_queue_capacity: usize = 256;

/// Maximum length of an inline title, in bytes.
pub const max_title_len: usize = 255;

/// Inline, copyable, truncation-safe title buffer.
///
/// Truncation never splits a UTF-8 codepoint: continuation bytes are backed off
/// so the stored bytes are always valid UTF-8 (JSON output must stay valid).
pub const TitleBuf = struct {
    buf: [max_title_len]u8 = @splat(0),
    len: usize = 0,

    pub fn from(src: []const u8) TitleBuf {
        var self: TitleBuf = .{};
        var n = @min(src.len, max_title_len);
        while (n > 0 and n < src.len and isUtf8Continuation(src[n])) : (n -= 1) {}
        @memcpy(self.buf[0..n], src[0..n]);
        self.len = n;
        return self;
    }

    pub fn slice(self: *const TitleBuf) []const u8 {
        return self.buf[0..self.len];
    }

    pub fn isEmpty(self: *const TitleBuf) bool {
        return self.len == 0;
    }

    fn isUtf8Continuation(byte: u8) bool {
        return byte >= 0x80 and byte <= 0xBF;
    }
};

/// Why a pane closed.
pub const CloseReason = enum {
    /// The child process exited.
    exit,
    /// The user or an agent closed it.
    requested,
    /// The window or tab it belonged to went away.
    container,

    pub fn name(self: CloseReason) []const u8 {
        return @tagName(self);
    }
};

/// One event. `seq` is assigned by the broker at publish time.
pub const Event = struct {
    kind: EventKind,
    pane_id: ?PaneId = null,
    seq: u64 = 0,
    payload: Payload = .{ .none = {} },

    pub const Payload = union(enum) {
        none: void,
        title_change: TitleChange,
        child_exit: ChildExit,
        resize: Resize,
        bell: Bell,
        focus_change: FocusChange,
        pane_created: PaneCreated,
        pane_closed: PaneClosed,
        events_dropped: Dropped,

        pub const TitleChange = struct { title: TitleBuf };
        pub const ChildExit = struct { exit_code: ?i32 = null, signal: ?u8 = null };
        pub const Resize = struct { cols: u16, rows: u16 };
        pub const Bell = struct { count: u64 = 1 };
        pub const FocusChange = struct { focused: bool };
        pub const PaneCreated = struct { title: TitleBuf = .{} };
        pub const PaneClosed = struct { reason: CloseReason = .exit };
        pub const Dropped = struct { dropped: u64 };
    };

    // ── Constructors ──

    pub fn titleChange(pane_id: PaneId, title: []const u8) Event {
        return .{
            .kind = .title_change,
            .pane_id = pane_id,
            .payload = .{ .title_change = .{ .title = .from(title) } },
        };
    }

    pub fn childExit(pane_id: PaneId, exit_code: ?i32, signal: ?u8) Event {
        return .{
            .kind = .child_exit,
            .pane_id = pane_id,
            .payload = .{ .child_exit = .{ .exit_code = exit_code, .signal = signal } },
        };
    }

    pub fn resize(pane_id: PaneId, cols: u16, rows: u16) Event {
        return .{
            .kind = .resize,
            .pane_id = pane_id,
            .payload = .{ .resize = .{ .cols = cols, .rows = rows } },
        };
    }

    pub fn bell(pane_id: PaneId) Event {
        return .{ .kind = .bell, .pane_id = pane_id, .payload = .{ .bell = .{} } };
    }

    pub fn focusChange(pane_id: PaneId, focused: bool) Event {
        return .{
            .kind = .focus_change,
            .pane_id = pane_id,
            .payload = .{ .focus_change = .{ .focused = focused } },
        };
    }

    pub fn paneCreated(pane_id: PaneId, title: []const u8) Event {
        return .{
            .kind = .pane_created,
            .pane_id = pane_id,
            .payload = .{ .pane_created = .{ .title = .from(title) } },
        };
    }

    pub fn paneClosed(pane_id: PaneId, reason: CloseReason) Event {
        return .{
            .kind = .pane_closed,
            .pane_id = pane_id,
            .payload = .{ .pane_closed = .{ .reason = reason } },
        };
    }

    /// Synthetic event reporting that the broker dropped events for this
    /// subscriber. `pane_id` is null because the loss spans panes.
    pub fn eventsDropped(dropped: u64) Event {
        return .{
            .kind = .events_dropped,
            .payload = .{ .events_dropped = .{ .dropped = dropped } },
        };
    }

    // ── Serialization ──

    /// Write the event envelope plus its `data` object.
    pub fn writeJson(self: Event, w: *std.Io.Writer) WriteError!void {
        var o = try Obj.init(w);
        try o.uint("v", protocol.version);
        try o.string("event", self.kind.name());
        try o.optPaneId("pane_id", self.pane_id);
        try o.uint("seq", self.seq);

        var data = try o.openIn("data", '{');
        switch (self.payload) {
            .none => {},
            .title_change => |v| try data.string("title", v.title.slice()),
            .pane_created => |v| if (v.title.isEmpty())
                try data.nullField("title")
            else
                try data.string("title", v.title.slice()),
            .child_exit => |v| {
                try data.optInt("exit_code", if (v.exit_code) |c| c else null);
                try data.optUint("signal", if (v.signal) |s| s else null);
            },
            .resize => |v| {
                try data.uint("cols", v.cols);
                try data.uint("rows", v.rows);
            },
            .bell => |v| try data.uint("count", v.count),
            .focus_change => |v| try data.boolean("focused", v.focused),
            .pane_closed => |v| try data.string("reason", v.reason.name()),
            .events_dropped => |v| try data.uint("dropped", v.dropped),
        }
        try data.close('}');
        try o.close('}');
    }

    /// Render to an owned, newline-free string. Caller frees.
    pub fn toJsonAlloc(self: Event, alloc: Allocator) protocol.EncodeError![]u8 {
        var buf: std.Io.Writer.Allocating = .init(alloc);
        errdefer buf.deinit();
        try self.writeJson(&buf.writer);
        return buf.toOwnedSlice();
    }
};

/// One subscriber's queue. Capacity is fixed at subscribe time.
pub const Subscriber = struct {
    id: u64,
    mask: EventMask,
    ring: []Event,
    head: usize = 0,
    len: usize = 0,
    /// Events dropped since the last drain, reported on the next drain.
    dropped: u64 = 0,

    fn depth(self: *const Subscriber) usize {
        return self.len;
    }

    /// Push, dropping the oldest event if the queue is full.
    fn push(self: *Subscriber, event: Event) void {
        if (self.len == self.ring.len) {
            self.head = (self.head + 1) % self.ring.len;
            self.len -= 1;
            self.dropped += 1;
        }
        const tail = (self.head + self.len) % self.ring.len;
        self.ring[tail] = event;
        self.len += 1;
    }

    fn pop(self: *Subscriber) ?Event {
        if (self.len == 0) return null;
        const event = self.ring[self.head];
        self.head = (self.head + 1) % self.ring.len;
        self.len -= 1;
        return event;
    }
};

/// Result of a drain.
pub const Drain = struct {
    /// Events written into the caller's buffer.
    events: usize = 0,
    /// Events dropped since the previous drain that must be reported to the
    /// subscriber as a synthetic `events_dropped` event.
    dropped: u64 = 0,

    pub fn isEmpty(self: Drain) bool {
        return self.events == 0 and self.dropped == 0;
    }
};

/// Fans events out to subscribers. One broker per server.
pub const Broker = struct {
    gpa: Allocator,
    mutex: std.Io.Mutex = .init,
    subscribers: std.ArrayListUnmanaged(Subscriber) = .empty,
    next_id: u64 = 1,
    next_seq: u64 = 1,
    /// Queue capacity used by `subscribe`.
    capacity: usize = default_queue_capacity,

    pub const Error = Allocator.Error || std.Io.Cancelable;

    pub fn init(gpa: Allocator) Broker {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *Broker, io: std.Io) void {
        self.mutex.lockUncancelable(io);
        for (self.subscribers.items) |s| self.gpa.free(s.ring);
        self.subscribers.deinit(self.gpa);
        self.mutex.unlock(io);
    }

    /// Register a subscriber. An empty mask means "all subscribable kinds".
    pub fn subscribe(self: *Broker, io: std.Io, mask: EventMask) Error!u64 {
        try self.mutex.lock(io);
        defer self.mutex.unlock(io);

        const ring = try self.gpa.alloc(Event, self.capacity);
        errdefer self.gpa.free(ring);
        @memset(ring, .{ .kind = .bell });

        const id = self.next_id;
        self.next_id += 1;
        try self.subscribers.append(self.gpa, .{
            .id = id,
            .mask = if (mask.count() == 0) EventKind.maskSubscribable() else mask,
            .ring = ring,
        });
        return id;
    }

    /// Remove a subscriber. Returns false if `id` is unknown.
    pub fn unsubscribe(self: *Broker, io: std.Io, id: u64) bool {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);

        for (self.subscribers.items, 0..) |s, i| {
            if (s.id != id) continue;
            self.gpa.free(s.ring);
            _ = self.subscribers.swapRemove(i);
            return true;
        }
        return false;
    }

    /// Fan an event out. The broker owns sequence assignment; the `seq` field
    /// of `event` is ignored. Returns the assigned sequence (0 when nothing was
    /// published because nobody is subscribed).
    pub fn publish(self: *Broker, io: std.Io, event: Event) u64 {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);

        if (self.subscribers.items.len == 0) return 0;

        const seq = self.next_seq;
        self.next_seq += 1;

        for (self.subscribers.items) |*s| {
            if (!s.mask.contains(event.kind)) continue;
            var queued = event;
            queued.seq = seq;
            s.push(queued);
        }
        return seq;
    }

    /// Copy up to `out.len` queued events for `id` into `out`, oldest first.
    /// Returns null when `id` is not subscribed.
    pub fn drain(self: *Broker, io: std.Io, id: u64, out: []Event) ?Drain {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);

        const s = self.find(id) orelse return null;
        var result: Drain = .{ .dropped = s.dropped };
        s.dropped = 0;
        while (result.events < out.len) {
            out[result.events] = s.pop() orelse break;
            result.events += 1;
        }
        return result;
    }

    /// Consume and return the drop counter for `id` without touching its
    /// queue. Callers that must report loss *before* the surviving events (the
    /// connection loop) use this instead of reading `Drain.dropped`.
    pub fn takeDropped(self: *Broker, io: std.Io, id: u64) ?u64 {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const s = self.find(id) orelse return null;
        const dropped = s.dropped;
        s.dropped = 0;
        return dropped;
    }

    /// Number of queued events for `id`, or null when not subscribed.
    pub fn depth(self: *Broker, io: std.Io, id: u64) ?usize {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const s = self.find(id) orelse return null;
        return s.depth();
    }

    /// Number of active subscribers.
    pub fn subscriberCount(self: *Broker, io: std.Io) usize {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        return self.subscribers.items.len;
    }

    /// The mask registered for `id`, or null when not subscribed.
    pub fn maskOf(self: *Broker, io: std.Io, id: u64) ?EventMask {
        self.mutex.lockUncancelable(io);
        defer self.mutex.unlock(io);
        const s = self.find(id) orelse return null;
        return s.mask;
    }

    /// Caller must hold the mutex.
    fn find(self: *Broker, id: u64) ?*Subscriber {
        for (self.subscribers.items) |*s| {
            if (s.id == id) return s;
        }
        return null;
    }
};

// ─────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────

const testing = std.testing;

fn testIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

test "title buffer: truncates without splitting utf-8" {
    const long_ascii = "a" ** (max_title_len + 10);
    const t1 = TitleBuf.from(long_ascii);
    try testing.expectEqual(max_title_len, t1.len);

    // "é" is two bytes; a buffer that would end mid-codepoint backs off.
    var src: [max_title_len + 1]u8 = @splat('x');
    src[max_title_len - 1] = 0xC3;
    src[max_title_len] = 0xA9;
    const t2 = TitleBuf.from(&src);
    try testing.expectEqual(max_title_len - 1, t2.len);
    try testing.expect(std.unicode.utf8ValidateSlice(t2.slice()));
}

test "broker: publish assigns increasing sequence numbers" {
    var broker = Broker.init(testing.allocator);
    defer broker.deinit(testIo());
    const io = testIo();

    const id = try broker.subscribe(io, EventKind.maskSubscribable());
    try testing.expectEqual(@as(u64, 1), broker.publish(io, Event.titleChange(PaneId.init(1), "a")));
    try testing.expectEqual(@as(u64, 2), broker.publish(io, Event.bell(PaneId.init(1))));

    var out: [4]Event = undefined;
    const drained = broker.drain(io, id, &out).?;
    try testing.expectEqual(@as(usize, 2), drained.events);
    try testing.expectEqual(@as(u64, 1), out[0].seq);
    try testing.expectEqual(@as(u64, 2), out[1].seq);
    try testing.expectEqual(EventKind.title_change, out[0].kind);
    try testing.expectEqualStrings("a", out[0].payload.title_change.title.slice());
}

test "broker: no subscribers means nothing is published" {
    var broker = Broker.init(testing.allocator);
    defer broker.deinit(testIo());
    const io = testIo();
    try testing.expectEqual(@as(u64, 0), broker.publish(io, Event.bell(PaneId.init(1))));
}

test "broker: mask filters kinds" {
    var broker = Broker.init(testing.allocator);
    defer broker.deinit(testIo());
    const io = testIo();

    var mask: EventMask = .initEmpty();
    mask.insert(.bell);
    const id = try broker.subscribe(io, mask);

    _ = broker.publish(io, Event.titleChange(PaneId.init(1), "ignored"));
    _ = broker.publish(io, Event.bell(PaneId.init(1)));

    var out: [4]Event = undefined;
    const drained = broker.drain(io, id, &out).?;
    try testing.expectEqual(@as(usize, 1), drained.events);
    try testing.expectEqual(EventKind.bell, out[0].kind);
}

test "broker: empty mask subscribes to every subscribable kind" {
    var broker = Broker.init(testing.allocator);
    defer broker.deinit(testIo());
    const io = testIo();

    const id = try broker.subscribe(io, .initEmpty());
    const mask = broker.maskOf(io, id).?;
    for (EventKind.subscribable) |k| try testing.expect(mask.contains(k));
    try testing.expect(!mask.contains(.events_dropped));
}

test "broker: overflow drops oldest and reports the count" {
    var broker = Broker.init(testing.allocator);
    defer broker.deinit(testIo());
    broker.capacity = 4;
    const io = testIo();

    const id = try broker.subscribe(io, EventKind.maskSubscribable());
    for (0..6) |i| {
        _ = broker.publish(io, Event.titleChange(PaneId.init(1), "title"));
        _ = i;
    }

    try testing.expectEqual(@as(?usize, 4), broker.depth(io, id));

    var out: [8]Event = undefined;
    const drained = broker.drain(io, id, &out).?;
    try testing.expectEqual(@as(usize, 4), drained.events);
    try testing.expectEqual(@as(u64, 2), drained.dropped);
    // The surviving events are the newest ones: seq 3..6.
    try testing.expectEqual(@as(u64, 3), out[0].seq);
    try testing.expectEqual(@as(u64, 6), out[3].seq);

    // The drop counter is consumed exactly once.
    const second = broker.drain(io, id, &out).?;
    try testing.expectEqual(@as(u64, 0), second.dropped);
    try testing.expectEqual(@as(usize, 0), second.events);
}

test "broker: drain respects the caller's buffer size" {
    var broker = Broker.init(testing.allocator);
    defer broker.deinit(testIo());
    const io = testIo();

    const id = try broker.subscribe(io, EventKind.maskSubscribable());
    for (0..3) |_| _ = broker.publish(io, Event.bell(PaneId.init(2)));

    var first: [1]Event = undefined;
    try testing.expectEqual(@as(usize, 1), broker.drain(io, id, &first).?.events);
    try testing.expectEqual(@as(?usize, 2), broker.depth(io, id));
    try testing.expectEqual(@as(usize, 1), first[0].seq);
}

test "broker: unsubscribe frees the queue and stops delivery" {
    var broker = Broker.init(testing.allocator);
    defer broker.deinit(testIo());
    const io = testIo();

    const id = try broker.subscribe(io, EventKind.maskSubscribable());
    try testing.expectEqual(@as(usize, 1), broker.subscriberCount(io));
    try testing.expect(broker.unsubscribe(io, id));
    try testing.expect(!broker.unsubscribe(io, id));
    try testing.expectEqual(@as(usize, 0), broker.subscriberCount(io));
    try testing.expectEqual(@as(?Drain, null), broker.drain(io, id, undefined));
    try testing.expectEqual(@as(?EventMask, null), broker.maskOf(io, id));
}

test "broker: multiple subscribers receive independent copies" {
    var broker = Broker.init(testing.allocator);
    defer broker.deinit(testIo());
    const io = testIo();

    const a = try broker.subscribe(io, EventKind.maskAll());
    const b = try broker.subscribe(io, EventKind.maskSubscribable());

    _ = broker.publish(io, Event.resize(PaneId.init(5), 120, 40));

    var out: [2]Event = undefined;
    const da = broker.drain(io, a, &out).?;
    try testing.expectEqual(@as(usize, 1), da.events);
    const db = broker.drain(io, b, &out).?;
    try testing.expectEqual(@as(usize, 1), db.events);
    try testing.expectEqual(@as(u16, 120), out[0].payload.resize.cols);
}

test "event json: envelope and payload" {
    var event = Event.titleChange(PaneId.init(3), "~/projects/khostty");
    event.seq = 12;

    const json = try event.toJsonAlloc(testing.allocator);
    defer testing.allocator.free(json);
    try testing.expectEqualStrings(
        "{\"v\":1,\"event\":\"title_change\",\"pane_id\":\"p-3\",\"seq\":12," ++
            "\"data\":{\"title\":\"~/projects/khostty\"}}",
        json,
    );
}

test "event json: every kind renders valid json" {
    const events = [_]Event{
        Event.titleChange(PaneId.init(1), "t"),
        Event.childExit(PaneId.init(1), 0, null),
        Event.childExit(PaneId.init(1), null, 9),
        Event.resize(PaneId.init(1), 80, 24),
        Event.bell(PaneId.init(1)),
        Event.focusChange(PaneId.init(1), true),
        Event.paneCreated(PaneId.init(1), "zsh"),
        Event.paneCreated(PaneId.init(1), ""),
        Event.paneClosed(PaneId.init(1), .requested),
        Event.eventsDropped(7),
    };

    for (events) |event| {
        const json = try event.toJsonAlloc(testing.allocator);
        defer testing.allocator.free(json);

        const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, json, .{});
        defer parsed.deinit();
        const obj = parsed.value.object;
        try testing.expectEqualStrings(event.kind.name(), obj.get("event").?.string);
        try testing.expect(obj.get("data").? == .object);
    }
}

test "event json: events_dropped has a null pane id" {
    var event = Event.eventsDropped(7);
    event.seq = 99;
    const json = try event.toJsonAlloc(testing.allocator);
    defer testing.allocator.free(json);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, json, .{});
    defer parsed.deinit();
    try testing.expectEqual(std.json.Value.null, parsed.value.object.get("pane_id").?);
    try testing.expectEqual(@as(i64, 7), parsed.value.object.get("data").?.object.get("dropped").?.integer);
}

test "close reason names" {
    inline for (@typeInfo(CloseReason).@"enum".fields) |f| {
        const reason: CloseReason = @enumFromInt(f.value);
        try testing.expectEqualStrings(f.name, reason.name());
    }
}
