// SPDX-License-Identifier: MPL-2.0
//! The options shared by the command line and the conversion pipeline.
const std = @import("std");

pub const Layout = enum {
    elk,
    dagre,
    renderer_default,

    pub fn name(self: Layout) []const u8 {
        return switch (self) {
            .elk => "elk",
            .dagre => "dagre",
            .renderer_default => "renderer-default",
        };
    }
};

pub const Direction = enum {
    auto,
    td,
    lr,
    bt,
    rl,

    pub fn name(self: Direction) []const u8 {
        return switch (self) {
            .auto => "auto",
            .td => "TD",
            .lr => "LR",
            .bt => "BT",
            .rl => "RL",
        };
    }
};

pub const ConfigSource = union(enum) {
    none,
    inline_json: []const u8,
    file: []const u8,
};

/// What to do with the pictures a drawing embeds.
pub const Images = union(enum) {
    none,
    /// `<stem>-images` next to the diagram.
    automatic,
    directory: []const u8,

    pub const Resolved = struct {
        /// Where the pictures are written, relative to the working directory.
        directory: []const u8,
        /// How the diagram names them; a relative reference resolves against
        /// the diagram, not against the working directory.
        reference: []const u8,
    };

    pub fn resolve(
        self: Images,
        allocator: std.mem.Allocator,
        output_path: ?[]const u8,
        input_path: ?[]const u8,
    ) error{OutOfMemory}!?Resolved {
        return switch (self) {
            .none => null,
            .directory => |path| .{
                .directory = try besideTheDiagramDirectory(allocator, output_path, path),
                .reference = path,
            },
            .automatic => blk: {
                const directory = try besideTheDiagram(
                    allocator,
                    output_path orelse documentPath(input_path) orelse "yed2mermaid",
                );
                break :blk .{
                    .directory = directory,
                    .reference = std.fs.path.basename(directory),
                };
            },
        };
    }
};

/// A directory given on the command line is read relative to the diagram: it is
/// what the diagram has to say, and the diagram is what the reader sees.
fn besideTheDiagramDirectory(
    allocator: std.mem.Allocator,
    output_path: ?[]const u8,
    given: []const u8,
) error{OutOfMemory}![]const u8 {
    if (std.fs.path.isAbsolute(given)) return given;
    const output = output_path orelse return given;
    return std.fs.path.join(allocator, &.{ std.fs.path.dirname(output) orelse ".", given });
}

fn documentPath(path: ?[]const u8) ?[]const u8 {
    const value = path orelse return null;
    return if (std.mem.eql(u8, value, "-")) null else value;
}

/// `charts/flow.mmd` -> `charts/flow-images`, so the pictures sit next to the
/// diagram and a relative reference in it resolves.
fn besideTheDiagram(allocator: std.mem.Allocator, path: []const u8) error{OutOfMemory}![]const u8 {
    const extension = std.fs.path.extension(path);
    return std.fmt.allocPrint(allocator, "{s}-images", .{path[0 .. path.len - extension.len]});
}

pub const Options = struct {
    direction: Direction = .auto,
    styling: bool = true,
    front_matter: bool = true,
    links: bool = false,
    quiet: bool = false,
    edge_filler: bool = true,
    images: Images = .none,
    layout: Layout = .elk,
    title: ?[]const u8 = null,
    config: ConfigSource = .none,
    output_path: ?[]const u8 = null,
    input_path: ?[]const u8 = null,
};

const testing = std.testing;

test "pictures are left out until asked for" {
    const images: Images = .none;
    try testing.expect(try images.resolve(testing.allocator, "chart.mmd", "chart.graphml") == null);
}

test "the picture directory sits next to the diagram and is named from there" {
    const images: Images = .automatic;
    const resolved = (try images.resolve(testing.allocator, "charts/flow.mmd", "docs/flow.graphml")).?;
    defer testing.allocator.free(resolved.directory);

    try testing.expectEqualStrings("charts/flow-images", resolved.directory);
    try testing.expectEqualStrings("flow-images", resolved.reference);
}

test "without an output the pictures go next to the document" {
    const images: Images = .automatic;
    const resolved = (try images.resolve(testing.allocator, null, "docs/flow.graphml")).?;
    defer testing.allocator.free(resolved.directory);

    try testing.expectEqualStrings("docs/flow-images", resolved.directory);
    try testing.expectEqualStrings("flow-images", resolved.reference);
}

test "a document from stdin has nothing to sit next to" {
    const images: Images = .automatic;
    const resolved = (try images.resolve(testing.allocator, null, "-")).?;
    defer testing.allocator.free(resolved.directory);

    try testing.expectEqualStrings("yed2mermaid-images", resolved.directory);
    try testing.expectEqualStrings("yed2mermaid-images", resolved.reference);
}

test "a directory given on the command line is read relative to the diagram" {
    const images: Images = .{ .directory = "assets/pics" };
    const resolved = (try images.resolve(testing.allocator, "charts/flow.mmd", null)).?;
    defer testing.allocator.free(resolved.directory);

    try testing.expectEqualStrings("charts/assets/pics", resolved.directory);
    try testing.expectEqualStrings("assets/pics", resolved.reference);
}

test "an absolute picture directory is taken as it is" {
    const images: Images = .{ .directory = "/srv/pics" };
    const resolved = (try images.resolve(testing.allocator, "charts/flow.mmd", null)).?;

    try testing.expectEqualStrings("/srv/pics", resolved.directory);
    try testing.expectEqualStrings("/srv/pics", resolved.reference);
}
