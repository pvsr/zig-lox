const std = @import("std");

const Chunk = @import("Chunk.zig");
const OpCode = Chunk.OpCode;
const compiler = @import("compiler.zig");
const debug = @import("debug.zig");
const Obj = @import("object.zig").Obj;
const Objects = @import("Objects.zig");
const Table = @import("table.zig").Table;
const Value = @import("value.zig").Value;

const VM = @This();

pub const InterpreterError = error{ CompileError, RuntimeError };

const STACK_MAX = 256;

chunk: *Chunk,
ip: [*]u8,
stack: std.ArrayList(Value),
objects: *Objects,
globals: Table,
gpa: std.mem.Allocator,

pub fn init(gpa: std.mem.Allocator) !VM {
    return .{
        .chunk = undefined,
        .ip = undefined,
        .stack = std.ArrayList(Value).empty,
        .objects = .init(gpa),
        .globals = Table.init(gpa),
        .gpa = gpa,
    };
}

pub fn deinit(self: *VM) void {
    self.stack.deinit(self.gpa);
    self.globals.deinit();
    self.objects.deinit(self.gpa);
}

pub fn interpret(self: *VM, source: *std.Io.Reader) !void {
    var chunk: Chunk = .init(self.gpa);
    defer chunk.deinit();

    if (!compiler.compile(self.gpa, source, &chunk, self.objects))
        return InterpreterError.CompileError;

    self.chunk = &chunk;
    self.ip = chunk.code.items.ptr;
    return self.run();
}

fn run(self: *VM) !void {
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
            .print => {
                self.pop().print();
                std.debug.print("\n", .{});
            },
            .jump => self.jump(self.readShort()),
            .jump_if_false => {
                const offset = self.readShort();
                if (isFalsey(self.peek(0))) self.jump(offset);
            },
            .jump_if_true => {
                const offset = self.readShort();
                if (!isFalsey(self.peek(0))) self.jump(offset);
            },
            .@"return" => return,
            .negate => {
                switch (self.stack.getLast()) {
                    .number => |a| self.push(.{ .number = -a }),
                    else => return self.runtimeError("Operand must be a number.", .{}),
                }
            },
            .add => try self.addOrConcat(),
            .subtract, .multiply, .divide, .greater, .less => try self.binaryOp(instruction),
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
            .pop => _ = self.pop(),
            .get_local => {
                const slot = self.readByte();
                self.push(self.stack.items[slot]);
            },
            .set_local => {
                const slot = self.readByte();
                self.stack.items[slot] = self.peek(0);
            },
            .get_global => {
                const name = self.readConstant().str;
                if (self.globals.get(name)) |value| {
                    self.push(value);
                } else {
                    return self.runtimeError("Undefined variable {s}\n", .{name.slice});
                }
            },
            .define_global => {
                self.globals.put(self.readConstant().str, self.peek(0)) catch unreachable;
                _ = self.pop();
            },
            .set_global => {
                const name = self.readConstant().str;
                const r = self.globals.getOrPut(name) catch unreachable;
                if (!r.found_existing) {
                    return self.runtimeError("Undefined variable '{s}'\n", .{name.slice});
                }
                r.value_ptr.* = self.peek(0);
            },
            .equal => {
                const b = self.pop();
                const a = self.pop();
                self.push(.{ .bool = a.equals(b) });
            },
        }
    }
}

fn addOrConcat(self: *VM) !void {
    switch (self.pop()) {
        .number => |b| switch (self.pop()) {
            .number => |a| {
                self.push(.{ .number = a + b });
                return;
            },
            else => |v| self.push(v),
        },
        .str => |b| switch (self.pop()) {
            .str => |a| {
                const str = std.mem.concat(self.gpa, u8, &[_][]const u8{ a.slice, b.slice }) catch unreachable;
                self.push(.ownedStr(self.gpa, self.objects, str));
                return;
            },
            else => |v| self.push(v),
        },
        else => {},
    }
    return self.runtimeError("Operands must be two numbers or two strings.", .{});
}

fn binaryOp(self: *VM, op: Chunk.OpCode) !void {
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
                return;
            },
            else => |v| self.push(v),
        },
        else => |v| self.push(v),
    }
    return self.runtimeError("Operands must be numbers.", .{});
}

fn readByte(self: *VM) u8 {
    const byte = self.ip[0];
    self.ip += 1;
    return byte;
}

fn readConstant(self: *VM) Value {
    return self.chunk.constants.items[self.readByte()];
}

fn readSignedShort(self: *VM) i16 {
    const short = std.mem.readInt(i16, self.ip[0..2], .little);
    self.ip += 2;
    return short;
}

fn jump(self: *VM, offset: i16) void {
    if (offset < 0) {
        const i: u16 = @intCast(-offset);
        self.ip -= i;
    } else {
        const i: u16 = @intCast(offset);
        self.ip += i;
    }
}

fn push(self: *VM, val: Value) void {
    self.stack.append(self.gpa, val) catch unreachable;
}

fn peek(self: *VM, offset: u8) Value {
    return self.stack.items[self.stack.items.len - (1 + offset)];
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

fn runtimeError(self: *VM, comptime message: []const u8, args: anytype) InterpreterError {
    std.debug.print(message, args);
    std.debug.print("\n", .{});

    const instruction = self.ip - self.chunk.code.items.ptr - 1;
    const line = self.chunk.lines.items[instruction];
    std.debug.print("[line {d}] in script\n", .{line});
    self.stack.clearRetainingCapacity();
    return InterpreterError.RuntimeError;
}

fn interpretStr(self: *VM, source: []const u8) !void {
    var r: std.Io.Reader = .fixed(source);
    return self.interpret(&r);
}

test {
    var vm = try VM.init(std.testing.allocator);
    defer vm.deinit();
    try vm.interpretStr(
        \\print "=" + "=" + "=" + ("=" + "=" + "=");
    );
    try vm.interpretStr(
        \\// print "not printed";
        \\print "hello " + "to" + " " + "read" + "ers" + " " + "of the vm tests";
        \\// print "also not printed"
    );
    try vm.interpretStr(
        \\var x = 1.5;
        \\var y = 2;
        \\print x + y + 3.5;
    );
    try vm.interpretStr(
        \\print !!true;
    );
}
