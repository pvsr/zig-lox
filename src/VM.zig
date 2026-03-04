const std = @import("std");

const Chunk = @import("Chunk.zig");
const OpCode = Chunk.OpCode;
const compiler = @import("compiler.zig");
const debug = @import("debug.zig");
const Value = @import("value.zig").Value;

const VM = @This();

pub const InterpretResult = enum { ok, compile_error, runtime_error };

const STACK_MAX = 256;

chunk: *Chunk,
ip: [*]u8,
stack: std.ArrayList(Value),
gpa: std.mem.Allocator,

pub fn init(gpa: std.mem.Allocator) !VM {
    return VM{
        .chunk = undefined,
        .ip = undefined,
        .stack = std.ArrayList(Value).empty,
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
                slot.print();
                std.debug.print(" ]", .{});
            }
            std.debug.print("\n", .{});
            _ = debug.disassembleInstruction(self.chunk, self.ip - self.chunk.code.items.ptr);
        }
        const instruction: OpCode = @enumFromInt(self.read_byte());
        switch (instruction) {
            .@"return" => {
                self.pop().print();
                std.debug.print("\n", .{});
                return InterpretResult.ok;
            },
            .negate => {
                switch (self.stack.getLast()) {
                    .number => |a| self.push(Value{ .number = -a }),
                    else => {
                        self.runtimeError("Operand must be a number.", .{});
                        return .runtime_error;
                    },
                }
            },
            .add, .subtract, .multiply, .divide => switch (self.binary_op(instruction)) {
                .ok => {},
                else => |err| return err,
            },
            .not => self.push(Value{ .bool = isFalsey(self.pop()) }),
            .constant => {
                const constant = self.read_constant();
                constant.print();
                std.debug.print("\n", .{});
                self.push(constant);
            },
            .nil => self.push(Value{ .nil = undefined }),
            .true => self.push(Value{ .bool = true }),
            .false => self.push(Value{ .bool = false }),
        }
    }
}

fn binary_op(self: *VM, op: Chunk.OpCode) InterpretResult {
    switch (self.pop()) {
        .number => |a| switch (self.pop()) {
            .number => |b| {
                const c = switch (op) {
                    .add => a + b,
                    .subtract => a - b,
                    .multiply => a * b,
                    .divide => a / b,
                    else => unreachable,
                };
                self.push(Value{ .number = c });
                return .ok;
            },
            else => |v| self.push(v),
        },
        else => |v| self.push(v),
    }
    self.runtimeError("Operands must be numbers.", .{});
    return .runtime_error;
}

fn read_byte(self: *VM) u8 {
    const byte = self.ip[0];
    self.ip += 1;
    return byte;
}

fn read_constant(self: *VM) Value {
    return self.chunk.constants.items[self.read_byte()];
}

fn push(self: *VM, val: Value) void {
    self.stack.append(self.gpa, val) catch unreachable;
}

pub fn pop(self: *VM) Value {
    return self.stack.pop().?;
}

fn isFalsey(value: Value) bool {
    return switch (value) {
        .nil => true,
        .bool => |b| !b,
        else => false,
    };
}

fn runtimeError(self: *VM, comptime message: []const u8, args: anytype) void {
    std.debug.print(message, args);
    std.debug.print("\n", .{});

    // TODO
    // const instruction = self.ip - self.chunk.code.items.ptr - 1;
    // const line = self.chunk.lines.items[instruction];
    // std.debug.print("[line {d}] in script\n", .{line});
    self.stack.clearRetainingCapacity();
}
