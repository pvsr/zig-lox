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

const MAX_LOCALS = std.math.maxInt(u8);

const Local = struct {
    name: Token,
    depth: ?u16,
};

const Compiler = struct {
    locals: [MAX_LOCALS]Local = undefined,
    localCount: u8 = 0,
    scopeDepth: u16 = 0,

    pub fn resolveLocal(self: Compiler, name: Token) ?u8 {
        var i = self.localCount;
        while (i > 0) : (i -= 1) {
            const local = compiler.locals[i - 1];
            if (std.mem.eql(u8, name.type.identifier, local.name.type.identifier)) {
                if (local.depth == null) {
                    @"error"("Can't read local variable in its own initializer.");
                }
                return i - 1;
            }
        }
        return null;
    }
};

var parser: Parser = undefined;
var compiler: Compiler = .{};

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

fn emitJump(op: Chunk.OpCode) usize {
    emitOp(op);
    emitByte(0xFF);
    emitByte(0xFF);
    return currentChunk().code.items.len - 2;
}

fn emitReturn() void {
    emitOp(.@"return");
}

fn emitConstant(value: Value) void {
    emitOp1(.constant, makeConstant(value));
}

fn patchJump(offset: usize) void {
    const jump = currentChunk().code.items.len - offset - 2;

    if (jump > std.math.maxInt(u16)) {
        @"error"("Too much code to jump over.");
    }

    const dest: u16 = @intCast(jump);

    const bytes = std.mem.toBytes(dest);
    currentChunk().code.replaceRangeAssumeCapacity(offset, 2, &bytes);
}

fn makeConstant(value: Value) u8 {
    const constant = currentChunk().addConstant(value);
    if (constant > std.math.maxInt(u8)) {
        @"error"("Too many constants in one chunk.");
        return 0;
    }
    return @intCast(constant);
}

fn endCompiler() void {
    emitReturn();
    if (debug.DEBUG and !parser.hadError) {
        debug.disassembleChunk(currentChunk(), "code");
    }
}

fn beginScope() void {
    compiler.scopeDepth += 1;
}

fn endScope() void {
    compiler.scopeDepth -= 1;

    while (compiler.localCount > 0 and compiler.locals[compiler.localCount - 1].depth orelse 0 > compiler.scopeDepth) {
        emitOp(.pop);
        compiler.localCount -= 1;
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
        r.add(.kw_and, null, @"and", .@"and");
        r.add(.kw_false, literal, null, .none);
        r.add(.kw_true, literal, null, .none);
        r.add(.kw_nil, literal, null, .none);
        r.add(.kw_or, null, @"or", .@"or");
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

fn addLocal(name: Token) void {
    if (compiler.localCount == MAX_LOCALS) {
        @"error"("Too many local variables in function.");
        return;
    }

    compiler.locals[compiler.localCount] = .{
        .name = name,
        .depth = null,
    };
    compiler.localCount += 1;
}

fn declareVariable() void {
    if (compiler.scopeDepth == 0) return;

    const name = parser.previous;
    var i = compiler.localCount;
    while (i > 0) : (i -= 1) {
        const local = compiler.locals[i - 1];
        if (local.depth orelse 0 > compiler.scopeDepth) break;

        if (std.mem.eql(u8, name.type.identifier, local.name.type.identifier)) {
            @"error"("Already a variable with this name in scope.");
        }
    }
    addLocal(name);
}

fn parseVariable(errorMessage: []const u8) u8 {
    consume(.identifier, errorMessage);

    declareVariable();
    if (compiler.scopeDepth > 0) return 0;

    return identifierConstant(parser.previous);
}

fn defineVariable(global: u8) void {
    if (compiler.scopeDepth > 0) {
        compiler.locals[compiler.localCount - 1].depth = compiler.scopeDepth;
        return;
    }

    emitOp1(.define_global, global);
}

fn @"and"() void {
    const endJump = emitJump(.jump_if_false);

    emitOp(.pop);
    parsePrecedence(.@"and");

    patchJump(endJump);
}

fn expression() void {
    parsePrecedence(.assignment);
}

fn block() void {
    while (parser.current.type != .right_brace and parser.current.type != .eof)
        declaration();

    consume(.right_brace, "Expect '}' after block.");
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
    } else if (match(.kw_if)) {
        ifStatement();
    } else if (match(.left_brace)) {
        beginScope();
        block();
        endScope();
    } else {
        expressionStatement();
    }
}

fn expressionStatement() void {
    expression();
    consume(.semicolon, "Expect ; after value.");
    emitOp(.pop);
}

fn ifStatement() void {
    consume(.left_paren, "Expect '(' after 'if'.");
    expression();
    consume(.right_paren, "Expect ')' after condition.");

    const then_jump = emitJump(.jump_if_false);
    emitOp(.pop);
    statement();

    const else_jump = emitJump(.jump);

    patchJump(then_jump);
    emitOp(.pop);

    if (match(.kw_else)) statement();
    patchJump(else_jump);
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

fn @"or"() void {
    const endJump = emitJump(.jump_if_true);

    emitOp(.pop);
    parsePrecedence(.@"or");

    patchJump(endJump);
}

fn string() void {
    emitConstant(.ownedStr(parser.gpa, parser.objects, parser.previous.type.string));
}

fn namedVariable(name: Token) void {
    var get_op: Chunk.OpCode = undefined;
    var set_op: Chunk.OpCode = undefined;
    var arg = compiler.resolveLocal(name);
    if (arg) |a| {
        _ = a;
        get_op = .get_local;
        set_op = .set_local;
    } else {
        arg = identifierConstant(name);
        get_op = .get_global;
        set_op = .set_global;
    }

    if (parser.canAssign and match(.equal)) {
        expression();
        emitOp1(set_op, arg.?);
    } else {
        emitOp1(get_op, arg.?);
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
