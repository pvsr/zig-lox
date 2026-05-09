const std = @import("std");

const VM = @import("VM.zig");
const repl = @import("repl.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    var stdout_buf: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buf);
    var stack_buf: VM.StackBuffer = undefined;
    var vm = try VM.init(gpa, &stdout.interface, &stack_buf);
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    switch (args.len) {
        1 => try repl.run(&vm),
        2 => try runFile(init.io, &vm, args[1]),
        else => {
            std.debug.print("Usage: zlox [path]\n", .{});
            std.process.exit(64);
        },
    }
    vm.deinit();
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
