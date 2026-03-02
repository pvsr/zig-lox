const std = @import("std");
const Value = @import("value.zig").Value;

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

pub const Chunk = struct {
    code: std.ArrayList(u8),
    constants: std.ArrayList(Value),
    lines: std.ArrayList(u32),

    pub fn init() Chunk {
        return Chunk{
            .code = std.ArrayList(u8).empty,
            .constants = std.ArrayList(Value).empty,
            .lines = std.ArrayList(u32).empty,
        };
    }

    pub fn write(self: *Chunk, gpa: std.mem.Allocator, byte: u8, line: u32) !void {
        try self.code.append(gpa, byte);
        try self.lines.append(gpa, line);
    }
};
