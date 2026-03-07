const std = @import("std");

const table = @import("table.zig");

pub const Str = struct {
    obj: Obj = .{
        .type = .string,
    },
    hash: u64,
    slice: []const u8,

    pub fn initHashed(s: []const u8, hash: u64) Str {
        return .{
            .slice = s,
            .hash = hash,
        };
    }

    pub fn init(s: []const u8) Str {
        return .initHashed(s, table.hash(s));
    }

    pub fn deinit(self: *Str, gpa: std.mem.Allocator) void {
        gpa.free(self.slice);
        gpa.destroy(self);
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
