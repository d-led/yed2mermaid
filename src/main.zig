// SPDX-License-Identifier: MPL-2.0
//! Command line wiring: read a file (or stdin), convert, write the result.
const std = @import("std");
const cli = @import("cli.zig");
const convert = @import("convert.zig");
const diagnostics = @import("diagnostics.zig");
const options = @import("options.zig");

const max_input_bytes = 64 << 20;
const max_config_bytes = 1 << 20;

pub fn main(init: std.process.Init) void {
    const arena = init.arena.allocator();
    const io = init.io;

    const raw_args = init.minimal.args.toSlice(arena) catch {
        std.process.exit(2);
    };
    var args: std.ArrayList([]const u8) = .empty;
    for (raw_args[1..]) |argument| {
        args.append(arena, argument) catch std.process.exit(2);
    }

    const command = cli.parse(args.items) catch |err| {
        std.debug.print("yed2mermaid: {s}\n\n{s}", .{ describe(err), cli.help_text });
        std.process.exit(1);
    };

    const exit_code: u8 = switch (command) {
        .help => blk: {
            writeStdout(io, cli.help_text) catch break :blk 2;
            break :blk 0;
        },
        .version => blk: {
            writeStdout(io, "yed2mermaid " ++ cli.version ++ "\n") catch break :blk 2;
            break :blk 0;
        },
        .convert => |opts| run(arena, io, opts),
    };

    if (exit_code != 0) std.process.exit(exit_code);
}

fn run(allocator: std.mem.Allocator, io: std.Io, opts: options.Options) u8 {
    const config_json = resolveConfig(allocator, io, opts.config) catch |err| {
        std.debug.print("yed2mermaid: cannot read --config: {s}\n", .{@errorName(err)});
        return 2;
    };

    const input = readInput(allocator, io, opts.input_path) catch |err| {
        std.debug.print("yed2mermaid: cannot read {s}: {s}\n", .{ opts.input_path orelse "-", @errorName(err) });
        return 2;
    };

    var diag = diagnostics.Diagnostics.init(allocator);
    const text = convert.convert(allocator, input, opts, config_json, &diag) catch |err| {
        reportWarnings(&diag, opts.quiet);
        std.debug.print("yed2mermaid: conversion failed: {s}\n", .{@errorName(err)});
        return 2;
    };

    reportWarnings(&diag, opts.quiet);

    writeOutput(io, opts.output_path, text) catch |err| {
        std.debug.print("yed2mermaid: cannot write {s}: {s}\n", .{ opts.output_path orelse "stdout", @errorName(err) });
        return 2;
    };
    return 0;
}

fn reportWarnings(diag: *const diagnostics.Diagnostics, quiet: bool) void {
    if (quiet) return;
    for (diag.warnings.items) |warning| {
        std.debug.print("warning: {s}\n", .{warning.message});
    }
}

fn resolveConfig(
    allocator: std.mem.Allocator,
    io: std.Io,
    source: options.ConfigSource,
) !?[]const u8 {
    return switch (source) {
        .none => null,
        .inline_json => |text| text,
        .file => |path| try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_config_bytes)),
    };
}

fn readInput(allocator: std.mem.Allocator, io: std.Io, path: ?[]const u8) ![]const u8 {
    const input = path orelse return error.MissingInput;
    if (std.mem.eql(u8, input, "-")) {
        var buffer: [4096]u8 = undefined;
        var reader: std.Io.File.Reader = .init(.stdin(), io, &buffer);
        return reader.interface.allocRemaining(allocator, .limited(max_input_bytes));
    }
    return std.Io.Dir.cwd().readFileAlloc(io, input, allocator, .limited(max_input_bytes));
}

fn writeOutput(io: std.Io, path: ?[]const u8, text: []const u8) !void {
    if (path) |output| {
        try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = output, .data = text });
        return;
    }
    try writeStdout(io, text);
}

fn writeStdout(io: std.Io, text: []const u8) !void {
    var buffer: [8192]u8 = undefined;
    var writer: std.Io.File.Writer = .init(.stdout(), io, &buffer);
    try writer.interface.writeAll(text);
    try writer.interface.flush();
}

fn describe(err: cli.Error) []const u8 {
    return switch (err) {
        error.UnknownOption => "unknown option",
        error.MissingValue => "missing option value",
        error.InvalidValue => "invalid option value",
        error.UnexpectedArgument => "unexpected extra argument",
        error.NoInput => "no input file",
    };
}
