const std = @import("std");

const VM = @import("VM.zig");

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator = debug_allocator.allocator();
    var stdout_buf: [4096]u8 = undefined;
    var stdout = std.fs.File.stdout().writer(&stdout_buf);
    var stack_buf: VM.StackBuffer = undefined;
    var vm = try VM.init(allocator, &stdout.interface, &stack_buf);
    switch (std.os.argv.len) {
        1 => try repl(&vm),
        2 => try runFile(&vm, std.mem.span(std.os.argv[1])),
        else => {
            std.debug.print("Usage: zlox [path]\n", .{});
            std.process.exit(64);
        },
    }
    vm.deinit();
}

fn repl(vm: *VM) !void {
    var buf: [1024]u8 = undefined;
    var stdin = std.fs.File.stdin().reader(&buf);
    while (true) {
        std.debug.print(">> ", .{});
        if (stdin.interface.takeDelimiter('\n')) |line| {
            if (line) |l| {
                if (std.mem.eql(u8, ".exit;", l)) return;
                vm.interpretStr(l) catch {};
            } else {
                break;
            }
        } else |err| switch (err) {
            error.StreamTooLong => {
                std.debug.print("Input too long, not executing.\n", .{});
                _ = try stdin.interface.discardRemaining();
            },
            error.ReadFailed => return,
        }
    }
}

fn runFile(vm: *VM, path: []const u8) !void {
    const f = try fileReader(path);
    defer f.close();
    var buf: [1024]u8 = undefined;
    var r = f.reader(&buf);
    vm.interpret(&r.interface) catch |err| {
        switch (err) {
            VM.InterpreterError.CompileError => std.process.exit(65),
            VM.InterpreterError.RuntimeError => std.process.exit(70),
        }
    };
}

fn fileReader(path: []const u8) !std.fs.File {
    if (std.fs.cwd().openFile(path, .{})) |f| {
        return f;
    } else |err| {
        std.debug.print("Could not open file {s}: {}\n", .{ path, err });
        std.process.exit(74);
    }
}

test {
    _ = @import("VM.zig");
}
