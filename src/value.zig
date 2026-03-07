const std = @import("std");

const Obj = @import("object.zig").Obj;
const Objects = @import("Objects.zig");
const Str = @import("object.zig").Str;

pub const Value = union(Type) {
    const Type = enum {
        bool,
        number,
        str,
        nil,
    };

    bool: bool,
    number: f64,
    str: Str,
    nil,

    pub fn ownedStr(gpa: std.mem.Allocator, objects: *Objects, slice: []const u8) Value {
        return createStr(gpa, objects, slice, true);
    }

    pub fn copyStr(gpa: std.mem.Allocator, objects: *Objects, slice: []const u8) Value {
        return createStr(gpa, objects, slice, false);
    }

    fn createStr(gpa: std.mem.Allocator, objects: *Objects, slice: []const u8, owned: bool) Value {
        return .{ .str = objects.createStr(gpa, slice, owned).* };
    }

    pub fn print(self: Value) void {
        switch (self) {
            .bool => |b| std.debug.print("{}", .{b}),
            .number => |n| std.debug.print("{d}", .{n}),
            .str => |s| std.debug.print("{s}", .{s.slice}),
            .nil => std.debug.print("nil", .{}),
        }
    }

    pub fn equals(self: Value, other: Value) bool {
        return switch (self) {
            .number => other == .number and self.number == other.number,
            .bool => other == .bool and self.bool == other.bool,
            .str => other == .str and self.str.slice.ptr == other.str.slice.ptr,
            .nil => other == .nil,
        };
    }
};

test {
    const gpa = std.testing.allocator;
    var objects = Objects.init(gpa);
    defer objects.deinit(gpa);
    const t: Value = .{ .bool = true };
    const f: Value = .{ .bool = false };
    const x: Value = .{ .number = 0 };
    const y: Value = .{ .number = 15.5 };
    const s1: Value = .copyStr(gpa, &objects, "123");
    const s2: Value = .copyStr(gpa, &objects, "abc");
    const nil: Value = .nil;
    try std.testing.expect(!t.equals(f));
    try std.testing.expect(t.equals(.{ .bool = true }));
    try std.testing.expect(f.equals(.{ .bool = false }));
    try std.testing.expect(!x.equals(y));
    try std.testing.expect(!x.equals(t));
    try std.testing.expect(x.equals(.{ .number = 0 }));
    try std.testing.expect(y.equals(.{ .number = 15.5 }));
    try std.testing.expect(!s1.equals(s2));
    try std.testing.expect(!s1.equals(y));
    try std.testing.expect(s1.equals(s1));
    try std.testing.expect(s1.equals(.copyStr(gpa, &objects, "123")));
    try std.testing.expect(s2.equals(.copyStr(gpa, &objects, "abc")));
    try std.testing.expect(!s1.equals(.copyStr(gpa, &objects, "")));
    try std.testing.expect(nil.equals(.nil));
    try std.testing.expect(!nil.equals(t));
    try std.testing.expect(!nil.equals(f));
    try std.testing.expect(!nil.equals(x));
}
