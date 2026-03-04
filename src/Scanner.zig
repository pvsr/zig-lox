const std = @import("std");

const Token = @import("Token.zig");

const Scanner = @This();

start: []const u8,
current: []const u8,
line: u16,

pub fn init(source: []const u8) Scanner {
    return .{
        .start = source,
        .current = source,
        .line = 1,
    };
}

pub fn scanToken(self: *Scanner) Token {
    self.skipWhitespace();
    self.start = self.current;

    if (self.isAtEnd()) return self.makeToken(.eof);

    const c = self.advance();

    if (isAlpha(c)) return self.identifier();
    if (isDigit(c)) return self.number();

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
        '"' => return self.string(),
        else => {},
    }

    return self.errorToken("Unexpected character.");
}

fn length(self: Scanner) usize {
    return self.start.len - self.current.len;
}

fn isAtEnd(self: Scanner) bool {
    return self.current.len == 0;
}

fn string(self: *Scanner) Token {
    while (!self.isAtEnd() and self.current[0] != '"') {
        if (self.current[0] == '\n') self.line += 1;
        _ = self.advance();
    }
    if (self.isAtEnd()) return self.errorToken("Unterminated string");
    _ = self.advance();
    return self.makeToken(.string);
}

fn number(self: *Scanner) Token {
    while (isDigit(self.peek())) {
        _ = self.advance();
    }
    if (self.peek() == '.' and self.current.len > 1 and isDigit(self.current[1])) {
        _ = self.advance();
        while (isDigit(self.peek())) {
            _ = self.advance();
        }
    }
    return self.makeToken(.number);
}

fn identifier(self: *Scanner) Token {
    while (isAlpha(self.peek()) or isDigit(self.peek())) {
        _ = self.advance();
    }
    return self.makeToken(self.identifierType());
}

fn identifierType(self: Scanner) Token.Type {
    return switch (self.start[0]) {
        'a' => self.checkKeyword(1, "nd", .kw_and),
        'c' => self.checkKeyword(1, "lass", .kw_class),
        'e' => self.checkKeyword(1, "lse", .kw_else),
        'f' => if (self.length() > 1)
            switch (self.start[1]) {
                'a' => self.checkKeyword(2, "lse", .kw_false),
                'o' => self.checkKeyword(2, "r", .kw_for),
                'u' => self.checkKeyword(2, "n", .kw_fun),
                else => .identifier,
            }
        else
            .identifier,
        'i' => self.checkKeyword(1, "f", .kw_if),
        'n' => self.checkKeyword(1, "il", .kw_nil),
        'o' => self.checkKeyword(1, "r", .kw_or),
        'p' => self.checkKeyword(1, "rint", .kw_print),
        'r' => self.checkKeyword(1, "eturn", .kw_return),
        's' => self.checkKeyword(1, "uper", .kw_super),
        't' => if (self.length() > 1)
            switch (self.start[1]) {
                'h' => self.checkKeyword(2, "is", .kw_this),
                'r' => self.checkKeyword(2, "ue", .kw_true),
                else => .identifier,
            }
        else
            .identifier,
        'v' => self.checkKeyword(1, "ar", .kw_var),
        'w' => self.checkKeyword(1, "hile", .kw_while),
        else => .identifier,
    };
}

fn checkKeyword(self: Scanner, start: u32, rest: []const u8, tokenType: Token.Type) Token.Type {
    if (std.mem.eql(u8, self.start[start..self.length()], rest))
        return tokenType
    else
        return .identifier;
}

fn makeToken(self: Scanner, tokenType: Token.Type) Token {
    return .{
        .type = tokenType,
        .slice = self.start[0..self.length()],
        .line = self.line,
    };
}

fn errorToken(self: Scanner, message: []const u8) Token {
    return .{
        .type = .err,
        .slice = message,
        .line = self.line,
    };
}

fn advance(self: *Scanner) u8 {
    const c = self.current[0];
    self.current = self.current[1..];
    return c;
}

fn peek(self: *Scanner) u8 {
    return if (self.isAtEnd()) undefined else self.current[0];
}

fn match(self: *Scanner, expected: u8) bool {
    if (self.peek() != expected) return false;
    self.current = self.current[1..];
    return true;
}

fn skipWhitespace(self: *Scanner) void {
    while (true) {
        switch (self.peek()) {
            ' ', '\r', '\t' => {
                _ = self.advance();
            },
            '\n' => {
                self.line += 1;
                _ = self.advance();
            },
            '/' => {
                if (!self.isAtEnd() and self.current[1] == '/') {
                    self.current = self.current[2..];
                    while (!self.isAtEnd() and self.current[0] != '\n') {
                        _ = self.advance();
                    }
                } else return;
            },
            else => return,
        }
        if (self.isAtEnd()) {
            return;
        }
    }
}

fn isAlpha(c: u8) bool {
    return c == '_' or
        (c >= 'a' and c <= 'z') or
        (c >= 'A' and c <= 'Z');
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}
