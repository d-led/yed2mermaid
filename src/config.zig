// SPDX-License-Identifier: MPL-2.0
//! Builds the optional Mermaid front-matter block.
//!
//! Mermaid applies the documented `config:` front-matter (v10.5+) to the
//! diagram default configuration. The default here selects the ELK layout;
//! anything the user passes with `--config` wins, and keys are emitted in
//! sorted order so the output is byte-stable.
const std = @import("std");
const options = @import("options.zig");

pub const Error = error{
    OutOfMemory,
    InvalidConfig,
    WriteFailed,
};

pub const Settings = struct {
    layout: options.Layout = .elk,
    title: ?[]const u8 = null,
    config_json: ?[]const u8 = null,
};

const Entry = struct {
    key: []const u8,
    value: std.json.Value,
};

/// Returns the front-matter block (including the trailing `---` line), or null
/// when there is nothing to configure.
pub fn frontMatter(allocator: std.mem.Allocator, settings: Settings) Error!?[]const u8 {
    var entries: std.ArrayList(Entry) = .empty;
    var has_layout = false;

    if (settings.config_json) |text| {
        const value = std.json.parseFromSliceLeaky(std.json.Value, allocator, text, .{}) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InvalidConfig,
        };
        const object = switch (value) {
            .object => |map| map,
            else => return error.InvalidConfig,
        };
        for (object.keys()) |key| {
            if (std.mem.eql(u8, key, "layout")) has_layout = true;
            try entries.append(allocator, .{ .key = key, .value = object.get(key).? });
        }
    }

    if (settings.layout != .renderer_default and !has_layout) {
        try entries.append(allocator, .{ .key = "layout", .value = .{ .string = settings.layout.name() } });
    }

    if (entries.items.len == 0 and settings.title == null) return null;

    sortEntries(entries.items);

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();
    const writer = &output.writer;

    try writer.writeAll("---\n");
    if (settings.title) |title| {
        try writer.writeAll("title: ");
        try writeScalar(writer, title);
        try writer.writeByte('\n');
    }
    if (entries.items.len > 0) {
        try writer.writeAll("config:");
        try writeEntries(writer, allocator, entries.items, 2);
        try writer.writeByte('\n');
    }
    try writer.writeAll("---\n");

    const block: []const u8 = try output.toOwnedSlice();
    return block;
}

fn writeEntries(
    writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
    entries: []const Entry,
    indent: usize,
) Error!void {
    for (entries) |entry| {
        try writer.writeByte('\n');
        try writeIndent(writer, indent);
        try writer.writeAll(entry.key);
        try writer.writeByte(':');
        if (isInline(entry.value)) {
            try writer.writeByte(' ');
            try writeInline(writer, entry.value);
        } else {
            try writeBlock(writer, allocator, entry.value, indent + 2);
        }
    }
}

fn sortedEntries(allocator: std.mem.Allocator, object: std.json.ObjectMap) Error![]Entry {
    var entries: std.ArrayList(Entry) = .empty;
    for (object.keys()) |key| {
        try entries.append(allocator, .{ .key = key, .value = object.get(key).? });
    }
    sortEntries(entries.items);
    return entries.toOwnedSlice(allocator);
}

fn sortEntries(entries: []Entry) void {
    std.mem.sort(Entry, entries, {}, struct {
        fn lessThan(_: void, left: Entry, right: Entry) bool {
            return std.mem.lessThan(u8, left.key, right.key);
        }
    }.lessThan);
}

fn isInline(value: std.json.Value) bool {
    return switch (value) {
        .object => |object| object.count() == 0,
        .array => |array| array.items.len == 0,
        else => true,
    };
}

fn writeBlock(
    writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
    value: std.json.Value,
    indent: usize,
) Error!void {
    switch (value) {
        .object => |object| {
            const entries = try sortedEntries(allocator, object);
            try writeEntries(writer, allocator, entries, indent);
        },
        .array => |array| {
            for (array.items) |item| {
                try writer.writeByte('\n');
                try writeIndent(writer, indent);
                try writer.writeAll("- ");
                if (isInline(item)) {
                    try writeInline(writer, item);
                } else {
                    try writeBlock(writer, allocator, item, indent + 2);
                }
            }
        },
        else => unreachable,
    }
}

fn writeInline(writer: *std.Io.Writer, value: std.json.Value) Error!void {
    switch (value) {
        .null => try writer.writeAll("null"),
        .bool => |flag| try writer.writeAll(if (flag) "true" else "false"),
        .integer => |number| try writer.print("{d}", .{number}),
        .float => |number| try writer.print("{d}", .{number}),
        .number_string => |text| try writer.writeAll(text),
        .string => |text| try writeScalar(writer, text),
        .object => try writer.writeAll("{}"),
        .array => try writer.writeAll("[]"),
    }
}

fn writeScalar(writer: *std.Io.Writer, text: []const u8) Error!void {
    if (!needsQuotes(text)) {
        try writer.writeAll(text);
        return;
    }
    try writer.writeByte('"');
    for (text) |byte| {
        switch (byte) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(byte),
        }
    }
    try writer.writeByte('"');
}

fn needsQuotes(text: []const u8) bool {
    if (text.len == 0) return true;
    if (std.ascii.isWhitespace(text[0]) or std.ascii.isWhitespace(text[text.len - 1])) return true;
    for (text) |byte| {
        if (std.mem.indexOfScalar(u8, ":#{}[],&*!|>'\"%@`", byte) != null) return true;
        if (byte == '\n' or byte == '\t') return true;
    }
    const reserved = [_][]const u8{ "true", "false", "null", "yes", "no", "on", "off", "~" };
    for (reserved) |word| {
        if (std.mem.eql(u8, text, word)) return true;
    }
    _ = std.fmt.parseFloat(f64, text) catch return false;
    return true;
}

fn writeIndent(writer: *std.Io.Writer, count: usize) Error!void {
    var remaining = count;
    while (remaining > 0) : (remaining -= 1) try writer.writeByte(' ');
}

fn lessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

const testing = std.testing;

fn render(allocator: std.mem.Allocator, settings: Settings) !?[]const u8 {
    return frontMatter(allocator, settings);
}

test "the default selects the elk layout" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const block = (try render(arena.allocator(), .{})).?;

    try testing.expectEqualStrings("---\nconfig:\n  layout: elk\n---\n", block);
}

test "user configuration is merged and keys are sorted" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const block = (try render(arena.allocator(), .{ .config_json = "{\"theme\":\"forest\"}" })).?;

    try testing.expectEqualStrings("---\nconfig:\n  layout: elk\n  theme: forest\n---\n", block);
}

test "a user layout wins over the default" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const block = (try render(arena.allocator(), .{ .config_json = "{\"layout\":\"dagre\"}" })).?;

    try testing.expectEqualStrings("---\nconfig:\n  layout: dagre\n---\n", block);
}

test "renderer-default emits no layout key" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    try testing.expectEqual(@as(?[]const u8, null), try render(arena.allocator(), .{ .layout = .renderer_default }));
}

test "a title alone still produces front-matter" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const block = (try render(arena.allocator(), .{
        .layout = .renderer_default,
        .title = "My chart",
    })).?;

    try testing.expectEqualStrings("---\ntitle: My chart\n---\n", block);
}

test "nested objects are indented and sorted" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const block = (try render(arena.allocator(), .{
        .config_json = "{\"flowchart\":{\"curve\":\"linear\",\"htmlLabels\":true}}",
    })).?;

    try testing.expectEqualStrings(
        "---\nconfig:\n  flowchart:\n    curve: linear\n    htmlLabels: true\n  layout: elk\n---\n",
        block,
    );
}

test "a title needing quotes is escaped" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const block = (try render(arena.allocator(), .{
        .layout = .renderer_default,
        .title = "a: b",
    })).?;

    try testing.expectEqualStrings("---\ntitle: \"a: b\"\n---\n", block);
}

test "invalid json is rejected" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    try testing.expectError(error.InvalidConfig, render(arena.allocator(), .{ .config_json = "{not json" }));
}

test "a non-object json document is rejected" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    try testing.expectError(error.InvalidConfig, render(arena.allocator(), .{ .config_json = "[1, 2]" }));
}
