// SPDX-License-Identifier: MPL-2.0
//! The single entry point used by the command line and by the tests.
const std = @import("std");
const xml = @import("xml.zig");
const yed = @import("yed.zig");
const config = @import("config.zig");
const mermaid = @import("mermaid.zig");
const options = @import("options.zig");
const diagnostics = @import("diagnostics.zig");

pub const Error = error{
    OutOfMemory,
    WriteFailed,
    InvalidInput,
    InvalidConfig,
};

/// Converts one yEd GraphML document into Mermaid text.
/// `config_json` is the already-resolved content of `--config`, if any.
pub fn convert(
    allocator: std.mem.Allocator,
    input: []const u8,
    opts: options.Options,
    config_json: ?[]const u8,
    diag: *diagnostics.Diagnostics,
) Error![]const u8 {
    var xml_diagnostic: xml.Diagnostic = .{};
    const root = xml.parse(allocator, input, &xml_diagnostic) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            try diag.warn("invalid XML at {d}:{d}: {s}", .{
                xml_diagnostic.line, xml_diagnostic.column, xml_diagnostic.message,
            });
            return error.InvalidInput;
        },
    };

    const diagram = yed.read(allocator, root, diag) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidInput,
    };

    const front: ?[]const u8 = if (opts.front_matter) try frontMatter(allocator, opts, config_json, diag) else null;

    const body = mermaid.render(allocator, diagram, .{
        .styling = opts.styling,
        .links = opts.links,
        .edge_filler = opts.edge_filler,
        .direction = opts.direction,
    }, diag) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.WriteFailed => return error.WriteFailed,
        error.InvalidDiagram => return error.InvalidInput,
    };

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    const writer = &output.writer;
    if (front) |block| try writer.writeAll(block);
    try writer.writeAll(body);

    const text: []const u8 = try output.toOwnedSlice();
    return text;
}

fn frontMatter(
    allocator: std.mem.Allocator,
    opts: options.Options,
    config_json: ?[]const u8,
    diag: *diagnostics.Diagnostics,
) Error!?[]const u8 {
    return config.frontMatter(allocator, .{
        .layout = opts.layout,
        .title = opts.title,
        .config_json = config_json,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.WriteFailed => return error.WriteFailed,
        error.InvalidConfig => {
            try diag.warn("the --config value must be a JSON object", .{});
            return error.InvalidConfig;
        },
    };
}

const testing = std.testing;

fn readFixture(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(testing.io, path, allocator, .limited(4 << 20));
}

fn convertFile(allocator: std.mem.Allocator, path: []const u8, opts: options.Options) !struct {
    text: []const u8,
    diag: diagnostics.Diagnostics,
} {
    const source = try readFixture(allocator, path);
    var diag = diagnostics.Diagnostics.init(allocator);
    const text = try convert(allocator, source, opts, null, &diag);
    return .{ .text = text, .diag = diag };
}

test "the example converts with front-matter, groups and edge labels" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const result = try convertFile(arena.allocator(), "example/example.graphml", .{});

    try testing.expect(std.mem.startsWith(u8, result.text, "---\nconfig:\n  layout: elk\n---\nflowchart TD\n"));
    try testing.expect(std.mem.indexOf(u8, result.text, "subgraph n1[\"Group 2\"]") != null);
    try testing.expect(std.mem.indexOf(u8, result.text, "n1_n1_n0 -. \"5-6 line\" .-> n1_n1_n1") != null);
    try testing.expect(std.mem.indexOf(u8, result.text, "n0 -- \"node 1 - group 1\" --> n1") != null);
}

test "unmapped picture nodes are announced and styled" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const result = try convertFile(arena.allocator(), "example/example.graphml", .{});

    try testing.expect(std.mem.indexOf(u8, result.text, "y:ImageNode is not mapped (node n6)") != null);
    try testing.expect(std.mem.indexOf(u8, result.text, "y:SVGNode is not mapped (node n3::n0)") != null);
    try testing.expect(std.mem.indexOf(u8, result.text, "stroke:#7B1FA2") != null);
}

test "plain output carries neither front-matter nor styles" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const result = try convertFile(arena.allocator(), "example/example.graphml", .{ .styling = false, .front_matter = false });

    try testing.expect(std.mem.startsWith(u8, result.text, "flowchart TD\n"));
    try testing.expect(std.mem.indexOf(u8, result.text, "style ") == null);
    try testing.expect(std.mem.indexOf(u8, result.text, "linkStyle ") == null);
}

test "an invalid document is reported with its position" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag = diagnostics.Diagnostics.init(arena.allocator());

    try testing.expectError(error.InvalidInput, convert(arena.allocator(), "<graphml><graph>", .{}, null, &diag));
    try testing.expectEqual(@as(usize, 1), diag.warnings.items.len);
}

test "the example outputs are regenerated from their fixtures" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const examples = [_]struct {
        fixture: []const u8,
        output: []const u8,
        opts: options.Options,
    }{
        .{ .fixture = "example/example.graphml", .output = "example/example.mmd", .opts = .{} },
        .{ .fixture = "example/example.graphml", .output = "example/example.plain.mmd", .opts = .{ .styling = false } },
        .{ .fixture = "example/palette.graphml", .output = "example/palette.mmd", .opts = .{} },
    };

    for (examples) |example| {
        const result = try convertFile(arena.allocator(), example.fixture, example.opts);
        try testing.expect(std.mem.indexOf(u8, result.text, "flowchart ") != null);
        try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = example.output, .data = result.text });
    }
}
