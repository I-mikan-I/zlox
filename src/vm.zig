const std = @import("std");
const chunk = @import("./chunk.zig");
const debug = @import("./debug.zig");
const compiler = @import("./compiler.zig");
const value = @import("./value.zig");
const common = @import("./common.zig");
const Chunk = chunk.Chunk;

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

pub const VM = struct {
    const Value = value.Value;
    const stack_max = 256;
    var stack: [stack_max]Value = undefined;
    alloc: std.mem.Allocator,
    chunk: *Chunk = undefined,
    ip: [*]u8 = undefined,
    stack_top: [*]Value = undefined,

    pub fn initVM(alloc: std.mem.Allocator) VM {
        var vm: VM = .{ .alloc = alloc };
        vm.resetStack();
        return vm;
    }

    pub fn freeVM(self: *VM) void {
        self.chunk.freeChunk();
    }

    pub fn interpret(self: *VM, source: [:0]const u8) InterpretResult {
        var c = chunk.Chunk.init(self.alloc);
        defer c.freeChunk();

        if (!compiler.compile(source, &c)) {
            return .interpret_compile_error;
        }

        self.chunk = &c;
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
                },
                .op_nil => self.push(Value.Nil()),
                .op_true => self.push(Value.Boolean(true)),
                .op_false => self.push(Value.Boolean(false)),
                .op_equal => {
                    var a = self.pop();
                    var b = self.pop();
                    self.push(Value.Boolean(valuesEqual(a, b)));
                },
                .op_negate => {
                    if (!self.peek(0).IsNumber()) {
                        self.runtimeError("Operand must be a number", .{});
                        return .interpret_runtime_error;
                    }
                    self.push(Value.Number(-(self.pop().as.number)));
                },
                .op_greater => self.binary_op(common.greater) orelse return .interpret_runtime_error,
                .op_less => self.binary_op(common.less) orelse return .interpret_runtime_error,
                .op_add => self.binary_op(common.add) orelse return .interpret_runtime_error,
                .op_subtract => self.binary_op(common.sub) orelse return .interpret_runtime_error,
                .op_multiply => self.binary_op(common.mul) orelse return .interpret_runtime_error,
                .op_divide => self.binary_op(common.div) orelse return .interpret_runtime_error,
                .op_not => self.push(Value.Boolean(isFalsey(self.pop()))),
            }
        }
    }

    fn resetStack(self: *VM) void {
        self.stack_top = &stack;
    }

    fn runtimeError(self: *VM, comptime format: []const u8, args: anytype) void {
        stderr.print(format, args) catch unreachable;
        stderr.writeByte('\n') catch unreachable;

        const instruction = @ptrToInt(self.ip) - @ptrToInt(self.chunk.code) - 1;
        const line = self.chunk.lines[instruction];
        stderr.print("[line {d}] in script\n", .{line}) catch unreachable;
        self.resetStack();
    }

    fn push(self: *VM, val: Value) void {
        std.debug.assert(@ptrToInt(self.stack_top) - @ptrToInt(&stack) < stack_max);
        self.stack_top.* = val;
        self.stack_top += 1;
    }

    fn pop(self: *VM) Value {
        std.debug.assert(@ptrToInt(self.stack_top) - @ptrToInt(&stack) > 0);
        self.stack_top -= 1;
        return self.stack_top[0];
    }

    fn peek(self: *VM, comptime distance: comptime_int) Value {
        return (self.stack_top - 1 - distance)[0];
    }

    fn isFalsey(val: Value) bool {
        return val.IsNil() or (val.IsBool() and !val.as.boolean);
    }

    fn valuesEqual(val1: Value, val2: Value) bool {
        if (val1.t != val2.t) return false;
        switch (val1.t) {
            .val_bool => return val1.as.boolean == val2.as.boolean,
            .val_nil => return true,
            .val_number => return val1.as.number == val2.as.number,
        }
    }

    inline fn readByte(self: *VM) u8 {
        const t = self.ip[0];
        self.ip += 1;
        return t;
    }

    inline fn readConstant(self: *VM) Value {
        return self.chunk.constants.values[self.readByte()];
    }

    inline fn binary_op(self: *VM, comptime op: fn (f64, f64) Value) ?void {
        if (!self.peek(0).IsNumber() or !self.peek(1).IsNumber()) {
            self.runtimeError("Operands must be numbers.", .{});
            return null;
        }
        const b = self.pop().as.number;
        const a = self.pop().as.number;
        self.push(op(a, b));
        return;
    }
};

pub const InterpretResult = enum {
    interpret_ok,
    interpret_compile_error,
    interpret_runtime_error,
};
