//! Tracks whether the GTK runtime ever managed to show a terminal surface.
//!
//! The GTK runtime needs to distinguish three outcomes when the app stops:
//!
//!   1. A surface was initialized at some point. The app worked, so the
//!      shutdown was clean and the exit status must stay 0.
//!   2. A surface initialization attempt failed. We never showed a terminal,
//!      so the exit status must be non-zero. Otherwise a headless host with
//!      no EGL driver looks exactly like a clean shutdown to supervisors,
//!      systemd units and CI checks. See KooshaPari/Khostty#65.
//!   3. Nothing was ever attempted, e.g. the app was started in the
//!      background with `initial-window = false`. Nothing failed, so the
//!      exit status must stay 0.
//!
//! This is a separate file with no GTK dependencies so that the decision
//! logic can be unit tested without a display server.

/// Why the GTK runtime failed to ever show a terminal surface.
pub const Failure = union(enum) {
    /// A surface initialization attempt failed with this error name.
    failed: []const u8,

    /// A window was requested but no surface was ever initialized. We don't
    /// know the exact cause, but the user never got a terminal.
    incomplete,
};

/// The state tracked across the lifetime of the GTK application.
pub const State = struct {
    /// True once a surface was successfully initialized.
    initialized: bool = false,

    /// The error name of the first failed initialization attempt, if any.
    /// The first failure wins because it is the root cause; later failures
    /// are usually just consequences of it.
    error_name: ?[]const u8 = null,

    /// True once a window was requested. This is set to true so long as we
    /// request a window exactly once. This prevents quitting the app before
    /// we've shown one window.
    window_requested: bool = false,

    /// Record that a window was requested.
    pub fn requestWindow(self: *State) void {
        self.window_requested = true;
    }

    /// Record that a surface was successfully initialized.
    pub fn initializedSuccessfully(self: *State) void {
        self.initialized = true;
    }

    /// Record that a surface initialization attempt failed.
    pub fn initFailed(self: *State, reason: []const u8) void {
        if (self.error_name == null) self.error_name = reason;
    }

    /// The reason we failed to ever initialize a surface, or null if we
    /// didn't fail.
    pub fn failure(self: *const State) ?Failure {
        // If we ever had a working surface then any later quit is clean.
        if (self.initialized) return null;

        // We tried to initialize a surface and it failed. This is our cause.
        if (self.error_name) |reason| return .{ .failed = reason };

        // We asked for a window but never got a working surface.
        if (self.window_requested) return .incomplete;

        // We never tried to initialize a surface at all (e.g. the app was
        // started in the background), so there is nothing that failed.
        return null;
    }
};

const testing = @import("std").testing;

test "nothing attempted is not a failure" {
    const state: State = .{};
    try testing.expect(state.failure() == null);
}

test "a failed initialization reports the first error" {
    var state: State = .{};
    state.requestWindow();
    state.initFailed("SurfaceError");
    state.initFailed("OtherError");

    const failure = state.failure() orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings("SurfaceError", failure.failed);
}

test "a successful initialization makes later failures irrelevant" {
    var state: State = .{};
    state.requestWindow();
    state.initFailed("SurfaceError");
    state.initializedSuccessfully();

    try testing.expect(state.failure() == null);
}

test "a requested window that never initializes is incomplete" {
    var state: State = .{};
    state.requestWindow();

    const failure = state.failure() orelse return error.TestUnexpectedResult;
    try testing.expect(failure == .incomplete);
}

test "a failure without a window request still reports the error" {
    var state: State = .{};
    state.initFailed("SurfaceInitializationFailed");

    const failure = state.failure() orelse return error.TestUnexpectedResult;
    try testing.expectEqualStrings("SurfaceInitializationFailed", failure.failed);
}
