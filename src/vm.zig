const std = @import("std");
const debug = @import("debug.zig");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("chunk.zig").OpCode;
const value = @import("value.zig");

pub const InterpretResult = enum { ok, compile_error, runtime_error };

const DEBUG = false;

const STACK_MAX = 256;

pub const VM = struct {
    chunk: *Chunk,
    ip: [*]u8,
    stack: std.ArrayList(value.Value),
    gpa: std.mem.Allocator,

    pub fn init(gpa: std.mem.Allocator, chunk: *Chunk) !VM {
        return VM{
            .chunk = chunk,
            .ip = chunk.code.items.ptr,
            .stack = std.ArrayList(value.Value).empty,
            .gpa = gpa,
        };
    }

    pub fn interpret(self: *VM) InterpretResult {
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
                OpCode.@"return" => {
                    value.printValue(self.pop());
                    std.debug.print("\n", .{});
                    return InterpretResult.ok;
                },
                OpCode.negate => self.push(-self.pop()),
                OpCode.add => self.push(self.pop() + self.pop()),
                OpCode.subtract => self.push(self.pop() - self.pop()),
                OpCode.multiply => self.push(self.pop() * self.pop()),
                OpCode.divide => self.push(self.pop() / self.pop()),
                OpCode.constant => {
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
};
