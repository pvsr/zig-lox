const std = @import("std");

const Chunk = @import("Chunk.zig");
const debug = @import("debug.zig");
const Scanner = @import("Scanner.zig");
const Token = @import("Token.zig");
const Objects = @import("Objects.zig");
const Value = @import("value.zig").Value;

pub fn compile(gpa: std.mem.Allocator, source: *std.Io.Reader, chunk: *Chunk, objects: *Objects) bool {
    var buf: [255]u8 = undefined;
    var out: std.Io.Writer = .fixed(&buf);
    var scanner: Scanner = .init(gpa, source, &out);
    var parser: Parser = .{
        .scanner = &scanner,
        .compilingChunk = chunk,
        .current = undefined,
        .previous = undefined,
        .canAssign = false,
        .hadError = false,
        .panicMode = false,
        .objects = objects,
        .gpa = gpa,
    };
    parser.advance();
    while (!parser.match(.eof)) {
        parser.declaration();
    }
    parser.endCompiler();
    return !parser.hadError;
}

const Parser = struct {
    scanner: *Scanner,
    compilingChunk: *Chunk,
    current: Token,
    previous: Token,
    canAssign: bool,
    hadError: bool,
    panicMode: bool,
    objects: *Objects,
    gpa: std.mem.Allocator,

    fn advance(self: *Parser) void {
        self.previous = self.current;
        while (true) {
            self.current = self.scanner.scanToken() catch unreachable;
            if (self.current.type != .err) break;

            self.errorAtCurrent(self.current.type.err);
        }
    }

    fn consume(self: *Parser, tokenType: Token.Type, message: []const u8) void {
        if (self.current.type == tokenType) {
            self.advance();
            return;
        }
        self.errorAtCurrent(message);
    }

    fn match(self: *Parser, token_type: Token.Type) bool {
        if (self.current.type != token_type) return false;
        self.advance();
        return true;
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

    const rules = ParseRules.init();

    fn binary(self: *Parser) void {
        const opType = self.previous.type;
        const rule = rules.get(opType);
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

    const Precedence = enum {
        none,
        assignment,
        @"or",
        @"and",
        equality,
        comparison,
        term,
        factor,
        unary,
        call,
        primary,

        pub fn lte(self: Precedence, other: Precedence) bool {
            return @intFromEnum(self) <= @intFromEnum(other);
        }

        pub fn canAssign(self: Precedence) bool {
            return self.lte(.assignment);
        }
    };

    const ParseFn = *const fn (parser: *Parser) void;

    const ParseRule = struct {
        prefix: ?ParseFn,
        infix: ?ParseFn,
        precedence: Precedence,

        const default = ParseRule{
            .prefix = null,
            .infix = null,
            .precedence = .none,
        };
    };

    const ParseRules = struct {
        const count = @typeInfo(Token.Type).@"enum".fields.len;
        rules: [count]ParseRule,

        fn init() ParseRules {
            var r = ParseRules{ .rules = [_]ParseRule{ParseRule.default} ** count };
            r.add(.left_paren, grouping, null, .none);
            r.add(.minus, unary, binary, .term);
            r.add(.plus, null, binary, .term);
            r.add(.slash, null, binary, .factor);
            r.add(.star, null, binary, .factor);
            r.add(.number, number, null, .none);
            r.add(.kw_false, literal, null, .none);
            r.add(.kw_true, literal, null, .none);
            r.add(.kw_nil, literal, null, .none);
            r.add(.bang, unary, null, .none);
            r.add(.bang_equal, null, binary, .equality);
            r.add(.equal_equal, null, binary, .equality);
            r.add(.greater, null, binary, .comparison);
            r.add(.greater_equal, null, binary, .comparison);
            r.add(.less, null, binary, .comparison);
            r.add(.less_equal, null, binary, .comparison);
            r.add(.identifier, variable, null, .none);
            r.add(.string, string, null, .none);
            return r;
        }

        fn add(self: *ParseRules, tokenType: Token.Type, prefix: ?ParseFn, infix: ?ParseFn, precedence: Precedence) void {
            self.rules[@intFromEnum(tokenType)] = .{
                .prefix = prefix,
                .infix = infix,
                .precedence = precedence,
            };
        }

        fn get(self: ParseRules, tokenType: Token.Type) ParseRule {
            return self.rules[@intFromEnum(tokenType)];
        }
    };

    fn parsePrecedence(self: *Parser, precedence: Precedence) void {
        self.canAssign = precedence.canAssign();
        self.advance();
        if (rules.get(self.previous.type).prefix) |prefixRule| {
            prefixRule(self);
        } else {
            self.@"error"("Expect expression.");
            return;
        }

        while (precedence.lte(rules.get(self.current.type).precedence)) {
            self.advance();
            if (rules.get(self.previous.type).infix) |infixRule| {
                infixRule(self);
            }
        }

        if (self.canAssign and self.match(.equal)) {
            self.@"error"("Invalid assignment target");
        }
    }

    fn identifierConstant(self: *Parser, name: Token) u8 {
        return self.makeConstant(.ownedStr(self.gpa, self.objects, name.type.identifier));
    }

    fn parseVariable(self: *Parser, errorMessage: []const u8) u8 {
        self.consume(.identifier, errorMessage);
        return self.identifierConstant(self.previous);
    }

    fn defineVariable(self: *Parser, global: u8) void {
        self.emitOp1(.define_global, global);
    }

    fn expression(self: *Parser) void {
        self.parsePrecedence(.assignment);
    }

    fn declaration(self: *Parser) void {
        if (self.match(.kw_var)) {
            self.varDeclaration();
        } else {
            self.statement();
        }

        if (self.panicMode) self.synchronize();
    }

    fn varDeclaration(self: *Parser) void {
        const global = self.parseVariable("Expect variable name.");
        if (self.match(.equal)) {
            self.expression();
        } else {
            self.emitOp(.nil);
        }
        self.consume(.semicolon, "Expect ';' after variable declaration.");
        self.defineVariable(global);
    }

    fn statement(self: *Parser) void {
        if (self.match(.kw_print)) {
            self.printStatement();
        } else {
            self.expressionStatement();
        }
    }

    fn expressionStatement(self: *Parser) void {
        self.expression();
        self.consume(.semicolon, "Expect ; after value.");
        self.emitOp(.pop);
    }

    fn printStatement(self: *Parser) void {
        self.expression();
        self.consume(.semicolon, "Expect ; after value.");
        self.emitOp(.print);
    }

    fn synchronize(self: *Parser) void {
        self.panicMode = false;

        while (self.current.type != .eof) {
            if (self.previous.type == .semicolon) return;
            switch (self.current.type) {
                .kw_class, .kw_fun, .kw_var, .kw_for, .kw_if, .kw_while, .kw_print, .kw_return => return,
                else => {},
            }
            self.advance();
        }
    }

    fn number(self: *Parser) void {
        self.emitConstant(.{ .number = self.previous.type.number });
    }

    fn string(self: *Parser) void {
        self.emitConstant(.ownedStr(self.gpa, self.objects, self.previous.type.string));
    }

    fn namedVariable(self: *Parser, name: Token) void {
        const arg = self.identifierConstant(name);
        if (self.canAssign and self.match(.equal)) {
            self.expression();
            self.emitOp1(.set_global, arg);
        } else {
            self.emitOp1(.get_global, arg);
        }
    }

    fn variable(self: *Parser) void {
        return self.namedVariable(self.previous);
    }

    fn errorAtCurrent(self: *Parser, message: []const u8) void {
        self.errorAt(self.current, message);
    }

    fn @"error"(self: *Parser, message: []const u8) void {
        self.errorAt(self.previous, message);
    }

    fn errorAt(self: *Parser, token: Token, message: []const u8) void {
        defer token.deinit(self.gpa);
        if (self.panicMode) return;
        self.panicMode = true;
        std.debug.print("[line {d}] Error", .{token.line});

        if (token.type == .eof) {
            std.debug.print(" at end", .{});
        } else if (token.type == .err) {
            // Nothing.
        } else {
            std.debug.print(" at '", .{});
            token.print();
            std.debug.print("'", .{});
        }

        std.debug.print(": {s}\n", .{message});
        self.hadError = true;
    }
};
