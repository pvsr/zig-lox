const std = @import("std");
const debug = @import("debug.zig");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("chunk.zig").OpCode;
const value = @import("value.zig");

pub const InterpretResult = enum { ok, compile_error, runtime_error };

const DEBUG = true;

const STACK_MAX = 256;

pub const VM = struct {
    chunk: *Chunk,
    ip: [*]u8,
    stack: []value.Value,
    stackTop: [*]value.Value,

    pub fn init(gpa: std.mem.Allocator, chunk: *Chunk) !VM {
        const stack = try gpa.alloc(value.Value, STACK_MAX);
        return VM{
            .chunk = chunk,
            .ip = chunk.code.items.ptr,
            .stack = stack,
            .stackTop = stack.ptr,
        };
    }

    pub fn interpret(self: *VM) InterpretResult {
        while (true) {
            if (DEBUG) {
                std.debug.print("          ", .{});
                for (self.stack[0 .. self.stackTop - self.stack.ptr]) |slot| {
                    std.debug.print("[ ", .{});
                    value.printValue(slot);
                    std.debug.print(" ]", .{});
                }
                std.debug.print("\n", .{});
                _ = debug.disassembleInstruction(self.chunk.*, self.ip - self.chunk.code.items.ptr);
            }
            const instruction: OpCode = @enumFromInt(self.read_byte());
            switch (instruction) {
                OpCode.op_return => {
                    value.printValue(self.pop());
                    std.debug.print("\n", .{});
                    return InterpretResult.ok;
                },
                OpCode.op_negate => self.push(-self.pop()),
                OpCode.op_add => self.push(self.pop() + self.pop()),
                OpCode.op_subtract => self.push(self.pop() - self.pop()),
                OpCode.op_multiply => self.push(self.pop() * self.pop()),
                OpCode.op_divide => self.push(self.pop() / self.pop()),
                OpCode.op_constant => {
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
        self.stackTop[0] = val;
        self.stackTop += 1;
    }

    pub fn pop(self: *VM) value.Value {
        self.stackTop -= 1;
        return self.stackTop[0];
    }
};
