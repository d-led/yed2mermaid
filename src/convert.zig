// SPDX-License-Identifier: MPL-2.0
//! The single entry point used by the command line and by the tests.
const std = @import("std");
const xml = @import("xml.zig");
const yed = @import("yed.zig");
const model = @import("model.zig");
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

pub const Request = struct {
    options: options.Options = .{},
    /// Already resolved content of `--config`, if any.
    config_json: ?[]const u8 = null,
    /// How the diagram refers to the extracted pictures; null leaves them out
    /// of the diagram.
    images: ?[]const u8 = null,
};

pub const PictureFile = struct {
    /// File name inside the extraction directory.
    name: []const u8,
    content: []const u8,
};

pub const Result = struct {
    text: []const u8,
    /// Pictures to write into the extraction directory, in document order.
    pictures: []const PictureFile = &.{},
};

/// Converts one yEd GraphML document into Mermaid text and the pictures it
/// refers to.
pub fn convert(
    allocator: std.mem.Allocator,
    input: []const u8,
    request: Request,
    diag: *diagnostics.Diagnostics,
) Error!Result {
    const opts = request.options;
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

    const front: ?[]const u8 = if (opts.front_matter) try frontMatter(allocator, opts, request.config_json, diag) else null;

    const body = mermaid.render(allocator, diagram, .{
        .styling = opts.styling,
        .links = opts.links,
        .edge_filler = opts.edge_filler,
        .direction = opts.direction,
        .images = request.images,
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
    return .{
        .text = text,
        .pictures = if (request.images == null)
            &.{}
        else
            try collectPictures(allocator, diagram.items),
    };
}

fn collectPictures(allocator: std.mem.Allocator, items: []const model.Item) Error![]const PictureFile {
    var pictures: std.ArrayList(PictureFile) = .empty;
    try appendPictures(allocator, items, &pictures);
    return pictures.toOwnedSlice(allocator);
}

fn appendPictures(
    allocator: std.mem.Allocator,
    items: []const model.Item,
    pictures: *std.ArrayList(PictureFile),
) Error!void {
    for (items) |item| switch (item) {
        .node => |node| {
            const picture = node.picture orelse continue;
            const content = picture.content orelse continue;
            const extension = picture.extension orelse continue;
            try pictures.append(allocator, .{
                .name = try mermaid.pictureName(allocator, node.id, extension),
                .content = content,
            });
        },
        .group => |group| try appendPictures(allocator, group.items, pictures),
    };
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
    const result = try convertFileWith(allocator, path, .{ .options = opts });
    return .{ .text = result.text, .diag = result.diag };
}

fn convertFileWith(allocator: std.mem.Allocator, path: []const u8, request: Request) !struct {
    text: []const u8,
    pictures: []const PictureFile,
    diag: diagnostics.Diagnostics,
} {
    const source = try readFixture(allocator, path);
    var diag = diagnostics.Diagnostics.init(allocator);
    const result = try convert(allocator, source, request, &diag);
    return .{ .text = result.text, .pictures = result.pictures, .diag = diag };
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

test "a picture that is not extracted is announced and styled as unknown" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const result = try convertFile(arena.allocator(), "example/example.graphml", .{});

    try testing.expect(std.mem.indexOf(u8, result.text, "%% yed2mermaid: the picture of node n6 is left out") != null);
    try testing.expect(std.mem.indexOf(u8, result.text, "%% yed2mermaid: the picture of node n3::n0 is left out") != null);
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

    try testing.expectError(error.InvalidInput, convert(arena.allocator(), "<graphml><graph>", .{}, &diag));
    try testing.expectEqual(@as(usize, 1), diag.warnings.items.len);
}

test "extracting pictures returns one file per embedded picture" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const result = try convertFileWith(arena.allocator(), "example/example.graphml", .{
        .options = .{},
        .images = "example-images",
    });

    try testing.expectEqual(@as(usize, 3), result.pictures.len);
    try testing.expectEqualStrings("n3_n0.svg", result.pictures[0].name);
    try testing.expectEqualStrings("n3_n1.svg", result.pictures[1].name);
    try testing.expectEqualStrings("n6.png", result.pictures[2].name);
    try testing.expect(std.mem.startsWith(u8, result.pictures[0].content, "<?xml") or
        std.mem.startsWith(u8, result.pictures[0].content, "<svg"));
    try testing.expect(std.mem.startsWith(u8, result.pictures[2].content, "\x89PNG"));
    try testing.expect(std.mem.indexOf(u8, result.text, "n3_n0@{ img: \"example-images/n3_n0.svg\"") != null);
}

test "without an extraction directory the pictures stay out of the result" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const result = try convertFileWith(arena.allocator(), "example/example.graphml", .{ .options = .{} });

    try testing.expectEqual(@as(usize, 0), result.pictures.len);
    try testing.expect(std.mem.indexOf(u8, result.text, "@{ img:") == null);
    try testing.expect(std.mem.indexOf(u8, result.text, "style n6 fill:#F8F8FF") != null);
}

test "the example outputs are regenerated from their fixtures" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const examples = [_]struct {
        fixture: []const u8,
        output: []const u8,
        opts: options.Options,
        images: ?[]const u8 = null,
    }{
        .{ .fixture = "example/example.graphml", .output = "example/example.mmd", .opts = .{} },
        .{ .fixture = "example/example.graphml", .output = "example/example.plain.mmd", .opts = .{ .styling = false } },
        .{ .fixture = "example/example.graphml", .output = "example/example.images.mmd", .opts = .{}, .images = "pictures" },
        .{ .fixture = "example/palette.graphml", .output = "example/palette.mmd", .opts = .{} },
    };

    for (examples) |example| {
        const result = try convertFileWith(arena.allocator(), example.fixture, .{
            .options = example.opts,
            .images = example.images,
        });
        try testing.expect(std.mem.indexOf(u8, result.text, "flowchart ") != null);
        try std.Io.Dir.cwd().writeFile(testing.io, .{ .sub_path = example.output, .data = result.text });
    }
}
