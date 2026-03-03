const std = @import("std");

const Value = @import("value.zig").Value;

const Chunk = @This();

pub const OpCode = enum(u8) {
    constant,
    @"return",
    negate,
    add,
    subtract,
    multiply,
    divide,
    _,
};

code: std.ArrayList(u8),
constants: std.ArrayList(Value),
lines: std.ArrayList(u32),
gpa: std.mem.Allocator,

pub fn init(gpa: std.mem.Allocator) Chunk {
    return Chunk{
        .code = std.ArrayList(u8).empty,
        .constants = std.ArrayList(Value).empty,
        .lines = std.ArrayList(u32).empty,
        .gpa = gpa,
    };
}

pub fn write(self: *Chunk, byte: u8, line: u32) void {
    self.code.append(self.gpa, byte) catch unreachable;
    _ = line;
    // self.lines.append(self.gpa, line) catch unreachable;
}

pub fn addConstant(self: *Chunk, value: Value) usize {
    self.constants.append(self.gpa, value) catch unreachable;
    return self.constants.items.len - 1;
}
