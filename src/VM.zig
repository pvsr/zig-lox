const std = @import("std");

const Chunk = @import("Chunk.zig");
const OpCode = Chunk.OpCode;
const compiler = @import("compiler.zig");
const debug = @import("debug.zig");
const value = @import("value.zig");

const VM = @This();

pub const InterpretResult = enum { ok, compile_error, runtime_error };

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
    var chunk = Chunk.init(self.gpa);
    // defer chunk.deinit();
    if (!compiler.compile(source, &chunk)) {
        return .compile_error;
    }
    self.chunk = &chunk;
    self.ip = chunk.code.items.ptr;
    return self.run();
}

fn run(self: *VM) InterpretResult {
    while (true) {
        if (debug.DEBUG) {
            std.debug.print("          ", .{});
            for (self.stack.items) |slot| {
                std.debug.print("[ ", .{});
                value.printValue(slot);
                std.debug.print(" ]", .{});
            }
            std.debug.print("\n", .{});
            _ = debug.disassembleInstruction(self.chunk, self.ip - self.chunk.code.items.ptr);
        }
        const instruction: OpCode = @enumFromInt(self.read_byte());
        switch (instruction) {
            .@"return" => {
                value.printValue(self.pop());
                std.debug.print("\n", .{});
                return InterpretResult.ok;
            },
            .negate => self.push(-self.pop()),
            .add, .subtract, .multiply, .divide => self.binary_op(instruction),
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

fn binary_op(self: *VM, op: Chunk.OpCode) void {
    const b = self.pop();
    const a = self.pop();
    const c = switch (op) {
        .add => a + b,
        .subtract => a - b,
        .multiply => a * b,
        .divide => a / b,
        else => unreachable,
    };
    self.push(c);
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
