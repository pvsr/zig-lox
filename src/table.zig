const std = @import("std");

const Str = @import("object.zig").Str;
const Value = @import("value.zig").Value;

pub fn hash(s: []const u8) u64 {
    return std.hash.Wyhash.hash(0, s);
}

const StrContext = struct {
    pub fn hash(self: StrContext, str: Str) u64 {
        _ = self;
        return str.hash;
    }

    pub fn eql(self: StrContext, a: Str, b: Str) bool {
        _ = self;
        return std.mem.eql(u8, a.slice, b.slice);
    }
};

pub const Table = std.HashMap(Str, Value, StrContext, std.hash_map.default_max_load_percentage);

test {
    var table = Table.init(std.testing.allocator);
    defer table.deinit();
    const t = Str.init("true");
    const f = Str.init("false");
    const x = Str.init("x");
    const y = Str.init("y");
    const s1 = Str.init("");
    const s2 = Str.init("   ");
    const none = Str.init("none");
    try table.put(t, .{ .bool = true });
    try table.put(f, .{ .bool = false });
    try table.put(x, .{ .number = 0 });
    try table.put(y, .{ .number = 15.5 });
    try table.put(s1, .{ .str = .init("123") });
    try table.put(s2, .{ .str = .init("abc") });
    try std.testing.expectEqual(table.get(t).?.bool, true);
    try std.testing.expectEqual(table.get(f).?.bool, false);
    try std.testing.expectEqual(table.get(x).?.number, 0);
    try std.testing.expectEqual(table.get(y).?.number, 15.5);
    try std.testing.expectEqual(table.get(s1).?.str.slice, "123");
    try std.testing.expectEqual(table.get(s2).?.str.slice, "abc");
    try std.testing.expectEqual(table.get(none), null);
}
