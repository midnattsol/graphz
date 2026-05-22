const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("graphz", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // ---- check: compile the library ----
    const lib_check = b.addLibrary(.{
        .linkage = .static,
        .name = "graphz",
        .root_module = mod,
    });
    _ = b.step("check", "Check that the library compiles");
    b.getInstallStep().dependOn(&lib_check.step);

    // ---- test: run all tests in the library module ----
    const lib_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_lib_tests.step);
    _ = optimize;
}
