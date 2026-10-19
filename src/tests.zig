// SPDX-License-Identifier: MPL-2.0
//! Aggregates the unit tests of every module so `zig build test` runs them all.
test {
    _ = @import("xml.zig");
    _ = @import("shapes.zig");
    _ = @import("yed.zig");
    _ = @import("config.zig");
    _ = @import("mermaid.zig");
    _ = @import("cli.zig");
    _ = @import("convert.zig");
}
