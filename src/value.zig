const std = @import("std");

pub const Str = struct {
    obj: Obj,
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
            .str => |a| switch (other) {
                .str => |b| return a.equals(b),
                else => {},
            },
            else => {},
        }
        return false;
    }
};
