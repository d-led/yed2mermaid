// SPDX-License-Identifier: MPL-2.0
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = addConverter(b, "yed2mermaid", target, optimize, false);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    b.step("run", "Convert a yEd graphml file to Mermaid").dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_tests = b.addRunArtifact(tests);
    run_tests.setCwd(b.path("."));
    // Tests read the fixtures under example/, which the build cache cannot see.
    run_tests.has_side_effects = true;
    b.step("test", "Run the test suite").dependOn(&run_tests.step);

    const dist_step = b.step("dist", "Cross-compile release binaries for all supported targets");

    for (dist_targets) |entry| {
        const resolved = b.resolveTargetQuery(entry.query);
        const dist_exe = addConverter(b, "yed2mermaid", resolved, .ReleaseSmall, true);
        const extension = if (entry.query.os_tag == .windows) ".exe" else "";
        const install = b.addInstallArtifact(dist_exe, .{
            .dest_dir = .{ .override = .{ .custom = "dist" } },
            .dest_sub_path = b.fmt("yed2mermaid-{s}{s}", .{ entry.name, extension }),
        });
        dist_step.dependOn(&install.step);
    }
}

const DistTarget = struct {
    name: []const u8,
    query: std.Target.Query,
};

const dist_targets = [_]DistTarget{
    .{ .name = "aarch64-macos", .query = .{ .cpu_arch = .aarch64, .os_tag = .macos } },
    .{ .name = "x86_64-linux-musl", .query = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl } },
    .{ .name = "aarch64-linux-musl", .query = .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl } },
    .{ .name = "x86_64-windows", .query = .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu } },
};

fn addConverter(
    b: *std.Build,
    name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: bool,
) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = strip,
        }),
    });
}
