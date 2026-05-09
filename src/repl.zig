const std = @import("std");
const posix = std.posix;

const VM = @import("VM.zig");

const c = @cImport({
    @cInclude("bestline.h");
});

pub fn run(vm: *VM) !void {
    const sa = posix.Sigaction{
        .handler = .{ .handler = posix.SIG.IGN },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };
    posix.sigaction(posix.SIG.INT, &sa, null);
    while (true) {
        const raw = c.bestlineWithHistory(">> ", "zlox");
        if (raw) |_| {
            const slice = std.mem.span(raw);
            const trimmed = std.mem.trim(u8, slice, " ");
            if (trimmed.len == 0) continue;
            if (trimmed[0] == '.') switch (handleCommand(vm, trimmed[1..])) {
                .handled => continue,
                .exit => return,
            };

            const last = trimmed[trimmed.len - 1];
            const unterminated = last != ';' and last != '}';
            const line = if (unterminated)
                try std.mem.concat(vm.gpa, u8, &[_][]const u8{ trimmed, ";" })
            else
                trimmed;
            defer if (unterminated) vm.gpa.free(line);

            if (vm.interpretStr(line)) |result| {
                if (result) |val| {
                    val.debug();
                    std.debug.print("\n", .{});
                }
            } else |_| {}
            std.c.free(raw);
        } else switch (posix.errno(-1)) {
            // ctrl-c
            .INTR => std.c._errno().* = 0,
            // ctrl-d
            else => return,
        }
    }
}

fn handleCommand(vm: *VM, cmd: []const u8) enum { handled, exit } {
    if (std.mem.eql(u8, "exit", cmd)) return .exit;

    if (std.mem.eql(u8, "vars", cmd)) {
        const count = vm.globals.count();
        std.debug.print("{d} global{s} defined\n", .{ count, if (count == 1) "" else "s" });
        var it = vm.globals.iterator();
        while (it.next()) |entry| {
            std.debug.print("{s}: ", .{entry.key_ptr.*.slice});
            entry.value_ptr.debug();
            std.debug.print("\n", .{});
        }
    } else {
        std.debug.print("unrecognized command {s}\n", .{cmd});
    }
    return .handled;
}
