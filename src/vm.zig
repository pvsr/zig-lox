const std = @import("std");
const debug = @import("debug.zig");
const Chunk = @import("chunk.zig").Chunk;
const OpCode = @import("chunk.zig").OpCode;
const value = @import("value.zig");

pub const InterpretResult = enum { ok, compile_error, runtime_error };

const DEBUG = true;

pub const VM = struct {
    chunk: *Chunk,
    ip: [*]u8,

    pub fn init(chunk: *Chunk) VM {
        return VM{
            .chunk = chunk,
            .ip = chunk.code.items.ptr,
        };
    }

    pub fn interpret(self: *VM) InterpretResult {
        while (true) {
            if (DEBUG) {
                _ = debug.disassembleInstruction(self.chunk.*, self.ip - self.chunk.code.items.ptr);
            }
            const instruction: OpCode = @enumFromInt(self.read_byte());
            switch (instruction) {
                OpCode.op_return => return InterpretResult.ok,
                OpCode.op_constant => {
                    const constant = self.read_constant();
                    value.printValue(constant);
                    std.debug.print("\n", .{});
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
};
