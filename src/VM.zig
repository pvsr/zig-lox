const std = @import("std");

const Chunk = @import("Chunk.zig");
const OpCode = Chunk.OpCode;
const compiler = @import("compiler.zig");
const debug = @import("debug.zig");
const value = @import("value.zig");

const VM = @This();

pub const InterpretResult = enum { ok, compile_error, runtime_error };

const DEBUG = false;
const STACK_MAX = 256;

chunk: *Chunk,
ip: [*]u8,
stack: std.ArrayList(value.Value),
gpa: std.mem.Allocator,

pub fn init(gpa: std.mem.Allocator) !VM {
    return VM{
        .chunk = undefined,
        .ip = undefined,
        .stack = std.ArrayList(value.Value).empty,
        .gpa = gpa,
    };
}

pub fn interpret(self: *VM, source: []const u8) !InterpretResult {
    compiler.compile(source);
    var c = Chunk.init();
    try c.constants.append(self.gpa, 2.1);
    try c.constants.append(self.gpa, 1);
    try c.constants.append(self.gpa, 0);
    try c.write(self.gpa, @intFromEnum(OpCode.constant), 1);
    try c.write(self.gpa, 0, 1);
    try c.write(self.gpa, @intFromEnum(OpCode.constant), 2);
    try c.write(self.gpa, 1, 2);
    try c.write(self.gpa, @intFromEnum(OpCode.constant), 3);
    try c.write(self.gpa, 2, 3);
    try c.write(self.gpa, @intFromEnum(OpCode.constant), 3);
    try c.write(self.gpa, 0, 3);
    try c.write(self.gpa, @intFromEnum(OpCode.negate), 3);
    try c.write(self.gpa, @intFromEnum(OpCode.add), 3);
    try c.write(self.gpa, @intFromEnum(OpCode.@"return"), 3);
    return self.interpretChunk(&c);
}

fn interpretChunk(self: *VM, chunk: *Chunk) InterpretResult {
    self.chunk = chunk;
    self.ip = chunk.code.items.ptr;
    return self.run();
}

fn run(self: *VM) InterpretResult {
    while (true) {
        if (DEBUG) {
            std.debug.print("          ", .{});
            for (self.stack.items) |slot| {
                std.debug.print("[ ", .{});
                value.printValue(slot);
                std.debug.print(" ]", .{});
            }
            std.debug.print("\n", .{});
            _ = debug.disassembleInstruction(self.chunk.*, self.ip - self.chunk.code.items.ptr);
        }
        const instruction: OpCode = @enumFromInt(self.read_byte());
        switch (instruction) {
            .@"return" => {
                value.printValue(self.pop());
                std.debug.print("\n", .{});
                return InterpretResult.ok;
            },
            .negate => self.push(-self.pop()),
            .add => self.push(self.pop() + self.pop()),
            .subtract => self.push(self.pop() - self.pop()),
            .multiply => self.push(self.pop() * self.pop()),
            .divide => self.push(self.pop() / self.pop()),
            .constant => {
                const constant = self.read_constant();
                value.printValue(constant);
                std.debug.print("\n", .{});
                self.push(constant);
            },
            _ => std.debug.print("Unknown opcode {d}\n", .{instruction}),
        }
    }
}

fn read_byte(self: *VM) u8 {
    const byte = self.ip[0];
    self.ip += 1;
    return byte;
}

fn read_constant(self: *VM) value.Value {
    return self.chunk.constants.items[self.read_byte()];
}

fn push(self: *VM, val: value.Value) void {
    self.stack.append(self.gpa, val) catch unreachable;
}

pub fn pop(self: *VM) value.Value {
    return self.stack.pop().?;
}
