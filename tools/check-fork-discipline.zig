// check-fork-discipline.zig
//
// Defensive tool: detects silent modifications to upstream-owned files in the
// khostty fork. Runs on every PR via `zig build check-fork-discipline` and via
// `.github/workflows/ci-fork-discipline.yml`.
//
// Background
// ----------
// Khostty is a fork of ghostty-org/ghostty. The design property is that any
// `src/terminal/` mod (or `src/Surface.zig`, `src/Command.zig`, `src/runner.zig`)
// by upstream should remain cheap to absorb. The risk is that a well-intentioned
// modification to one of these files silently breaks that property — e.g. the
// 2026-10-17 EGL type regression, where upstream moved an enum variant and the
// BOTH-arms synthetic harness caught the move.
//
// This tool is the general guard for that risk across all upstream-owned
// surfaces, not just EGL.
//
// What it checks
// --------------
// For every file in the upstream-owned surface list:
//   1. Has the fork modified it relative to `<upstream>`? (`git diff --name-only`)
//   2. If yes, is the modification documented in `docs/FORK.md`?
//   3. If yes, is every added line inside a `// FORK:` block in the source file?
//   4. Does each `// FORK:` block reference a tracking issue (`#123` or `GH-123`)?
//
// Output
// ------
// - Markdown report to stdout, or to `--output <path>`.
// - Exit 0 on clean, exit 1 on violations when `--strict` is passed.
// - Default mode is advisory: the report is generated but the exit code is 0
//   so the operator can review the output before tightening rules.
//
// Usage
// -----
//   zig run tools/check-fork-discipline.zig -- \
//     --repo-root . \
//     --upstream upstream/main \
//     --output artifacts/fork-discipline.md

const std = @import("std");

/// Glob patterns identifying files that the fork treats as upstream-owned.
/// A modification to any of these surfaces is the regression risk this guard
/// exists to flag.
const UPSTREAM_OWNED_PATTERNS = [_][]const u8{
    "src/terminal/",
    "src/Surface.zig",
    "src/Command.zig",
    "src/runner.zig",
};

const FORK_DOC_FILE = "docs/FORK.md";

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();

    // ---- 1. Parse CLI args -------------------------------------------------
    var repo_root: []const u8 = ".";
    var upstream_ref: []const u8 = "upstream/main";
    var output_path: ?[]const u8 = null;
    var strict: bool = false;

    var args_iter = std.process.Args.Iterator.initAllocator(init.minimal.args, gpa) catch |err| {
        std.debug.print("failed to init args iterator: {t}\n", .{err});
        std.process.exit(2);
    };
    defer args_iter.deinit();
    // Skip argv[0] (program name).
    _ = args_iter.next();
    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "--repo-root")) {
            repo_root = args_iter.next() orelse fatal("--repo-root requires a value");
        } else if (std.mem.eql(u8, arg, "--upstream")) {
            upstream_ref = args_iter.next() orelse fatal("--upstream requires a value");
        } else if (std.mem.eql(u8, arg, "--output")) {
            output_path = args_iter.next() orelse fatal("--output requires a value");
        } else if (std.mem.eql(u8, arg, "--strict")) {
            strict = true;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printUsage();
            return;
        } else {
            std.debug.print("unknown argument: {s}\n", .{arg});
            printUsage();
            std.process.exit(2);
        }
    }

    std.debug.print(
        "[check-fork-discipline] repo={s} upstream={s} mode={s}\n",
        .{ repo_root, upstream_ref, if (strict) "strict" else "advisory" },
    );

    // ---- 2. Discover diverged files ----------------------------------------
    const diverged_files = gitDiffNameOnly(gpa, io, repo_root, upstream_ref) catch |err| {
        std.debug.print("git diff --name-only failed: {t}\n", .{err});
        std.process.exit(2);
    };
    defer gpa.free(diverged_files);
    defer {
        for (diverged_files) |f| gpa.free(f);
    }

    std.debug.print("[check-fork-discipline] diverged files vs {s}: {d}\n", .{
        upstream_ref, diverged_files.len,
    });

    // ---- 3. Filter for upstream-owned divergences -------------------------
    var upstream_owned = std.ArrayList([]const u8).empty;
    defer upstream_owned.deinit(gpa);

    for (diverged_files) |f| {
        if (isUpstreamOwned(f)) {
            try upstream_owned.append(gpa, f);
        }
    }

    std.debug.print(
        "[check-fork-discipline] upstream-owned divergences: {d}\n",
        .{upstream_owned.items.len},
    );

    // ---- 4. Load docs/FORK.md for the documentation check ------------------
    const fork_doc_path = std.fs.path.join(gpa, &.{ repo_root, FORK_DOC_FILE }) catch |err| {
        std.debug.print("path join failed: {t}\n", .{err});
        std.process.exit(2);
    };
    defer gpa.free(fork_doc_path);

    const fork_doc = std.Io.Dir.cwd().readFileAlloc(
        io,
        fork_doc_path,
        gpa,
        .limited(8 * 1024 * 1024),
    ) catch |err| switch (err) {
        error.FileNotFound => "", // treat missing FORK.md as "no documentation"
        else => {
            std.debug.print("read {s} failed: {t}\n", .{ fork_doc_path, err });
            std.process.exit(2);
        },
    };
    defer if (fork_doc.len > 0) gpa.free(fork_doc);

    // ---- 5. Build the Markdown report (two-pass) -------------------------
    // First pass: collect per-file content + totals.
    var per_file = std.ArrayList([]u8).empty;
    defer {
        for (per_file.items) |s| gpa.free(s);
        per_file.deinit(gpa);
    }

    var total_violations: usize = 0;
    var documented_count: usize = 0;

    for (upstream_owned.items) |file_path| {
        const is_documented = std.mem.indexOf(u8, fork_doc, file_path) != null;
        if (is_documented) documented_count += 1;

        var per_file_buf = std.ArrayList(u8).empty;
        defer per_file_buf.deinit(gpa);

        const violations = try analyzeFile(
            gpa,
            arena,
            io,
            repo_root,
            upstream_ref,
            file_path,
            is_documented,
            &per_file_buf,
        );

        total_violations += violations;
        try per_file.append(gpa, try per_file_buf.toOwnedSlice(gpa));
    }

    // Second pass: assemble the final report knowing the totals.
    var final_report = std.ArrayList(u8).empty;
    defer final_report.deinit(gpa);

    try final_report.print(gpa,
        \\# Fork Discipline Report
        \\
        \\Upstream base: `{s}`  ·  Working tree mode: {s}
        \\
        \\## Summary
        \\
        \\- Total files diverged from upstream: {d}
        \\- Upstream-owned surfaces diverged: **{d}**
        \\- Documented in `docs/FORK.md`: {d}
        \\- Total discipline violations: {d}
        \\
    , .{
        upstream_ref,
        if (strict) "strict (CI failing on violations)" else "advisory (CI passes; review report)",
        diverged_files.len,
        upstream_owned.items.len,
        documented_count,
        total_violations,
    });

    if (upstream_owned.items.len == 0) {
        try final_report.appendSlice(gpa,
            \\### Clean
            \\
            \\No upstream-owned files have been modified in this fork. Upstream merges will be cheap to absorb.
            \\
        );
    } else {
        try final_report.appendSlice(gpa, "## Per-File Findings\n\n");
        for (per_file.items) |s| {
            try final_report.appendSlice(gpa, s);
        }
    }

    // ---- 6. Emit the report -----------------------------------------------
    if (output_path) |path| {
        const file = std.Io.Dir.cwd().createFile(io, path, .{}) catch |err| {
            std.debug.print("createFile({s}) failed: {t}\n", .{ path, err });
            std.process.exit(2);
        };
        defer file.close(io);
        file.writeStreamingAll(io, final_report.items) catch |err| {
            std.debug.print("write {s} failed: {t}\n", .{ path, err });
            std.process.exit(2);
        };
        std.debug.print("[check-fork-discipline] report written to {s}\n", .{path});
    } else {
        var buf: [4096]u8 = undefined;
        var w = std.Io.File.stdout().writerStreaming(io, &buf);
        try w.interface.writeAll(final_report.items);
        try w.interface.flush();
    }

    // ---- 7. Exit code ------------------------------------------------------
    if (total_violations > 0 and strict) {
        std.debug.print(
            "[check-fork-discipline] {d} violation(s); exiting 1\n",
            .{total_violations},
        );
        std.process.exit(1);
    }

    std.debug.print(
        "[check-fork-discipline] done (violations={d}, mode={s})\n",
        .{ total_violations, if (strict) "strict" else "advisory" },
    );
}

// ============================================================================
//                          subprocess helpers
// ============================================================================

/// Run `git diff --name-only <upstream_ref> HEAD` in `repo_root` and return the
/// list of changed file paths. Caller owns the returned slice + each entry.
fn gitDiffNameOnly(
    gpa: std.mem.Allocator,
    io: std.Io,
    repo_root: []const u8,
    upstream_ref: []const u8,
) ![][]const u8 {
    const result = std.process.run(gpa, io, .{
        .argv = &.{
            "git",
            "diff",
            "--name-only",
            upstream_ref,
            "HEAD",
        },
        .cwd = .{ .path = repo_root },
    }) catch |err| return err;
    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0) {
            std.debug.print("git diff --name-only exited {d}: {s}\n", .{ code, result.stderr });
            return error.GitDiffFailed;
        },
        else => return error.GitDiffFailed,
    }

    return splitNonEmptyLines(gpa, result.stdout);
}

/// Run `git diff -U3 <upstream_ref> HEAD -- <file>` and return the raw diff.
fn gitDiffForFile(
    gpa: std.mem.Allocator,
    io: std.Io,
    repo_root: []const u8,
    upstream_ref: []const u8,
    file_path: []const u8,
) ![]u8 {
    const result = std.process.run(gpa, io, .{
        .argv = &.{
            "git", "diff", "-U3", upstream_ref, "HEAD", "--", file_path,
        },
        .cwd = .{ .path = repo_root },
    }) catch |err| return err;
    defer gpa.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0) return error.GitDiffFailed,
        else => return error.GitDiffFailed,
    }

    return result.stdout;
}

// ============================================================================
//                            pattern matching
// ============================================================================

/// True if `path` matches any of the upstream-owned surface patterns. Patterns
/// are exact prefixes for directories and exact matches for top-level files.
fn isUpstreamOwned(path: []const u8) bool {
    for (UPSTREAM_OWNED_PATTERNS) |pat| {
        if (std.mem.endsWith(u8, pat, "/")) {
            // Directory prefix: any path starting with `<dir>/`.
            if (std.mem.startsWith(u8, path, pat)) return true;
        } else {
            if (std.mem.eql(u8, path, pat)) return true;
        }
    }
    return false;
}

// ============================================================================
//                              diff parsing
// ============================================================================

const LineRange = struct {
    /// 1-based start line in the new file (the fork's HEAD).
    start: usize,
    /// 1-based end line in the new file (inclusive).
    end: usize,
};

/// Parse a unified diff and return the line ranges in the new (fork) file that
/// were added. Lines that were *modified* in place (i.e. context lines that
/// were kept but changed on a `c` hunk) are not flagged — only true insertions
/// and the `+` side of modifications.
///
/// The parser is minimal: it handles `@@ -old_start,old_count +new_start,new_count @@`
/// hunk headers and tracks a per-hunk counter that advances for each `+` line
/// it sees. Context lines (` `) and `-` lines (deletions) advance the old-file
/// counter only. Blank lines inside a hunk (no leading prefix) are treated as
/// context because git emits them that way.
fn parseDiffAddedRanges(arena: std.mem.Allocator, diff: []const u8) !std.ArrayList(LineRange) {
    var ranges = std.ArrayList(LineRange).empty;
    errdefer ranges.deinit(arena);

    const lines = try splitLinesRaw(arena, diff);
    defer {
        for (lines) |l| arena.free(l);
        arena.free(lines);
    }

    var new_line: usize = 0;
    var hunk_start: usize = 0;
    var hunk_end: usize = 0; // last + line in the current segment
    var in_hunk = false;
    var seen_plus = false; // track if a + line has been seen in the current hunk segment

    for (lines) |line| {
        if (std.mem.startsWith(u8, line, "@@")) {
            // Flush any open hunk that wasn't terminated cleanly.
            if (in_hunk and seen_plus and hunk_start > 0 and hunk_end >= hunk_start) {
                try ranges.append(arena, .{ .start = hunk_start, .end = hunk_end });
            }
            in_hunk = false;
            hunk_start = 0;
            hunk_end = 0;
            seen_plus = false;

            const hunk = parseHunkHeader(line) orelse continue;
            new_line = hunk.new_start;
            in_hunk = true;
            continue;
        }

        if (!in_hunk) continue;

        if (line.len > 0 and line[0] == '+') {
            if (hunk_start == 0) hunk_start = new_line;
            hunk_end = new_line;
            seen_plus = true;
            new_line += 1;
        } else if (line.len > 0 and line[0] == '-') {
            // Deletion: advances old counter only. Skip new-line increment.
            continue;
        } else if (line.len > 0 and line[0] == ' ') {
            // Context line: flush open range, then advance both counters.
            if (seen_plus and hunk_start > 0 and hunk_end >= hunk_start) {
                try ranges.append(arena, .{ .start = hunk_start, .end = hunk_end });
            }
            hunk_start = 0;
            hunk_end = 0;
            seen_plus = false;
            new_line += 1;
            continue;
        } else if (line.len == 0) {
            // Blank line inside a hunk: git emits these as truly empty (no
            // leading space) when the surrounding context is blank too. Treat
            // as a context line.
            if (seen_plus and hunk_start > 0 and hunk_end >= hunk_start) {
                try ranges.append(arena, .{ .start = hunk_start, .end = hunk_end });
            }
            hunk_start = 0;
            hunk_end = 0;
            seen_plus = false;
            new_line += 1;
            continue;
        } else if (std.mem.eql(u8, line, "\\ No newline at end of file")) {
            continue;
        } else {
            // Anything else (file header, etc.) closes the current hunk.
            if (seen_plus and hunk_start > 0 and hunk_end >= hunk_start) {
                try ranges.append(arena, .{ .start = hunk_start, .end = hunk_end });
            }
            in_hunk = false;
            hunk_start = 0;
            hunk_end = 0;
            seen_plus = false;
        }
    }

    if (in_hunk and seen_plus and hunk_start > 0 and hunk_end >= hunk_start) {
        try ranges.append(arena, .{ .start = hunk_start, .end = hunk_end });
    }

    return ranges;
}

const HunkHeader = struct {
    new_start: usize,
    new_count: usize,
};

/// Parse `@@ -a,b +c,d @@ optional`. Returns null on malformed input.
fn parseHunkHeader(line: []const u8) ?HunkHeader {
    // Find `+`.
    const plus_idx = std.mem.indexOf(u8, line, "+") orelse return null;
    // Find the comma or space after the `+`.
    var end_idx = plus_idx + 1;
    while (end_idx < line.len and (line[end_idx] == '+' or line[end_idx] == '-' or
        line[end_idx] == '@')) : (end_idx += 1)
    {}
    while (end_idx < line.len and line[end_idx] != ',' and line[end_idx] != ' ' and
        line[end_idx] != '@') : (end_idx += 1)
    {}

    const start_str = line[plus_idx + 1 .. end_idx];
    const start = std.fmt.parseInt(usize, start_str, 10) catch return null;

    var count: usize = 1; // default when count omitted, per unified-diff convention
    if (end_idx < line.len and line[end_idx] == ',') {
        const count_str = line[end_idx + 1 ..];
        var count_end: usize = 0;
        while (count_end < count_str.len and count_str[count_end] != ' ' and
            count_str[count_end] != '@') : (count_end += 1)
        {}
        count = std.fmt.parseInt(usize, count_str[0..count_end], 10) catch 1;
    }

    return .{ .new_start = start, .new_count = count };
}

// ============================================================================
//                         FORK-block detection
// ============================================================================

/// True if any line within `range.start..=range.end` is inside a `// FORK:`
/// block in the source file. A `// FORK:` block is a contiguous run of comment
/// lines at the start of which one line matches `// FORK:` (case-insensitive
/// prefix), terminating at the first blank line or non-comment line.
///
/// We deliberately do NOT require the FORK: marker to be on the same line as
/// the modification — only that some FORK: marker precedes the changed line
/// without an intervening blank/non-comment line. This matches how Ghostty's
/// upstream comments are written and avoids false positives from inline `+`
/// additions that re-use a marker already present in context.
fn isRangeInForkBlock(lines: []const []const u8, range: LineRange) bool {
    if (range.start == 0) return false;

    var in_fork_block = false;
    var i: usize = 0;
    while (i < lines.len) : (i += 1) {
        const ln = lines[i];
        const trimmed = std.mem.trim(u8, ln, " \t");

        if (isForkMarker(trimmed)) {
            in_fork_block = true;
            continue;
        }

        if (!in_fork_block) continue;

        // The block ends at a blank line or a non-comment line.
        if (trimmed.len == 0 or !std.mem.startsWith(u8, trimmed, "//")) {
            in_fork_block = false;
            continue;
        }

        const line_num_1based: usize = i + 1;
        if (line_num_1based >= range.start and line_num_1based <= range.end) {
            return true;
        }
    }
    return false;
}

/// True if `line` (already trimmed) is a `// FORK:` marker. Recognised forms:
///   // FORK: ...
///   //FORK: ...
///   /// FORK: ...   (doc comment variant)
fn isForkMarker(line: []const u8) bool {
    var rest: []const u8 = line;
    if (std.mem.startsWith(u8, rest, "///")) {
        rest = rest[3..];
    } else if (std.mem.startsWith(u8, rest, "//")) {
        rest = rest[2..];
    } else return false;

    // Skip a single optional space, then require `FORK:`.
    if (rest.len > 0 and rest[0] == ' ') rest = rest[1..];
    if (rest.len < 5) return false;
    return std.mem.eql(u8, rest[0..5], "FORK:") or std.mem.eql(u8, rest[0..5], "fork:");
}

/// True if any FORK marker within `range.start..=range.end` references a
/// tracking issue such as `#123` or `GH-123`. We accept the marker itself OR
/// any subsequent comment line in the same block. This is the loosest check;
/// the goal is to catch "I added a fork block but forgot to link the issue".
fn forkBlockHasIssueRef(lines: []const []const u8, range: LineRange) bool {
    var i: usize = 0;
    while (i < lines.len) : (i += 1) {
        const line_num_1based: usize = i + 1;
        if (line_num_1based < range.start) continue;
        if (line_num_1based > range.end) break;

        const trimmed = std.mem.trim(u8, lines[i], " \t");
        if (hasIssueRef(trimmed)) return true;
    }
    return false;
}

/// True if `line` looks like it references a GitHub issue. We accept either
/// `GH-123` or `#123` (preceded by whitespace or start-of-line). Inline `://`
/// URLs containing `#1234` are deliberately NOT counted — that's almost
/// always an HTTP fragment, not a tracker reference.
fn hasIssueRef(line: []const u8) bool {
    // Look for `#NNN` or `GH-NNN` or `khostty-NNN`.
    var idx: usize = 0;
    while (idx < line.len) {
        if (line[idx] == '#') {
            // Require at least one digit.
            if (idx + 1 < line.len and line[idx + 1] >= '0' and line[idx + 1] <= '9') {
                // Reject if it looks like a URL fragment (preceded by alphanumeric).
                if (idx == 0 or !(line[idx - 1] >= 'a' and line[idx - 1] <= 'z') and
                    !(line[idx - 1] >= 'A' and line[idx - 1] <= 'Z'))
                {
                    return true;
                }
            }
        } else if (idx + 2 < line.len and
            (std.mem.eql(u8, line[idx ..][0..2], "GH") or
            std.mem.eql(u8, line[idx ..][0..2], "gh")) and
            line[idx + 2] == '-')
        {
            if (idx + 3 < line.len and line[idx + 3] >= '0' and line[idx + 3] <= '9') {
                return true;
            }
        }
        idx += 1;
    }
    return false;
}

// ============================================================================
//                            per-file analysis
// ============================================================================

/// Analyze one upstream-owned file and write its Markdown section. Returns the
/// number of violations found.
fn analyzeFile(
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    io: std.Io,
    repo_root: []const u8,
    upstream_ref: []const u8,
    file_path: []const u8,
    is_documented: bool,
    report: *std.ArrayList(u8),
) !usize {
    var violations: usize = 0;

    try report.print(gpa, "### `{s}`\n\n", .{file_path});

    // Documentation check.
    try report.print(gpa, "- Documented in `{s}`: **{s}**\n", .{
        FORK_DOC_FILE,
        if (is_documented) "yes" else "no",
    });
    if (!is_documented) violations += 1;

    // Get the diff.
    const diff = gitDiffForFile(gpa, io, repo_root, upstream_ref, file_path) catch |err| {
        try report.print(gpa, "- Could not read diff: `{t}`\n\n", .{err});
        return violations + 1;
    };
    defer gpa.free(diff);

    if (diff.len == 0) {
        try report.appendSlice(gpa, "- Diff: empty (file matches upstream)\n\n");
        return violations;
    }

    // Parse added ranges.
    var added_ranges = try parseDiffAddedRanges(arena, diff);
    defer added_ranges.deinit(arena);

    try report.print(gpa, "- Diff hunks: {d}\n", .{added_ranges.items.len});

    if (added_ranges.items.len == 0) {
        try report.appendSlice(gpa, "- Added-line ranges: none (only deletions/context)\n\n");
        return violations;
    }

    // Format ranges.
    try report.appendSlice(gpa, "- Added-line ranges: ");
    for (added_ranges.items, 0..) |r, i| {
        if (i > 0) try report.appendSlice(gpa, ", ");
        try report.print(gpa, "L{d}–L{d}", .{ r.start, r.end });
    }
    try report.appendSlice(gpa, "\n");

    // Read the file content for FORK-block detection.
    const abs_path = std.fs.path.join(gpa, &.{ repo_root, file_path }) catch |err| {
        try report.print(gpa, "- Could not build absolute path: `{t}`\n\n", .{err});
        return violations + 1;
    };
    defer gpa.free(abs_path);

    const content = std.Io.Dir.cwd().readFileAlloc(
        io,
        abs_path,
        gpa,
        .limited(8 * 1024 * 1024),
    ) catch |err| {
        try report.print(gpa, "- Could not read file: `{t}`\n\n", .{err});
        return violations + 1;
    };
    defer gpa.free(content);

    const file_lines = try splitLinesRaw(arena, content);
    defer {
        for (file_lines) |l| arena.free(l);
        arena.free(file_lines);
    }

    // FORK-block coverage check.
    var uncovered_ranges: usize = 0;
    var undocumented_blocks: usize = 0;
    for (added_ranges.items) |r| {
        if (!isRangeInForkBlock(file_lines, r)) {
            uncovered_ranges += 1;
        } else if (!forkBlockHasIssueRef(file_lines, r)) {
            undocumented_blocks += 1;
        }
    }

    if (uncovered_ranges == 0 and undocumented_blocks == 0) {
        try report.appendSlice(gpa,
            "- All modifications are inside `// FORK:` blocks with issue references\n\n");
    } else {
        try report.print(gpa,
            "- ⚠ {d} added range(s) are NOT inside any `// FORK:` block\n",
            .{uncovered_ranges},
        );
        violations += uncovered_ranges;

        try report.print(gpa,
            "- ⚠ {d} `// FORK:` block(s) have no issue reference (`#NNN` / `GH-NNN`)\n",
            .{undocumented_blocks},
        );
        violations += undocumented_blocks;
        try report.appendSlice(gpa, "\n");
    }

    // Verdict.
    if (violations == 0) {
        try report.appendSlice(gpa, "**Verdict:** PASS\n\n");
    } else {
        try report.print(gpa, "**Verdict:** {d} violation(s)\n\n", .{violations});
    }

    return violations;
}

// ============================================================================
//                          string utilities
// ============================================================================

/// Split on `\n`. Empty lines are kept (we use this to detect blank-line block
/// termination in FORK markers). `splitScalar` includes a trailing empty
/// element after a final `\n`; callers that want strict content-only should
/// use `splitNonEmptyLines` instead.
fn splitLinesRaw(arena: std.mem.Allocator, s: []const u8) ![][]const u8 {
    var out = std.ArrayList([]const u8).empty;
    errdefer {
        for (out.items) |l| arena.free(l);
        out.deinit(arena);
    }

    var it = std.mem.splitScalar(u8, s, '\n');
    while (it.next()) |part| {
        const dup = try arena.dupe(u8, part);
        try out.append(arena, dup);
    }
    return out.toOwnedSlice(arena);
}

/// Like `splitLinesRaw` but filters out empty lines. Used for the output of
/// `git diff --name-only`, which emits one path per line.
fn splitNonEmptyLines(gpa: std.mem.Allocator, s: []const u8) ![][]const u8 {
    var out = std.ArrayList([]const u8).empty;
    errdefer {
        for (out.items) |l| gpa.free(l);
        out.deinit(gpa);
    }

    var it = std.mem.splitScalar(u8, s, '\n');
    while (it.next()) |part| {
        if (part.len == 0) continue;
        const dup = try gpa.dupe(u8, part);
        try out.append(gpa, dup);
    }
    return out.toOwnedSlice(gpa);
}

// ============================================================================
//                           misc helpers
// ============================================================================

fn fatal(msg: []const u8) noreturn {
    std.debug.print("error: {s}\n", .{msg});
    std.process.exit(2);
}

fn printUsage() void {
    std.debug.print(
        \\
        \\check-fork-discipline.zig — flag modifications to upstream-owned surfaces
        \\
        \\Usage:
        \\  zig run tools/check-fork-discipline.zig -- [options]
        \\
        \\Options:
        \\  --repo-root <path>   Path to the khostty checkout (default: .)
        \\  --upstream <ref>     Upstream git ref to diff against (default: upstream/main)
        \\  --output <path>      Write the Markdown report to a file (default: stdout)
        \\  --strict             Exit 1 on violations (default: advisory, exit 0)
        \\  -h, --help           Show this help
        \\
        \\Upstream-owned patterns checked:
    , .{});
    for (UPSTREAM_OWNED_PATTERNS) |p| {
        std.debug.print("  - {s}\n", .{p});
    }
    std.debug.print("\n", .{});
}

// ============================================================================
//                                 tests
// ============================================================================

test "isUpstreamOwned recognises terminal subdir" {
    try std.testing.expect(isUpstreamOwned("src/terminal/mouse.zig"));
    try std.testing.expect(isUpstreamOwned("src/terminal/page.zig"));
}

test "isUpstreamOwned recognises top-level files" {
    try std.testing.expect(isUpstreamOwned("src/Surface.zig"));
    try std.testing.expect(isUpstreamOwned("src/Command.zig"));
    try std.testing.expect(isUpstreamOwned("src/runner.zig"));
}

test "isUpstreamOwned rejects fork-owned paths" {
    try std.testing.expect(!isUpstreamOwned("src/apprt/ipc/protocol.zig"));
    try std.testing.expect(!isUpstreamOwned("src/apprt/windows/App.zig"));
    try std.testing.expect(!isUpstreamOwned("docs/FORK.md"));
    try std.testing.expect(!isUpstreamOwned("README.md"));
}

test "parseHunkHeader handles standard form" {
    try std.testing.expectEqualDeep(
        HunkHeader{ .new_start = 87, .new_count = 7 },
        parseHunkHeader("@@ -84,7 +87,7 @@ pub const Shape").?,
    );
}

test "parseHunkHeader handles omitted count" {
    try std.testing.expectEqualDeep(
        HunkHeader{ .new_start = 1, .new_count = 1 },
        parseHunkHeader("@@ -1 +1 @@").?,
    );
}

test "isForkMarker accepts FORK: prefix variants" {
    try std.testing.expect(isForkMarker("// FORK: khostty-only mouse shape"));
    try std.testing.expect(isForkMarker("///FORK: doc-comment variant"));
    try std.testing.expect(isForkMarker("//FORK: no space"));
    try std.testing.expect(!isForkMarker("// fork-block-start"));
    try std.testing.expect(!isForkMarker("fn fork()"));
}

test "hasIssueRef recognises #N and GH-N" {
    try std.testing.expect(hasIssueRef("// FORK: see #14736"));
    try std.testing.expect(hasIssueRef("// tracked in GH-1234"));
    try std.testing.expect(hasIssueRef("no leading ws:foo #9"));
    try std.testing.expect(!hasIssueRef("// url https://example.com/#section"));
    try std.testing.expect(!hasIssueRef("// no refs at all"));
}

test "splitLinesRaw preserves empty lines for block parsing" {
    const arena = std.testing.allocator;
    const lines = try splitLinesRaw(arena, "a\nb\n\nc\n");
    defer {
        for (lines) |l| arena.free(l);
        arena.free(lines);
    }
    // splitScalar includes the trailing empty element after the final \n.
    try std.testing.expectEqual(@as(usize, 5), lines.len);
    try std.testing.expectEqualStrings("a", lines[0]);
    try std.testing.expectEqualStrings("b", lines[1]);
    try std.testing.expectEqualStrings("", lines[2]);
    try std.testing.expectEqualStrings("c", lines[3]);
    try std.testing.expectEqualStrings("", lines[4]);
}

test "parseDiffAddedRanges handles simple insertion" {
    const arena = std.testing.allocator;
    const diff =
        \\--- a/src/terminal/mouse.zig
        \\+++ b/src/terminal/mouse.zig
        \\@@ -87,7 +87,7 @@ pub const Shape = enum(c_int) {
        \\             .{ .name = "GhosttyMouseShape" },
        \\             ),
        \\
        \\-            .none => void,
        \\+            .none, .windows => void,
        \\         };
        \\     };
        \\
    ;
    var ranges = try parseDiffAddedRanges(arena, diff);
    defer ranges.deinit(arena);
    try std.testing.expectEqual(@as(usize, 1), ranges.items.len);
    try std.testing.expectEqual(@as(usize, 90), ranges.items[0].start);
    try std.testing.expectEqual(@as(usize, 90), ranges.items[0].end);
}