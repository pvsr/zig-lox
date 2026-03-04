const std = @import("std");

const Chunk = @import("Chunk.zig");
const debug = @import("debug.zig");
const Scanner = @import("Scanner.zig");
const Token = @import("Token.zig");
const Value = @import("value.zig").Value;
const Obj = @import("value.zig").Obj;

pub fn compile(gpa: std.mem.Allocator, source: []const u8, chunk: *Chunk) struct { bool, *std.SinglyLinkedList } {
    var scanner = Scanner.init(source);
    var objects = std.SinglyLinkedList{};
    var parser = Parser{
        .scanner = &scanner,
        .compilingChunk = chunk,
        .current = undefined,
        .previous = undefined,
        .hadError = false,
        .panicMode = false,
        .objects = &objects,
        .gpa = gpa,
    };
    parser.advance();
    parser.expression();
    parser.consume(.eof, "Expect end of expression.");
    parser.endCompiler();
    return .{ !parser.hadError, parser.objects };
}

const Precedence = enum { none, assignment, @"or", @"and", equality, comparison, term, factor, unary, call, primary };

const ParseFn = *const fn (parser: *Parser) void;

const ParseRule = struct {
    prefix: ?ParseFn,
    infix: ?ParseFn,
    precedence: Precedence,
};

const Parser = struct {
    scanner: *Scanner,
    compilingChunk: *Chunk,
    current: Token,
    previous: Token,
    hadError: bool,
    panicMode: bool,
    objects: *std.SinglyLinkedList,
    gpa: std.mem.Allocator,

    fn advance(self: *Parser) void {
        self.previous = self.current;
        while (true) {
            self.current = self.scanner.scanToken();
            if (self.current.type != .err) break;

            self.errorAtCurrent(self.current.slice);
        }
    }

    fn consume(self: *Parser, tokenType: Token.Type, message: []const u8) void {
        if (self.current.type == tokenType) {
            self.advance();
            return;
        }
        self.errorAtCurrent(message);
    }

    fn currentChunk(self: *Parser) *Chunk {
        return self.compilingChunk;
    }

    fn emitByte(self: *Parser, byte: u8) void {
        self.currentChunk().write(byte, self.previous.line);
    }

    fn emitOp(self: *Parser, op: Chunk.OpCode) void {
        self.emitByte(@intFromEnum(op));
    }

    fn emitOps(self: *Parser, op1: Chunk.OpCode, op2: Chunk.OpCode) void {
        self.emitOp(op1);
        self.emitOp(op2);
    }

    fn emitOp1(self: *Parser, op: Chunk.OpCode, byte: u8) void {
        self.emitOp(op);
        self.emitByte(byte);
    }

    fn emitReturn(self: *Parser) void {
        self.emitOp(.@"return");
    }

    fn emitConstant(self: *Parser, value: Value) void {
        self.emitOp1(.constant, self.makeConstant(value));
    }

    fn makeConstant(self: *Parser, value: Value) u8 {
        const constant = self.currentChunk().addConstant(value);
        if (constant > 0xFF) {
            self.@"error"("Too many constants in one chunk.");
            return 0;
        }
        return @truncate(constant);
    }

    fn endCompiler(self: *Parser) void {
        self.emitReturn();
        if (debug.DEBUG and !self.hadError) {
            debug.disassembleChunk(self.currentChunk(), "code");
        }
    }

    fn binary(self: *Parser) void {
        const opType = self.previous.type;
        const rule = getRule(opType);
        self.parsePrecedence(@enumFromInt(@intFromEnum(rule.precedence) + 1));

        switch (opType) {
            .plus => self.emitOp(.add),
            .minus => self.emitOp(.subtract),
            .star => self.emitOp(.multiply),
            .slash => self.emitOp(.divide),
            .bang_equal => self.emitOps(.equal, .not),
            .equal_equal => self.emitOp(.equal),
            .greater => self.emitOp(.greater),
            .greater_equal => self.emitOps(.less, .not),
            .less => self.emitOp(.less),
            .less_equal => self.emitOps(.greater, .not),
            else => unreachable,
        }
    }

    fn literal(self: *Parser) void {
        switch (self.previous.type) {
            .kw_false => self.emitOp(.false),
            .kw_nil => self.emitOp(.nil),
            .kw_true => self.emitOp(.true),
            else => unreachable,
        }
    }

    fn grouping(self: *Parser) void {
        self.expression();
        self.consume(.right_paren, "Expect ')' after expression.");
    }

    fn unary(self: *Parser) void {
        const opType = self.previous.type;
        self.parsePrecedence(.unary);
        switch (opType) {
            .minus => self.emitOp(.negate),
            .bang => self.emitOp(.not),
            else => unreachable,
        }
    }

    const rules = blk: {
        const default = ParseRule{
            .prefix = null,
            .infix = null,
            .precedence = .none,
        };
        const count = @typeInfo(Token.Type).@"enum".fields.len;
        var t: [count]ParseRule = [_]ParseRule{default} ** count;
        t[@intFromEnum(Token.Type.left_paren)] = .{
            .prefix = grouping,
            .infix = null,
            .precedence = .none,
        };
        t[@intFromEnum(Token.Type.minus)] = .{
            .prefix = unary,
            .infix = binary,
            .precedence = .term,
        };
        t[@intFromEnum(Token.Type.plus)] = .{
            .prefix = null,
            .infix = binary,
            .precedence = .term,
        };
        t[@intFromEnum(Token.Type.slash)] = .{
            .prefix = null,
            .infix = binary,
            .precedence = .factor,
        };
        t[@intFromEnum(Token.Type.star)] = .{
            .prefix = null,
            .infix = binary,
            .precedence = .factor,
        };
        t[@intFromEnum(Token.Type.number)] = .{
            .prefix = number,
            .infix = null,
            .precedence = .none,
        };
        t[@intFromEnum(Token.Type.kw_false)] = .{
            .prefix = literal,
            .infix = null,
            .precedence = .none,
        };
        t[@intFromEnum(Token.Type.kw_true)] = .{
            .prefix = literal,
            .infix = null,
            .precedence = .none,
        };
        t[@intFromEnum(Token.Type.kw_nil)] = .{
            .prefix = literal,
            .infix = null,
            .precedence = .none,
        };
        t[@intFromEnum(Token.Type.bang)] = .{
            .prefix = unary,
            .infix = null,
            .precedence = .none,
        };
        t[@intFromEnum(Token.Type.bang_equal)] = .{
            .prefix = null,
            .infix = binary,
            .precedence = .equality,
        };
        t[@intFromEnum(Token.Type.equal_equal)] = .{
            .prefix = null,
            .infix = binary,
            .precedence = .equality,
        };
        t[@intFromEnum(Token.Type.greater)] = .{
            .prefix = null,
            .infix = binary,
            .precedence = .comparison,
        };
        t[@intFromEnum(Token.Type.greater_equal)] = .{
            .prefix = null,
            .infix = binary,
            .precedence = .comparison,
        };
        t[@intFromEnum(Token.Type.less)] = .{
            .prefix = null,
            .infix = binary,
            .precedence = .comparison,
        };
        t[@intFromEnum(Token.Type.less_equal)] = .{
            .prefix = null,
            .infix = binary,
            .precedence = .comparison,
        };
        t[@intFromEnum(Token.Type.string)] = .{
            .prefix = string,
            .infix = null,
            .precedence = .none,
        };
        break :blk t;
    };

    fn parsePrecedence(self: *Parser, precedence: Precedence) void {
        self.advance();
        if (getRule(self.previous.type).prefix) |prefixRule| {
            prefixRule(self);
        } else {
            self.@"error"("Expect expression.");
            return;
        }

        while (@intFromEnum(precedence) <= @intFromEnum(getRule(self.current.type).precedence)) {
            self.advance();
            if (getRule(self.previous.type).infix) |infixRule| {
                infixRule(self);
            }
        }
    }

    fn getRule(tokenType: Token.Type) ParseRule {
        return rules[@intFromEnum(tokenType)];
    }

    fn expression(self: *Parser) void {
        self.parsePrecedence(.assignment);
    }

    fn number(self: *Parser) void {
        const n = std.fmt.parseFloat(f64, self.previous.slice) catch unreachable;
        self.emitConstant(.{ .number = n });
    }

    fn string(self: *Parser) void {
        const str = self.previous.slice[1 .. self.previous.slice.len - 1];
        const dupe = self.gpa.dupe(u8, str) catch unreachable;
        self.emitConstant(.string(self.gpa, self.objects, dupe));
    }

    fn errorAtCurrent(self: *Parser, message: []const u8) void {
        self.errorAt(self.current, message);
    }

    fn @"error"(self: *Parser, message: []const u8) void {
        self.errorAt(self.previous, message);
    }

    fn errorAt(self: *Parser, token: Token, message: []const u8) void {
        if (self.panicMode) return;
        self.panicMode = true;
        std.debug.print("[line {d}] Error", .{token.line});

        if (token.type == .eof) {
            std.debug.print(" at end", .{});
        } else if (token.type == .err) {
            // Nothing.
        } else {
            std.debug.print(" at '{s}'", .{token.slice});
        }

        std.debug.print(": {s}\n", .{message});
        self.hadError = true;
    }
};
