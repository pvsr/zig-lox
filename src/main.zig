const std = @import("std");

const VM = @import("VM.zig");

const c = @cImport({
    @cInclude("bestline.h");
});

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var stdout_buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buf);
    var stack_buf: VM.StackBuffer = undefined;
    var vm = try VM.init(gpa, &stdout.interface, &stack_buf);
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    switch (args.len) {
        1 => try repl(&vm),
        2 => try runFile(init.io, &vm, args[1]),
        else => {
            std.debug.print("Usage: zlox [path]\n", .{});
            std.process.exit(64);
        },
    }
    vm.deinit();
}

fn repl(vm: *VM) !void {
    const sa = std.posix.Sigaction{
        .handler = .{ .handler = std.posix.SIG.IGN },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &sa, null);
    while (true) {
        const raw = c.bestlineWithHistory(">> ", "zlox");
        if (raw) |_| {
            const slice = std.mem.span(raw);
            const trimmed = std.mem.trim(u8, slice, " ");
            if (trimmed.len == 0) continue;
            if (std.mem.eql(u8, ".exit", trimmed)) return;

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
        } else switch (std.posix.errno(-1)) {
            // ctrl-c
            .INTR => std.c._errno().* = 0,
            // ctrl-d
            else => return,
        }
    }
}

fn runFile(io: std.Io, vm: *VM, path: []const u8) !void {
    const f = try fileReader(io, path);
    defer f.close(io);
    var buf: [1024]u8 = undefined;
    var r = f.reader(io, &buf);
    _ = vm.interpret(&r.interface) catch |err| {
        switch (err) {
            VM.InterpreterError.CompileError => std.process.exit(65),
            VM.InterpreterError.RuntimeError => std.process.exit(70),
        }
    };
}

fn fileReader(io: std.Io, path: []const u8) !std.Io.File {
    if (std.Io.Dir.cwd().openFile(io, path, .{})) |f| {
        return f;
    } else |err| {
        std.debug.print("Could not open file {s}: {}\n", .{ path, err });
        std.process.exit(74);
    }
}

test {
    _ = @import("VM.zig");
}
