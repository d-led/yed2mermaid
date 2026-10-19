// SPDX-License-Identifier: MPL-2.0
//! Renders the neutral diagram model as Mermaid flowchart text.
//!
//! Rules that matter for correctness:
//!  * every group becomes a `subgraph`, nested as in the document;
//!  * an edge is emitted in the lowest common ancestor of its endpoints, so
//!    internal edges stay inside their subgraph and crossing edges do not;
//!  * `linkStyle` indexes are the emission order of all links, counted once.
const std = @import("std");
const model = @import("model.zig");
const options = @import("options.zig");
const diagnostics = @import("diagnostics.zig");
const shapes = @import("shapes.zig");

pub const Error = error{
    OutOfMemory,
    WriteFailed,
    InvalidDiagram,
};

pub const RenderOptions = struct {
    styling: bool = true,
    links: bool = false,
    direction: options.Direction = .auto,
};

const unknown_style = "fill:#F8F8FF,stroke:#7B1FA2,stroke-width:2px,stroke-dasharray:4 4,color:#4A148C";

pub fn render(
    allocator: std.mem.Allocator,
    diagram: model.Diagram,
    render_options: RenderOptions,
    diag: *diagnostics.Diagnostics,
) Error![]const u8 {
    var ids = IdTables.init(allocator);
    try collectIds(&ids, diagram.items);

    const containers = try allocator.alloc(?[]const u8, diagram.edges.len);
    for (diagram.edges, 0..) |edge, index| {
        containers[index] = containerOf(&ids, edge);
    }

    var output: std.Io.Writer.Allocating = .init(allocator);
    defer output.deinit();

    var emitter: Emitter = .{
        .allocator = allocator,
        .writer = &output.writer,
        .ids = &ids,
        .edges = diagram.edges,
        .containers = containers,
        .output_indexes = try allocator.alloc(usize, diagram.edges.len),
        .statements = .empty,
        .diagnostics = diag,
        .render_options = render_options,
        .links_emitted = 0,
    };

    const direction = resolveDirection(&ids, diagram, render_options.direction);
    try emitter.writer.print("flowchart {s}\n", .{direction.name()});
    try emitter.emitItems(diagram.items, 1, null);

    if (render_options.styling) {
        for (emitter.statements.items) |statement| {
            try emitter.writer.print("{s}\n", .{statement});
        }
        for (diagram.edges, 0..) |edge, index| {
            try emitter.emitLinkStyle(edge, emitter.output_indexes[index]);
        }
    }

    const text: []const u8 = try output.toOwnedSlice();
    return text;
}

const Emitter = struct {
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    ids: *IdTables,
    edges: []const model.Edge,
    containers: []const ?[]const u8,
    output_indexes: []usize,
    statements: std.ArrayList([]const u8),
    diagnostics: *diagnostics.Diagnostics,
    render_options: RenderOptions,
    links_emitted: usize,

    fn emitItems(self: *Emitter, items: []const model.Item, indent: usize, container: ?[]const u8) Error!void {
        for (items) |*item| {
            switch (item.*) {
                .node => |node| try self.emitNode(&node, indent),
                .group => {
                    const group = &item.group;
                    try self.emitGroup(group, indent);
                },
            }
        }
        try self.emitEdgesFor(container, indent);
    }

    fn emitNode(self: *Emitter, node: *const model.Node, indent: usize) Error!void {
        const id = self.ids.ids.get(node.id) orelse return error.InvalidDiagram;

        if (node.note) |note| {
            try writeIndent(self.writer, indent);
            try self.writer.print("%% yed2mermaid: {s}\n", .{note});
        }

        try writeIndent(self.writer, indent);
        try self.writer.writeAll(id);
        try writeShapeStart(self.writer, node.shape);
        try writeLabel(self.writer, node.label);
        try writeShapeEnd(self.writer, node.shape);
        try self.writer.writeByte('\n');

        if (!self.render_options.styling) return;
        try self.recordStyle(id, node.style, node.treatment == .unknown);

        if (self.render_options.links) {
            if (node.url) |url| {
                const statement = try std.fmt.allocPrint(self.allocator, "click {s} \"{s}\"", .{ id, url });
                try self.statements.append(self.allocator, statement);
            }
        }
    }

    fn emitGroup(self: *Emitter, group: *const model.Group, indent: usize) Error!void {
        const id = self.ids.ids.get(group.id) orelse return error.InvalidDiagram;

        try writeIndent(self.writer, indent);
        try self.writer.writeAll("subgraph ");
        try self.writer.writeAll(id);
        try self.writer.writeAll("[\"");
        try writeLabel(self.writer, group.title);
        try self.writer.writeAll("\"]\n");

        try self.emitItems(group.items, indent + 1, group.id);

        try writeIndent(self.writer, indent);
        try self.writer.writeAll("end\n");

        if (!self.render_options.styling) return;
        try self.recordStyle(id, group.style, false);
    }

    fn emitEdgesFor(self: *Emitter, container: ?[]const u8, indent: usize) Error!void {
        for (self.edges, 0..) |edge, index| {
            if (!sameContainer(self.containers[index], container)) continue;
            try self.emitEdge(edge, indent, index);
        }
    }

    fn emitEdge(self: *Emitter, edge: model.Edge, indent: usize, index: usize) Error!void {
        const source = self.ids.ids.get(edge.source) orelse return error.InvalidDiagram;
        const target = self.ids.ids.get(edge.target) orelse return error.InvalidDiagram;

        const has_label = edge.label != null;
        const connector = connectorFor(edge, has_label);
        if (connector.approximate) {
            try self.diagnostics.warn(
                "edge {s} uses arrow heads Mermaid cannot express exactly; drawn with standard heads",
                .{edge.id},
            );
        }

        try writeIndent(self.writer, indent);
        try self.writer.writeAll(source);
        try self.writer.writeByte(' ');
        try self.writer.writeAll(connector.left);
        if (edge.label) |label| {
            try self.writer.writeAll(" \"");
            try writeLabel(self.writer, label);
            try self.writer.writeAll("\" ");
        }
        try self.writer.writeAll(connector.right);
        try self.writer.writeByte(' ');
        try self.writer.writeAll(target);
        try self.writer.writeByte('\n');

        self.output_indexes[index] = self.links_emitted;
        self.links_emitted += 1;
    }

    fn recordStyle(self: *Emitter, id: []const u8, style: model.Style, unknown: bool) Error!void {
        var props: std.Io.Writer.Allocating = .init(self.allocator);
        defer props.deinit();

        if (unknown) {
            try props.writer.writeAll(unknown_style);
        } else {
            var first = true;
            if (!style.fill_visible) {
                try appendProperty(&props.writer, &first, "fill:none");
            } else if (style.fill) |fill| {
                try props.writer.print("fill:{s}", .{fill});
                first = false;
            }
            if (style.stroke) |stroke| {
                try appendProperty(&props.writer, &first, "stroke:");
                try props.writer.writeAll(stroke);
            }
            if (style.stroke_width > 0) {
                try appendProperty(&props.writer, &first, "stroke-width:");
                try props.writer.print("{d}px", .{style.stroke_width});
            }
            try appendDashPattern(&props.writer, &first, style.stroke_kind);
            if (style.text_color) |color| {
                try appendProperty(&props.writer, &first, "color:");
                try props.writer.writeAll(color);
            }
        }

        if (props.written().len == 0) return;
        const statement = try std.fmt.allocPrint(self.allocator, "style {s} {s}", .{ id, props.written() });
        try self.statements.append(self.allocator, statement);
    }

    fn emitLinkStyle(self: *Emitter, edge: model.Edge, output_index: usize) Error!void {
        var props: std.Io.Writer.Allocating = .init(self.allocator);
        defer props.deinit();

        var first = true;
        if (edge.width != 1) {
            try appendProperty(&props.writer, &first, "stroke-width:");
            try props.writer.print("{d}px", .{edge.width});
        }
        try appendDashPattern(&props.writer, &first, edge.line);

        if (props.written().len == 0) return;
        try self.writer.print("linkStyle {d} {s}\n", .{ output_index, props.written() });
    }
};

fn appendProperty(writer: *std.Io.Writer, first: *bool, text: []const u8) Error!void {
    if (!first.*) try writer.writeByte(',');
    first.* = false;
    try writer.writeAll(text);
}

fn appendDashPattern(writer: *std.Io.Writer, first: *bool, kind: model.LineKind) Error!void {
    switch (kind) {
        .solid => {},
        .dashed => try appendProperty(writer, first, "stroke-dasharray:5 5"),
        .dotted => try appendProperty(writer, first, "stroke-dasharray:2 2"),
    }
}

const IdTables = struct {
    allocator: std.mem.Allocator,
    ids: std.StringHashMap([]const u8),
    taken: std.StringHashMap(void),
    paths: std.StringHashMap([]const *const model.Group),
    rects: std.StringHashMap(model.Rect),

    fn init(allocator: std.mem.Allocator) IdTables {
        return .{
            .allocator = allocator,
            .ids = std.StringHashMap([]const u8).init(allocator),
            .taken = std.StringHashMap(void).init(allocator),
            .paths = std.StringHashMap([]const *const model.Group).init(allocator),
            .rects = std.StringHashMap(model.Rect).init(allocator),
        };
    }

    fn assign(self: *IdTables, raw: []const u8) Error![]const u8 {
        if (self.ids.get(raw)) |existing| return existing;

        const base = try sanitizeId(self.allocator, raw);
        var candidate = base;
        var suffix: usize = 2;
        while (self.taken.contains(candidate)) : (suffix += 1) {
            candidate = try std.fmt.allocPrint(self.allocator, "{s}_{d}", .{ base, suffix });
        }
        try self.ids.put(raw, candidate);
        try self.taken.put(candidate, {});
        return candidate;
    }
};

fn collectIds(ids: *IdTables, items: []const model.Item) Error!void {
    var stack: std.ArrayList(*const model.Group) = .empty;
    defer stack.deinit(ids.allocator);
    try collectInto(ids, items, &stack);
}

fn collectInto(ids: *IdTables, items: []const model.Item, stack: *std.ArrayList(*const model.Group)) Error!void {
    for (items) |*item| {
        switch (item.*) {
            .node => {
                const node = &item.node;
                _ = try ids.assign(node.id);
                try ids.paths.put(node.id, try ids.allocator.dupe(*const model.Group, stack.items));
                try ids.rects.put(node.id, node.rect);
            },
            .group => {
                const group = &item.group;
                _ = try ids.assign(group.id);
                // An edge that points at a group belongs to the group's parent:
                // the subgraph itself is the target, so the link is external.
                try ids.paths.put(group.id, try ids.allocator.dupe(*const model.Group, stack.items));
                try ids.rects.put(group.id, group.rect);

                try stack.append(ids.allocator, group);
                try collectInto(ids, group.items, stack);
                _ = stack.pop();
            },
        }
    }
}

fn containerOf(ids: *IdTables, edge: model.Edge) ?[]const u8 {
    const source_path = ids.paths.get(edge.source) orelse return null;
    const target_path = ids.paths.get(edge.target) orelse return null;

    var common: usize = 0;
    while (common < source_path.len and common < target_path.len and
        source_path[common] == target_path[common]) : (common += 1)
    {}
    if (common == 0) return null;
    return source_path[common - 1].id;
}

fn sameContainer(left: ?[]const u8, right: ?[]const u8) bool {
    if (left == null and right == null) return true;
    if (left == null or right == null) return false;
    return std.mem.eql(u8, left.?, right.?);
}

fn resolveDirection(ids: *IdTables, diagram: model.Diagram, requested: options.Direction) options.Direction {
    if (requested != .auto) return requested;

    var horizontal: f32 = 0;
    var vertical: f32 = 0;
    for (diagram.edges) |edge| {
        const source = ids.rects.get(edge.source) orelse continue;
        const target = ids.rects.get(edge.target) orelse continue;
        horizontal += target.centerX() - source.centerX();
        vertical += target.centerY() - source.centerY();
    }

    if (@abs(vertical) >= @abs(horizontal)) {
        return if (vertical >= 0) .td else .bt;
    }
    return if (horizontal >= 0) .lr else .rl;
}

fn sanitizeId(allocator: std.mem.Allocator, raw: []const u8) Error![]const u8 {
    var buffer: std.ArrayList(u8) = .empty;
    var previous_was_separator = false;
    for (raw, 0..) |byte, index| {
        const valid = std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '-';
        if (!valid) {
            if (!previous_was_separator) {
                if (buffer.items.len == 0) {
                    try buffer.append(allocator, 'n');
                }
                try buffer.append(allocator, '_');
            }
            previous_was_separator = true;
            continue;
        }
        if (index == 0 and std.ascii.isDigit(byte)) try buffer.append(allocator, 'n');
        try buffer.append(allocator, byte);
        previous_was_separator = false;
    }
    if (buffer.items.len == 0) try buffer.append(allocator, 'n');
    return buffer.toOwnedSlice(allocator);
}

const Connector = struct {
    left: []const u8,
    right: []const u8,
    approximate: bool = false,
};

fn connectorFor(edge: model.Edge, has_label: bool) Connector {
    const dotted = edge.line != .solid;
    const left_head = head(edge.source_arrow, true);
    const right_head = head(edge.target_arrow, false);
    const standard_heads = (left_head.len == 0 or std.mem.eql(u8, left_head, "<")) and
        (right_head.len == 0 or std.mem.eql(u8, right_head, ">"));

    if (dotted) {
        if (has_label) return .{ .left = "-.", .right = ".->", .approximate = !standard_heads };
        return .{ .left = "-.->", .right = "", .approximate = !standard_heads };
    }

    if (!has_label) {
        if (left_head.len == 0 and right_head.len == 0) return .{ .left = "---", .right = "" };
        if (left_head.len == 0) {
            if (std.mem.eql(u8, right_head, ">")) return .{ .left = "-->", .right = "" };
            if (std.mem.eql(u8, right_head, "o")) return .{ .left = "--o", .right = "" };
            return .{ .left = "--x", .right = "" };
        }
        if (right_head.len == 0) {
            if (std.mem.eql(u8, left_head, "<")) return .{ .left = "<--", .right = "" };
            if (std.mem.eql(u8, left_head, "o")) return .{ .left = "o--", .right = "" };
            return .{ .left = "x--", .right = "" };
        }
        return .{ .left = "<-->", .right = "", .approximate = !standard_heads };
    }

    if (left_head.len == 0 and right_head.len == 0) return .{ .left = "--", .right = "---" };
    if (left_head.len == 0) {
        if (std.mem.eql(u8, right_head, ">")) return .{ .left = "--", .right = "-->" };
        if (std.mem.eql(u8, right_head, "o")) return .{ .left = "--", .right = "--o" };
        return .{ .left = "--", .right = "--x" };
    }
    if (std.mem.eql(u8, right_head, ">") and std.mem.eql(u8, left_head, "<")) {
        return .{ .left = "<--", .right = "-->" };
    }
    return .{ .left = "<--", .right = "-->", .approximate = true };
}

fn head(arrow: model.Arrow, source: bool) []const u8 {
    return switch (arrow) {
        .none => "",
        .standard => if (source) "<" else ">",
        .circle => "o",
        .diamond => "x",
        .other => "",
    };
}

fn writeShapeStart(writer: *std.Io.Writer, shape: shapes.Shape) Error!void {
    const prefix = switch (shape) {
        .rectangle => "[",
        .rounded => "(",
        .stadium => "([",
        .diamond => "{",
        .hexagon => "{{",
        .parallelogram => "[/",
        .trapezoid => "[/",
        .subroutine => "[[",
        .cylinder => "[(",
        .circle => "((",
        .asymmetric => ">",
    };
    try writer.writeAll(prefix);
    try writer.writeByte('"');
}

fn writeShapeEnd(writer: *std.Io.Writer, shape: shapes.Shape) Error!void {
    switch (shape) {
        .rectangle => try writer.writeAll("\"]"),
        .rounded => try writer.writeAll("\")"),
        .stadium => try writer.writeAll("\"])"),
        .diamond => try writer.writeAll("\"}"),
        .hexagon => try writer.writeAll("\"}}"),
        .parallelogram => try writer.writeAll("\"/]"),
        .trapezoid => try writer.writeAll("\"\\]"),
        .subroutine => try writer.writeAll("\"]]"),
        .cylinder => try writer.writeAll("\")]"),
        .circle => try writer.writeAll("\"))"),
        .asymmetric => try writer.writeAll("\"]"),
    }
}

fn writeLabel(writer: *std.Io.Writer, text: []const u8) Error!void {
    for (text) |byte| {
        switch (byte) {
            '"' => try writer.writeAll("#quot;"),
            '\n' => try writer.writeAll("<br/>"),
            else => try writer.writeByte(byte),
        }
    }
}

fn writeIndent(writer: *std.Io.Writer, count: usize) Error!void {
    var remaining = count;
    while (remaining > 0) : (remaining -= 1) try writer.writeAll("  ");
}

const testing = std.testing;

fn testNode(id: []const u8, label: []const u8, rect: model.Rect) model.Node {
    return .{
        .id = id,
        .label = label,
        .shape = .rectangle,
        .treatment = .exact,
        .style = .{ .fill = "#FFCC00", .stroke = "#000000" },
        .rect = rect,
    };
}

fn sampleDiagram(allocator: std.mem.Allocator) !model.Diagram {
    const inner = try allocator.dupe(model.Item, &.{
        .{ .node = testNode("g1::a", "Inner", .{ .x = 0, .y = 0, .width = 10, .height = 10 }) },
    });
    const items = try allocator.dupe(model.Item, &.{
        .{ .group = .{
            .id = "g1",
            .title = "Group 1",
            .style = .{ .fill = "#F5F5F5", .stroke = "#000000", .stroke_kind = .dashed },
            .rect = .{ .x = 0, .y = 0, .width = 50, .height = 50 },
            .items = inner,
        } },
        .{ .node = testNode("out", "Outside", .{ .x = 100, .y = 100, .width = 10, .height = 10 }) },
    });
    const edges = try allocator.dupe(model.Edge, &.{
        .{ .id = "e0", .source = "g1::a", .target = "out", .label = "go", .line = .dotted, .width = 2 },
        .{ .id = "e1", .source = "out", .target = "g1", .label = "into" },
    });
    return .{ .items = items, .edges = edges };
}

fn renderSample(allocator: std.mem.Allocator, render_options: RenderOptions) ![]const u8 {
    var diag = diagnostics.Diagnostics.init(allocator);
    const diagram = try sampleDiagram(allocator);
    return render(allocator, diagram, render_options, &diag);
}

test "nodes are nested inside the subgraph of their group" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const text = try renderSample(arena.allocator(), .{});

    try testing.expect(std.mem.indexOf(u8, text, "subgraph g1[\"Group 1\"]\n    g1_a[\"Inner\"]\n  end") != null);
}

test "an edge to a group is declared outside the subgraph" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const text = try renderSample(arena.allocator(), .{});

    try testing.expect(std.mem.indexOf(u8, text, "  out -- \"into\" --> g1\n") != null);
}

test "a dotted edge with a label keeps both" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const text = try renderSample(arena.allocator(), .{});

    try testing.expect(std.mem.indexOf(u8, text, "g1_a -. \"go\" .-> out") != null);
}

test "an edge whose width and dash pattern differ from the default is styled by index" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const text = try renderSample(arena.allocator(), .{});

    try testing.expect(std.mem.indexOf(u8, text, "linkStyle 0 stroke-width:2px,stroke-dasharray:2 2") != null);
    try testing.expect(std.mem.indexOf(u8, text, "linkStyle 1") == null);
}

test "node and group styles follow the document" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const text = try renderSample(arena.allocator(), .{});

    try testing.expect(std.mem.indexOf(u8, text, "style g1_a fill:#FFCC00,stroke:#000000,stroke-width:1px") != null);
    try testing.expect(std.mem.indexOf(u8, text, "style g1 fill:#F5F5F5,stroke:#000000,stroke-width:1px,stroke-dasharray:5 5") != null);
}

test "plain mode emits no style statements" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const text = try renderSample(arena.allocator(), .{ .styling = false });

    try testing.expect(std.mem.indexOf(u8, text, "style ") == null);
    try testing.expect(std.mem.indexOf(u8, text, "linkStyle ") == null);
}

test "an unknown node is styled so it stands out" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag = diagnostics.Diagnostics.init(arena.allocator());

    const items = try arena.allocator().dupe(model.Item, &.{
        .{ .node = .{
            .id = "pic",
            .label = "logo",
            .shape = .rectangle,
            .treatment = .unknown,
            .style = .{},
            .rect = .{},
            .note = "y:ImageNode is not mapped (node pic)",
        } },
    });
    const text = try render(arena.allocator(), .{ .items = items, .edges = &.{} }, .{}, &diag);

    try testing.expect(std.mem.indexOf(u8, text, "%% yed2mermaid: y:ImageNode is not mapped (node pic)") != null);
    try testing.expect(std.mem.indexOf(u8, text, "stroke:#7B1FA2") != null);
}

test "quotes in labels are escaped and colons in ids are sanitized" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag = diagnostics.Diagnostics.init(arena.allocator());

    const items = try arena.allocator().dupe(model.Item, &.{
        .{ .node = testNode("n1::n0", "say \"hi\"", .{}) },
    });
    const text = try render(arena.allocator(), .{ .items = items, .edges = &.{} }, .{}, &diag);

    try testing.expect(std.mem.indexOf(u8, text, "n1_n0[\"say #quot;hi#quot;\"]") != null);
}

test "a double arrow becomes a bidirectional link" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag = diagnostics.Diagnostics.init(arena.allocator());

    const items = try arena.allocator().dupe(model.Item, &.{
        .{ .node = testNode("a", "A", .{}) },
        .{ .node = testNode("b", "B", .{}) },
    });
    const edges = try arena.allocator().dupe(model.Edge, &.{
        .{ .id = "e", .source = "a", .target = "b", .source_arrow = .standard, .target_arrow = .standard },
    });
    const text = try render(arena.allocator(), .{ .items = items, .edges = edges }, .{}, &diag);

    try testing.expect(std.mem.indexOf(u8, text, "a <--> b") != null);
}

test "the direction follows the drawing when asked to auto" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const text = try renderSample(arena.allocator(), .{ .direction = .auto });

    try testing.expect(std.mem.startsWith(u8, text, "flowchart TD\n"));
}

const paint_properties = [_][]const u8{ "fill", "stroke", "stroke-width", "stroke-dasharray", "color" };

fn isPaintProperty(name: []const u8) bool {
    for (paint_properties) |property| {
        if (std.mem.eql(u8, property, name)) return true;
    }
    return false;
}

test "styles only set paint properties, never geometry" {
    // Mermaid sizes nodes from their labels. Touching width, height, padding or
    // font-size here would make the diagram fight the layout engine, so the
    // emitter must stay on paint-only properties.
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();

    const text = try renderSample(arena.allocator(), .{});

    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " ");
        if (!std.mem.startsWith(u8, trimmed, "style ")) continue;

        const after_keyword = trimmed["style ".len..];
        const id_end = std.mem.indexOfScalar(u8, after_keyword, ' ').?;
        const properties = after_keyword[id_end + 1 ..];

        var items = std.mem.splitScalar(u8, properties, ',');
        while (items.next()) |item| {
            const colon = std.mem.indexOfScalar(u8, item, ':').?;
            try testing.expect(isPaintProperty(item[0..colon]));
        }
    }
}
