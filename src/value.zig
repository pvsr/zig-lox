const std = @import("std");

pub const Str = struct {
    obj: Obj,
    hash: u64 = 0,
    slice: []const u8,

    pub fn init(s: []const u8) Str {
        return .{
            .obj = .{
                .type = .string,
            },
            .slice = s,
        };
    }

    pub fn deinit(self: *Str, gpa: std.mem.Allocator) void {
        gpa.free(self.slice);
        gpa.destroy(self);
    }

    pub fn equals(self: Str, other: Str) bool {
        return std.mem.eql(u8, self.slice, other.slice);
    }
};

pub const Obj = struct {
    const Type = enum { string };

    type: Type,
    node: std.SinglyLinkedList.Node = .{},

    pub fn deinit(self: *Obj, gpa: std.mem.Allocator) void {
        const P = switch (self.type) {
            .string => Str,
        };
        var parent: *P = @fieldParentPtr("obj", self);
        parent.deinit(gpa);
    }
};

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

    pub fn string(gpa: std.mem.Allocator, objects: *std.SinglyLinkedList, slice: []const u8) Value {
        var str = gpa.create(Str) catch unreachable;
        str.* = .init(slice);
        objects.prepend(&str.obj.node);
        return .{ .str = str.* };
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
        switch (self) {
            .number => |a| switch (other) {
                .number => |b| return a == b,
                else => {},
            },
            .bool => |a| switch (other) {
                .bool => |b| return a == b,
                else => {},
            },
            .str => |a| switch (other) {
                .str => |b| return a.equals(b),
                else => {},
            },
            .nil => switch (other) {
                .nil => return true,
                else => {},
            },
        }
        return false;
    }
};

test {
    const t: Value = .{ .bool = true };
    const f: Value = .{ .bool = false };
    const x: Value = .{ .number = 0 };
    const y: Value = .{ .number = 15.5 };
    const s1: Value = .{ .str = .init("123") };
    const s2: Value = .{ .str = .init("abc") };
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
    try std.testing.expect(s1.equals(.{ .str = .init("123") }));
    try std.testing.expect(s2.equals(.{ .str = .init("abc") }));
    try std.testing.expect(nil.equals(.nil));
    try std.testing.expect(!nil.equals(t));
    try std.testing.expect(!nil.equals(f));
}
