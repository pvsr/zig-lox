const std = @import("std");
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;

const Token = @import("Token.zig");

const Scanner = @This();

alloc: std.mem.Allocator,
src: *Reader,
out: *Writer,
line: u16,

pub fn init(alloc: std.mem.Allocator, src: *Reader, out: *Writer) Scanner {
    return .{
        .alloc = alloc,
        .src = src,
        .out = out,
        .line = 1,
    };
}

pub fn scanToken(self: *Scanner) !Token {
    try self.skipWhitespace();

    const c = self.src.peekByte() catch |err|
        if (err == error.EndOfStream) return self.makeToken(.eof) else return err;

    if (isAlpha(c)) {
        self.advance();
        return self.identifier();
    }
    if (isDigit(c)) {
        self.advance();
        return self.number();
    }

    self.toss();
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
        '!' => return self.makeToken(if (try self.match('=')) .bang_equal else .bang),
        '=' => return self.makeToken(if (try self.match('=')) .equal_equal else .equal),
        '<' => return self.makeToken(if (try self.match('=')) .less_equal else .less),
        '>' => return self.makeToken(if (try self.match('=')) .greater_equal else .greater),
        '"' => return self.string(),
        else => {},
    }

    return self.errorToken("Unexpected character.");
}

fn string(self: *Scanner) !Token {
    while (self.src.peekByte()) |c| {
        switch (c) {
            '"' => {
                self.toss();
                break;
            },
            '\n' => {
                self.toss();
                self.line += 1;
            },
            else => self.advance(),
        }
    } else |err| {
        return if (err == error.EndOfStream) self.errorToken("Unterminated string") else err;
    }
    return self.makeToken(.string);
}

fn number(self: *Scanner) !Token {
    var decimal = false;
    while (self.src.peekByte()) |c| {
        if (isDigit(c)) {
            self.advance();
        } else if (!decimal and c == '.') {
            const next = self.src.peekArray(2) catch |err|
                if (err == error.EndOfStream) break else return err;
            if (isDigit(next[1])) {
                self.advance();
                self.advance();
            } else break;
            decimal = true;
        } else break;
    } else |err| if (err != error.EndOfStream) return err;

    return self.makeToken(.number);
}

fn identifier(self: *Scanner) !Token {
    while (self.src.peekByte()) |c| {
        if (isAlpha(c) or isDigit(c))
            self.advance()
        else
            break;
    } else |err| if (err != error.EndOfStream) return err;

    return self.makeToken(try self.identifierType());
}

fn identifierType(self: *Scanner) !Token.Type {
    var r: Reader = .fixed(self.out.buffered());
    return switch (r.takeByte() catch unreachable) {
        'a' => try checkKeyword(&r, "nd", .kw_and),
        'c' => try checkKeyword(&r, "lass", .kw_class),
        'e' => try checkKeyword(&r, "lse", .kw_else),
        'f' => switch (r.takeByte() catch |err|
            return if (err == error.EndOfStream) .identifier else err) {
            'a' => try checkKeyword(&r, "lse", .kw_false),
            'o' => try checkKeyword(&r, "r", .kw_for),
            'u' => try checkKeyword(&r, "n", .kw_fun),
            else => .identifier,
        },
        'i' => try checkKeyword(&r, "f", .kw_if),
        'n' => try checkKeyword(&r, "il", .kw_nil),
        'o' => try checkKeyword(&r, "r", .kw_or),
        'p' => try checkKeyword(&r, "rint", .kw_print),
        'r' => try checkKeyword(&r, "eturn", .kw_return),
        's' => try checkKeyword(&r, "uper", .kw_super),
        't' => switch (r.takeByte() catch |err|
            return if (err == error.EndOfStream) .identifier else err) {
            'h' => try checkKeyword(&r, "is", .kw_this),
            'r' => try checkKeyword(&r, "ue", .kw_true),
            else => .identifier,
        },
        'v' => try checkKeyword(&r, "ar", .kw_var),
        'w' => try checkKeyword(&r, "hile", .kw_while),
        else => .identifier,
    };
}

fn checkKeyword(r: *Reader, comptime rest: []const u8, tokenType: Token.Type) !Token.Type {
    if (std.mem.eql(u8, r.takeArray(rest.len) catch |err|
        return if (err == error.EndOfStream) .identifier else err, rest))
        return tokenType
    else
        return .identifier;
}

fn makeToken(self: *Scanner, tokenType: Token.Type) Token {
    defer _ = self.out.consumeAll();
    return .init(self, tokenType);
}

fn errorToken(self: Scanner, message: []const u8) Token {
    return .err(self.line, message);
}

fn advance(self: *Scanner) void {
    return self.src.streamExact(self.out, 1) catch unreachable;
}

fn toss(self: *Scanner) void {
    self.src.toss(1);
}

fn match(self: *Scanner, expected: u8) !bool {
    if (try self.src.peekByte() != expected) return false;
    self.toss();
    return true;
}

fn skipWhitespace(self: *Scanner) !void {
    while (self.src.peekByte()) |c| {
        switch (c) {
            ' ', '\r', '\t' => self.toss(),
            '\n' => {
                self.line += 1;
                self.toss();
            },
            '/' => {
                const next = self.src.peekArray(2) catch |err|
                    return if (err == error.EndOfStream) {} else err;
                if (next[1] == '/') {
                    _ = self.src.discardDelimiterInclusive('\n') catch |err|
                        return if (err == error.EndOfStream) {} else err;
                    self.line += 1;
                }
            },
            else => return,
        }
    } else |err| {
        if (err == error.EndOfStream) return else return err;
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

test {
    try scanTest("!true", &.{ .{
        .type = .bang,
        .line = 1,
    }, .{
        .type = .kw_true,
        .line = 1,
    } });
    try scanTest("false == nil", &.{ .{
        .type = .kw_false,
        .line = 1,
    }, .{
        .type = .equal_equal,
        .line = 1,
    }, .{
        .type = .kw_nil,
        .line = 1,
    } });
    try scanTest("\"abc\" + \"def\"", &.{ .{
        .type = .{
            .string = "abc",
        },
        .line = 1,
    }, .{
        .type = .plus,
        .line = 1,
    }, .{
        .type = .{
            .string = "def",
        },
        .line = 1,
    } });
    try scanTest("p", &.{.{ .type = .{ .identifier = "p" }, .line = 1 }});

    const src = "print 1.5 true;";
    const tokens: [5]Token = .{
        .{
            .type = .kw_print,
            .line = 1,
        },
        .{
            .type = .{
                .number = 1.5,
            },
            .line = 1,
        },
        .{
            .type = .kw_true,
            .line = 1,
        },
        .{
            .type = .semicolon,
            .line = 1,
        },
        .{
            .type = .eof,
            .line = 1,
        },
    };
    try scanTest(src, &tokens);
}

fn scanTest(src: []const u8, tokens: []const Token) !void {
    const alloc = std.testing.allocator;
    var buf: [255]u8 = undefined;
    var w: Writer = .fixed(&buf);
    var r: Reader = .fixed(src);
    var s: Scanner = .init(alloc, &r, &w);

    for (tokens) |token| {
        var t = try s.scanToken();
        defer t.deinit(alloc);
        try std.testing.expectEqualDeep(token, t);
    }
    try std.testing.expectEqualDeep(try s.scanToken(), Token{
        .type = .eof,
        .line = 1,
    });
}
