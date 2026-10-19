// SPDX-License-Identifier: MPL-2.0
//! Warnings collected while reading and rendering. Keeping them in a value
//! (instead of printing) keeps the pipeline pure and testable.
const std = @import("std");

pub const Warning = struct {
    message: []const u8,
};

pub const Diagnostics = struct {
    allocator: std.mem.Allocator,
    warnings: std.ArrayList(Warning) = .empty,

    pub fn init(allocator: std.mem.Allocator) Diagnostics {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Diagnostics) void {
        self.warnings.deinit(self.allocator);
    }

    pub fn warn(self: *Diagnostics, comptime format: []const u8, args: anytype) !void {
        const message = try std.fmt.allocPrint(self.allocator, format, args);
        try self.warnings.append(self.allocator, .{ .message = message });
    }
};
