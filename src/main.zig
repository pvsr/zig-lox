const std = @import("std");

const anyline = @import("anyline");
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
}

const CSI = "\x1B[";
fn clearLine() void {
    std.debug.print(CSI ++ "2K" ++ CSI ++ "G", .{});
}

fn repl(vm: *VM) !void {
    // TODO only print if stdin is a terminal
    std.debug.print("zig-lox interpreter 0.0.1\n", .{});
    anyline.usingHistory();
    defer {
        anyline.freeHistory(vm.gpa);
        anyline.freeKillRing(vm.gpa);
    }
    while (true) {
        if (anyline.readLine(vm.gpa, ">> ")) |in| {
            defer vm.gpa.free(in);
            const trimmed = std.mem.trim(u8, in, " ");
            if (trimmed.len == 0) continue;

            const last = trimmed[trimmed.len - 1];
            const unterminated = last != ';' and last != '}';
            const line = if (unterminated)
                try std.mem.concat(vm.gpa, u8, &[_][]const u8{ trimmed, ";" })
            else
                trimmed;
            defer if (unterminated) vm.gpa.free(line);

            if (std.mem.eql(u8, ".exit;", line)) {
                return;
            }

            var r: std.Io.Reader = .fixed(line);
            vm.interpret(&r) catch {};
            try anyline.addHistory(vm.gpa, in);
        } else |err| switch (err) {
            error.ProcessExit => clearLine(),
            error.EndOfInput => return,
            else => return err,
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
