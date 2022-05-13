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
const Value = value.Value;
const Obj = object.Obj;
const ObjFunction = object.ObjFunction;

var stdout = common.stdout;
var stderr = common.stderr;

const CallFrame = struct {
    function: *ObjFunction,
    ip: [*]u8,
    slots: [*]Value,
};

pub const VM = struct {
    const frames_max = 64;
    const stack_max = frames_max * 256;
    pub var objects: ?*object.Obj = null; // linked list of allocated objects
    pub var strings: Table = undefined;
    frames: [frames_max]CallFrame = undefined,
    frame_count: usize = 0,
    frame: *CallFrame = undefined,
    globals: Table = Table.initTable(),
    stack: *[stack_max]Value = undefined,
    alloc: std.mem.Allocator,
    chunk: *Chunk = undefined,
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
        var function = compiler.compile(source) orelse return .interpret_compile_error;

        self.push(Value.Object(@ptrCast(*Obj, function)));
        _ = self.call(function, 0);

        return self.run();
    }

    fn run(self: *VM) InterpretResult {
        self.frame = &self.frames[self.frame_count - 1];
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
                _ = debug.disassembleInstruction(self.frame.function.chunk(), @intCast(u32, @ptrToInt(self.frame.ip) - @ptrToInt(self.frame.function.chunk().code)));
            }
            const inst = @intToEnum(chunk.OpCode, self.readByte());
            switch (inst) {
                .op_return => {
                    const result = self.pop();
                    self.frame_count -= 1;
                    if (self.frame_count == 0) {
                        _ = self.pop();
                        return .interpret_ok;
                    }

                    self.stack_top = self.frame.slots;
                    self.push(result);
                    self.frame = &self.frames[self.frame_count - 1];
                },
                .op_call => {
                    const arg_count = self.readByte();
                    if (!self.callValue(self.peek(arg_count), arg_count)) {
                        return .interpret_runtime_error;
                    }
                    self.frame = &self.frames[self.frame_count - 1];
                },
                .op_jump => {
                    const offset = self.readShort();
                    self.frame.ip += offset;
                },
                .op_loop => {
                    const offset = self.readShort();
                    self.frame.ip -= offset;
                },
                .op_jump_if_false => {
                    const offset = self.readShort();
                    if (isFalsey(self.peek(0))) self.frame.ip += offset;
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
                    self.push(self.frame.slots[slot]);
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
                    self.frame.slots[slot] = self.peek(0);
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

    fn callValue(self: *VM, callee: Value, arg_count: usize) bool {
        if (callee.isObject()) {
            switch (callee.as.obj.t) {
                .obj_function => return self.call(callee.as.obj.asFunction(), arg_count),
                else => {},
            }
        }
        self.runtimeError("Can only call functions and classes.", .{});
        return false;
    }

    fn call(self: *VM, callee: *ObjFunction, arg_count: usize) bool {
        if (arg_count != callee.arity) {
            self.runtimeError("Expected {d} arguments but got {d}.", .{ callee.arity, arg_count });
            return false;
        }
        if (self.frame_count == frames_max) {
            self.runtimeError("Stack overflow.", .{});
            return false;
        }
        var frame = &self.frames[self.frame_count];
        self.frame_count += 1;
        frame.function = callee;
        frame.ip = callee.chunk().code;
        frame.slots = self.stack_top - arg_count - 1;
        return true;
    }

    fn resetStack(self: *VM) void {
        self.stack_top = self.stack;
    }

    fn runtimeError(self: *VM, comptime format: []const u8, args: anytype) void {
        stderr.print(format, args) catch unreachable;
        stderr.writeByte('\n') catch unreachable;
        var index: isize = @intCast(isize, self.frame_count) - 1;
        while (index >= 0) : (index -= 1) {
            const frame = &self.frames[@intCast(usize, index)];
            const function = frame.function;
            const instruction = @ptrToInt(frame.ip) - @ptrToInt(function.chunk().code) - 1;
            stderr.print("[line {d}] in ", .{function.chunk().lines[instruction]}) catch unreachable;
            if (function.name) |name| {
                stderr.print("{s}()\n", .{name.chars[0..name.length]}) catch unreachable;
            } else {
                stderr.print("script\n", .{}) catch unreachable;
            }
        }
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

    fn peek(self: *VM, distance: usize) Value {
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
        defer self.frame.ip += 1;
        return self.frame.ip[0];
    }

    inline fn readConstant(self: *VM) Value {
        return self.frame.function.chunk().constants.values[self.readByte()];
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
        self.frame.ip += 2;
        return (@intCast(u16, (self.frame.ip - 2)[0]) << 8) | (self.frame.ip - 1)[0];
    }
};

pub const InterpretResult = enum {
    interpret_ok,
    interpret_compile_error,
    interpret_runtime_error,
};
