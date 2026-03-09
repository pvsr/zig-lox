const std = @import("std");

const Obj = @import("object.zig").Obj;
const Str = @import("object.zig").Str;
const table = @import("table.zig");
const Table = table.Table;

const Self = @This();

nodes: std.SinglyLinkedList,
strings: Table,

pub fn init(gpa: std.mem.Allocator) *Self {
    const self = gpa.create(Self) catch unreachable;
    self.* = .{
        .nodes = .{},
        .strings = Table.init(gpa),
    };
    return self;
}

pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
    var it = self.nodes.first;
    while (it) |node| {
        var object: *Obj = @fieldParentPtr("node", node);
        it = node.next;
        object.deinit(gpa);
    }
    self.strings.deinit();
    gpa.destroy(self);
}

const FixedHashContext = struct {
    h: u64,
    pub fn hash(self: FixedHashContext, s: []const u8) u64 {
        _ = s;
        return self.h;
    }
    pub fn eql(self: FixedHashContext, a: []const u8, b: Str) bool {
        _ = self;
        return std.mem.eql(u8, a, b.slice);
    }
};

pub fn createStr(self: *Self, gpa: std.mem.Allocator, str: []const u8, owned: bool) *Str {
    const h = table.hash(str);
    const r = self.strings.getOrPutAdapted(str, FixedHashContext{ .h = h }) catch unreachable;
    if (!r.found_existing) {
        const s = gpa.create(Str) catch unreachable;
        s.* = .initHashed(if (owned) str else gpa.dupe(u8, str) catch unreachable, h);
        r.key_ptr.* = s.*;
        r.value_ptr.* = .nil;
        self.nodes.prepend(&s.*.obj.node);
    } else if (owned) {
        gpa.free(str);
    }
    return r.key_ptr;
}
