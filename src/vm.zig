const std = @import("std");
const chunk = @import("./chunk.zig");
const debug = @import("./debug.zig");
const compiler = @import("./compiler.zig");
const memory = @import("./memory.zig");
const object = @import("./object.zig");
const value = @import("./value.zig");
const common = @import("./common.zig");
const Table = @import("./table.zig").Table;
const Chunk = chunk.Chunk;

var stdout = common.stdout;
var stderr = common.stderr;

pub const VM = struct {
    const Value = value.Value;
    const stack_max = 256;
    pub var objects: ?*object.Obj = null; // linked list of allocated objects
    pub var strings: Table = undefined;
    globals: Table = Table.initTable(),
    stack: *[stack_max]Value = undefined,
    alloc: std.mem.Allocator,
    chunk: *Chunk = undefined,
    ip: [*]u8 = undefined,
    stack_top: [*]Value = undefined,

    pub fn initVM(alloc: std.mem.Allocator) VM {
        var vm: VM = .{ .alloc = alloc };
        vm.stack = alloc.create([stack_max]Value) catch std.os.exit(1);
        vm.resetStack();
        strings = Table.initTable();
        return vm;
    }

    pub fn freeVM(self: *VM) void {
        strings.freeTable();
        self.globals.freeTable();
        memory.freeObjects(self.alloc);
        self.alloc.destroy(self.stack);
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
                for (self.stack) |*v| {
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
                    return .interpret_ok;
                },
                .op_jump => {
                    const offset = self.readShort();
                    self.ip += offset;
                },
                .op_jump_if_false => {
                    const offset = self.readShort();
                    if (isFalsey(self.peek(0))) self.ip += offset;
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
                    self.push(Value.Boolean(value.valuesEqual(a, b)));
                },
                .op_negate => {
                    if (!self.peek(0).isNumber()) {
                        self.runtimeError("Operand must be a number", .{});
                        return .interpret_runtime_error;
                    }
                    self.push(Value.Number(-(self.pop().as.number)));
                },
                .op_print => {
                    value.printValue(self.pop(), stdout);
                    stdout.print("\n", .{}) catch unreachable;
                },
                .op_pop => {
                    _ = self.pop();
                },
                .op_get_local => {
                    const slot = self.readByte();
                    self.push(self.stack[slot]);
                },
                .op_get_global => {
                    const name = self.readString();
                    if (self.globals.tableGet(name)) |v| {
                        self.push(v);
                    } else {
                        self.runtimeError("Undefined variable '{s}'", .{name.chars[0..name.length]});
                        return .interpret_runtime_error;
                    }
                },
                .op_define_global => {
                    const name = self.readString();
                    _ = self.globals.tableSet(name, self.peek(0));
                    _ = self.pop();
                },
                .op_set_local => {
                    const slot = self.readByte();
                    self.stack[slot] = self.peek(0);
                },
                .op_set_global => {
                    const name = self.readString();
                    if (self.globals.tableSet(name, self.peek(0))) {
                        _ = self.globals.tableDelete(name);
                        self.runtimeError("Undefined variable '{s}'", .{name.chars[0..name.length]});
                        return .interpret_runtime_error;
                    }
                },
                .op_greater => self.binary_op(common.greater) orelse return .interpret_runtime_error,
                .op_less => self.binary_op(common.less) orelse return .interpret_runtime_error,
                .op_add => {
                    const a = self.peek(0);
                    const b = self.peek(1);
                    if (a.isString() and b.isString()) self.concatenate() else if (a.isNumber() and b.isNumber()) {
                        _ = self.pop();
                        _ = self.pop();
                        self.push(Value.Number(a.as.number + b.as.number));
                    } else {
                        self.runtimeError("Operand must be two numbers or two strings.", .{});
                        return .interpret_runtime_error;
                    }
                },
                .op_subtract => self.binary_op(common.sub) orelse return .interpret_runtime_error,
                .op_multiply => self.binary_op(common.mul) orelse return .interpret_runtime_error,
                .op_divide => self.binary_op(common.div) orelse return .interpret_runtime_error,
                .op_not => self.push(Value.Boolean(isFalsey(self.pop()))),
            }
        }
    }

    fn resetStack(self: *VM) void {
        self.stack_top = self.stack;
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
        std.debug.assert(@ptrToInt(self.stack_top) - @ptrToInt(self.stack) < stack_max);
        self.stack_top.* = val;
        self.stack_top += 1;
    }

    fn pop(self: *VM) Value {
        std.debug.assert(@ptrToInt(self.stack_top) - @ptrToInt(self.stack) > 0);
        self.stack_top -= 1;
        return self.stack_top[0];
    }

    fn peek(self: *VM, comptime distance: comptime_int) Value {
        return (self.stack_top - 1 - distance)[0];
    }

    fn isFalsey(val: Value) bool {
        return val.isNil() or (val.isBool() and !val.as.boolean);
    }

    fn concatenate(self: *VM) void {
        const b = self.pop().as.obj.asString();
        const a = self.pop().as.obj.asString();
        const length = a.length + b.length;
        const chars = memory.allocate(u8, length + 1, self.alloc);
        std.mem.copy(u8, chars[0..a.length], a.chars[0..a.length]);
        std.mem.copy(u8, chars[a.length..length], b.chars[0..b.length]);
        chars[length] = 0;
        self.push(Value.Object(object.takeString(chars, length)));
    }

    inline fn readByte(self: *VM) u8 {
        const t = self.ip[0];
        self.ip += 1;
        return t;
    }

    inline fn readConstant(self: *VM) Value {
        return self.chunk.constants.values[self.readByte()];
    }

    inline fn readString(self: *VM) *object.ObjString {
        return self.readConstant().as.obj.asString();
    }

    inline fn binary_op(self: *VM, comptime op: fn (f64, f64) Value) ?void {
        if (!self.peek(0).isNumber() or !self.peek(1).isNumber()) {
            self.runtimeError("Operands must be numbers.", .{});
            return null;
        }
        const b = self.pop().as.number;
        const a = self.pop().as.number;
        self.push(op(a, b));
        return;
    }

    inline fn readShort(self: *VM) u16 {
        self.ip += 2;
        return (@intCast(u16, (self.ip - 2)[0]) << 8) | (self.ip - 1)[0];
    }
};

pub const InterpretResult = enum {
    interpret_ok,
    interpret_compile_error,
    interpret_runtime_error,
};
