// SPDX-License-Identifier: MPL-2.0
//! Reads yEd's GraphML flavour into the neutral diagram model.
//!
//! The reader is deliberately realizer-agnostic: instead of knowing every
//! yFiles realizer, it takes the active realizer of a node and reads the first
//! `Geometry`, `Fill`, `BorderStyle`, `NodeLabel` and `Shape` found there.
//! Group nodes are recognised by `yfiles.foldertype="group"` (or a nested
//! `<graph>`), never by the realizer type.
const std = @import("std");
const xml = @import("xml.zig");
const shapes = @import("shapes.zig");
const model = @import("model.zig");
const diagnostics = @import("diagnostics.zig");

pub const Error = error{
    OutOfMemory,
    NotGraphMl,
    InvalidGraph,
};

pub fn read(
    allocator: std.mem.Allocator,
    root: *xml.Element,
    diag: *diagnostics.Diagnostics,
) Error!model.Diagram {
    if (!std.mem.eql(u8, xml.localName(root.name), "graphml")) return error.NotGraphMl;

    const graph = root.child("graph") orelse root.firstDescendant("graph") orelse return error.NotGraphMl;

    var context: Context = .{
        .allocator = allocator,
        .keys = try keyNames(allocator, root),
        .diagnostics = diag,
    };

    var items: std.ArrayList(model.Item) = .empty;
    var edges: std.ArrayList(model.Edge) = .empty;
    try context.readGraph(graph, &items, &edges);

    const diagram: model.Diagram = .{
        .items = try items.toOwnedSlice(allocator),
        .edges = try edges.toOwnedSlice(allocator),
    };
    try validateEndpoints(allocator, diagram, diag);
    return diagram;
}

const Context = struct {
    allocator: std.mem.Allocator,
    keys: std.StringHashMap([]const u8),
    diagnostics: *diagnostics.Diagnostics,

    fn readGraph(
        self: *Context,
        graph: *xml.Element,
        items: *std.ArrayList(model.Item),
        edges: *std.ArrayList(model.Edge),
    ) Error!void {
        for (graph.children) |child| {
            const name = xml.localName(child.name);
            if (std.mem.eql(u8, name, "node")) {
                try items.append(self.allocator, try self.readNode(child, edges));
            } else if (std.mem.eql(u8, name, "edge")) {
                try edges.append(self.allocator, try self.readEdge(child));
            }
        }
    }

    fn readNode(self: *Context, element: *xml.Element, edges: *std.ArrayList(model.Edge)) Error!model.Item {
        const id = element.attribute("id") orelse return error.InvalidGraph;
        const graphics = findGraphics(element) orelse return error.InvalidGraph;
        const realizer_element = activeRealizer(graphics.element);
        const realizer = xml.localName(realizer_element.name);
        const style = readStyle(realizer_element);
        const rect = readRect(realizer_element.firstDescendant("Geometry"));
        const is_group = isGroup(element);

        if (is_group) {
            const title = labelText(realizer_element) orelse "Group";
            var children: std.ArrayList(model.Item) = .empty;
            if (element.child("graph")) |nested| try self.readGraph(nested, &children, edges);
            return .{ .group = .{
                .id = id,
                .title = title,
                .style = style,
                .rect = rect,
                .items = try children.toOwnedSlice(self.allocator),
            } };
        }

        const resolution = try self.resolve(realizer, realizer_element, id);
        const label = if (std.mem.eql(u8, realizer, "UMLClassNode"))
            try self.umlLabel(realizer_element)
        else
            labelText(realizer_element) orelse id;

        return .{ .node = .{
            .id = id,
            .label = label,
            .shape = resolution.shape,
            .treatment = resolution.treatment,
            .style = style,
            .rect = rect,
            .url = self.urlOf(element),
            .note = resolution.note,
        } };
    }

    fn readEdge(self: *Context, element: *xml.Element) Error!model.Edge {
        _ = self;
        var edge: model.Edge = .{
            .id = element.attribute("id") orelse "",
            .source = element.attribute("source") orelse return error.InvalidGraph,
            .target = element.attribute("target") orelse return error.InvalidGraph,
        };

        if (element.firstDescendant("LineStyle")) |line_style| {
            if (line_style.attribute("type")) |raw| edge.line = lineKind(raw);
            if (line_style.attribute("width")) |raw| edge.width = parseFloat(raw, 1);
        }
        if (element.firstDescendant("Arrows")) |arrows| {
            if (arrows.attribute("source")) |raw| edge.source_arrow = arrowKind(raw);
            if (arrows.attribute("target")) |raw| edge.target_arrow = arrowKind(raw);
        }
        edge.label = labelText(element);
        return edge;
    }

    fn resolve(
        self: *Context,
        realizer: []const u8,
        element: *xml.Element,
        id: []const u8,
    ) Error!Resolved {
        if (isPicture(realizer)) {
            const note = try std.fmt.allocPrint(self.allocator, "y:{s} is not mapped (node {s})", .{ realizer, id });
            try self.diagnostics.warnings.append(self.allocator, .{ .message = note });
            return .{ .shape = .rectangle, .treatment = .unknown, .note = note };
        }

        const configuration = element.attribute("configuration");
        const shape_type = if (element.firstDescendant("Shape")) |shape| shape.attribute("type") else null;
        const bpmn_type = bpmnType(element);

        var resolution: ?shapes.Resolution = null;
        if (configuration) |qualified| {
            if (std.mem.startsWith(u8, qualified, "com.yworks.bpmn.")) {
                resolution = shapes.findBpmn(qualified, bpmn_type);
            }
            if (resolution == null) resolution = shapes.findByConfiguration(qualified);
        }
        if (resolution == null) {
            if (shape_type) |raw| resolution = shapes.findByShapeType(raw);
        }

        if (resolution == null) {
            // A vector realizer we do not know: a labelled rectangle is still a
            // faithful stand-in, so it is approximate rather than unknown.
            const note = try self.approximationNote(realizer, configuration, .rectangle, id);
            try self.diagnostics.warnings.append(self.allocator, .{ .message = note });
            return .{ .shape = .rectangle, .treatment = .approximate, .note = note };
        }

        const resolved = resolution.?;
        if (resolved.treatment == .exact) {
            return .{ .shape = resolved.shape, .treatment = .exact, .note = null };
        }
        const note = try self.approximationNote(realizer, configuration, resolved.shape, id);
        try self.diagnostics.warnings.append(self.allocator, .{ .message = note });
        return .{ .shape = resolved.shape, .treatment = resolved.treatment, .note = note };
    }

    fn approximationNote(
        self: *Context,
        realizer: []const u8,
        configuration: ?[]const u8,
        shape: shapes.Shape,
        id: []const u8,
    ) Error![]const u8 {
        if (configuration) |qualified| {
            return std.fmt.allocPrint(self.allocator, "{s} is drawn as {s} (node {s})", .{
                qualified, shapes.shapeName(shape), id,
            });
        }
        return std.fmt.allocPrint(self.allocator, "y:{s} is drawn as {s} (node {s})", .{
            realizer, shapes.shapeName(shape), id,
        });
    }

    /// yEd's UML class node carries its members in nested labels. A Mermaid
    /// flowchart box can show them as extra lines separated by a rule.
    fn umlLabel(self: *Context, element: *xml.Element) Error![]const u8 {
        var buffer: std.ArrayList(u8) = .empty;

        if (element.firstDescendant("UML")) |uml| {
            if (uml.attribute("stereotype")) |stereotype| {
                if (stereotype.len > 0) {
                    try buffer.appendSlice(self.allocator, "\u{00ab}");
                    try buffer.appendSlice(self.allocator, stereotype);
                    try buffer.appendSlice(self.allocator, "\u{00bb}\n");
                }
            }
        }
        if (labelText(element)) |name| try buffer.appendSlice(self.allocator, name);

        try appendSection(&buffer, self.allocator, element.firstDescendant("AttributeLabel"));
        try appendSection(&buffer, self.allocator, element.firstDescendant("MethodLabel"));

        if (buffer.items.len == 0) return "Class";
        return buffer.toOwnedSlice(self.allocator);
    }

    fn urlOf(self: *Context, element: *xml.Element) ?[]const u8 {
        for (element.children) |child| {
            if (!std.mem.eql(u8, xml.localName(child.name), "data")) continue;
            const key = child.attribute("key") orelse continue;
            const name = self.keys.get(key) orelse continue;
            if (!std.mem.eql(u8, name, "url")) continue;
            const text = child.textOrEmpty();
            if (text.len > 0) return text;
        }
        return null;
    }
};

const Resolved = struct {
    shape: shapes.Shape,
    treatment: shapes.Treatment,
    note: ?[]const u8,
};

fn appendSection(buffer: *std.ArrayList(u8), allocator: std.mem.Allocator, element: ?*xml.Element) !void {
    const section = element orelse return;
    const text = std.mem.trim(u8, section.text, " \t\r\n");
    if (text.len == 0) return;
    if (buffer.items.len > 0) try buffer.appendSlice(allocator, "\n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\n");
    try buffer.appendSlice(allocator, text);
}

fn isGroup(node: *xml.Element) bool {
    if (node.attribute("yfiles.foldertype")) |foldertype| {
        if (std.mem.eql(u8, foldertype, "group")) return true;
    }
    return node.child("graph") != null;
}

fn isPicture(realizer: []const u8) bool {
    const pictures = [_][]const u8{ "SVGNode", "ImageNode", "TableNode", "TableGroupNode" };
    for (pictures) |picture| if (std.mem.eql(u8, picture, realizer)) return true;
    return false;
}

const Graphics = struct {
    element: *xml.Element,
    realizer: []const u8,
};

fn findGraphics(node: *xml.Element) ?Graphics {
    return findGraphicsIn(node);
}

fn findGraphicsIn(element: *xml.Element) ?Graphics {
    for (element.children) |child| {
        const name = xml.localName(child.name);
        if (std.mem.eql(u8, name, "graph")) continue;
        if (isRealizer(name)) return .{ .element = child, .realizer = name };
        if (findGraphicsIn(child)) |found| return found;
    }
    return null;
}

fn isRealizer(name: []const u8) bool {
    const realizers = [_][]const u8{
        "ShapeNode",           "GenericNode",  "GenericGroupNode",
        "ProxyAutoBoundsNode", "UMLClassNode", "SVGNode",
        "ImageNode",           "TableNode",    "TableGroupNode",
        "GroupNode",
    };
    for (realizers) |realizer| if (std.mem.eql(u8, realizer, name)) return true;
    return false;
}

/// A proxy realizer keeps several alternatives; yEd stores the index of the
/// one that is currently drawn.
fn activeRealizer(element: *xml.Element) *xml.Element {
    const name = xml.localName(element.name);
    const is_proxy = std.mem.eql(u8, name, "ProxyAutoBoundsNode") or
        std.mem.eql(u8, name, "ProxyShapeNode");
    if (!is_proxy) return element;

    const realizers = element.child("Realizers") orelse return element;
    const active = if (realizers.attribute("active")) |raw| std.fmt.parseInt(usize, raw, 10) catch 0 else 0;
    if (active >= realizers.children.len) return element;
    return realizers.children[active];
}

fn readStyle(realizer: *xml.Element) model.Style {
    var style: model.Style = .{};

    if (realizer.firstDescendant("Fill")) |fill| {
        style.fill = fill.attribute("color");
        if (fill.attribute("hasColor")) |raw| {
            if (std.mem.eql(u8, raw, "false")) style.fill_visible = false;
        }
        if (fill.attribute("transparent")) |raw| {
            if (std.mem.eql(u8, raw, "true")) style.fill_visible = false;
        }
    }
    if (realizer.firstDescendant("BorderStyle")) |border| {
        style.stroke = border.attribute("color");
        if (border.attribute("width")) |raw| style.stroke_width = parseFloat(raw, 1);
        if (border.attribute("type")) |raw| style.stroke_kind = lineKind(raw);
    }
    if (findLabel(realizer)) |label| style.text_color = label.attribute("textColor");
    return style;
}

fn readRect(geometry: ?*xml.Element) model.Rect {
    const element = geometry orelse return .{};
    return .{
        .x = parseFloat(element.attribute("x") orelse "0", 0),
        .y = parseFloat(element.attribute("y") orelse "0", 0),
        .width = parseFloat(element.attribute("width") orelse "0", 0),
        .height = parseFloat(element.attribute("height") orelse "0", 0),
    };
}

fn labelText(element: *xml.Element) ?[]const u8 {
    const label = findLabel(element) orelse return null;
    const text = label.textOrEmpty();
    return if (text.len == 0) null else text;
}

fn findLabel(element: *xml.Element) ?*xml.Element {
    for (element.children) |child| {
        if (std.mem.eql(u8, xml.localName(child.name), "NodeLabel") or
            std.mem.eql(u8, xml.localName(child.name), "EdgeLabel"))
        {
            if (child.attribute("visible")) |visible| {
                if (std.mem.eql(u8, visible, "false")) continue;
            }
            return child;
        }
        if (findLabel(child)) |found| return found;
    }
    return null;
}

fn bpmnType(element: *xml.Element) ?[]const u8 {
    return findProperty(element, "com.yworks.bpmn.type");
}

fn findProperty(element: *xml.Element, name: []const u8) ?[]const u8 {
    for (element.children) |child| {
        if (std.mem.eql(u8, xml.localName(child.name), "Property")) {
            if (child.attribute("name")) |property_name| {
                if (std.mem.eql(u8, property_name, name)) return child.attribute("value");
            }
        }
        if (findProperty(child, name)) |found| return found;
    }
    return null;
}

fn lineKind(raw: []const u8) model.LineKind {
    if (std.mem.eql(u8, raw, "dashed")) return .dashed;
    if (std.mem.eql(u8, raw, "dotted")) return .dotted;
    return .solid;
}

fn arrowKind(raw: []const u8) model.Arrow {
    if (std.mem.eql(u8, raw, "none")) return .none;
    if (std.mem.eql(u8, raw, "standard")) return .standard;
    if (std.mem.eql(u8, raw, "circle")) return .circle;
    if (std.mem.eql(u8, raw, "diamond")) return .diamond;
    return .other;
}

fn parseFloat(raw: []const u8, fallback: f32) f32 {
    return std.fmt.parseFloat(f32, raw) catch fallback;
}

fn keyNames(allocator: std.mem.Allocator, root: *xml.Element) !std.StringHashMap([]const u8) {
    var keys = std.StringHashMap([]const u8).init(allocator);
    for (root.children) |child| {
        if (!std.mem.eql(u8, xml.localName(child.name), "key")) continue;
        const id = child.attribute("id") orelse continue;
        const name = child.attribute("attr.name") orelse continue;
        try keys.put(id, name);
    }
    return keys;
}

fn validateEndpoints(
    allocator: std.mem.Allocator,
    diagram: model.Diagram,
    diag: *diagnostics.Diagnostics,
) Error!void {
    var ids = std.StringHashMap(void).init(allocator);
    try collectIds(&ids, diagram.items);

    for (diagram.edges) |edge| {
        if (!ids.contains(edge.source)) {
            try diag.warn("edge {s} starts at unknown node {s}", .{ edge.id, edge.source });
            return error.InvalidGraph;
        }
        if (!ids.contains(edge.target)) {
            try diag.warn("edge {s} ends at unknown node {s}", .{ edge.id, edge.target });
            return error.InvalidGraph;
        }
    }
}

fn collectIds(ids: *std.StringHashMap(void), items: []const model.Item) !void {
    for (items) |item| switch (item) {
        .node => |node| try ids.put(node.id, {}),
        .group => |group| {
            try ids.put(group.id, {});
            try collectIds(ids, group.items);
        },
    };
}

const testing = std.testing;

const sample =
    "<graphml xmlns:y=\"http://www.yworks.com/xml/graphml\">\n" ++
    "  <key for=\"node\" id=\"d6\" yfiles.type=\"nodegraphics\"/>\n" ++
    "  <graph edgedefault=\"directed\" id=\"G\">\n" ++
    "    <node id=\"n0\">\n" ++
    "      <data key=\"d6\"><y:GenericNode configuration=\"com.yworks.flowchart.decision\">\n" ++
    "        <y:Geometry height=\"30\" width=\"60\" x=\"0\" y=\"0\"/>\n" ++
    "        <y:Fill color=\"#FFCC00\" transparent=\"false\"/>\n" ++
    "        <y:BorderStyle color=\"#000000\" type=\"line\" width=\"1.0\"/>\n" ++
    "        <y:NodeLabel textColor=\"#000000\">Go?</y:NodeLabel>\n" ++
    "      </y:GenericNode></data>\n" ++
    "    </node>\n" ++
    "    <node id=\"g0\" yfiles.foldertype=\"group\">\n" ++
    "      <data key=\"d6\"><y:ProxyAutoBoundsNode><y:Realizers active=\"0\">\n" ++
    "        <y:GroupNode>\n" ++
    "          <y:Geometry height=\"100\" width=\"100\" x=\"10\" y=\"10\"/>\n" ++
    "          <y:Fill color=\"#F5F5F5\" transparent=\"false\"/>\n" ++
    "          <y:BorderStyle color=\"#000000\" type=\"dashed\" width=\"1.0\"/>\n" ++
    "          <y:NodeLabel>Group A</y:NodeLabel>\n" ++
    "        </y:GroupNode>\n" ++
    "        <y:GroupNode><y:NodeLabel>Folded A</y:NodeLabel></y:GroupNode>\n" ++
    "      </y:Realizers></y:ProxyAutoBoundsNode></data>\n" ++
    "      <graph id=\"g0:\">\n" ++
    "        <node id=\"g0::n0\"><data key=\"d6\"><y:ShapeNode>\n" ++
    "          <y:Geometry height=\"30\" width=\"60\" x=\"20\" y=\"20\"/>\n" ++
    "          <y:Fill color=\"#CCCCFF\" transparent=\"false\"/>\n" ++
    "          <y:BorderStyle color=\"#000000\" type=\"line\" width=\"1.0\"/>\n" ++
    "          <y:NodeLabel>Inside</y:NodeLabel>\n" ++
    "          <y:Shape type=\"ellipse\"/>\n" ++
    "        </y:ShapeNode></data></node>\n" ++
    "      </graph>\n" ++
    "    </node>\n" ++
    "    <node id=\"pic\"><data key=\"d6\"><y:ImageNode>\n" ++
    "      <y:Geometry height=\"30\" width=\"30\" x=\"0\" y=\"0\"/>\n" ++
    "      <y:NodeLabel>logo</y:NodeLabel>\n" ++
    "      <y:Image refid=\"1\"/>\n" ++
    "    </y:ImageNode></data></node>\n" ++
    "    <edge id=\"e0\" source=\"n0\" target=\"g0\"><data key=\"d10\"><y:PolyLineEdge>\n" ++
    "      <y:LineStyle color=\"#000000\" type=\"dotted\" width=\"2.0\"/>\n" ++
    "      <y:Arrows source=\"none\" target=\"standard\"/>\n" ++
    "      <y:EdgeLabel>yes</y:EdgeLabel>\n" ++
    "    </y:PolyLineEdge></data></edge>\n" ++
    "  </graph>\n" ++
    "</graphml>\n";

fn readSample(allocator: std.mem.Allocator, diag: *diagnostics.Diagnostics) !model.Diagram {
    var xml_diagnostic: xml.Diagnostic = .{};
    const root = try xml.parse(allocator, sample, &xml_diagnostic);
    return read(allocator, root, diag);
}

test "a palette node keeps its label, shape and style" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag = diagnostics.Diagnostics.init(arena.allocator());

    const diagram = try readSample(arena.allocator(), &diag);
    const node = diagram.items[0].node;

    try testing.expectEqualStrings("Go?", node.label);
    try testing.expectEqual(shapes.Shape.diamond, node.shape);
    try testing.expectEqual(shapes.Treatment.exact, node.treatment);
    try testing.expectEqualStrings("#FFCC00", node.style.fill.?);
}

test "a group becomes a group with the label of its active realizer" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag = diagnostics.Diagnostics.init(arena.allocator());

    const diagram = try readSample(arena.allocator(), &diag);
    const group = diagram.items[1].group;

    try testing.expectEqualStrings("Group A", group.title);
    try testing.expectEqual(@as(usize, 1), group.items.len);
    try testing.expectEqualStrings("Inside", group.items[0].node.label);
    try testing.expectEqual(model.LineKind.dashed, group.style.stroke_kind);
}

test "a picture realizer is reported as unknown" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag = diagnostics.Diagnostics.init(arena.allocator());

    const diagram = try readSample(arena.allocator(), &diag);
    const picture = diagram.items[2].node;

    try testing.expectEqual(shapes.Treatment.unknown, picture.treatment);
    try testing.expectEqualStrings("logo", picture.label);
    try testing.expect(diag.warnings.items.len >= 1);
}

test "an edge keeps its label, line kind and width" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag = diagnostics.Diagnostics.init(arena.allocator());

    const diagram = try readSample(arena.allocator(), &diag);
    const edge = diagram.edges[0];

    try testing.expectEqualStrings("yes", edge.label.?);
    try testing.expectEqual(model.LineKind.dotted, edge.line);
    try testing.expectEqual(@as(f32, 2), edge.width);
}

test "a uml class node carries its members in the label" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var diag = diagnostics.Diagnostics.init(arena.allocator());

    const source =
        "<graphml xmlns:y=\"http://www.yworks.com/xml/graphml\"><graph id=\"G\">\n" ++
        "  <node id=\"n0\"><data key=\"d6\"><y:UMLClassNode>\n" ++
        "    <y:Geometry height=\"100\" width=\"100\" x=\"0\" y=\"0\"/>\n" ++
        "    <y:Fill color=\"#FFFF00\" transparent=\"false\"/>\n" ++
        "    <y:BorderStyle color=\"#000000\" type=\"line\" width=\"1.0\"/>\n" ++
        "    <y:NodeLabel>Account</y:NodeLabel>\n" ++
        "    <y:UML stereotype=\"entity\">\n" ++
        "      <y:AttributeLabel>balance</y:AttributeLabel>\n" ++
        "      <y:MethodLabel>withdraw</y:MethodLabel>\n" ++
        "    </y:UML>\n" ++
        "  </y:UMLClassNode></data></node>\n" ++
        "</graph></graphml>\n";

    var xml_diagnostic: xml.Diagnostic = .{};
    const root = try xml.parse(arena.allocator(), source, &xml_diagnostic);
    const diagram = try read(arena.allocator(), root, &diag);

    const expected = "\u{00ab}entity\u{00bb}\nAccount\n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\nbalance\n\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\nwithdraw";
    try testing.expectEqualStrings(expected, diagram.items[0].node.label);
}
