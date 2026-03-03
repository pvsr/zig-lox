const std = @import("std");

const Chunk = @import("Chunk.zig");
const value = @import("value.zig");

pub const DEBUG = true;

pub fn disassembleChunk(chunk: *Chunk, name: []const u8) void {
    std.debug.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunk.code.items.len) {
        offset = disassembleInstruction(chunk, offset);
    }
}

pub fn disassembleInstruction(chunk: *Chunk, offset: usize) usize {
    std.debug.print("{d:04} ", .{offset});

    // TODO fix lines
    // if (offset > 0 and chunk.lines.items[offset] == chunk.lines.items[offset - 1]) {
    //     std.debug.print("   | ", .{});
    // } else {
    //     std.debug.print("{d:4} ", .{chunk.lines.items[offset]});
    // }

    const instruction: Chunk.OpCode = @enumFromInt(chunk.code.items[offset]);
    return offset + switch (instruction) {
        .@"return", .negate, .add, .subtract, .multiply, .divide => simpleInstruction(@tagName(instruction)),
        .constant => constantInstruction(@tagName(instruction), chunk, offset),
        _ => blk: {
            std.debug.print("Unknown opcode {d}\n", .{instruction});
            break :blk 1;
        },
    };
}

fn simpleInstruction(name: []const u8) u8 {
    std.debug.print("{s}\n", .{name});
    return 1;
}

fn constantInstruction(name: []const u8, chunk: *Chunk, offset: usize) u8 {
    const constant = chunk.code.items[offset + 1];
    std.debug.print("{s:<16} {d:4} '", .{ name, constant });
    value.printValue(chunk.constants.items[constant]);
    std.debug.print("'\n", .{});
    return 2;
}
