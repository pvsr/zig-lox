const std = @import("std");

const Chunk = @import("Chunk.zig");

pub var DEBUG = false;

pub fn disassembleChunk(chunk: *Chunk, name: []const u8) void {
    std.debug.print("== {s} ==\n", .{name});

    var offset: usize = 0;
    while (offset < chunk.code.items.len) {
        offset = disassembleInstruction(chunk, offset);
    }
}

pub fn disassembleInstruction(chunk: *Chunk, offset: usize) usize {
    std.debug.print("{d:04} ", .{offset});

    if (offset > 0 and chunk.lines.items[offset] == chunk.lines.items[offset - 1]) {
        std.debug.print("   | ", .{});
    } else {
        std.debug.print("{d:4} ", .{chunk.lines.items[offset]});
    }

    const instruction: Chunk.OpCode = @enumFromInt(chunk.code.items[offset]);
    return offset + switch (instruction) {
        .constant, .get_global, .define_global, .set_global => constantInstruction(@tagName(instruction), chunk, offset),
        else => simpleInstruction(@tagName(instruction)),
    };
}

fn simpleInstruction(name: []const u8) u8 {
    std.debug.print("{s}\n", .{name});
    return 1;
}

fn constantInstruction(name: []const u8, chunk: *Chunk, offset: usize) u8 {
    const constant = chunk.code.items[offset + 1];
    std.debug.print("{s:<16} {d:4} '", .{ name, constant });
    chunk.constants.items[constant].print();
    std.debug.print("'\n", .{});
    return 2;
}
