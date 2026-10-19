// SPDX-License-Identifier: MPL-2.0
//! Translation tables from yEd's palette identifiers to Mermaid's shape
//! vocabulary.
//!
//! These tables are a compatibility map between format identifiers and the
//! shapes Mermaid itself offers. They contain no yWorks assets, icons, colours
//! or drawing definitions: every colour and border in the output is read from
//! the input document.
const std = @import("std");

pub const Shape = enum {
    rectangle,
    rounded,
    stadium,
    diamond,
    hexagon,
    parallelogram,
    trapezoid,
    subroutine,
    cylinder,
    circle,
    asymmetric,
};

pub const Treatment = enum {
    /// Mermaid has an equivalent for the yEd shape.
    exact,
    /// Same semantic family, but drawn with a different glyph.
    approximate,
    /// The content cannot be represented and is drawn as a marked box.
    unknown,
};

pub const Resolution = struct {
    shape: Shape,
    treatment: Treatment,
};

pub const Mapping = struct {
    name: []const u8,
    shape: Shape,
    exact: bool = true,
};

/// The yEd flowchart palette (`com.yworks.flowchart.*`).
pub const flowchart = [_]Mapping{
    .{ .name = "start1", .shape = .stadium },
    .{ .name = "start2", .shape = .stadium },
    .{ .name = "terminator", .shape = .stadium },
    .{ .name = "process", .shape = .rectangle },
    .{ .name = "predefinedProcess", .shape = .subroutine },
    .{ .name = "decision", .shape = .diamond },
    .{ .name = "loopLimit", .shape = .hexagon, .exact = false },
    .{ .name = "loopLimitEnd", .shape = .hexagon, .exact = false },
    .{ .name = "document", .shape = .parallelogram, .exact = false },
    .{ .name = "data", .shape = .parallelogram },
    .{ .name = "directData", .shape = .parallelogram, .exact = false },
    .{ .name = "storedData", .shape = .cylinder, .exact = false },
    .{ .name = "sequentialData", .shape = .parallelogram, .exact = false },
    .{ .name = "dataBase", .shape = .cylinder },
    .{ .name = "internalStorage", .shape = .subroutine, .exact = false },
    .{ .name = "manualInput", .shape = .parallelogram },
    .{ .name = "card", .shape = .rectangle, .exact = false },
    .{ .name = "paperType", .shape = .parallelogram, .exact = false },
    .{ .name = "cloud", .shape = .stadium, .exact = false },
    .{ .name = "delay", .shape = .rounded },
    .{ .name = "display", .shape = .trapezoid, .exact = false },
    .{ .name = "manualOperation", .shape = .trapezoid },
    .{ .name = "preparation", .shape = .hexagon },
    .{ .name = "onPageReference", .shape = .circle, .exact = false },
    .{ .name = "offPageReference", .shape = .circle, .exact = false },
    .{ .name = "userMessage", .shape = .rectangle, .exact = false },
    .{ .name = "networkMessage", .shape = .rectangle, .exact = false },
    .{ .name = "annotation", .shape = .rounded, .exact = false },
};

/// `y:Shape/@type`, as used by the shape-node palette.
pub const shape_types = [_]Mapping{
    .{ .name = "rectangle", .shape = .rectangle },
    .{ .name = "roundrectangle", .shape = .rounded },
    .{ .name = "ellipse", .shape = .stadium },
    .{ .name = "diamond", .shape = .diamond },
    .{ .name = "hexagon", .shape = .hexagon },
    .{ .name = "octagon", .shape = .hexagon, .exact = false },
    .{ .name = "parallelogram", .shape = .parallelogram },
    .{ .name = "parallelogram2", .shape = .parallelogram, .exact = false },
    .{ .name = "trapezoid", .shape = .trapezoid },
    .{ .name = "rectangle3d", .shape = .rectangle, .exact = false },
    .{ .name = "fatarrow", .shape = .parallelogram, .exact = false },
    .{ .name = "fatarrow2", .shape = .parallelogram, .exact = false },
    .{ .name = "star5", .shape = .hexagon, .exact = false },
    .{ .name = "star6", .shape = .hexagon, .exact = false },
    .{ .name = "star8", .shape = .hexagon, .exact = false },
    .{ .name = "triangle", .shape = .asymmetric, .exact = false },
};

pub const entity_relationship = [_]Mapping{
    .{ .name = "big_entity", .shape = .rectangle },
    .{ .name = "small_entity", .shape = .rectangle },
    .{ .name = "relationship", .shape = .diamond },
    .{ .name = "attribute", .shape = .stadium },
};

pub const sbgn = [_]Mapping{
    .{ .name = "UnspecifiedEntity", .shape = .rectangle, .exact = false },
    .{ .name = "SimpleChemical", .shape = .circle, .exact = false },
    .{ .name = "Macromolecule", .shape = .stadium, .exact = false },
    .{ .name = "NucleicAcidFeature", .shape = .stadium, .exact = false },
    .{ .name = "PerturbingAgent", .shape = .hexagon, .exact = false },
    .{ .name = "EmptySet", .shape = .circle, .exact = false },
    .{ .name = "UnitOfInformation", .shape = .rounded, .exact = false },
    .{ .name = "StateVariable", .shape = .stadium, .exact = false },
    .{ .name = "Phenotype", .shape = .hexagon, .exact = false },
    .{ .name = "Submap", .shape = .rectangle, .exact = false },
    .{ .name = "Tag", .shape = .rectangle, .exact = false },
    .{ .name = "Process", .shape = .rectangle, .exact = false },
    .{ .name = "Operator", .shape = .circle, .exact = false },
    .{ .name = "Complex", .shape = .rounded, .exact = false },
};

pub const bpmn_families = [_]Mapping{
    .{ .name = "Activity", .shape = .rounded },
    .{ .name = "Gateway", .shape = .diamond },
    .{ .name = "Event", .shape = .circle },
    .{ .name = "Conversation", .shape = .hexagon, .exact = false },
};

/// Returns the shape for a qualified yEd palette configuration such as
/// `com.yworks.flowchart.decision`.
pub fn findByConfiguration(configuration: []const u8) ?Resolution {
    if (std.mem.startsWith(u8, configuration, "com.yworks.flowchart.")) {
        return lookup(&flowchart, suffix(configuration));
    }
    if (std.mem.startsWith(u8, configuration, "com.yworks.entityRelationship.")) {
        return lookup(&entity_relationship, suffix(configuration));
    }
    if (std.mem.startsWith(u8, configuration, "com.yworks.sbgn.")) {
        return lookup(&sbgn, suffix(configuration));
    }
    if (std.mem.startsWith(u8, configuration, "com.yworks.bpmn.")) {
        return findBpmn(configuration, null);
    }
    return null;
}

/// BPMN stores the family in the configuration and the concrete kind in the
/// node's style properties. The family is enough to pick a glyph; the concrete
/// kind only refines artifact-like nodes.
pub fn findBpmn(configuration: []const u8, bpmn_type: ?[]const u8) ?Resolution {
    const family = bpmnFamily(configuration);
    if (lookup(&bpmn_families, family)) |resolved| return resolved;

    if (!std.mem.eql(u8, family, "Artifact")) return null;

    const kind = bpmn_type orelse return .{ .shape = .rectangle, .treatment = .approximate };
    if (std.mem.eql(u8, kind, "ARTIFACT_TYPE_DATA_OBJECT") or
        std.mem.eql(u8, kind, "ARTIFACT_TYPE_REQUEST_MESSAGE") or
        std.mem.eql(u8, kind, "ARTIFACT_TYPE_REPLY_MESSAGE"))
    {
        return .{ .shape = .parallelogram, .treatment = .approximate };
    }
    if (std.mem.eql(u8, kind, "ARTIFACT_TYPE_DATA_STORE")) {
        return .{ .shape = .cylinder, .treatment = .approximate };
    }
    if (std.mem.eql(u8, kind, "ARTIFACT_TYPE_ANNOTATION")) {
        return .{ .shape = .rounded, .treatment = .approximate };
    }
    return .{ .shape = .rectangle, .treatment = .approximate };
}

pub fn findByShapeType(shape_type: []const u8) ?Resolution {
    return lookup(&shape_types, shape_type);
}

pub fn shapeName(shape: Shape) []const u8 {
    return @tagName(shape);
}

fn lookup(mappings: []const Mapping, name: []const u8) ?Resolution {
    for (mappings) |mapping| {
        if (!std.mem.eql(u8, mapping.name, name)) continue;
        return .{
            .shape = mapping.shape,
            .treatment = if (mapping.exact) .exact else .approximate,
        };
    }
    return null;
}

fn bpmnFamily(configuration: []const u8) []const u8 {
    const last = suffix(configuration);
    if (!std.mem.eql(u8, last, "withShadow")) return last;

    const without_last = configuration[0 .. configuration.len - last.len - 1];
    return suffix(without_last);
}

fn suffix(qualified_name: []const u8) []const u8 {
    const dot = std.mem.lastIndexOfScalar(u8, qualified_name, '.') orelse return qualified_name;
    return qualified_name[dot + 1 ..];
}

const testing = std.testing;

test "a flowchart decision is a diamond" {
    const resolved = findByConfiguration("com.yworks.flowchart.decision").?;

    try testing.expectEqual(Shape.diamond, resolved.shape);
    try testing.expectEqual(Treatment.exact, resolved.treatment);
}

test "a flowchart document keeps its meaning with an approximate shape" {
    const resolved = findByConfiguration("com.yworks.flowchart.document").?;

    try testing.expectEqual(Shape.parallelogram, resolved.shape);
    try testing.expectEqual(Treatment.approximate, resolved.treatment);
}

test "every flowchart palette entry resolves" {
    var buffer: [128]u8 = undefined;
    for (flowchart) |mapping| {
        const qualified = try std.fmt.bufPrint(&buffer, "com.yworks.flowchart.{s}", .{mapping.name});
        try testing.expect(findByConfiguration(qualified) != null);
    }
}

test "a bpmn gateway is a diamond and a data store keeps its cylinder" {
    const gateway = findBpmn("com.yworks.bpmn.Gateway.withShadow", "GATEWAY_TYPE_PARALLEL").?;
    const store = findBpmn("com.yworks.bpmn.Artifact.withShadow", "ARTIFACT_TYPE_DATA_STORE").?;

    try testing.expectEqual(Shape.diamond, gateway.shape);
    try testing.expectEqual(Shape.cylinder, store.shape);
}

test "an entity relationship node maps by its role" {
    const relationship = findByConfiguration("com.yworks.entityRelationship.relationship").?;

    try testing.expectEqual(Shape.diamond, relationship.shape);
}

test "a star has no exact equivalent" {
    const resolved = findByShapeType("star8").?;

    try testing.expectEqual(Treatment.approximate, resolved.treatment);
}

test "an unknown configuration has no resolution" {
    try testing.expect(findByConfiguration("BevelNode") == null);
}
