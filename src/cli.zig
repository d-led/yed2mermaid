// SPDX-License-Identifier: MPL-2.0
//! Argument parsing. Kept free of I/O so it can be tested exhaustively.
const std = @import("std");
const options = @import("options.zig");

pub const version = "0.1.0";

pub const Command = union(enum) {
    help,
    version,
    convert: options.Options,
};

pub const Error = error{
    UnknownOption,
    MissingValue,
    InvalidValue,
    UnexpectedArgument,
    NoInput,
};

pub const help_text =
    \\yed2mermaid - convert yEd GraphML flowcharts to Mermaid
    \\
    \\Usage:
    \\  yed2mermaid [options] <file.graphml|->
    \\
    \\Options:
    \\  -o, --output <path>       write to <path> instead of stdout
    \\  -d, --direction <dir>     auto (default), td, lr, bt, rl
    \\      --style <mode>        yed (default) or none
    \\      --plain               shorthand for --style none
    \\      --layout <name>       elk (default), dagre, renderer-default
    \\      --config <json|file>  Mermaid config merged over the defaults
    \\      --title <text>        title in the front-matter
    \\      --no-front-matter     omit the front-matter block
    \\      --links               emit click lines for yEd node URLs
    \\      --images[=<dir>]      write the pictures the drawing embeds into <dir> and point
    \\                            the diagram at them; without <dir> they go to
    \\                            <output>-images ("auto" says the same)
    \\      --edge-filler         give label-less edges invisible labels so they keep a visible shaft (default)
    \\      --no-edge-filler      emit label-less edges exactly as drawn, which can shrink them to arrow heads
    \\      --quiet               do not print warnings
    \\  -h, --help                show this help
    \\  -V, --version             show the version
    \\
    \\Reads from stdin when the input is "-".
    \\
;

pub fn parse(args: []const []const u8) Error!Command {
    var result: options.Options = .{};
    var index: usize = 0;
    var end_of_options = false;

    while (index < args.len) : (index += 1) {
        const arg = args[index];

        if (!end_of_options and std.mem.eql(u8, arg, "--")) {
            end_of_options = true;
            continue;
        }

        if (!end_of_options and std.mem.startsWith(u8, arg, "--")) {
            const equals = std.mem.indexOfScalar(u8, arg, '=');
            const name = if (equals) |at| arg[0..at] else arg;
            const attached = if (equals) |at| arg[at + 1 ..] else null;

            if (std.mem.eql(u8, name, "--help")) return .help;
            if (std.mem.eql(u8, name, "--version")) return .version;
            if (std.mem.eql(u8, name, "--plain")) {
                result.styling = false;
                continue;
            }
            if (std.mem.eql(u8, name, "--no-front-matter")) {
                result.front_matter = false;
                continue;
            }
            if (std.mem.eql(u8, name, "--links")) {
                result.links = true;
                continue;
            }
            if (std.mem.eql(u8, name, "--images")) {
                result.images = if (attached) |dir| try parseImages(dir) else .automatic;
                continue;
            }
            if (std.mem.eql(u8, name, "--edge-filler")) {
                result.edge_filler = true;
                continue;
            }
            if (std.mem.eql(u8, name, "--no-edge-filler")) {
                result.edge_filler = false;
                continue;
            }
            if (std.mem.eql(u8, name, "--quiet")) {
                result.quiet = true;
                continue;
            }
            if (std.mem.eql(u8, name, "--output")) {
                result.output_path = try takeValue(args, &index, attached);
                continue;
            }
            if (std.mem.eql(u8, name, "--direction")) {
                result.direction = try parseDirection(try takeValue(args, &index, attached));
                continue;
            }
            if (std.mem.eql(u8, name, "--style")) {
                result.styling = try parseStyling(try takeValue(args, &index, attached));
                continue;
            }
            if (std.mem.eql(u8, name, "--layout")) {
                result.layout = try parseLayout(try takeValue(args, &index, attached));
                continue;
            }
            if (std.mem.eql(u8, name, "--config")) {
                result.config = classifyConfig(try takeValue(args, &index, attached));
                continue;
            }
            if (std.mem.eql(u8, name, "--title")) {
                result.title = try takeValue(args, &index, attached);
                continue;
            }
            return error.UnknownOption;
        }

        if (!end_of_options and arg.len == 2 and arg[0] == '-') {
            switch (arg[1]) {
                'h' => return .help,
                'V' => return .version,
                'o' => {
                    result.output_path = try takeValue(args, &index, null);
                    continue;
                },
                'd' => {
                    result.direction = try parseDirection(try takeValue(args, &index, null));
                    continue;
                },
                else => return error.UnknownOption,
            }
        }

        if (result.input_path != null) return error.UnexpectedArgument;
        result.input_path = arg;
    }

    if (result.input_path == null) return error.NoInput;
    return .{ .convert = result };
}

fn takeValue(args: []const []const u8, index: *usize, attached: ?[]const u8) Error![]const u8 {
    if (attached) |value| {
        if (value.len == 0) return error.MissingValue;
        return value;
    }
    if (index.* + 1 >= args.len) return error.MissingValue;
    index.* += 1;
    return args[index.*];
}

fn parseDirection(value: []const u8) Error!options.Direction {
    const directions = [_]struct { name: []const u8, value: options.Direction }{
        .{ .name = "auto", .value = .auto },
        .{ .name = "td", .value = .td },
        .{ .name = "lr", .value = .lr },
        .{ .name = "bt", .value = .bt },
        .{ .name = "rl", .value = .rl },
    };
    for (directions) |direction| {
        if (std.mem.eql(u8, direction.name, value)) return direction.value;
    }
    return error.InvalidValue;
}

fn parseStyling(value: []const u8) Error!bool {
    if (std.mem.eql(u8, value, "yed")) return true;
    if (std.mem.eql(u8, value, "none")) return false;
    return error.InvalidValue;
}

fn parseLayout(value: []const u8) Error!options.Layout {
    if (std.mem.eql(u8, value, "elk")) return .elk;
    if (std.mem.eql(u8, value, "dagre")) return .dagre;
    if (std.mem.eql(u8, value, "renderer-default")) return .renderer_default;
    return error.InvalidValue;
}

fn classifyConfig(value: []const u8) options.ConfigSource {
    if (std.mem.startsWith(u8, std.mem.trimStart(u8, value, " \t"), "{")) return .{ .inline_json = value };
    return .{ .file = value };
}

fn parseImages(value: []const u8) Error!options.Images {
    if (value.len == 0) return error.MissingValue;
    if (std.mem.eql(u8, value, "auto")) return .automatic;
    return .{ .directory = value };
}

const testing = std.testing;

test "a file argument becomes the input" {
    const command = try parse(&.{"chart.graphml"});
    try testing.expectEqualStrings("chart.graphml", command.convert.input_path.?);
}

test "plain disables styling" {
    const command = try parse(&.{ "--plain", "chart.graphml" });
    try testing.expect(!command.convert.styling);
}

test "an inline value may follow the option name" {
    const command = try parse(&.{ "--layout=dagre", "chart.graphml" });
    try testing.expectEqual(options.Layout.dagre, command.convert.layout);
}

test "a config that starts with a brace is inline json" {
    const command = try parse(&.{ "--config", "{\"theme\":\"forest\"}", "chart.graphml" });

    try testing.expectEqualStrings("{\"theme\":\"forest\"}", command.convert.config.inline_json);
}

test "a config path stays a path" {
    const command = try parse(&.{ "--config", "mermaid.json", "chart.graphml" });

    try testing.expectEqualStrings("mermaid.json", command.convert.config.file);
}

test "an unknown option is rejected" {
    try testing.expectError(error.UnknownOption, parse(&.{ "--nope", "chart.graphml" }));
}

test "a missing value is rejected" {
    try testing.expectError(error.MissingValue, parse(&.{ "chart.graphml", "--output" }));
}

test "an invalid direction is rejected" {
    try testing.expectError(error.InvalidValue, parse(&.{ "--direction", "up", "chart.graphml" }));
}

test "a second input argument is rejected" {
    try testing.expectError(error.UnexpectedArgument, parse(&.{ "a.graphml", "b.graphml" }));
}

test "no input is rejected" {
    try testing.expectError(error.NoInput, parse(&.{"--plain"}));
}

test "help and version are commands of their own" {
    const help = try parse(&.{"--help"});
    const version_command = try parse(&.{"-V"});

    try testing.expect(help == .help);
    try testing.expect(version_command == .version);
}

test "--images alone extracts next to the output" {
    const command = try parse(&.{ "--images", "chart.graphml", "-o", "charts/flow.mmd" });

    try testing.expect(command.convert.images == .automatic);
}

test "--images=<dir> extracts into that directory" {
    const command = try parse(&.{ "--images=assets/pics", "chart.graphml" });

    try testing.expectEqualStrings("assets/pics", command.convert.images.directory);
}

test "--images=auto is the same as --images" {
    const command = try parse(&.{ "--images=auto", "chart.graphml" });

    try testing.expect(command.convert.images == .automatic);
}

test "--images= is a missing value" {
    try testing.expectError(error.MissingValue, parse(&.{ "--images=", "chart.graphml" }));
}
