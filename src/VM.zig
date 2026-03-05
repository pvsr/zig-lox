const std = @import("std");

const Chunk = @import("Chunk.zig");
const OpCode = Chunk.OpCode;
const compiler = @import("compiler.zig");
const debug = @import("debug.zig");
const Obj = @import("value.zig").Obj;
const Value = @import("value.zig").Value;

const VM = @This();

pub const InterpretResult = enum { ok, compile_error, runtime_error };

const STACK_MAX = 256;

chunk: *Chunk,
ip: [*]u8,
stack: std.ArrayList(Value),
objects: *std.SinglyLinkedList,
gpa: std.mem.Allocator,

pub fn init(gpa: std.mem.Allocator) !VM {
    return .{
        .chunk = undefined,
        .ip = undefined,
        .stack = std.ArrayList(Value).empty,
        .objects = undefined,
        .gpa = gpa,
    };
}

pub fn interpret(self: *VM, source: []const u8) !InterpretResult {
    var chunk = Chunk.init(self.gpa);
    defer chunk.deinit();

    const hadError, const objects = compiler.compile(self.gpa, source, &chunk);
    if (hadError) return .compile_error;

    self.chunk = &chunk;
    self.ip = chunk.code.items.ptr;
    self.objects = objects;
    defer {
        var it = objects.first;
        while (it) |node| {
            const object: *Obj = @fieldParentPtr("node", node);
            switch (object.obj) {
                .string => |str| self.gpa.free(str),
            }
            defer self.gpa.destroy(object);
            it = node.next;
        }
    }
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
        const instruction: OpCode = @enumFromInt(self.readByte());
        switch (instruction) {
            .@"return" => {
                self.pop().print();
                std.debug.print("\n", .{});
                return InterpretResult.ok;
            },
            .negate => {
                switch (self.stack.getLast()) {
                    .number => |a| self.push(.{ .number = -a }),
                    else => {
                        self.runtimeError("Operand must be a number.", .{});
                        return .runtime_error;
                    },
                }
            },
            .add => switch (self.addOrConcat()) {
                .ok => {},
                else => |err| return err,
            },
            .subtract, .multiply, .divide, .greater, .less => switch (self.binaryOp(instruction)) {
                .ok => {},
                else => |err| return err,
            },
            .not => self.push(.{ .bool = isFalsey(self.pop()) }),
            .constant => {
                const constant = self.readConstant();
                constant.print();
                std.debug.print("\n", .{});
                self.push(constant);
            },
            .nil => self.push(Value.nil),
            .true => self.push(.{ .bool = true }),
            .false => self.push(.{ .bool = false }),
            .equal => {
                const b = self.pop();
                const a = self.pop();
                self.push(.{ .bool = a.equals(b) });
            },
        }
    }
}

fn addOrConcat(self: *VM) InterpretResult {
    switch (self.pop()) {
        .number => |b| switch (self.pop()) {
            .number => |a| {
                self.push(.{ .number = a + b });
                return .ok;
            },
            else => |v| self.push(v),
        },
        .obj => |o2| switch (o2.obj) {
            .string => |b| switch (self.pop()) {
                .obj => |o1| switch (o1.obj) {
                    .string => |a| {
                        const str = std.mem.concat(self.gpa, u8, &[_][]const u8{ a, b }) catch unreachable;
                        self.push(.string(self.gpa, self.objects, str));
                        return .ok;
                    },
                },
                else => |v| self.push(v),
            },
        },
        else => {},
    }
    self.runtimeError("Operands must be two numbers or two strings.", .{});
    return .runtime_error;
}

fn binaryOp(self: *VM, op: Chunk.OpCode) InterpretResult {
    switch (self.pop()) {
        .number => |b| switch (self.pop()) {
            .number => |a| {
                const c: Value = switch (op) {
                    .add => .{ .number = a + b },
                    .subtract => .{ .number = a - b },
                    .multiply => .{ .number = a * b },
                    .divide => .{ .number = a / b },
                    .greater => .{ .bool = a > b },
                    .less => .{ .bool = a < b },
                    else => unreachable,
                };
                self.push(c);
                return .ok;
            },
            else => |v| self.push(v),
        },
        else => |v| self.push(v),
    }
    self.runtimeError("Operands must be numbers.", .{});
    return .runtime_error;
}

fn readByte(self: *VM) u8 {
    const byte = self.ip[0];
    self.ip += 1;
    return byte;
}

fn readConstant(self: *VM) Value {
    return self.chunk.constants.items[self.readByte()];
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

    const instruction = self.ip - self.chunk.code.items.ptr - 1;
    const line = self.chunk.lines.items[instruction];
    std.debug.print("[line {d}] in script\n", .{line});
    self.stack.clearRetainingCapacity();
}
