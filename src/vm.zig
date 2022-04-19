const std = @import("std");
const chunk = @import("./chunk.zig");
const debug = @import("./debug.zig");
const compiler = @import("./compiler.zig");
const value = @import("./value.zig");
const common = @import("./common.zig");
const Chunk = chunk.Chunk;

const stdout = std.io.getStdOut().writer();

pub const VM = struct {
    const Value = value.Value;
    const stack_max = 256;
    var stack: [stack_max]Value = undefined;
    alloc: std.mem.Allocator,
    chunk: *Chunk = undefined,
    ip: [*]u8 = undefined,
    stack_top: [*]Value = undefined,

    fn initVM(alloc: std.mem.Allocator) VM {
        var vm: VM = .{ .alloc = alloc };
        vm.resetStack();
        return vm;
    }

    fn freeVM() void {}

    pub fn interpret(self: *VM, source: [:0]const u8) InterpretResult {
        var c = chunk.Chunk.init(self.alloc);
        defer c.freeChunk();

        if (!compiler.compile(source, &c)) {
            return .interpret_compile_error;
        }

        self.chunk = c;
        self.ip = self.chunk.code;

        return self.run();
    }

    fn run(self: *VM) InterpretResult {
        while (true) {
            if (common.trace_enabled) {
                stdout.print("          ", .{}) catch unreachable;
                for (stack) |*v| {
                    if (@ptrToInt(v) >= @ptrToInt(self.stack_top)) {
                        break;
                    }
                    stdout.print("[ ", .{}) catch unreachable;
                    value.printValue(v.*, stdout);
                    stdout.print(" ]", .{}) catch unreachable;
                }
                stdout.print("\n", .{}) catch unreachable;
                _ = debug.disassembleInstruction(self.chunk, @intCast(u32, @ptrToInt(self.ip) - @ptrToInt(self.chunk.code)));
            }
            const inst = @intToEnum(chunk.OpCode, self.readByte());
            switch (inst) {
                .op_return => {
                    value.printValue(self.pop(), stdout);
                    stdout.print("\n", .{}) catch unreachable;
                    return .interpret_ok;
                },
                .op_constant => {
                    const constant = self.readConstant();
                    self.push(constant);
                    stdout.print("\n", .{}) catch unreachable;
                },
                .op_negate => {
                    self.push(-self.pop());
                },
                .op_add => self.binary_op(common.add),
                .op_subtract => self.binary_op(common.sub),
                .op_multiply => self.binary_op(common.mul),
                .op_divide => self.binary_op(common.div),
            }
        }
    }

    fn resetStack(self: *VM) void {
        self.stack_top = &stack;
    }

    fn push(self: *VM, val: Value) void {
        std.debug.assert(@ptrToInt(self.stack_top) - @ptrToInt(&stack) < stack_max);
        self.stack_top.* = val;
        self.stack_top += 1;
    }

    fn pop(
        self: *VM,
    ) Value {
        std.debug.assert(@ptrToInt(self.stack_top) - @ptrToInt(&stack) > 0);
        self.stack_top -= 1;
        return self.stack_top[0];
    }

    inline fn readByte(self: *VM) u8 {
        const t = self.ip[0];
        self.ip += 1;
        return t;
    }

    inline fn readConstant(self: *VM) Value {
        return self.chunk.constants.values[self.readByte()];
    }

    inline fn binary_op(self: *VM, comptime op: fn (anytype, anytype) Value) void {
        const b = self.pop();
        const a = self.pop();
        self.push(op(a, b));
    }
};

pub const InterpretResult = enum {
    interpret_ok,
    interpret_compile_error,
    interpret_runtime_error,
};
