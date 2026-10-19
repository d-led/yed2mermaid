// SPDX-License-Identifier: MPL-2.0
//! The neutral diagram model shared by the yEd reader and the Mermaid emitter.
const std = @import("std");
const shapes = @import("shapes.zig");

pub const LineKind = enum {
    solid,
    dashed,
    dotted,
};

pub const Arrow = enum {
    none,
    standard,
    circle,
    diamond,
    other,
};

pub const Rect = struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,

    pub fn centerX(self: Rect) f32 {
        return self.x + self.width / 2;
    }

    pub fn centerY(self: Rect) f32 {
        return self.y + self.height / 2;
    }
};

pub const Style = struct {
    fill: ?[]const u8 = null,
    fill_visible: bool = true,
    stroke: ?[]const u8 = null,
    stroke_width: f32 = 1,
    stroke_kind: LineKind = .solid,
    text_color: ?[]const u8 = null,
};

pub const Node = struct {
    id: []const u8,
    label: []const u8,
    shape: shapes.Shape,
    treatment: shapes.Treatment,
    style: Style,
    rect: Rect,
    url: ?[]const u8 = null,
    /// Human readable explanation for approximate/unknown nodes.
    note: ?[]const u8 = null,
    /// Set when the drawing shows a picture instead of a drawn shape.
    picture: ?Picture = null,
};

/// Where a node's picture lives: either a reference the drawing itself carries,
/// or bytes yEd embedded in the document under `<y:Resources>`.
pub const Picture = struct {
    url: ?[]const u8 = null,
    content: ?[]const u8 = null,
    extension: ?[]const u8 = null,

    /// True when the picture can be shown: an external reference, or embedded
    /// bytes we know how to name.
    pub fn isUsable(self: Picture) bool {
        if (self.url != null) return true;
        return self.content != null and self.extension != null;
    }
};

pub const Group = struct {
    id: []const u8,
    title: []const u8,
    style: Style,
    rect: Rect,
    items: []Item,
};

pub const Item = union(enum) {
    node: Node,
    group: Group,
};

pub const Edge = struct {
    id: []const u8,
    source: []const u8,
    target: []const u8,
    label: ?[]const u8 = null,
    line: LineKind = .solid,
    width: f32 = 1,
    source_arrow: Arrow = .none,
    target_arrow: Arrow = .standard,
};

pub const Diagram = struct {
    items: []const Item,
    edges: []const Edge,
};
