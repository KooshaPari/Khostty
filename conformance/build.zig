// Conformance test build script
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const conformance_step = b.step("conformance", "Run VT/ANSI conformance tests");

    // Create the conformance test executable
    const conformance_mod = b.createModule(.{
        .root_source_file = b.path("conformance/run.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link ghostty-vt library
    const ghostty_dep = b.dependency("ghostty", .{
        .target = target,
        .optimize = optimize,
    });

    conformance_mod.addImport("ghostty-vt", ghostty_dep.module("ghostty-vt"));

    // Add C headers include path
    conformance_mod.addIncludePath(b.path("include/ghostty"));

    const conformance_exe = b.addExecutable(.{
        .name = "conformance_test",
        .root_module = conformance_mod,
    });

    // Link against libghostty-vt
    conformance_exe.linkSystemLibrary("ghostty-vt", .{});

    // Run step
    const run_cmd = b.addRunArtifact(conformance_exe);
    conformance_step.dependOn(&run_cmd.step);
}