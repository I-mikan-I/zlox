const std = @import("std");
const scanner = @import("./scanner.zig");
const common = @import("./common.zig");
const debug = @import("./debug.zig");
const Chunk = @import("./chunk.zig").Chunk;
const Value = @import("./value.zig").Value;
const OpCode = @import("./chunk.zig").OpCode;
const TokenType = scanner.TokenType;

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

const Parser = struct {
    current: scanner.Token = undefined,
    previous: scanner.Token = undefined,
    had_error: bool = false,
    panic_mode: bool = false,
};

const Precedence = enum(u8) {
    prec_none,
    prec_assignment,
    prec_or,
    prec_and,
    prec_equality,
    prec_comparison,
    prec_term,
    prec_factor,
    prec_unary,
    prec_call,
    prec_primary,
};

const ParseFn = fn () void;

const ParseRule = struct {
    prefix: ?ParseFn,
    infix: ?ParseFn,
    precedence: Precedence,
};

const rules: [@enumToInt(TokenType.lox_eof) + 1]ParseRule = blk: {
    comptime var tmp: [@enumToInt(TokenType.lox_eof) + 1]ParseRule = .{.{ .prefix = null, .infix = null, .precedence = .prec_none }} ** (@enumToInt(TokenType.lox_eof) + 1);
    tmp[@enumToInt(TokenType.left_paren)] = .{ .prefix = grouping, .infix = null, .precedence = .prec_none };
    tmp[@enumToInt(TokenType.minus)] = .{ .prefix = unary, .infix = binary, .precedence = .prec_term };
    tmp[@enumToInt(TokenType.bang)] = .{ .prefix = unary, .infix = null, .precedence = .prec_none };
    tmp[@enumToInt(TokenType.bang_equal)] = .{ .prefix = null, .infix = binary, .precedence = .prec_equality };
    tmp[@enumToInt(TokenType.equal_equal)] = .{ .prefix = null, .infix = binary, .precedence = .prec_equality };
    tmp[@enumToInt(TokenType.greater)] = .{ .prefix = null, .infix = binary, .precedence = .prec_comparison };
    tmp[@enumToInt(TokenType.greater_equal)] = .{ .prefix = null, .infix = binary, .precedence = .prec_comparison };
    tmp[@enumToInt(TokenType.less)] = .{ .prefix = null, .infix = binary, .precedence = .prec_comparison };
    tmp[@enumToInt(TokenType.less_equal)] = .{ .prefix = null, .infix = binary, .precedence = .prec_comparison };
    tmp[@enumToInt(TokenType.plus)] = .{ .prefix = null, .infix = binary, .precedence = .prec_term };
    tmp[@enumToInt(TokenType.slash)] = .{ .prefix = null, .infix = binary, .precedence = .prec_factor };
    tmp[@enumToInt(TokenType.star)] = .{ .prefix = null, .infix = binary, .precedence = .prec_factor };
    tmp[@enumToInt(TokenType.number)] = .{ .prefix = number, .infix = null, .precedence = .prec_none };
    tmp[@enumToInt(TokenType.lox_false)] = .{ .prefix = literal, .infix = null, .precedence = .prec_none };
    tmp[@enumToInt(TokenType.lox_true)] = .{ .prefix = literal, .infix = null, .precedence = .prec_none };
    tmp[@enumToInt(TokenType.lox_nil)] = .{ .prefix = literal, .infix = null, .precedence = .prec_none };
    break :blk tmp;
};

var p: Parser = undefined;
var s: scanner.Scanner = undefined;
var c: *Chunk = undefined;

fn getRule(t: TokenType) *const ParseRule {
    return &rules[@enumToInt(t)];
}

fn currentChunk() *Chunk {
    return c;
}

pub fn compile(source: [:0]const u8, chunk: *Chunk) bool {
    p = Parser{};
    s = scanner.Scanner.init(source);
    c = chunk;
    advance();
    expression();
    consume(.lox_eof, "Expect end of expression.");
    endCompiler();
    return !p.had_error;
}

fn expression() void {
    parsePrecedence(.prec_assignment);
}

fn number() void {
    var value = std.fmt.parseFloat(f64, p.previous.start[0..p.previous.length]) catch {
        errorAtPrevious("Invalid character in number.");
        return;
    };
    emitConstant(Value.Number(value));
}

fn grouping() void {
    expression();
    consume(.right_paren, "Expect ')' after expression.");
}

fn unary() void {
    const operator_type = p.previous.t;

    parsePrecedence(.prec_unary);

    switch (operator_type) {
        .bang => emitByte(@enumToInt(OpCode.op_not)),
        .minus => emitByte(@enumToInt(OpCode.op_negate)),
        else => unreachable,
    }
}

fn binary() void {
    const operator_type = p.previous.t;
    const rule = getRule(operator_type);
    parsePrecedence(@intToEnum(Precedence, @enumToInt(rule.precedence) + 1));
    switch (operator_type) {
        .bang_equal => emitBytes(&.{ @enumToInt(OpCode.op_equal), @enumToInt(OpCode.op_not) }),
        .equal_equal => emitByte(@enumToInt(OpCode.op_equal)),
        .greater => emitByte(@enumToInt(OpCode.op_greater)),
        .greater_equal => emitBytes(&.{ @enumToInt(OpCode.op_less), @enumToInt(OpCode.op_not) }),
        .less => emitByte(@enumToInt(OpCode.op_less)),
        .less_equal => emitBytes(&.{ @enumToInt(OpCode.op_greater), @enumToInt(OpCode.op_not) }),
        .plus => emitByte(@enumToInt(OpCode.op_add)),
        .minus => emitByte(@enumToInt(OpCode.op_subtract)),
        .star => emitByte(@enumToInt(OpCode.op_multiply)),
        .slash => emitByte(@enumToInt(OpCode.op_divide)),
        else => return,
    }
}

fn literal() void {
    switch (p.previous.t) {
        .lox_false => emitByte(@enumToInt(OpCode.op_false)),
        .lox_true => emitByte(@enumToInt(OpCode.op_true)),
        .lox_nil => emitByte(@enumToInt(OpCode.op_nil)),
        else => unreachable,
    }
}

fn parsePrecedence(precedence: Precedence) void {
    advance();
    const prefix_rule = getRule(p.previous.t).prefix;
    if (prefix_rule) |rule| {
        rule();
    } else {
        errorAtPrevious("Expect expression.");
        return;
    }

    while (@enumToInt(precedence) <= @enumToInt(getRule(p.current.t).precedence)) {
        advance();
        const infix_rule = getRule(p.previous.t).infix;
        infix_rule.?();
    }
}

fn advance() void {
    p.previous = p.current;

    while (true) {
        p.current = s.scanToken();
        if (p.current.t != .lox_error) break;

        errorAtCurrent(p.current.start[0..p.current.length]);
    }
}

fn consume(t: TokenType, message: []const u8) void {
    if (p.current.t == t) {
        advance();
        return;
    }

    errorAtCurrent(message);
}

fn makeConstant(value: Value) u8 {
    const constant = currentChunk().addConstant(value);
    if (constant >= std.math.maxInt(u8)) {
        errorAtPrevious("Too many constants in one chunk.");
        return 0;
    }

    return @intCast(u8, constant);
}

fn emitByte(byte: u8) void {
    currentChunk().writeChunk(byte, @intCast(u32, p.previous.line));
}

fn emitBytes(bytes: []const u8) void {
    for (bytes) |byte| {
        emitByte(byte);
    }
}

fn emitReturn() void {
    emitByte(@enumToInt(OpCode.op_return));
}

fn emitConstant(value: Value) void {
    emitBytes(&.{ @enumToInt(OpCode.op_constant), makeConstant(value) });
}

fn endCompiler() void {
    emitReturn();
    if (comptime common.dump_enabled) {
        if (!p.had_error) {
            debug.disassembleChunk(currentChunk(), "code");
        }
    }
}

fn errorAtCurrent(message: []const u8) void {
    errorAt(&p.current, message);
}

// aka error()
fn errorAtPrevious(message: []const u8) void {
    errorAt(&p.previous, message);
}

fn errorAt(token: *scanner.Token, message: []const u8) void {
    if (p.panic_mode) return;
    p.panic_mode = true;
    stderr.print("[line {d}] Error", .{token.line}) catch unreachable;

    if (token.t == .lox_eof) {
        stderr.print(" at end", .{}) catch unreachable;
    } else if (token.t == .lox_error) {
        // Nothing
    } else {
        stderr.print(" at '{s}\n'", .{token.start[0..token.length]}) catch unreachable;
    }

    stderr.print(": {s}\n", .{message}) catch unreachable;
    p.had_error = true;
}
