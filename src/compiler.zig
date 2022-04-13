const std = @import("std");
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();
const scanner = @import("./scanner.zig");
const Chunk = @import("./chunk.zig").Chunk;
const Value = @import("./value.zig").Value;

const Parser = struct {
    current: scanner.Token = undefined,
    previous: scanner.Token = undefined,
    had_error: bool = false,
    panic_mode: bool = false,
};

const Precedence = enum(u8) {
    prec_none,
    prec_assigment,
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

var p: Parser = undefined;
var s: scanner.Scanner = undefined;
var c: *Chunk = undefined;

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
    var value = std.fmt.parseFloat(i64, parser.previous.start[0..parser.previous.length]);
    emitConstant(value);
}

fn grouping() void {
    expression();
    consume(.right_paren, "Expect ')' after expression.");
}

fn unary() void {
    var operator_type = p.previous.t;

    parsePrecedence(.prec_unary);

    switch (operator_type) {
        .minus => emitByte(.op_negate),
        default => unreachable,
    }
}

fn parsePrecedence(precedence: Precedence) void {}

fn advance() void {
    parser.previous = parser.current;

    while (true) {
        parser.current = s.scanToken();
        if (parser.current.t != .lox_error) break;

        errorAtCurrent(parser.current.start);
    }
}

fn consume(t: scanner.TokenType, message: []const u8) void {
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

    return @floatToInt(u8, constant);
}

fn emitByte(byte: u8) void {
    writeChunk(currentChunk(), byte, parser.previous.line);
}

fn emitBytes(bytes: []const u8) void {
    for (bytes) |byte| {
        emitByte(byte);
    }
}

fn emitReturn() void {
    emitByte(.op_return);
}

fn emitConstant(value: Value) void {
    emitBytes(.{ @enumToInt(.op_constant), makeConstant(value) });
}

fn endCompiler() void {
    emitReturn();
}

fn errorAtCurrent(message: []const u8) void {
    errorAt(&p.current, message);
}

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
