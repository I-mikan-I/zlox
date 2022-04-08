const std = @import("std");

pub const Token = struct {
    t: TokenType,
    start: [*]const u8,
    length: usize,
    line: usize,
};

pub const TokenType = enum(u8) {

    // single char
    left_paren,
    right_paren,
    left_brace,
    right_brace,
    comma,
    dot,
    minus,
    plus,
    semicolon,
    slash,
    star,
    // multi char
    bang,
    bang_equal,
    equal,
    equal_equal,
    greater,
    greater_equal,
    less,
    less_equal,
    // literals
    identifier,
    string,
    number,
    // keywords
    lox_and,
    lox_class,
    lox_else,
    lox_false,
    lox_for,
    lox_fun,
    lox_if,
    lox_nil,
    lox_or,
    lox_print,
    lox_return,
    lox_super,
    lox_this,
    lox_true,
    lox_var,
    lox_while,
    lox_error,
    lox_eof,
};

pub const Scanner = struct {
    start: [*]const u8,
    current: [*]const u8,
    line: usize = 1,

    const Self = @This();

    pub fn init(source: []const u8) Self {
        return .{
            .start = source.ptr,
            .current = source.ptr,
        };
    }

    pub fn scanToken(self: *Self) Token {
        self.skipWhitespace();
        self.start = self.current;
        if (self.isAtEnd()) return self.makeToken(.lox_eof);

        const c = self.advance();

        switch (c) {
            '(' => return self.makeToken(.left_paren),
            ')' => return self.makeToken(.right_paren),
            '{' => return self.makeToken(.left_brace),
            '}' => return self.makeToken(.right_brace),
            ';' => return self.makeToken(.semicolon),
            ',' => return self.makeToken(.comma),
            '.' => return self.makeToken(.dot),
            '-' => return self.makeToken(.minus),
            '+' => return self.makeToken(.plus),
            '/' => return self.makeToken(.slash),
            '*' => return self.makeToken(.star),

            '!' => return self.makeToken(if (self.match('=')) .bang_equal else .bang),
            '=' => return self.makeToken(if (self.match('=')) .equal_equal else .equal),
            '<' => return self.makeToken(if (self.match('=')) .less_equal else .less),
            '>' => return self.makeToken(if (self.match('=')) .greater_equal else .greater),

            else => return self.errorToken("Unexpected character."),
        }
    }

    fn isAtEnd(self: *Self) bool {
        return self.current[0] == 0;
    }

    fn advance(self: *Self) u8 {
        defer self.current += 1;
        return self.current[0];
    }

    fn skipWhitespace(self: *Self) void {
        while (true) {
            const c = self.peek();
            switch (c) {
                ' ', '\r', '\t' => _ = self.advance(),
                '\n' => {
                    self.line += 1;
                    _ = self.advance();
                },
                '/' => {
                    if (self.peekNext() == '/') {
                        while (self.peek() != '\n' and !self.isAtEnd()) {
                            _ = self.advance();
                        }
                    } else return;
                },
                else => return,
            }
        }
    }

    fn peek(self: *Self) u8 {
        return self.current[0];
    }

    fn peekNext(self: *Self) u8 {
        if (self.isAtEnd()) return 0;
        return self.current[1];
    }

    fn match(self: *Self, char: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.current[0] != char) return false;
        self.current += 1;
        return true;
    }

    fn makeToken(self: *Self, t: TokenType) Token {
        return .{
            .t = t,
            .start = self.start,
            .length = @ptrToInt(self.current) - @ptrToInt(self.start),
            .line = self.line,
        };
    }

    fn errorToken(self: *Self, message: []const u8) Token {
        return .{
            .t = .lox_error,
            .start = message.ptr,
            .length = message.len,
            .line = self.line,
        };
    }
};
