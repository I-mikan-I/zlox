const std = @import("std");
const chunk = @import("./chunk.zig");
const stdout = std.io.getStdOut().writer();
const stdin = std.io.getStdIn().reader();

var alloc = std.testing.allocator; // todo: replace

const vm = @import("./vm.zig");

pub fn main() anyerror!void {
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
            _ = vm.VM.interpret(slice);
        } else {
            stdout.print("\n", .{}) catch unreachable;
            break;
        }
    }
}

fn runFile(path: []const u8) void {
    const source = readFile(path);
    const result = vm.VM.interpret(source);
    alloc.free(source);
    switch (result) {
        vm.InterpretResult.interpret_compile_error => std.os.exit(65),
        vm.InterpretResult.interpret_runtime_error => std.os.exit(70),
        else => {},
    }
}

fn readFile(path: []const u8) []const u8 {
    var file = std.fs.openFileAbsolute(path, .{}) catch {
        std.log.err("Could not open file {s}.\n", .{path});
        std.os.exit(74);
    };
    defer file.close();

    const buffer = file.readToEndAlloc(alloc, 10 << 20) catch {
        std.log.err("Could not read file {s}.\n", .{path});
        std.os.exit(74);
    };
    return buffer;
}

test "chunks" {
    const debug = @import("./debug.zig");
    const a = std.testing.allocator;
    var c = chunk.Chunk.init(a);
    var constant = c.addConstant(1.2);
    c.writeChunk(@enumToInt(chunk.OpCode.op_constant), 123);
    c.writeChunk(constant, 123);

    constant = c.addConstant(3.4);
    c.writeChunk(@enumToInt(chunk.OpCode.op_constant), 123);
    c.writeChunk(constant, 123);

    c.writeChunk(@enumToInt(chunk.OpCode.op_add), 123);

    constant = c.addConstant(5.6);
    c.writeChunk(@enumToInt(chunk.OpCode.op_constant), 123);
    c.writeChunk(constant, 123);

    c.writeChunk(@enumToInt(chunk.OpCode.op_divide), 123);
    c.writeChunk(@enumToInt(chunk.OpCode.op_negate), 123);
    c.writeChunk(@enumToInt(chunk.OpCode.op_return), 123);
    std.debug.print("\nDISASM\n", .{});
    debug.disassembleChunk(&c, "test chunk"[0..]);
    std.debug.print("\nEXEC\n", .{});
    _ = vm.interpret(&c);
    c.freeChunk();
}
