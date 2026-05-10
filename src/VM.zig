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

const log = @import("log.zig").scoped(.compile);

const VM = @This();

pub const InterpreterError = error{ CompileError, RuntimeError };

const STACK_MAX = 255;

gpa: std.mem.Allocator,
out: *Writer,
globals: Table,
objects: *Objects,
stack: std.ArrayListUnmanaged(Value),
chunk: *Chunk = undefined,
ip: [*]u8 = undefined,

pub const StackBuffer = [STACK_MAX]Value;

pub fn init(gpa: std.mem.Allocator, out: *Writer, stack_buf: *StackBuffer) !VM {
    return .{
        .gpa = gpa,
        .out = out,
        .globals = .init(gpa),
        .objects = .init(gpa),
        .stack = .initBuffer(stack_buf),
    };
}

pub fn deinit(self: *VM) void {
    self.globals.deinit();
    self.objects.deinit(self.gpa);
}

pub fn interpret(self: *VM, source: *Reader) !?Value {
    var chunk: Chunk = .init(self.gpa);
    defer chunk.deinit();

    if (!compiler.compile(self.gpa, source, &chunk, self.objects))
        return InterpreterError.CompileError;

    self.chunk = &chunk;
    self.ip = chunk.code.items.ptr;
    return self.run();
}

fn run(self: *VM) !?Value {
    var result: ?Value = null;
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
        if (instruction != .@"return") result = null;
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
            .@"return" => return result,
            .negate => switch (self.stack.getLast()) {
                .number => self.push(.{ .number = -self.pop().number }),
                else => return self.runtimeError("Operand must be a number.", .{}),
            },
            .add => try self.addOrConcat(),
            .subtract, .multiply, .divide, .greater, .less => try self.binaryOp(instruction),
            .not => self.push(.{ .bool = isFalsey(self.pop()) }),
            .constant => self.push(self.readConstant()),
            .nil => self.push(Value.nil),
            .true => self.push(.{ .bool = true }),
            .false => self.push(.{ .bool = false }),
            .pop => result = self.pop(),
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
                    return self.runtimeError("Undefined variable '{s}'\n", .{name.slice});
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
    return result;
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
    self.stack.appendAssumeCapacity(val);
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
    const instruction = self.ip - self.chunk.code.items.ptr - 1;
    const line = self.chunk.lines.items[instruction];
    log.err("[line {d}] " ++ message, .{line} ++ args);
    self.stack.clearRetainingCapacity();
    return InterpreterError.RuntimeError;
}

pub fn interpretStr(self: *VM, source: []const u8) !?Value {
    var r: Reader = .fixed(source);
    return self.interpret(&r);
}

test {
    @import("log.zig").LOG = false;
    var out_buf: [256]u8 = undefined;
    var out: Writer = .fixed(&out_buf);
    var stack_buf: StackBuffer = undefined;
    var vm = try VM.init(std.testing.allocator, &out, &stack_buf);
    defer vm.deinit();

    try testInterpretErr(&vm, "var = 0;", error.CompileError);
    try testInterpretErr(&vm, "1 + true;", error.RuntimeError);

    try testInterpret(&vm, "!true;", .{ .bool = false });
    try testInterpret(&vm, "!!true;", .{ .bool = true });
    try testInterpret(&vm, "100 / -5;", .{ .number = -20 });
    try testInterpret(&vm,
        \\"=" + "=" + "=" + ("=" + "=" + "=");
    , testStr(&vm, "======"));
    try testInterpret(&vm,
        \\var x = 1.5;
        \\var y = -2;
        \\x + y + 3.5;
    , .{ .number = 3 });

    try testInterpretOut(&vm, "{var a = 1; print a;}", "1\n");
    try testInterpretOut(&vm,
        \\// print "not printed";
        \\print "hello " + "vm" + " " + "tests";
        \\// print "also not printed"
    , "hello vm tests\n");
    try testInterpretOut(&vm,
        \\var i = 0;
        \\while (i < 3) { print i; i = i + 1; }
    , "0\n1\n2\n");
    try testInterpretOut(&vm,
        \\for (var i = 0; i < 3; i = i + 1) { print i; }
    , "0\n1\n2\n");
}
fn testStr(vm: *VM, slice: []const u8) Value {
    return .copyStr(vm.gpa, vm.objects, slice);
}

fn testInterpret(vm: *VM, src: []const u8, expected: Value) !void {
    const result = try vm.interpretStr(src);
    try std.testing.expect(result != null);
    try std.testing.expectEqual(expected, result.?);
}

fn testInterpretOut(vm: *VM, src: []const u8, expected: []const u8) !void {
    _ = try vm.interpretStr(src);
    try std.testing.expectEqualSlices(u8, expected, vm.out.buffered());
    _ = vm.out.consumeAll();
}

fn testInterpretErr(vm: *VM, src: []const u8, expected: anyerror) !void {
    try std.testing.expectError(expected, vm.interpretStr(src));
}
