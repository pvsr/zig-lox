const std = @import("std");

const VM = @import("VM.zig");

pub fn main() !void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    const allocator = debug_allocator.allocator();
    var vm = try VM.init(allocator);
    switch (std.os.argv.len) {
        1 => try repl(&vm),
        2 => try runFile(&vm, std.mem.span(std.os.argv[1])),
        else => {
            std.debug.print("Usage: zlox [path]\n", .{});
            std.process.exit(64);
        },
    }
    vm.deinit();
    _ = debug_allocator.detectLeaks();
}

fn repl(vm: *VM) !void {
    var buf: [1024]u8 = undefined;
    var line: [1024]u8 = undefined;
    var w: std.io.Writer = .fixed(&line);
    while (true) {
        var stdin = std.fs.File.stdin().reader(&buf);

        std.debug.print("> ", .{});
        if (stdin.interface.streamDelimiter(&w, '\n')) |len| {
            try vm.interpret(line[0..len]);
        } else |err| switch (err) {
            error.EndOfStream => return,
            else => unreachable,
        }
    }
}

fn runFile(vm: *VM, path: []const u8) !void {
    const source = try readFile(vm.gpa, path);
    defer vm.gpa.free(source);
    vm.interpret(source) catch |err| {
        switch (err) {
            VM.InterpreterError.CompileError => std.process.exit(65),
            VM.InterpreterError.RuntimeError => std.process.exit(70),
        }
    };
}

fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    if (std.fs.cwd().openFile(path, .{})) |f| {
        defer f.close();
        var buf: [1024]u8 = undefined;
        var r = f.reader(&buf);
        return r.interface.allocRemaining(allocator, .unlimited);
    } else |err| {
        std.debug.print("Could not open file {s}: {}\n", .{ path, err });
        std.process.exit(74);
    }
}
