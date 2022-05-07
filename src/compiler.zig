const std = @import("std");
const scanner = @import("./scanner.zig");
const common = @import("./common.zig");
const debug = @import("./debug.zig");
const object = @import("./object.zig");
const Chunk = @import("./chunk.zig").Chunk;
const Value = @import("./value.zig").Value;
const OpCode = @import("./chunk.zig").OpCode;
const TokenType = scanner.TokenType;
const Token = scanner.Token;

const stdout = common.stdout;
const stderr = common.stderr;

const Parser = struct {
    current: Token = undefined,
    previous: Token = undefined,
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

const ParseFn = fn (can_assign: bool) void;

const ParseRule = struct {
    prefix: ?ParseFn,
    infix: ?ParseFn,
    precedence: Precedence,
};

const Compiler = struct {
    locals: [256]Local = undefined,
    local_count: u8 = 0,
    scope_depth: usize = 0,

    fn init() Compiler {
        return .{};
    }
};

const Local = struct {
    name: Token,
    depth: isize,
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
    tmp[@enumToInt(TokenType.string)] = .{ .prefix = string, .infix = null, .precedence = .prec_none };
    tmp[@enumToInt(TokenType.identifier)] = .{ .prefix = variable, .infix = null, .precedence = .prec_none };
    tmp[@enumToInt(TokenType.lox_and)] = .{ .prefix = null, .infix = and_, .precedence = .prec_and };
    tmp[@enumToInt(TokenType.lox_or)] = .{ .prefix = null, .infix = or_, .precedence = .prec_or };
    break :blk tmp;
};

var p: Parser = undefined;
var current: *Compiler = undefined;
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
    var compiler = Compiler.init();
    current = &compiler;
    c = chunk;
    advance();
    while (!match(.lox_eof)) declaration();
    endCompiler();
    return !p.had_error;
}

fn synchronize() void {
    p.panic_mode = false;

    while (p.current.t != .lox_eof) {
        if (p.previous.t == .semicolon) return;
        switch (p.current.t) {
            .lox_class, .lox_fun, .lox_var, .lox_for, .lox_if, .lox_while, .lox_print, .lox_return => return,
            else => {},
        }
        advance();
    }
}

fn expression() void {
    parsePrecedence(.prec_assignment);
}

fn block() void {
    while (!check(.right_brace) and !check(.lox_eof)) declaration();
    consume(.right_brace, "Expect '}' after block.");
}

fn beginScope() void {
    current.scope_depth += 1;
}

fn endScope() void {
    current.scope_depth -= 1;
    while (current.local_count > 0 and current.locals[@intCast(usize, current.local_count - 1)].depth > current.scope_depth) {
        emitByte(@enumToInt(OpCode.op_pop));
        current.local_count -= 1;
    }
}

fn varDeclaration() void {
    const global = parseVariable("Expect variable name.");

    if (match(.equal)) expression() else emitByte(@enumToInt(OpCode.op_nil));
    consume(.semicolon, "Expect ';' after a variable declaration.");

    defineVariable(global);
}

fn defineVariable(global: u8) void {
    if (current.scope_depth > 0) {
        markInitialized();
        return;
    }
    emitBytes(&.{ @enumToInt(OpCode.op_define_global), global });
}

fn markInitialized() void {
    current.locals[current.local_count - 1].depth = @intCast(isize, current.scope_depth);
}

fn declareVariable() void {
    if (current.scope_depth == 0) return;
    const name = &p.previous;
    var i: usize = current.local_count;
    while (i >= 0) : (i -= 1) {
        const local = &current.locals[i];
        if (local.depth != -1 and local.depth < current.scope_depth) break;
        if (identifiersEqual(name, &local.name)) {
            errorAtPrevious("Already a variable with this name in this scope.");
        }
    }
    addLocal(name.*);
}

fn addLocal(name: Token) void {
    defer current.local_count += 1;
    if (current.local_count > 256) {
        errorAtPrevious("Too many local variables in function.");
        return;
    }
    const local = &current.locals[current.local_count];
    local.name = name;
    local.depth = -1;
}

fn expressionStatement() void {
    expression();
    consume(.semicolon, "Expect ';' after expression.");
    emitByte(@enumToInt(OpCode.op_pop));
}

fn ifStatement() void {
    consume(.left_paren, "Expect '(' after 'if'.");
    expression();
    consume(.right_paren, "Expect ')' after condition.");

    const then_jump = emitJump(.op_jump_if_false);
    emitByte(@enumToInt(OpCode.op_pop));
    statement();
    const else_jump = emitJump(.op_jump);
    patchJump(then_jump);

    emitByte(@enumToInt(OpCode.op_pop));
    if (match(.lox_else)) statement();
    patchJump(else_jump);
}

fn and_(_: bool) void {
    const end_jump = emitJump(.op_jump_if_false);

    emitByte(@enumToInt(OpCode.op_pop));
    parsePrecedence(.prec_and);

    patchJump(end_jump);
}

fn or_(_: bool) void {
    const else_jump = emitJump(.op_jump_if_false);
    const end_jump = emitJump(.op_jump);

    patchJump(else_jump);
    emitByte(@enumToInt(OpCode.op_pop));

    parsePrecedence(.prec_or);
    patchJump(end_jump);
}

fn printStatement() void {
    expression();
    consume(.semicolon, "Expect ';' after value.");
    emitByte(@enumToInt(OpCode.op_print));
}

fn whileStatement() void {
    const loop_start = currentChunk().count;
    consume(.left_paren, "Expect '(' after 'while'.");
    expression();
    consume(.right_paren, "Expect ')' after condition");

    const exit_jump = emitJump(.op_jump_if_false);
    emitByte(@enumToInt(OpCode.op_pop));
    statement();
    emitLoop(loop_start);

    patchJump(exit_jump);
    emitByte(@enumToInt(OpCode.op_pop));
}

fn forStatement() void {
    beginScope();
    defer endScope();
    consume(.left_paren, "Expect '(' after 'for'.");
    if (match(.semicolon)) {} else if (match(.lox_var)) {
        varDeclaration();
    } else {
        expressionStatement();
    }

    var loop_start = currentChunk().count;
    var exit_jump: ?u32 = null;
    if (!match(.semicolon)) {
        expression();
        consume(.semicolon, "Expect ';' after loop condition");
        exit_jump = emitJump(.op_jump_if_false);
        emitByte(@enumToInt(OpCode.op_pop));
    }

    if (!match(.right_paren)) {
        const body_jump = emitJump(.op_jump);
        const increment_start = currentChunk().count;
        expression();
        emitByte(@enumToInt(OpCode.op_pop));
        consume(.right_paren, "Expect ')' after for clauses");

        emitLoop(loop_start);
        loop_start = increment_start;
        patchJump(body_jump);
    }

    statement();
    emitLoop(loop_start);
    if (exit_jump) |ej| {
        patchJump(ej);
        emitByte(@enumToInt(OpCode.op_pop));
    }
    //endScope()
}

fn declaration() void {
    if (match(.lox_var)) varDeclaration() else statement();

    if (p.panic_mode) synchronize();
}

fn statement() void {
    if (match(.lox_print)) printStatement() else if (match(.lox_for)) forStatement() else if (match(.lox_if)) ifStatement() else if (match(.lox_while)) whileStatement() else if (match(.left_brace)) {
        beginScope();
        block();
        endScope();
    } else expressionStatement();
}

fn number(_: bool) void {
    var value = std.fmt.parseFloat(f64, p.previous.start[0..p.previous.length]) catch {
        errorAtPrevious("Invalid character in number.");
        return;
    };
    emitConstant(Value.Number(value));
}

fn string(_: bool) void {
    emitConstant(Value.Object(object.copyString(p.previous.start + 1, p.previous.length - 2)));
}

fn variable(can_assign: bool) void {
    namedVariable(&p.previous, can_assign);
}

fn namedVariable(name: *Token, can_assign: bool) void {
    var getOp: u8 = undefined;
    var setOp: u8 = undefined;
    var arg = resolveLocal(current, name);
    if (arg) |_| {
        getOp = @enumToInt(OpCode.op_get_local);
        setOp = @enumToInt(OpCode.op_set_local);
    } else {
        arg = identifierConstant(name);
        getOp = @enumToInt(OpCode.op_get_global);
        setOp = @enumToInt(OpCode.op_set_global);
    }
    if (can_assign and match(.equal)) {
        expression();
        emitBytes(&.{ setOp, arg.? });
    } else {
        emitBytes(&.{ getOp, arg.? });
    }
}

fn grouping(_: bool) void {
    expression();
    consume(.right_paren, "Expect ')' after expression.");
}

fn unary(_: bool) void {
    const operator_type = p.previous.t;

    parsePrecedence(.prec_unary);

    switch (operator_type) {
        .bang => emitByte(@enumToInt(OpCode.op_not)),
        .minus => emitByte(@enumToInt(OpCode.op_negate)),
        else => unreachable,
    }
}

fn binary(_: bool) void {
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

fn literal(_: bool) void {
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
    var can_assign: bool = undefined;
    if (prefix_rule) |rule| {
        can_assign = @enumToInt(precedence) <= @enumToInt(Precedence.prec_assignment);
        rule(can_assign);
    } else {
        errorAtPrevious("Expect expression.");
        return;
    }

    while (@enumToInt(precedence) <= @enumToInt(getRule(p.current.t).precedence)) {
        advance();
        const infix_rule = getRule(p.previous.t).infix;
        infix_rule.?(can_assign);
    }
    if (can_assign and match(.equal)) {
        errorAtPrevious("Invalid assignment target.");
    }
}

fn parseVariable(errorMessage: []const u8) u8 {
    consume(.identifier, errorMessage);
    declareVariable();
    if (current.scope_depth > 0) return 0;
    return identifierConstant(&p.previous);
}

fn identifierConstant(name: *Token) u8 {
    return makeConstant(Value.Object(object.copyString(name.start, name.length)));
}

fn identifiersEqual(a: *Token, b: *Token) bool {
    return std.mem.eql(u8, a.start[0..a.length], b.start[0..b.length]);
}

fn resolveLocal(compiler: *Compiler, name: *Token) ?u8 {
    var i: isize = compiler.local_count;
    i -= 1;
    while (i >= 0) : (i -= 1) {
        const local = &compiler.locals[@intCast(u8, i)];
        if (identifiersEqual(name, &local.name)) {
            if (local.depth == -1) {
                errorAtPrevious("Can't read local variable in its own initializer.");
            }
            return @intCast(u8, i);
        }
    }
    return null;
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

fn match(token: TokenType) bool {
    if (!check(token)) return false;
    advance();
    return true;
}

fn check(token: TokenType) bool {
    return p.current.t == token;
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

fn emitJump(instruction: OpCode) u32 {
    emitByte(@enumToInt(instruction));
    emitByte(0xFF);
    emitByte(0xFF);
    return currentChunk().count - 2;
}

fn emitLoop(start: u32) void {
    emitByte(@enumToInt(OpCode.op_loop));
    const offset = currentChunk().count - start + 2;
    if (offset > 0xFFFF) errorAtPrevious("Loop body too large.");
    emitByte(@truncate(u8, offset >> 8));
    emitByte(@truncate(u8, offset));
}

fn patchJump(offset: u32) void {
    const jump = currentChunk().count - offset - 2;
    if (jump > 0xFFFF) {
        errorAtPrevious("Too much code to jump over.");
    }
    currentChunk().code[offset] = @truncate(u8, jump >> 8);
    currentChunk().code[offset + 1] = @truncate(u8, jump);
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

fn errorAt(token: *Token, message: []const u8) void {
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
