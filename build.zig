const std = @import("std");

pub fn build(b:*std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("bartholomew", .{
        .root_source_file = b.path("src/bart.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{
        .root_module = b.addModule("bartholomew_tests", .{
            .root_source_file = b.path("src/test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_test = b.addRunArtifact(tests);
    run_test.has_side_effects = true;

    const test_step = b.step("test", "run the tests for Bartholomew");
    test_step.dependOn(&run_test.step);
}
