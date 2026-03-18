const std = @import("std");

const Chunk = @import("Chunk.zig");
const debug = @import("debug.zig");
const Scanner = @import("Scanner.zig");
const Token = @import("Token.zig");
const Objects = @import("Objects.zig");
const Value = @import("value.zig").Value;

const Parser = struct {
    gpa: std.mem.Allocator,
    scanner: *Scanner,
    objects: *Objects,
    compilingChunk: *Chunk,
    current: Token = undefined,
    previous: Token = undefined,
    canAssign: bool = false,
    hadError: bool = false,
    panicMode: bool = false,
};

var parser: Parser = undefined;

pub fn compile(gpa: std.mem.Allocator, source: *std.Io.Reader, chunk: *Chunk, objects: *Objects) bool {
    var buf: [255]u8 = undefined;
    var out: std.Io.Writer = .fixed(&buf);
    var scanner: Scanner = .init(gpa, source, &out);
    parser = .{
        .gpa = gpa,
        .scanner = &scanner,
        .objects = objects,
        .compilingChunk = chunk,
    };
    advance();
    while (!match(.eof)) {
        declaration();
    }
    endCompiler();
    return !parser.hadError;
}

fn advance() void {
    parser.previous = parser.current;
    while (true) {
        parser.current = parser.scanner.scanToken() catch unreachable;
        if (parser.current.type != .err) break;

        errorAtCurrent(parser.current.type.err);
    }
}

fn consume(tokenType: Token.Type, message: []const u8) void {
    if (parser.current.type == tokenType) {
        advance();
        return;
    }
    errorAtCurrent(message);
}

fn match(token_type: Token.Type) bool {
    if (parser.current.type != token_type) return false;
    advance();
    return true;
}

fn currentChunk() *Chunk {
    return parser.compilingChunk;
}

fn emitByte(byte: u8) void {
    currentChunk().write(byte, parser.previous.line);
}

fn emitOp(op: Chunk.OpCode) void {
    emitByte(@intFromEnum(op));
}

fn emitOps(op1: Chunk.OpCode, op2: Chunk.OpCode) void {
    emitOp(op1);
    emitOp(op2);
}

fn emitOp1(op: Chunk.OpCode, byte: u8) void {
    emitOp(op);
    emitByte(byte);
}

fn emitReturn() void {
    emitOp(.@"return");
}

fn emitConstant(value: Value) void {
    emitOp1(.constant, makeConstant(value));
}

fn makeConstant(value: Value) u8 {
    const constant = currentChunk().addConstant(value);
    if (constant > 0xFF) {
        @"error"("Too many constants in one chunk.");
        return 0;
    }
    return @truncate(constant);
}

fn endCompiler() void {
    emitReturn();
    if (debug.DEBUG and !parser.hadError) {
        debug.disassembleChunk(currentChunk(), "code");
    }
}

const rules = ParseRules.init();

fn binary() void {
    const opType = parser.previous.type;
    const rule = rules.get(opType);
    parsePrecedence(@enumFromInt(@intFromEnum(rule.precedence) + 1));

    switch (opType) {
        .plus => emitOp(.add),
        .minus => emitOp(.subtract),
        .star => emitOp(.multiply),
        .slash => emitOp(.divide),
        .bang_equal => emitOps(.equal, .not),
        .equal_equal => emitOp(.equal),
        .greater => emitOp(.greater),
        .greater_equal => emitOps(.less, .not),
        .less => emitOp(.less),
        .less_equal => emitOps(.greater, .not),
        else => unreachable,
    }
}

fn literal() void {
    switch (parser.previous.type) {
        .kw_false => emitOp(.false),
        .kw_nil => emitOp(.nil),
        .kw_true => emitOp(.true),
        else => unreachable,
    }
}

fn grouping() void {
    expression();
    consume(.right_paren, "Expect ')' after expression.");
}

fn unary() void {
    const opType = parser.previous.type;
    parsePrecedence(.unary);
    switch (opType) {
        .minus => emitOp(.negate),
        .bang => emitOp(.not),
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

const ParseFn = *const fn () void;

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

fn parsePrecedence(precedence: Precedence) void {
    parser.canAssign = precedence.canAssign();
    advance();
    if (rules.get(parser.previous.type).prefix) |prefixRule| {
        prefixRule();
    } else {
        @"error"("Expect expression.");
        return;
    }

    while (precedence.lte(rules.get(parser.current.type).precedence)) {
        advance();
        if (rules.get(parser.previous.type).infix) |infixRule| {
            infixRule();
        }
    }

    if (parser.canAssign and match(.equal)) {
        @"error"("Invalid assignment target");
    }
}

fn identifierConstant(name: Token) u8 {
    return makeConstant(.ownedStr(parser.gpa, parser.objects, name.type.identifier));
}

fn parseVariable(errorMessage: []const u8) u8 {
    consume(.identifier, errorMessage);
    return identifierConstant(parser.previous);
}

fn defineVariable(global: u8) void {
    emitOp1(.define_global, global);
}

fn expression() void {
    parsePrecedence(.assignment);
}

fn declaration() void {
    if (match(.kw_var)) {
        varDeclaration();
    } else {
        statement();
    }

    if (parser.panicMode) synchronize();
}

fn varDeclaration() void {
    const global = parseVariable("Expect variable name.");
    if (match(.equal)) {
        expression();
    } else {
        emitOp(.nil);
    }
    consume(.semicolon, "Expect ';' after variable declaration.");
    defineVariable(global);
}

fn statement() void {
    if (match(.kw_print)) {
        printStatement();
    } else {
        expressionStatement();
    }
}

fn expressionStatement() void {
    expression();
    consume(.semicolon, "Expect ; after value.");
    emitOp(.pop);
}

fn printStatement() void {
    expression();
    consume(.semicolon, "Expect ; after value.");
    emitOp(.print);
}

fn synchronize() void {
    parser.panicMode = false;

    while (parser.current.type != .eof) {
        if (parser.previous.type == .semicolon) return;
        switch (parser.current.type) {
            .kw_class, .kw_fun, .kw_var, .kw_for, .kw_if, .kw_while, .kw_print, .kw_return => return,
            else => {},
        }
        advance();
    }
}

fn number() void {
    emitConstant(.{ .number = parser.previous.type.number });
}

fn string() void {
    emitConstant(.ownedStr(parser.gpa, parser.objects, parser.previous.type.string));
}

fn namedVariable(name: Token) void {
    const arg = identifierConstant(name);
    if (parser.canAssign and match(.equal)) {
        expression();
        emitOp1(.set_global, arg);
    } else {
        emitOp1(.get_global, arg);
    }
}

fn variable() void {
    return namedVariable(parser.previous);
}

fn errorAtCurrent(message: []const u8) void {
    errorAt(parser.current, message);
}

fn @"error"(message: []const u8) void {
    errorAt(parser.previous, message);
}

fn errorAt(token: Token, message: []const u8) void {
    defer token.deinit(parser.gpa);
    if (parser.panicMode) return;
    parser.panicMode = true;
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
    parser.hadError = true;
}
