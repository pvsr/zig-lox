const std = @import("std");
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;

const Chunk = @import("Chunk.zig");
const JumpOffset = Chunk.JumpOffset;
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
out: *Writer,

pub fn init(gpa: std.mem.Allocator, out: *Writer) !VM {
    return .{
        .chunk = undefined,
        .ip = undefined,
        .stack = std.ArrayList(Value).empty,
        .objects = .init(gpa),
        .globals = Table.init(gpa),
        .gpa = gpa,
        .out = out,
    };
}

pub fn deinit(self: *VM) void {
    self.stack.deinit(self.gpa);
    self.globals.deinit();
    self.objects.deinit(self.gpa);
}

pub fn interpret(self: *VM, source: *Reader) !void {
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
                slot.debug();
                std.debug.print(" ]", .{});
            }
            std.debug.print("\n", .{});
            _ = debug.disassembleInstruction(self.chunk, self.ip - self.chunk.code.items.ptr);
        }
        const instruction: OpCode = @enumFromInt(self.readByte());
        switch (instruction) {
            .print => self.print(self.pop()) catch return self.runtimeError("Write error.", .{}),
            .jump => self.jump(self.readJumpOffset()),
            .jump_if_false => {
                const offset = self.readJumpOffset();
                if (isFalsey(self.peek(0))) self.jump(offset);
            },
            .jump_if_true => {
                const offset = self.readJumpOffset();
                if (!isFalsey(self.peek(0))) self.jump(offset);
            },
            .@"return" => return,
            .negate => switch (self.stack.getLast()) {
                .number => |a| self.push(.{ .number = -a }),
                else => return self.runtimeError("Operand must be a number.", .{}),
            },
            .add => try self.addOrConcat(),
            .subtract, .multiply, .divide, .greater, .less => try self.binaryOp(instruction),
            .not => self.push(.{ .bool = isFalsey(self.pop()) }),
            .constant => self.push(self.readConstant()),
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

fn readJumpOffset(self: *VM) JumpOffset {
    const short = std.mem.readInt(JumpOffset, self.ip[0..2], .little);
    self.ip += 2;
    return short;
}

fn jump(self: *VM, offset: JumpOffset) void {
    if (offset < 0) {
        const i: u16 = @intCast(-offset);
        self.ip -= i;
    } else {
        const i: u16 = @intCast(offset);
        self.ip += i;
    }
}

fn print(self: *VM, value: Value) !void {
    try value.write(self.out);
    try self.out.writeByte('\n');
    try self.out.flush();
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
    var r: Reader = .fixed(source);
    return self.interpret(&r);
}

test {
    var out_buf: [256]u8 = undefined;
    var w: Writer = .fixed(&out_buf);
    var vm = try VM.init(std.testing.allocator, &w);
    defer vm.deinit();
    try testInterpret(&vm,
        \\print "=" + "=" + "=" + ("=" + "=" + "=");
    , "======\n");
    try testInterpret(&vm,
        \\// print "not printed";
        \\print "hello " + "vm" + " " + "tests";
        \\// print "also not printed"
    , "hello vm tests\n");
    try testInterpret(&vm,
        \\var x = 1.5;
        \\var y = 2;
        \\print x + y + 3.5;
    , "7\n");
    try testInterpret(&vm,
        \\print !!true;
    , "true\n");
}

fn testInterpret(vm: *VM, src: []const u8, expected: []const u8) !void {
    try vm.interpretStr(src);
    try std.testing.expectEqualSlices(u8, vm.out.buffered(), expected);
    _ = vm.out.consumeAll();
}
