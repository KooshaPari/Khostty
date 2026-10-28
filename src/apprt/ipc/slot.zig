//! FORK: request slots for operations that must run on the app thread.
//!
//! KooshaPari/Khostty#76.
//!
//! ## Why this exists
//!
//! Every method of the windowed IPC vtable runs on a per-connection thread, but
//! several of them read state the app thread owns: the surface list, GTK widget
//! properties (`getTitle`, `getSize`), and the IO thread's `terminal`. That is
//! undefined behaviour. `pane.create` was the one that aborted deterministically
//! (#71); the rest have simply not lost the race yet.
//!
//! The fix is a request/response boundary. The caller owns a `Slot` on its own
//! stack, posts a pointer, and waits for `done`. The app thread fills the
//! result and then sets `done` under `mutex`, so everything the caller reads
//! after observing `done` is stable: the app thread never touches the slot
//! again.
//!
//! ## Rules
//!
//! - Only plain data crosses. No pointers into app-owned memory: borrowed
//!   slices (`title`, `cwd`) are copied into fixed buffers here and the caller
//!   re-allocates them into its own arena.
//! - The app thread must never block on a caller. A slow caller costs it one
//!   uncontended mutex acquisition, nothing more.
//! - This module imports std and nothing else, so both the core (`App.zig`) and
//!   the IPC host can use it without an import cycle.

const std = @import("std");

/// One surface as observed on the app thread.
pub const Surface = struct {
    id: u64 = 0,
    pid: ?u32 = null,
    cols: ?u16 = null,
    rows: ?u16 = null,
    focused: bool = false,

    /// `PaneInfo.title` / `cwd` are borrowed slices, so they are copied here.
    /// 255 is the same ceiling the termio mailbox already uses.
    title_buf: [255]u8 = [_]u8{0} ** 255,
    title_len: usize = 0,
    cwd_buf: [255]u8 = [_]u8{0} ** 255,
    cwd_len: usize = 0,

    pub fn title(self: *const Surface) ?[]const u8 {
        if (self.title_len == 0) return null;
        return self.title_buf[0..self.title_len];
    }

    pub fn cwd(self: *const Surface) ?[]const u8 {
        if (self.cwd_len == 0) return null;
        return self.cwd_buf[0..self.cwd_len];
    }
};

/// A request owned by the caller's stack and serviced on the app thread.
pub const Slot = struct {
    kind: Kind = .list_surfaces,

    mutex: std.Io.Mutex = .init,
    /// Written by the app thread last, read by the caller first.
    done: bool = false,

    surfaces_buf: [64]Surface = [_]Surface{.{}} ** 64,
    surfaces_len: usize = 0,

    pub const Kind = enum {
        /// Enumerate every surface with its observable properties.
        list_surfaces,
    };
};
