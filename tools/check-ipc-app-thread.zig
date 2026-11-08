//! FORK: guard the IPC app-thread boundary.
//!
//! KooshaPari/Khostty#76.
//!
//! ## What it enforces
//!
//! Every method of the windowed IPC vtable runs on a per-connection thread.
//! Several of them used to read state only the app thread may touch - the
//! surface list, GTK widget properties, the IO thread's `terminal`. That is
//! undefined behaviour, and it stayed invisible for a long time because the
//! race was never lost in CI.
//!
//! Those calls now go through `App.runOnAppThread`, which runs a closure on the
//! app thread. This checker fails the build if a call site regresses.
//!
//! ## How it decides
//!
//! It walks `src/apprt/ipc/app_host.zig` tracking which function each line
//! belongs to, and flags app-state access found in a function that is not
//! allowed to do it.
//!
//! Allowed (they run, or are only reachable, on the app thread):
//!   - anything ending in `Inner` - the bodies executed inside a thunk
//!   - the named allowlist below
//!
//! This is a name-based whitelist rather than a type system. It is deliberately
//! blunt: a false positive is a two-second fix (move the code into `*Inner`), a
//! false negative is a terminal that can abort under an agent. Bias to loud.
//!
//! Run: `zig run tools/check-ipc-app-thread.zig -- src/apprt/ipc/app_host.zig`

const std = @import("std");

/// Tokens that only make sense on the app thread.
const forbidden = [_][]const u8{
    "app.surfaces",
    "app.focused_surface",
    "app.findSurfaceByID",
    ".rt_surface.getTitle",
    ".rt_surface.getSize",
    ".rt_surface.getCursorPos",
    ".rt_surface.getContentScale",
    "core.io.terminal",
};

/// Functions permitted to touch app state. Everything else must either be an
/// `*Inner` body (run inside a thunk) or go through `app.runOnAppThread`.
const allowed = [_][]const u8{
    "init",
    "host",
    "setEventBroker",
    "publishTitleChange",
    "publishChildExit",
    "publishResize",
    "publishBell",
    "ctxHost",
    // Top-level accessors. Each is only reachable from an `*Inner` body or a
    // publish hook, both of which run on the app thread. They are listed
    // explicitly rather than by prefix so that adding a new one forces a
    // deliberate decision here.
    "titleOf",
    "cwdOf",
    "pidOf",
    "colsOf",
    "rowsOf",
    "pixelSizeOf",
    "scrollbackRows",
    "collectIds",
    "mapActionError",
    // The body of a thunk: nested `fn run` inside a payload struct. This is the
    // one place a vtable method is ALLOWED to touch app state, because Task
    // guarantees it runs on the app thread.
    "run",
    // Test-only helpers.
    "fakeSurface",
};

fn isAllowed(name: []const u8) bool {
    if (std.mem.endsWith(u8, name, "Inner")) return true;
    for (allowed) |a| {
        if (std.mem.eql(u8, name, a)) return true;
    }
    return false;
}

/// Extract `NAME` from a line like `    fn NAME(` or `    pub fn NAME(`.
fn fnName(line: []const u8) ?[]const u8 {
    const marker = "fn ";
    const at = std.mem.indexOf(u8, line, marker) orelse return null;
    var rest = line[at + marker.len ..];
    const open = std.mem.indexOfScalar(u8, rest, '(') orelse return null;
    rest = rest[0..open];
    const trimmed = std.mem.trim(u8, rest, " \t");
    if (trimmed.len == 0) return null;
    return trimmed;
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.gpa;

    var path: []const u8 = "src/apprt/ipc/app_host.zig";
    var args_iter = try std.process.Args.Iterator.initAllocator(init.minimal.args, alloc);
    defer args_iter.deinit();
    _ = args_iter.next(); // argv[0]
    if (args_iter.next()) |arg| path = arg;

    const src = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        path,
        alloc,
        .limited(8 * 1024 * 1024),
    );
    defer alloc.free(src);

    var violations: usize = 0;
    var current: ?[]const u8 = null;
    var line_no: usize = 0;

    var it = std.mem.splitScalar(u8, src, '\n');
    while (it.next()) |line| {
        line_no += 1;

        // Track the enclosing function at ANY indentation: vtable methods are
        // indented four spaces, top-level accessors sit at column zero, and
        // thunk bodies are nested twelve deep inside a payload struct.
        const lead = std.mem.trimStart(u8, line, " \t");
        if (std.mem.startsWith(u8, lead, "fn ") or
            std.mem.startsWith(u8, lead, "pub fn "))
        {
            current = fnName(lead);
        }

        const name = current orelse continue;
        if (isAllowed(name)) continue;

        // Ignore comments: this file documents the rule it is enforcing.
        const stripped = std.mem.trimStart(u8, line, " \t");
        if (std.mem.startsWith(u8, stripped, "//")) continue;

        for (forbidden) |token| {
            if (std.mem.indexOf(u8, line, token) == null) continue;
            std.debug.print(
                "{s}:{d}: {s} touches app state but does not run on the app thread\n" ++
                    "    in fn {s}\n" ++
                    "    use app.runOnAppThread, or move the body into a *Inner function\n",
                .{ path, line_no, token, name },
            );
            violations += 1;
            break; // one report per line
        }
    }

    // A second rule: a task must never be stack allocated. A task can outlive
    // the frame that posted it (the wait may time out), so a stack task means
    // the app thread can write into a dead frame.
    if (std.mem.indexOf(u8, src, "ipc_task.Task.init(") != null) {
        std.debug.print(
            "{s}: tasks must be heap allocated (Task.create), not Task.init: " ++
                "a task can outlive the frame that posted it\n",
            .{path},
        );
        violations += 1;
    }

    if (violations > 0) {
        std.debug.print("\n{d} app-thread violation(s) in {s}\n", .{ violations, path });
        std.process.exit(1);
    }

    std.debug.print("ipc app-thread guard: {s} clean\n", .{path});
}
