const std = @import("std");
const Scanner = @import("Scanner.zig");

const Token = @This();

const Value = union(enum) {
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
    // One or two character tokens.
    bang,
    bang_equal,
    equal,
    equal_equal,
    greater,
    greater_equal,
    less,
    less_equal,
    // Literals.
    identifier: []const u8,
    string: []const u8,
    number: f64,
    // Keywords.
    kw_and,
    kw_class,
    kw_else,
    kw_false,
    kw_for,
    kw_fun,
    kw_if,
    kw_nil,
    kw_or,
    kw_print,
    kw_return,
    kw_super,
    kw_this,
    kw_true,
    kw_var,
    kw_while,
    err: []const u8,
    eof,
};

pub const Type = @typeInfo(Token.Value).@"union".tag_type.?;

line: u16,
type: Value,

pub fn init(scanner: *Scanner, tokenType: Token.Type) Token {
    return .{
        .line = scanner.line,
        .type = switch (tokenType) {
            .identifier => .{ .identifier = string(scanner) },
            .string => .{ .string = string(scanner) },
            .number => .{ .number = number(scanner) },
            .err => unreachable,
            inline else => |t| t,
        },
    };
}

pub fn err(line: u16, message: []const u8) Token {
    return .{
        .line = line,
        .type = .{ .err = message },
    };
}

fn string(scanner: *Scanner) []const u8 {
    return scanner.alloc.dupe(u8, scanner.out.buffered()) catch unreachable;
}

fn number(scanner: *Scanner) f64 {
    return std.fmt.parseFloat(f64, scanner.out.buffered()) catch unreachable;
}

pub fn deinit(self: Token, alloc: std.mem.Allocator) void {
    switch (self.type) {
        .string, .identifier => |slice| alloc.free(slice),
        else => {},
    }
}

pub fn print(self: Token) void {
    if (self.type == .number)
        return std.debug.print("{d}", .{self.type.number});

    std.debug.print("{s}", .{switch (self.type) {
        .left_paren => "(",
        .right_paren => ")",
        .left_brace => "{",
        .right_brace => "}",
        .comma => ",",
        .dot => ".",
        .minus => "-",
        .plus => "+",
        .semicolon => ";",
        .slash => "/",
        .star => "*",
        .bang => "!",
        .bang_equal => "!=",
        .equal => "=",
        .equal_equal => "==",
        .greater => ">",
        .greater_equal => ">=",
        .less => "<",
        .less_equal => "<=",
        .string, .identifier => |str| str,
        .number => unreachable,
        .kw_and => "and",
        .kw_class => "class",
        .kw_else => "else",
        .kw_false => "false",
        .kw_for => "for",
        .kw_fun => "fun",
        .kw_if => "if",
        .kw_nil => "nil",
        .kw_or => "or",
        .kw_print => "print",
        .kw_return => "return",
        .kw_super => "super",
        .kw_this => "this",
        .kw_true => "true",
        .kw_var => "var",
        .kw_while => "while",
        else => @tagName(self.type),
    }});
}
