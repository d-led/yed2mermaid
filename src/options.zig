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

pub const Options = struct {
    direction: Direction = .auto,
    styling: bool = true,
    front_matter: bool = true,
    links: bool = false,
    quiet: bool = false,
    edge_filler: bool = false,
    layout: Layout = .elk,
    title: ?[]const u8 = null,
    config: ConfigSource = .none,
    output_path: ?[]const u8 = null,
    input_path: ?[]const u8 = null,
};
