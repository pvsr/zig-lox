const std = @import("std");
const ArrayList = std.ArrayList;
const chunk = @import("chunk.zig");
const debug = @import("debug.zig");
const value = @import("value.zig");
const vm = @import("vm.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var c = chunk.Chunk.init();
    try c.constants.append(allocator, 2.1);
    try c.constants.append(allocator, 1);
    try c.constants.append(allocator, 0);
    try c.write(allocator, @intFromEnum(chunk.OpCode.constant), 1);
    try c.write(allocator, 0, 1);
    try c.write(allocator, @intFromEnum(chunk.OpCode.constant), 2);
    try c.write(allocator, 1, 2);
    try c.write(allocator, @intFromEnum(chunk.OpCode.constant), 3);
    try c.write(allocator, 2, 3);
    try c.write(allocator, @intFromEnum(chunk.OpCode.constant), 3);
    try c.write(allocator, 0, 3);
    try c.write(allocator, @intFromEnum(chunk.OpCode.negate), 3);
    try c.write(allocator, @intFromEnum(chunk.OpCode.add), 3);
    try c.write(allocator, @intFromEnum(chunk.OpCode.@"return"), 3);
    var v: vm.VM = try vm.VM.init(allocator, &c);
    _ = v.interpret();
}
