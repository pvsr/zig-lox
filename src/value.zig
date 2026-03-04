const std = @import("std");

pub const Value = union(enum) {
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
};
