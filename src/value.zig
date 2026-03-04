const std = @import("std");

const Type = enum {
    bool,
    number,
    nil,
};

pub const Value = union(Type) {
    bool: bool,
    number: f64,
    nil,

    pub fn print(value: Value) void {
        switch (value) {
            .bool => |b| std.debug.print("{}", .{b}),
            .number => |n| std.debug.print("{d}", .{n}),
            .nil => std.debug.print("nil", .{}),
        }
    }

    pub fn equals(self: Value, other: Value) bool {
        if (self == .nil or other == .nil) return true;
        switch (self) {
            .number => |a| switch (other) {
                .number => |b| return a == b,
                else => {},
            },
            .bool => |a| switch (other) {
                .bool => |b| return a == b,
                else => {},
            },
            else => {},
        }
        return false;
    }
};
