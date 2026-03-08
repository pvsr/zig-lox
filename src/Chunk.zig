const std = @import("std");

const Value = @import("value.zig").Value;

const Chunk = @This();

pub const OpCode = enum(u8) {
    constant,
    nil,
    true,
    false,
    pop,
    get_global,
    define_global,
    set_global,
    equal,
    greater,
    less,
    print,
    @"return",
    not,
    negate,
    add,
    subtract,
    multiply,
    divide,
};

code: std.ArrayList(u8),
constants: std.ArrayList(Value),
lines: std.ArrayList(u32),
gpa: std.mem.Allocator,

pub fn init(gpa: std.mem.Allocator) Chunk {
    return .{
        .code = std.ArrayList(u8).empty,
        .constants = std.ArrayList(Value).empty,
        .lines = std.ArrayList(u32).empty,
        .gpa = gpa,
    };
}

pub fn deinit(self: *Chunk) void {
    self.code.deinit(self.gpa);
    self.constants.deinit(self.gpa);
    self.lines.deinit(self.gpa);
}

pub fn write(self: *Chunk, byte: u8, line: u32) void {
    self.code.append(self.gpa, byte) catch unreachable;
    self.lines.append(self.gpa, line) catch unreachable;
}

pub fn addConstant(self: *Chunk, value: Value) usize {
    self.constants.append(self.gpa, value) catch unreachable;
    return self.constants.items.len - 1;
}
