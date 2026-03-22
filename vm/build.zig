const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "kestrel",
        .root_module = root_mod,
    });
    // Required on Linux (Zig 0.15+): std.c via primitives.getProcess must link libc explicitly.
    exe.linkLibC();
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("run", "Run the VM");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_module = root_mod,
    });
    tests.linkLibC();
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run VM unit tests");
    test_step.dependOn(&run_tests.step);
}
