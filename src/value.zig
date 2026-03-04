const std = @import("std");

pub const Obj = struct {
    const Type = enum { string };

    node: std.SinglyLinkedList.Node = .{},
    obj: union(Obj.Type) {
        string: []const u8,
    },

    pub fn string(str: []const u8) Obj {
        return .{ .obj = .{ .string = str } };
    }

    fn print(self: Obj) void {
        switch (self.obj) {
            .string => |s| std.debug.print("{s}", .{s}),
        }
    }

    fn equals(self: Obj, other: Obj) bool {
        switch (self.obj) {
            .string => |a| switch (other.obj) {
                .string => |b| return std.mem.eql(u8, a, b),
            },
        }
        return false;
    }
};

pub const Value = union(Type) {
    const Type = enum {
        bool,
        number,
        obj,
        nil,
    };

    bool: bool,
    number: f64,
    obj: Obj,
    nil,

    pub fn string(gpa: std.mem.Allocator, objects: *std.SinglyLinkedList, str: []const u8) Value {
        var obj = gpa.create(Obj) catch unreachable;
        obj.* = .string(str);
        objects.prepend(&obj.node);
        return .{ .obj = obj.* };
    }

    pub fn print(self: Value) void {
        switch (self) {
            .bool => |b| std.debug.print("{}", .{b}),
            .number => |n| std.debug.print("{d}", .{n}),
            .nil => std.debug.print("nil", .{}),
            .obj => |o| o.print(),
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
            .obj => |a| switch (other) {
                .obj => |b| return a.equals(b),
                else => {},
            },
            else => {},
        }
        return false;
    }
};
