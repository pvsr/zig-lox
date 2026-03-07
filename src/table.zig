const std = @import("std");

const Str = @import("value.zig").Str;
const Value = @import("value.zig").Value;

const StrContext = struct {
    ctx: std.hash_map.StringContext = .{},

    pub fn hash(self: StrContext, str: *Str) u64 {
        if (str.hash == 0) {
            var h = self.ctx.hash(str.slice);
            if (h == 0) h = 1;
            str.hash = h;
        }
        return str.hash;
    }

    pub fn eql(self: StrContext, a: *Str, b: *Str) bool {
        return self.ctx.eql(a.slice, b.slice);
    }
};

const Table = std.HashMap(*Str, Value, StrContext, std.hash_map.default_max_load_percentage);

test {
    var table = Table.init(std.testing.allocator);
    defer table.deinit();
    var t = Str.init("true");
    var f = Str.init("false");
    var x = Str.init("x");
    var y = Str.init("y");
    var s1 = Str.init("");
    var s2 = Str.init("   ");
    var none = Str.init("none");
    try table.put(&t, .{ .bool = true });
    try table.put(&f, .{ .bool = false });
    try table.put(&x, .{ .number = 0 });
    try table.put(&y, .{ .number = 15.5 });
    try table.put(&s1, .{ .str = .init("123") });
    try table.put(&s2, .{ .str = .init("abc") });
    std.debug.assert(table.get(&t).?.equals(.{ .bool = true }));
    std.debug.assert(table.get(&f).?.equals(.{ .bool = false }));
    std.debug.assert(table.get(&x).?.equals(.{ .number = 0 }));
    std.debug.assert(table.get(&y).?.equals(.{ .number = 15.5 }));
    std.debug.assert(table.get(&s1).?.equals(.{ .str = .init("123") }));
    std.debug.assert(table.get(&s2).?.equals(.{ .str = .init("abc") }));
    std.debug.assert(table.get(&none) == null);
}
