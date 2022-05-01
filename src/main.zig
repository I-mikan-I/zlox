const std = @import("std");
const chunk = @import("./chunk.zig");
const vm = @import("./vm.zig");

const stdout = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();
var alloc = @import("./common.zig").alloc;

var v: vm.VM = undefined;

pub fn main() anyerror!void {
    v = vm.VM.initVM(alloc);
    defer v.freeVM();
    var args = std.process.args();
    _ = args.skip();
    var argv: [1][]const u8 = undefined;
    var index: u8 = 0;
    while (args.next(alloc)) |arg| {
        if (index >= 1) break;
        argv[index] = arg catch continue;
        index += 1;
    }
    if (index == 0) {
        repl();
    } else if (index == 1) {
        runFile(argv[0]);
    } else {
        std.log.err("Usage: clox [path]\n", .{});
    }
}

fn repl() void {
    var line: [1024]u8 = undefined;
    while (true) {
        stdout.print("> ", .{}) catch unreachable;

        if (stdin.readUntilDelimiterOrEof(&line, '\n') catch null) |slice| {
            var source = line[0 .. slice.len + 1];
            source[slice.len] = 0;
            _ = v.interpret(source[0..slice.len :0]);
        } else {
            stdout.print("\n", .{}) catch unreachable;
            break;
        }
    }
}

fn runFile(path: []const u8) void {
    const source = readFile(path);
    const result = v.interpret(source);
    alloc.free(source);
    switch (result) {
        vm.InterpretResult.interpret_compile_error => std.os.exit(65),
        vm.InterpretResult.interpret_runtime_error => std.os.exit(70),
        else => {},
    }
}

fn readFile(path: []const u8) [:0]const u8 {
    var file = std.fs.openFileAbsolute(path, .{}) catch {
        std.log.err("Could not open file {s}.\n", .{path});
        std.os.exit(74);
    };
    defer file.close();

    var buffer = alloc.alloc(u8, (file.stat() catch std.os.exit(74)).size + 1) catch {
        std.log.err("Could not allocate memory.\n", .{});
        std.os.exit(74);
    };

    const length = file.readAll(buffer) catch {
        std.log.err("Could not read file {s}.\n", .{path});
        std.os.exit(74);
    };
    buffer[length] = 0;
    return buffer[0..length :0];
}

test "main-test" {
    v = vm.VM.initVM(std.testing.allocator);
    defer v.freeVM();
    try std.testing.expectEqual(v.interpret("print -(3*8) == ---24;"), vm.InterpretResult.interpret_ok);
}

test "main-string" {
    v = vm.VM.initVM(std.testing.allocator);
    defer v.freeVM();
    try std.testing.expectEqual(v.interpret("print \"hello!\";"), vm.InterpretResult.interpret_ok);
}

test "global var" {
    v = vm.VM.initVM(std.testing.allocator);
    defer v.freeVM();
    try std.testing.expectEqual(v.interpret(
        \\var breakfast = "corn flakes";
        \\breakfast = breakfast + " " + breakfast;
        \\print breakfast;
    ), vm.InterpretResult.interpret_ok);
}
