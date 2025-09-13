const std = @import("std");
const libgit2 = @import("deps/libgit2.zig");
const zlib = @import("deps/zlib.zig");
const mbedtls = @import("deps/mbedtls.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const z = zlib.create(b, target, optimize);
    const tls = mbedtls.create(b, target, optimize);

    const git2 = try libgit2.create(b, target, optimize);
    tls.link(git2.step);
    z.link(git2.step);

    {
        const exe = b.addExecutable(.{
            .name = "radargit",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        exe.linkLibC();
        exe.addIncludePath(b.path("deps/libgit2/include"));
        exe.linkLibrary(git2.step);
        exe.root_module.addImport("xitui", b.dependency("xitui", .{}).module("xitui"));
        //exe.root_module.addAnonymousImport("xitui", .{ .root_source_file = b.path("../xitui/src/lib.zig") });
        b.installArtifact(exe);

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
        const run_step = b.step("run", "Run the app");
        run_step.dependOn(&run_cmd.step);
    }

    {
        const unit_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/test.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        unit_tests.linkLibC();
        unit_tests.addIncludePath(b.path("deps/libgit2/include"));
        unit_tests.linkLibrary(git2.step);
        unit_tests.root_module.addImport("xitui", b.dependency("xitui", .{}).module("xitui"));
        //unit_tests.root_module.addAnonymousImport("xitui", .{ .root_source_file = b.path("../xitui/src/lib.zig") });

        const run_unit_tests = b.addRunArtifact(unit_tests);
        const test_step = b.step("test", "Run unit tests");
        test_step.dependOn(&run_unit_tests.step);
    }
}
