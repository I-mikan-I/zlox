const std = @import("std");
const chunk = @import("./chunk.zig");
const vm = @import("./vm.zig");
const common = @import("./common.zig");

const stdout = common.stdout;
const stdin = std.io.getStdIn().reader();
var alloc = @import("./common.zig").alloc;

var v: vm.VM = .{};

pub fn main() anyerror!void {
    v.initVM();
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
    var file = std.fs.cwd().openFile(path, .{}) catch {
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
    v.initVM();
    defer v.freeVM();
    try std.testing.expectEqual(v.interpret("print -(3*8) == ---24;"), vm.InterpretResult.interpret_ok);
}

test "main-string" {
    v.initVM();
    defer v.freeVM();
    try std.testing.expectEqual(v.interpret("print \"hello!\";"), vm.InterpretResult.interpret_ok);
}

test "global var" {
    v.initVM();
    defer v.freeVM();
    try std.testing.expectEqual(v.interpret(
        \\var breakfast = "corn flakes";
        \\breakfast = breakfast + " " + breakfast;
        \\print breakfast;
    ), vm.InterpretResult.interpret_ok);
}

test "local var" {
    v.initVM();
    defer v.freeVM();
    common.buffer_stream.reset();
    const expected = "hello another world\n";
    try std.testing.expectEqual(v.interpret(
        \\var global = "hello";
        \\{
        \\  var local = "world";
        \\  {
        \\    var local = " another ";
        \\    global = global + local;
        \\  }
        \\  global = global + local;
        \\}
        \\print global;
    ), vm.InterpretResult.interpret_ok);
    try std.testing.expectEqualStrings(expected, common.buffer_stream.getWritten());
}

test "loops" {
    v.initVM();
    defer v.freeVM();
    common.buffer_stream.reset();
    const expected = "1000\n";
    try std.testing.expectEqual(v.interpret(
        \\var counter = 0;
        \\for (var index = 0; index < 1000; index = index + 1) {
        \\  counter = counter + 1;
        \\}
        \\print counter;
    ), vm.InterpretResult.interpret_ok);
    try std.testing.expectEqualStrings(expected, common.buffer_stream.getWritten());
}

test "functions" {
    v.initVM();
    defer v.freeVM();
    common.buffer_stream.reset();
    const expected = "true\nfalse\ntrue\n";
    try std.testing.expectEqual(v.interpret(
        \\fun even(num) {
        \\  if (num == 0) return true;
        \\  return odd(num - 1);
        \\}
        \\fun odd(num) {
        \\  if (num == 0) return false;
        \\  return even(num - 1);
        \\}
        \\print even(22);
        \\print even(21);
        \\print odd(3);
    ), vm.InterpretResult.interpret_ok);
    try std.testing.expectEqualStrings(expected, common.buffer_stream.getWritten());
}

test "closure_outer" {
    v.initVM();
    defer v.freeVM();
    common.buffer_stream.reset();
    const expected = "outside\n";
    try std.testing.expectEqual(v.interpret(
        \\fun outer() {
        \\var x = "outside";
        \\fun inner() {
        \\print x;
        \\}
        \\inner();
        \\}
        \\outer();
    ), vm.InterpretResult.interpret_ok);
    try std.testing.expectEqualStrings(expected, common.buffer_stream.getWritten());
}

test "closure_reference" {
    v.initVM();
    defer v.freeVM();
    common.buffer_stream.reset();
    const expected = "updated\n";
    try std.testing.expectEqual(v.interpret(
        \\var globalSet;
        \\var globalGet;
        \\fun main() {
        \\    var a = "initial";
        \\    fun set() { a = "updated"; }
        \\    fun get() { print a; }
        \\    globalSet = set;
        \\    globalGet = get;
        \\}
        \\main();
        \\globalSet();
        \\globalGet();
    ), vm.InterpretResult.interpret_ok);
    try std.testing.expectEqualStrings(expected, common.buffer_stream.getWritten());
}

test "field_access" {
    v.initVM();
    defer v.freeVM();
    common.buffer_stream.reset();
    const expected = "3\n";
    try std.testing.expectEqual(v.interpret(
        \\class Pair {}
        \\var pair = Pair();
        \\pair.first = 1;
        \\pair.second = 2;
        \\print pair.first + pair.second;
    ), vm.InterpretResult.interpret_ok);
    try std.testing.expectEqualStrings(expected, common.buffer_stream.getWritten());
}

test "methods" {
    v.initVM();
    defer v.freeVM();
    common.buffer_stream.reset();
    const expected = "Enjoy your cup of coffee and chicory\n";
    try std.testing.expectEqual(v.interpret(
        \\class CoffeeMaker {
        \\    init(coffee) {
        \\        this.coffee = coffee;
        \\    }
        \\    brew() {
        \\        print "Enjoy your cup of " + this.coffee;
        \\        this.coffee = nil;
        \\    }
        \\}
        \\var maker = CoffeeMaker("coffee and chicory");
        \\maker.brew();
    ), vm.InterpretResult.interpret_ok);
    try std.testing.expectEqualStrings(expected, common.buffer_stream.getWritten());
}

test "field call" {
    v.initVM();
    defer v.freeVM();
    common.buffer_stream.reset();
    const expected = "indirection\n";
    try std.testing.expectEqual(v.interpret(
        \\class CoffeeMaker {
        \\    init() {
        \\        fun f() {
        \\          print this.word;
        \\        }
        \\        this.fn = f;
        \\    }
        \\}
        \\var maker = CoffeeMaker();
        \\maker.word = "indirection";
        \\maker.fn();
    ), vm.InterpretResult.interpret_ok);
    try std.testing.expectEqualStrings(expected, common.buffer_stream.getWritten());
}

test "super" {
    v.initVM();
    defer v.freeVM();
    common.buffer_stream.reset();
    const expected = "Cutting food...\nCooking at 90 degrees!\n";
    try std.testing.expectEqual(v.interpret(
        \\class Base {
        \\    cook() {
        \\        print "Cooking at " + this.getTemp();
        \\    }
        \\    getTemp() {
        \\        return "100 degrees!";
        \\    }
        \\}
        \\class Derived < Base {
        \\    getTemp() {
        \\        return "90 degrees!";
        \\    }
        \\    cook() {
        \\        print "Cutting food...";
        \\        super.cook();
        \\    }
        \\}
        \\var d = Derived();
        \\d.cook();
    ), vm.InterpretResult.interpret_ok);
    try std.testing.expectEqualStrings(expected, common.buffer_stream.getWritten());
}
