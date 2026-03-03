const std = @import("std");

const Scanner = @import("Scanner.zig");

pub fn compile(source: []const u8) void {
    var scanner = Scanner.init(source);
    var line: i32 = -1;
    while (true) {
        const token = scanner.scanToken();
        if (token.line != line) {
            std.debug.print("{d:4} ", .{token.line});
            line = token.line;
        } else {
            std.debug.print("   | ", .{});
        }
        std.debug.print("{d:2} '{s}'\n", .{ token.type, token.slice });

        if (token.type == .eof) break;
    }
}
