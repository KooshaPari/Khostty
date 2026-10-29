//! `pane.Host` implementation backed by the running application.
//!
//! This is the only file in `src/apprt/ipc/` that knows about the app runtime,
//! and it is deliberately thin: every operation maps onto an existing core or
//! apprt API, and anything the runtime cannot do returns `error.Unsupported`
//! with the reason recorded in `protocol.md`, rather than a plausible
//! substitute that would silently do the wrong thing.
//!
//! What the runtime can and cannot do (verified against the tree, not assumed):
//!
//! | command        | implementation                                        |
//! |----------------|-------------------------------------------------------|
//! | `pane.create`  | `apprt.Action.new_split` + surface diff (below)        |
//! | `pane.close`   | `CoreSurface.close()` (the app's own close path)       |
//! | `pane.focus`   | **unsupported**: no API focuses a surface by id        |
//! | `pane.list`    | `App.surfaces`                                         |
//! | `pane.write`   | `termio.Termio.terminal_stream.nextSlice`              |
//! | `pane.state`   | `termio.Termio.terminal` + `rt_surface`                |
//! | `pane.search`  | **unsupported**: upstream search is async and UI-driven |
//! | `pane.resize_split` / `equalize` / `zoom` | the matching actions    |
//!
//! `new_split` is fire-and-forget: the action is queued and returns no handle,
//! so `pane.create` snapshots the runtime's surfaces, performs the action, and
//! then diffs (bounded wait) to find the new pane. If no new surface appears it
//! returns `error.Internal`: an invented pane id would be worse than an error.
//!
//! Availability
//! ------------
//! `windowed` is false for every build configuration without addressable panes
//! (`.none`, the `windows` scaffold, and the lib/wasm artifacts). In those
//! builds every method returns `error.Unsupported` and no runtime API is
//! referenced at all, so the tree still compiles for them.
//!
//! Threading
//! ---------
//! The terminal is owned by the app's IO thread while the IPC server runs
//! per-connection threads. `AppHost` holds a mutex, but that only serializes
//! *IPC* callers; it does not make concurrent access from the app thread safe.
//! The remaining integration step is the same mailbox hop the rest of the app
//! uses, and it lives outside this file:
//!
//!   * `pane.write` should queue through the surface mailbox
//!     (`CoreSurface.queueIo`) instead of touching the parser directly;
//!   * the event hooks below belong next to the runtime's existing callbacks:
//!     the OSC 0/2 title path for `publishTitleChange`, the child-exit message
//!     for `publishChildExit`, the resize callback for `publishResize`, and the
//!     bell path for `publishBell`.
//!
//! Until that hop is wired, `AppHost` must be called from the app thread. That
//! requirement is stated in `protocol.md` section 7 rather than hidden.

const std = @import("std");
const Allocator = std.mem.Allocator;

const build_config = @import("../../build_config.zig");
const apprt = @import("../../apprt.zig");
const App = @import("../../App.zig");
const CoreSurface = @import("../../Surface.zig");
const terminalpkg = @import("../../terminal/main.zig");

const pane = @import("pane.zig");
const protocol = @import("protocol.zig");
const state = @import("state.zig");
const events = @import("events.zig");
const ipc_task = @import("task.zig");

const PaneId = protocol.PaneId;

/// Whether this build has a windowed runtime with addressable panes. Only the
/// GTK runtime qualifies today: the Windows runtime is a scaffold (WBS G3) and
/// the lib/wasm artifacts have no windows at all.
pub const windowed: bool = switch (build_config.artifact) {
    .exe => switch (build_config.app_runtime) {
        .gtk => true,
        .none, .windows => false,
    },
    .lib, .wasm_module => false,
};

/// Human-readable reason every command is unavailable, for logs and docs.
pub fn unavailableReason() []const u8 {
    return switch (build_config.artifact) {
        .lib => "this artifact is a library: there are no surfaces to address",
        .wasm_module => "the wasm artifact has no windowed surfaces",
        .exe => switch (build_config.app_runtime) {
            .none => "the `none` runtime has no windows",
            .windows => "the Windows runtime is a scaffold: it has no panes yet",
            .gtk => "",
        },
    };
}

pub const AppHost = struct {
    gpa: Allocator,
    /// IO used for the host mutex and the bounded split wait. Supplied by the
    /// server so the host never invents a second event loop.
    io: std.Io,
    app: *App,
    mutex: std.Io.Mutex = .init,
    /// How long to wait for a single app-thread round trip.
    call_timeout_ms: u64 = 2000,
    /// How long to wait for the queued `new_split` to produce a surface.
    split_wait_ms: u64 = 500,
    /// Poll interval while waiting for that surface.
    split_poll_interval_ms: u64 = 2,
    /// Optional event sink; when set, the publish hooks deliver to subscribers.
    broker: ?*events.Broker = null,

    pub fn init(gpa: Allocator, io: std.Io, app: *App) AppHost {
        return .{ .gpa = gpa, .io = io, .app = app };
    }

    /// The host handle. Which vtable is returned is decided at comptime: a
    /// build without addressable panes gets the all-`Unsupported` one, whose
    /// bodies touch no runtime API.
    pub fn host(self: *AppHost) pane.Host {
        if (comptime windowed) {
            return .{ .ctx = self, .vtable = &windowed_vtable };
        }
        return .{ .ctx = self, .vtable = &unavailable_vtable };
    }

    pub fn setEventBroker(self: *AppHost, broker: ?*events.Broker) void {
        self.broker = broker;
    }

    // ── Event publication hooks ──
    //
    // Pushes, not commands: the runtime calls these from the places where it
    // already reacts to a title change, a child exit, a resize, or a bell.

    /// Publish a title change for a surface the runtime just retitled.
    pub fn publishTitleChange(self: *AppHost, core: *CoreSurface) void {
        const broker = self.broker orelse return;
        const title = titleOf(core) orelse "";
        _ = broker.publish(self.io, events.Event.titleChange(PaneId.init(core.id), title));
    }

    /// Publish a child exit for a surface whose child process ended.
    pub fn publishChildExit(
        self: *AppHost,
        core: *CoreSurface,
        exit_code: ?i32,
        signal: ?u8,
    ) void {
        const broker = self.broker orelse return;
        _ = broker.publish(
            self.io,
            events.Event.childExit(PaneId.init(core.id), exit_code, signal),
        );
    }

    /// Publish a resize for a surface whose grid changed.
    pub fn publishResize(self: *AppHost, core: *CoreSurface, cols: u16, rows: u16) void {
        const broker = self.broker orelse return;
        _ = broker.publish(self.io, events.Event.resize(PaneId.init(core.id), cols, rows));
    }

    /// Publish a bell for a surface that rang one.
    pub fn publishBell(self: *AppHost, core: *CoreSurface) void {
        const broker = self.broker orelse return;
        _ = broker.publish(self.io, events.Event.bell(PaneId.init(core.id)));
    }

    // ── VTable ──

    fn ctxHost(ctx: *anyopaque) *AppHost {
        return @ptrCast(@alignCast(ctx));
    }

    /// The vtable used by a windowed build. Its bodies are only analyzed when
    /// `windowed` is true (they are reachable only through the comptime branch
    /// in `host`), so a non-windowed build never even type-checks the runtime
    /// API calls below.
    const windowed_vtable: pane.Host.VTable = .{
        .create = createWithDiff,
        .close = closeCore,
        .focus = focusUnsupported,
        .list = listSurfaces,
        .write = writeToParser,
        .snapshot = snapshotCore,
        .search = searchUnsupported,
        .resize = resizeSplit,
        .equalize = equalizeSplits,
        .zoom = toggleZoom,
    };

    /// The vtable used by every build without addressable panes. `list` is null
    /// so the manager falls back to its own registry of panes it has seen.
    const unavailable_vtable: pane.Host.VTable = .{
        .create = unsupportedCreate,
        .close = unsupportedClose,
        .focus = focusUnsupported,
        .list = null,
        .write = unsupportedWrite,
        .snapshot = unsupportedSnapshot,
        .search = searchUnsupported,
        .resize = unsupportedResize,
        .equalize = unsupportedEqualize,
        .zoom = unsupportedZoom,
    };

    fn unsupportedCreate(_: *anyopaque, _: Allocator, _: pane.CreateRequest) pane.HostError!pane.PaneHandle {
        return error.Unsupported;
    }

    fn unsupportedClose(_: *anyopaque, _: PaneId) pane.HostError!void {
        return error.Unsupported;
    }

    fn focusUnsupported(_: *anyopaque, _: PaneId) pane.HostError!void {
        // Nothing in the core or the apprt focuses a surface by id: focus is a
        // window/tab operation the runtime owns (protocol.md 4.1). Faking it
        // with a relative `goto_split` would move focus to a different pane
        // than the caller asked for, so this reports the truth.
        return error.Unsupported;
    }

    fn searchUnsupported(
        _: *anyopaque,
        _: Allocator,
        _: PaneId,
        _: []const u8,
        _: usize,
        _: *std.ArrayListUnmanaged(pane.SearchMatch),
    ) pane.HostError!void {
        // Upstream search is asynchronous and UI-facing: it starts through the
        // `start_search` action and reports results back as apprt actions
        // (`search_total`, `search_selected`) so a human watches the highlight
        // move. There is no synchronous "scan and return matches" core API, so
        // implementing this over IPC requires adding one. Saying so is the
        // honest answer: a second search implementation inside the agent
        // surface would fork behavior away from the UI.
        return error.Unsupported;
    }

    fn unsupportedWrite(_: *anyopaque, _: PaneId, _: []const u8) pane.HostError!usize {
        return error.Unsupported;
    }

    fn unsupportedSnapshot(
        _: *anyopaque,
        _: Allocator,
        _: PaneId,
        _: *state.Snapshot,
    ) pane.HostError!void {
        return error.Unsupported;
    }

    fn unsupportedResize(
        _: *anyopaque,
        _: PaneId,
        _: protocol.Direction,
        _: u16,
    ) pane.HostError!void {
        return error.Unsupported;
    }

    fn unsupportedEqualize(_: *anyopaque) pane.HostError!void {
        return error.Unsupported;
    }

    fn unsupportedZoom(_: *anyopaque, _: PaneId) pane.HostError!void {
        return error.Unsupported;
    }

    // ── Windowed implementations ──

    fn createWithDiff(
        ctx: *anyopaque,
        arena: Allocator,
        req: pane.CreateRequest,
    ) pane.HostError!pane.PaneHandle {
        // Everything that touches app state runs on the app thread; everything
        // that only touches the caller's own memory runs here.
        //
        // The split itself is one app-thread task. Identifying the new pane
        // needs a SECOND app-thread task per poll, because the surface list is
        // app state. That is why this is not a single thunk: the split happens
        // on one tick and the surface appears on a later one.
        //
        // KooshaPari/Khostty#73, #76.
        const self = ctxHost(ctx);
        const direction: apprt.action.SplitDirection = switch (req.dir) {
            .up => .up,
            .down => .down,
            .left => .left,
            .right => .right,
        };

        // 1. Initiate the split on the app thread.
        const SplitPayload = struct {
            host: *AppHost,
            parent_id: ?u64,
            direction: apprt.action.SplitDirection,
            title: ?[:0]const u8,
            err: ?pane.HostError = null,

            fn run(raw: *anyopaque) void {
                const p: *@This() = @ptrCast(@alignCast(raw));
                p.host.splitInner(p.parent_id, p.direction, p.title) catch |e| {
                    p.err = e;
                };
            }
        };

        var split_payload: SplitPayload = .{
            .host = self,
            .parent_id = if (req.parent) |id| id.raw else null,
            .direction = direction,
            // Sentinel-terminated because SetTitle requires it. The arena is
            // the caller's, and it outlives this call because the app thread
            // finishes with the payload before we return.
            .title = if (req.title) |v| try arena.dupeZ(u8, v) else null,
        };
        {
            const task = try ipc_task.Task.create(
                std.heap.c_allocator,
                &split_payload,
                SplitPayload.run,
            );
            _ = try self.app.runOnAppThread(task, self.call_timeout_ms);
        }
        if (split_payload.err) |e| return e;

        // 2. Poll the app thread for the surface that was not there before.
        //
        // GTK updates the split tree synchronously but creates the surface on
        // a later loop iteration, so the new pane is not available immediately.
        const IdsPayload = struct {
            host: *AppHost,
            before: []const u64,
            found: ?u64 = null,

            fn run(raw: *anyopaque) void {
                const p: *@This() = @ptrCast(@alignCast(raw));
                p.found = p.host.findNewSurfaceInner(p.before);
            }
        };

        // Snapshot the current ids on the app thread, so the diff is against a
        // consistent set rather than one taken mid-mutation.
        var before: [64]u64 = undefined;
        var before_len: usize = 0;
        {
            const BeforePayload = struct {
                host: *AppHost,
                buf: *[64]u64,
                len: *usize,

                fn run(raw: *anyopaque) void {
                    const p: *@This() = @ptrCast(@alignCast(raw));
                    p.host.snapshotSurfaceIdsInner(p.buf, p.len);
                }
            };
            var bp: BeforePayload = .{
                .host = self,
                .buf = &before,
                .len = &before_len,
            };
            const task = try ipc_task.Task.create(
                std.heap.c_allocator,
                &bp,
                BeforePayload.run,
            );
            _ = try self.app.runOnAppThread(task, self.call_timeout_ms);
        }

        var created: ?u64 = null;
        {
            const deadline = std.Io.Timestamp.now(self.io, .awake);
            while (created == null) {
                if (deadline.durationTo(
                    std.Io.Timestamp.now(self.io, .awake),
                ).toMilliseconds() > self.split_wait_ms) break;

                var ip: IdsPayload = .{ .host = self, .before = before[0..before_len] };
                const task = try ipc_task.Task.create(
                    std.heap.c_allocator,
                    &ip,
                    IdsPayload.run,
                );
                _ = try self.app.runOnAppThread(task, self.call_timeout_ms);
                created = ip.found;

                if (created == null) {
                    std.Io.sleep(
                        self.io,
                        std.Io.Duration.fromMilliseconds(@intCast(self.split_poll_interval_ms)),
                        .awake,
                    ) catch break;
                }
            }
        }
        const id = created orelse return error.Internal;

        // 3. Read the new pane's info on the app thread.
        const InfoPayload = struct {
            host: *AppHost,
            id: u64,
            result: ?SplitRequestResult = null,

            fn run(raw: *anyopaque) void {
                const p: *@This() = @ptrCast(@alignCast(raw));
                p.result = p.host.surfaceInfoInner(p.id);
            }
        };
        var info_payload: InfoPayload = .{ .host = self, .id = id };
        {
            const task = try ipc_task.Task.create(
                std.heap.c_allocator,
                &info_payload,
                InfoPayload.run,
            );
            _ = try self.app.runOnAppThread(task, self.call_timeout_ms);
        }
        const info = info_payload.result orelse return error.Internal;

        // The title was applied by the app thread as part of the split.
        // Copy it into the caller's arena so the handle cannot dangle.
        const title: ?[]const u8 = if (info.title_len > 0)
            try arena.dupe(u8, info.title_buf[0..info.title_len])
        else
            null;

        return .{
            .id = PaneId.init(info.id),
            .pid = info.pid,
            .title = title,
            .cols = info.cols,
            .rows = info.rows,
            .focused = info.focused,
        };
    }

    fn closeCore(ctx: *anyopaque, id: PaneId) pane.HostError!void {
        const Payload = struct {
            host: *AppHost,
            id: PaneId,
            err: ?pane.HostError = null,

            fn run(raw: *anyopaque) void {
                const self: *@This() = @ptrCast(@alignCast(raw));
                // Resolution and the close both touch app state, so both run
                // on the app thread.
                const core = self.host.findCoreInner(self.id) orelse {
                    self.err = error.PaneNotFound;
                    return;
                };
                core.close();
            }
        };

        const self = ctxHost(ctx);
        var payload: Payload = .{ .host = self, .id = id };
        // The task is heap allocated: it may outlive this frame if the wait
        // times out.
        //
        // The PAYLOAD stays on this stack frame, and it points at `arena` and
        // `out`, which the caller owns. That is only safe because
        // `runOnAppThread` does not return until the app thread has finished
        // with the payload - including when the wait times out and the app
        // thread had already claimed the task.
        //
        // KooshaPari/Khostty#79.
        const task = try ipc_task.Task.create(
            std.heap.c_allocator,
            &payload,
            Payload.run,
        );
        if (!try self.app.runOnAppThread(task, self.call_timeout_ms))
            return error.Internal;
        if (payload.err) |e| return e;
    }

    fn listSurfaces(
        ctx: *anyopaque,
        arena: Allocator,
        out: *std.ArrayListUnmanaged(pane.PaneInfo),
    ) pane.HostError!void {
        const Payload = struct {
            host: *AppHost,
            arena: Allocator,
            out: *std.ArrayListUnmanaged(pane.PaneInfo),
            err: ?pane.HostError = null,

            fn run(raw: *anyopaque) void {
                const self: *@This() = @ptrCast(@alignCast(raw));
                self.host.listInner(self.arena, self.out) catch |e| {
                    self.err = e;
                };
            }
        };

        const self = ctxHost(ctx);
        var payload: Payload = .{ .host = self, .arena = arena, .out = out };
        // The task is heap allocated: it may outlive this frame if the wait
        // times out.
        //
        // The PAYLOAD stays on this stack frame, and it points at `arena` and
        // `out`, which the caller owns. That is only safe because
        // `runOnAppThread` does not return until the app thread has finished
        // with the payload - including when the wait times out and the app
        // thread had already claimed the task.
        //
        // KooshaPari/Khostty#79.
        const task = try ipc_task.Task.create(
            std.heap.c_allocator,
            &payload,
            Payload.run,
        );
        if (!try self.app.runOnAppThread(task, self.call_timeout_ms))
            return error.Internal;
        if (payload.err) |e| return e;
    }

    fn writeToParser(ctx: *anyopaque, id: PaneId, data: []const u8) pane.HostError!usize {
        const self = ctxHost(ctx);
        const core = self.findCoreInner(id) orelse return error.PaneNotFound;
        // The same parser the pty output goes through, so escape sequences and
        // modes behave exactly as if the program had written them.
        //
        // The parser is owned by the app's IO thread; this function runs on an
        // IPC connection thread. Hand the bytes to the IO thread through the
        // surface mailbox instead of calling `nextSlice` here, so the parser
        // is only ever mutated from the thread that owns it. See
        // `CoreSurface.writeToParser` and `protocol.md` section 7.
        //
        // The byte count is reported optimistically: the bytes are queued for
        // the IO thread, which is the same guarantee the previous direct call
        // gave (it always returned `data.len`).
        //
        // FORK: KooshaPari/Khostty#48.
        try core.writeToParser(data);
        return data.len;
    }

    fn snapshotCore(
        ctx: *anyopaque,
        arena: Allocator,
        id: PaneId,
        out: *state.Snapshot,
    ) pane.HostError!void {
        const Payload = struct {
            host: *AppHost,
            arena: Allocator,
            id: PaneId,
            out: *state.Snapshot,
            err: ?pane.HostError = null,

            fn run(raw: *anyopaque) void {
                const self: *@This() = @ptrCast(@alignCast(raw));
                const core = self.host.findCoreInner(self.id) orelse {
                    self.err = error.PaneNotFound;
                    return;
                };
                self.host.snapshotInner(self.arena, core, self.out) catch |e| {
                    self.err = e;
                };
            }
        };

        const self = ctxHost(ctx);
        var payload: Payload = .{ .host = self, .arena = arena, .id = id, .out = out };
        // The task is heap allocated: it may outlive this frame if the wait
        // times out.
        //
        // The PAYLOAD stays on this stack frame, and it points at `arena` and
        // `out`, which the caller owns. That is only safe because
        // `runOnAppThread` does not return until the app thread has finished
        // with the payload - including when the wait times out and the app
        // thread had already claimed the task.
        //
        // KooshaPari/Khostty#79.
        const task = try ipc_task.Task.create(
            std.heap.c_allocator,
            &payload,
            Payload.run,
        );
        if (!try self.app.runOnAppThread(task, self.call_timeout_ms))
            return error.Internal;
        if (payload.err) |e| return e;
    }

    fn resizeSplit(
        ctx: *anyopaque,
        id: PaneId,
        dir: protocol.Direction,
        amount: u16,
    ) pane.HostError!void {
        const self = ctxHost(ctx);
        const core = self.findCoreInner(id) orelse return error.PaneNotFound;
        // Explicit switch, NOT @enumFromInt/@intFromEnum: protocol.Direction is
        // {right, down, left, up} but ResizeSplit.Direction is
        // {up, down, left, right}. Converting by integer would silently swap
        // right and up.
        const direction: apprt.action.ResizeSplit.Direction = switch (dir) {
            .up => .up,
            .down => .down,
            .left => .left,
            .right => .right,
        };
        _ = core.rt_app.performAction(
            .{ .surface = core },
            .resize_split,
            .{ .amount = amount, .direction = direction },
        ) catch |err| return mapActionError(err);
    }

    fn equalizeSplits(ctx: *anyopaque) pane.HostError!void {
        const Payload = struct {
            host: *AppHost,
            err: ?pane.HostError = null,

            fn run(raw: *anyopaque) void {
                const self: *@This() = @ptrCast(@alignCast(raw));
                // `focused_surface` is app state, so resolving it belongs on
                // the app thread. KooshaPari/Khostty#76.
                const core = self.host.app.focused_surface orelse {
                    self.err = error.PaneNotFound;
                    return;
                };
                _ = core.rt_app.performAction(
                    .{ .surface = core },
                    .equalize_splits,
                    {},
                ) catch |e| {
                    self.err = mapActionError(e);
                };
            }
        };

        const self = ctxHost(ctx);
        var payload: Payload = .{ .host = self };
        // The task is heap allocated: it may outlive this frame if the wait
        // times out.
        //
        // The PAYLOAD stays on this stack frame, and it points at `arena` and
        // `out`, which the caller owns. That is only safe because
        // `runOnAppThread` does not return until the app thread has finished
        // with the payload - including when the wait times out and the app
        // thread had already claimed the task.
        //
        // KooshaPari/Khostty#79.
        const task = try ipc_task.Task.create(
            std.heap.c_allocator,
            &payload,
            Payload.run,
        );
        if (!try self.app.runOnAppThread(task, self.call_timeout_ms))
            return error.Internal;
        if (payload.err) |e| return e;
    }

    fn toggleZoom(ctx: *anyopaque, id: PaneId) pane.HostError!void {
        const Payload = struct {
            host: *AppHost,
            id: PaneId,
            err: ?pane.HostError = null,

            fn run(raw: *anyopaque) void {
                const self: *@This() = @ptrCast(@alignCast(raw));
                const core = self.host.findCoreInner(self.id) orelse {
                    self.err = error.PaneNotFound;
                    return;
                };
                _ = core.rt_app.performAction(
                    .{ .surface = core },
                    .toggle_split_zoom,
                    {},
                ) catch |e| {
                    self.err = mapActionError(e);
                };
            }
        };

        const self = ctxHost(ctx);
        var payload: Payload = .{ .host = self, .id = id };
        // The task is heap allocated: it may outlive this frame if the wait
        // times out.
        //
        // The PAYLOAD stays on this stack frame, and it points at `arena` and
        // `out`, which the caller owns. That is only safe because
        // `runOnAppThread` does not return until the app thread has finished
        // with the payload - including when the wait times out and the app
        // thread had already claimed the task.
        //
        // KooshaPari/Khostty#79.
        const task = try ipc_task.Task.create(
            std.heap.c_allocator,
            &payload,
            Payload.run,
        );
        if (!try self.app.runOnAppThread(task, self.call_timeout_ms))
            return error.Internal;
        if (payload.err) |e| return e;
    }

    // ── Windowed implementations ──

    fn listInner(
        self: *AppHost,
        arena: Allocator,
        out: *std.ArrayListUnmanaged(pane.PaneInfo),
    ) pane.HostError!void {
        // Runs on the app thread (see `listSurfaces`), so reading the surface
        // list and the GTK getters here is sound. KooshaPari/Khostty#76.
        for (self.app.surfaces.items) |rt_surface| {
            const core = rt_surface.core();
            try out.append(arena, .{
                .id = PaneId.init(core.id),
                .title = if (titleOf(core)) |t| try arena.dupe(u8, t) else null,
                .pid = pidOf(core),
                .cwd = if (cwdOf(core)) |cwd| try arena.dupe(u8, cwd) else null,
                .cols = colsOf(core),
                .rows = rowsOf(core),
                .focused = self.app.focused_surface == core,
                // The runtime drops the surface when the child exits and keeps
                // no exit status, so this stays unknown rather than false.
                .exited = null,
            });
        }
    }

    /// Fill a snapshot. Runs on the app thread.
    fn snapshotInner(
        self: *AppHost,
        arena: Allocator,
        core: *CoreSurface,
        out: *state.Snapshot,
    ) pane.HostError!void {
        const term = &core.io.terminal;
        const screen = term.screens.active;
        const cursor = screen.cursor;
        const pixels = pixelSizeOf(core);

        out.* = .{
            .pane_id = PaneId.init(core.id),
            .title = if (titleOf(core)) |t| try arena.dupe(u8, t) else null,
            .pid = pidOf(core),
            .cwd = if (cwdOf(core)) |cwd| try arena.dupe(u8, cwd) else null,
            .size = .{
                .cols = @intCast(term.cols),
                .rows = @intCast(term.rows),
                .pixel_width = pixels.width,
                .pixel_height = pixels.height,
            },
            .cursor = .{
                .row = @intCast(cursor.y),
                .col = @intCast(cursor.x),
                .visible = !cursor.style.flags.invisible,
                // Explicit switch, NOT @enumFromInt: cursor.Style is
                // {bar, block, underline, block_hollow} while state.CursorStyle
                // is {block, bar, underline, block_hollow}. Converting by
                // integer would report every bar cursor as a block.
                .style = switch (cursor.cursor_style) {
                    .bar => .bar,
                    .block => .block,
                    .underline => .underline,
                    .block_hollow => .block_hollow,
                },
                .blinking = term.modes.get(.cursor_blinking),
            },
            .alt_screen = term.screens.active_key == .alternate,
            .focused = self.app.focused_surface == core,
            .mouse_tracking = term.modes.get(.mouse_event_normal) or
                term.modes.get(.mouse_event_button) or
                term.modes.get(.mouse_event_any),
            // The runtime keeps no bell counter and does not retain the child's
            // exit status after teardown, so these stay unknown instead of
            // being fabricated.
            .bell_count = null,
            .scrollback_rows = scrollbackRows(term),
            .viewport_rows = @intCast(term.rows),
            .exited = null,
            .exit_code = null,
            .exit_signal = null,
            .command = null,
            .last_activity_ms = null,
        };
    }

    /// Scalar info for one surface, as observed on the app thread.
    const SplitRequestResult = struct {
        id: u64,
        pid: ?u32 = null,
        cols: ?u16 = null,
        rows: ?u16 = null,
        focused: bool = false,
        title_buf: [255]u8 = [_]u8{0} ** 255,
        title_len: usize = 0,
    };

    /// Perform the split. Runs on the app thread, inside a thunk.
    ///
    /// The payload fields are spelled out rather than taken as `anytype`: the
    /// payload is a local struct declared inside the caller, and an `anytype`
    /// parameter cannot be instantiated with it in a way that type-checks.
    fn splitInner(
        self: *AppHost,
        parent_id: ?u64,
        direction: apprt.action.SplitDirection,
        title: ?[:0]const u8,
    ) !void {
        // Resolve the parent here: `focused_surface` and the surface list are
        // app state.
        const parent = if (parent_id) |id|
            self.findCoreInner(PaneId.init(id)) orelse return error.PaneNotFound
        else
            self.app.focused_surface orelse return error.Unsupported;

        _ = parent.rt_app.performAction(
            .{ .surface = parent },
            .new_split,
            direction,
        ) catch |err| return mapActionError(err);

        // Apply a requested title through the same action OSC 0/2 uses. A
        // write, so it belongs on this thread.
        if (title) |t| {
            if (self.findCoreInner(parent.id)) |core| {
                _ = core.rt_app.performAction(
                    .{ .surface = core },
                    .set_title,
                    .{ .title = t },
                ) catch {};
            }
        }
    }

    /// Record the current surface ids. Runs on the app thread.
    fn snapshotSurfaceIdsInner(self: *AppHost, buf: *[64]u64, len: *usize) void {
        len.* = 0;
        for (self.app.surfaces.items) |rt_surface| {
            if (len.* >= buf.len) break;
            buf[len.*] = rt_surface.core().id;
            len.* += 1;
        }
    }

    /// Find a surface id that was not in `before`. Runs on the app thread.
    fn findNewSurfaceInner(self: *AppHost, before: []const u64) ?u64 {
        for (self.app.surfaces.items) |rt_surface| {
            const id = rt_surface.core().id;
            var known = false;
            for (before) |b| {
                if (b == id) {
                    known = true;
                    break;
                }
            }
            if (!known) return id;
        }
        return null;
    }

    /// Read one surface's info. Runs on the app thread.
    fn surfaceInfoInner(self: *AppHost, id: u64) ?SplitRequestResult {
        const core = self.findCoreInner(PaneId.init(id)) orelse return null;
        var result: SplitRequestResult = .{ .id = core.id };
        result.pid = pidOf(core);
        result.cols = colsOf(core);
        result.rows = rowsOf(core);
        result.focused = self.app.focused_surface == core;
        if (titleOf(core)) |t| {
            const n = @min(t.len, result.title_buf.len);
            @memcpy(result.title_buf[0..n], t[0..n]);
            result.title_len = n;
        }
        return result;
    }

    fn findCoreInner(self: *AppHost, id: PaneId) ?*CoreSurface {
        return self.app.findSurfaceByID(id.raw);
    }
};

fn collectIds(gpa: Allocator, panes: []const pane.PaneInfo) Allocator.Error![]PaneId {
    const ids = try gpa.alloc(PaneId, panes.len);
    for (panes, ids) |info, *id| id.* = info.id;
    return ids;
}

fn titleOf(core: *CoreSurface) ?[]const u8 {
    if (comptime windowed) {
        return core.rt_surface.getTitle();
    } else {
        return null;
    }
}

fn cwdOf(core: *CoreSurface) ?[]const u8 {
    if (comptime windowed) {
        return core.io.terminal.getPwd();
    } else {
        return null;
    }
}

/// The foreground process of the pane's pty. For an idle shell this is the
/// shell; once a command takes the foreground it is that command.
fn pidOf(core: *CoreSurface) ?u32 {
    if (comptime windowed) {
        const pid = core.io.getProcessInfo(.foreground_pid) orelse return null;
        return std.math.cast(u32, pid);
    } else {
        return null;
    }
}

fn colsOf(core: *CoreSurface) ?u16 {
    if (comptime windowed) {
        return std.math.cast(u16, core.io.terminal.cols);
    } else {
        return null;
    }
}

fn rowsOf(core: *CoreSurface) ?u16 {
    if (comptime windowed) {
        return std.math.cast(u16, core.io.terminal.rows);
    } else {
        return null;
    }
}

fn pixelSizeOf(core: *CoreSurface) struct { width: ?u32, height: ?u32 } {
    if (comptime windowed) {
        const size = core.rt_surface.getSize() catch
            return .{ .width = null, .height = null };
        return .{ .width = size.width, .height = size.height };
    } else {
        return .{ .width = null, .height = null };
    }
}

fn scrollbackRows(term: *const terminalpkg.Terminal) ?u64 {
    if (comptime windowed) {
        const total: usize = term.screens.active.pages.total_rows;
        const viewport: usize = term.rows;
        if (total <= viewport) return 0;
        return @intCast(total - viewport);
    } else {
        return null;
    }
}

/// Map an apprt action error onto the host error set.
fn mapActionError(err: anyerror) pane.HostError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.Internal,
    };
}
