// Hand-crafted bytecode integration tests (spec 04, 08 §2.4). Opcode bytes must match exec.zig.
const std = @import("std");
const Value = @import("value.zig").Value;
const load_mod = @import("load.zig");
const exec_mod = @import("exec.zig");

const LOAD_CONST: u8 = 0x01;
const LOAD_LOCAL: u8 = 0x02;
const STORE_LOCAL: u8 = 0x03;
const ADD: u8 = 0x04;
const SUB: u8 = 0x05;
const MUL: u8 = 0x06;
const DIV: u8 = 0x07;
const MOD: u8 = 0x08;
const POW: u8 = 0x09;
const EQ: u8 = 0x0A;
const NE: u8 = 0x0B;
const LT: u8 = 0x0C;
const LE: u8 = 0x0D;
const GT: u8 = 0x0E;
const GE: u8 = 0x0F;
const CALL: u8 = 0x10;
const RET: u8 = 0x11;
const JUMP: u8 = 0x12;
const JUMP_IF_FALSE: u8 = 0x13;
const CONSTRUCT: u8 = 0x14;
const MATCH: u8 = 0x15;
const ALLOC_RECORD: u8 = 0x16;
const GET_FIELD: u8 = 0x17;
const SET_FIELD: u8 = 0x18;
const SPREAD: u8 = 0x19;
const THROW: u8 = 0x1A;
const TRY: u8 = 0x1B;
const END_TRY: u8 = 0x1C;
const CALL_INDIRECT: u8 = 0x20;
const LOAD_FN: u8 = 0x21;
const MAKE_CLOSURE: u8 = 0x22;

fn writeU32(buf: []u8, off: usize, v: u32) void {
    std.mem.writeInt(u32, buf[off..][0..4], v, .little);
}

fn writeI32(buf: []u8, off: usize, v: i32) void {
    std.mem.writeInt(i32, buf[off..][0..4], v, .little);
}

/// Run top-level code (empty function table) and return the top stack value after outer RET.
fn runTop(a: std.mem.Allocator, code: []const u8, constants: []const Value, shapes: []const load_mod.ShapeEntry, adts: []const load_mod.AdtEntry) !Value {
    const file_data = try a.alloc(u8, 0);
    const code_owned = try a.dupe(u8, code);
    const constants_owned = try a.alloc(Value, constants.len);
    @memcpy(constants_owned, constants);

    var m = load_mod.Module{
        .code = code_owned,
        .constants = constants_owned,
        .functions = &[_]load_mod.FnEntry{},
        .shapes = shapes,
        .adts = adts,
        .strings = &[_]load_mod.StringEntry{},
        .string_slices = &[_][]const u8{},
        .float_objects = &[_][]u8{},
        .import_specifiers = &[_][]const u8{},
        .imported_functions = &[_]load_mod.ImportedFnEntry{},
        .globals = &[_]Value{},
        .file_data = file_data,
        .debug_files = &[_][]const u8{},
        .debug_entries = &[_]load_mod.DebugEntry{},
    };
    defer load_mod.freeModule(a, &m);

    var top: Value = undefined;
    try std.testing.expect(exec_mod.run(a, &m, "vm_bytecode_tests.ks", &top));
    return top;
}

fn expectIntTop(a: std.mem.Allocator, code: []const u8, constants: []const Value, shapes: []const load_mod.ShapeEntry, adts: []const load_mod.AdtEntry, want: i64) !void {
    const top = try runTop(a, code, constants, shapes, adts);
    try std.testing.expect(top.tag == .int);
    try std.testing.expect(Value.intTo(top) == want);
}

fn expectBoolTop(a: std.mem.Allocator, code: []const u8, constants: []const Value, want: bool) !void {
    const top = try runTop(a, code, constants, &[_]load_mod.ShapeEntry{}, &[_]load_mod.AdtEntry{});
    try std.testing.expect(top.tag == .bool);
    try std.testing.expect((top.payload != 0) == want);
}

test "bytecode ADD SUB MUL DIV MOD POW int" {
    const a = std.testing.allocator;
    // (10 + 3) * 2 - 5 = 21
    try expectIntTop(a, &.{
        LOAD_CONST, 0, 0, 0, 0,
        LOAD_CONST, 1, 0, 0, 0,
        ADD,
        LOAD_CONST, 2, 0, 0, 0,
        MUL,
        LOAD_CONST, 3, 0, 0, 0,
        SUB,
        RET,
    }, &[_]Value{ Value.int(10), Value.int(3), Value.int(2), Value.int(5) }, &[_]load_mod.ShapeEntry{}, &[_]load_mod.AdtEntry{}, 21);
    // 100 / 7 = 14
    try expectIntTop(a, &.{
        LOAD_CONST, 0, 0, 0, 0,
        LOAD_CONST, 1, 0, 0, 0,
        DIV,
        RET,
    }, &[_]Value{ Value.int(100), Value.int(7) }, &[_]load_mod.ShapeEntry{}, &[_]load_mod.AdtEntry{}, 14);
    // 100 % 7 = 2
    try expectIntTop(a, &.{
        LOAD_CONST, 0, 0, 0, 0,
        LOAD_CONST, 1, 0, 0, 0,
        MOD,
        RET,
    }, &[_]Value{ Value.int(100), Value.int(7) }, &[_]load_mod.ShapeEntry{}, &[_]load_mod.AdtEntry{}, 2);
    // 2 ** 10 = 1024
    try expectIntTop(a, &.{
        LOAD_CONST, 0, 0, 0, 0,
        LOAD_CONST, 1, 0, 0, 0,
        POW,
        RET,
    }, &[_]Value{ Value.int(2), Value.int(10) }, &[_]load_mod.ShapeEntry{}, &[_]load_mod.AdtEntry{}, 1024);
}

test "bytecode comparisons EQ NE LT for int and bool" {
    const a = std.testing.allocator;
    try expectBoolTop(a, &.{
        LOAD_CONST, 0, 0, 0, 0,
        LOAD_CONST, 1, 0, 0, 0,
        LT,
        RET,
    }, &[_]Value{ Value.int(1), Value.int(2) }, true);
    try expectBoolTop(a, &.{
        LOAD_CONST, 0, 0, 0, 0,
        LOAD_CONST, 1, 0, 0, 0,
        EQ,
        RET,
    }, &[_]Value{ Value.int(7), Value.int(7) }, true);
    try expectBoolTop(a, &.{
        LOAD_CONST, 0, 0, 0, 0,
        LOAD_CONST, 1, 0, 0, 0,
        NE,
        RET,
    }, &[_]Value{ Value.boolVal(false), Value.boolVal(true) }, true);
    try expectBoolTop(a, &.{
        LOAD_CONST, 0, 0, 0, 0,
        LOAD_CONST, 1, 0, 0, 0,
        LE,
        RET,
    }, &[_]Value{ Value.int(2), Value.int(2) }, true);
    try expectBoolTop(a, &.{
        LOAD_CONST, 0, 0, 0, 0,
        LOAD_CONST, 1, 0, 0, 0,
        GE,
        RET,
    }, &[_]Value{ Value.int(5), Value.int(3) }, true);
    try expectBoolTop(a, &.{
        LOAD_CONST, 0, 0, 0, 0,
        LOAD_CONST, 1, 0, 0, 0,
        GT,
        RET,
    }, &[_]Value{ Value.int(9), Value.int(1) }, true);
}

test "bytecode JUMP and JUMP_IF_FALSE" {
    const a = std.testing.allocator;
    // JUMP at 0: after decode pc=5; target pc+off=10 skips false push, lands on true+RET
    try expectBoolTop(a, &.{
        JUMP,       5, 0, 0, 0,
        LOAD_CONST, 0, 0, 0, 0,
        LOAD_CONST, 1, 0, 0, 0,
        RET,
    }, &[_]Value{ Value.boolVal(false), Value.boolVal(true) }, true);

    // false: skip ldc(42)+RET (6 bytes); pc after reading offset is 10, so offset=6 lands on ldc(99)
    const top = try runTop(a, &.{
        LOAD_CONST,     0, 0, 0, 0,
        JUMP_IF_FALSE,  6, 0, 0, 0,
        LOAD_CONST,     1, 0, 0, 0,
        RET,
        LOAD_CONST,     2, 0, 0, 0,
        RET,
    }, &[_]Value{ Value.boolVal(false), Value.int(42), Value.int(99) }, &[_]load_mod.ShapeEntry{}, &[_]load_mod.AdtEntry{});
    try std.testing.expect(top.tag == .int);
    try std.testing.expect(Value.intTo(top) == 99);
}

test "bytecode ALLOC_RECORD GET_FIELD SET_FIELD" {
    const a = std.testing.allocator;
    const file_data = try a.alloc(u8, 0);
    const names = try a.alloc([]const u8, 2);
    names[0] = "a";
    names[1] = "b";
    const shapes = try a.alloc(load_mod.ShapeEntry, 1);
    shapes[0] = .{ .field_count = 2, .field_names = names };

    var code: [48]u8 = undefined;
    var c: usize = 0;
    code[c] = LOAD_CONST;
    writeU32(&code, c + 1, 0);
    c += 5;
    code[c] = LOAD_CONST;
    writeU32(&code, c + 1, 1);
    c += 5;
    code[c] = ALLOC_RECORD;
    writeU32(&code, c + 1, 0);
    c += 5;
    code[c] = STORE_LOCAL;
    writeU32(&code, c + 1, 0);
    c += 5;
    code[c] = LOAD_CONST;
    writeU32(&code, c + 1, 2);
    c += 5;
    code[c] = LOAD_LOCAL;
    writeU32(&code, c + 1, 0);
    c += 5;
    code[c] = SET_FIELD;
    writeU32(&code, c + 1, 0);
    c += 5;
    code[c] = LOAD_LOCAL;
    writeU32(&code, c + 1, 0);
    c += 5;
    code[c] = GET_FIELD;
    writeU32(&code, c + 1, 1);
    c += 5;
    code[c] = RET;
    c += 1;

    const constants = [_]Value{ Value.int(1), Value.int(2), Value.int(40) };
    const code_owned = try a.dupe(u8, code[0..c]);
    const constants_owned = try a.alloc(Value, constants.len);
    @memcpy(constants_owned, &constants);

    var m = load_mod.Module{
        .code = code_owned,
        .constants = constants_owned,
        .functions = &[_]load_mod.FnEntry{},
        .shapes = shapes,
        .adts = &[_]load_mod.AdtEntry{},
        .strings = &[_]load_mod.StringEntry{},
        .string_slices = &[_][]const u8{},
        .float_objects = &[_][]u8{},
        .import_specifiers = &[_][]const u8{},
        .imported_functions = &[_]load_mod.ImportedFnEntry{},
        .globals = &[_]Value{},
        .file_data = file_data,
        .debug_files = &[_][]const u8{},
        .debug_entries = &[_]load_mod.DebugEntry{},
    };
    defer load_mod.freeModule(a, &m);

    var top: Value = undefined;
    try std.testing.expect(exec_mod.run(a, &m, "vm_bytecode_tests.ks", &top));
    try std.testing.expect(top.tag == .int);
    try std.testing.expect(Value.intTo(top) == 2);
}

test "bytecode SPREAD extends record" {
    const a = std.testing.allocator;
    const file_data = try a.alloc(u8, 0);
    const names2 = try a.alloc([]const u8, 2);
    names2[0] = "x";
    names2[1] = "y";
    const names3 = try a.alloc([]const u8, 3);
    names3[0] = "x";
    names3[1] = "y";
    names3[2] = "z";
    const shapes = try a.alloc(load_mod.ShapeEntry, 2);
    shapes[0] = .{ .field_count = 2, .field_names = names2 };
    shapes[1] = .{ .field_count = 3, .field_names = names3 };

    var code: [48]u8 = undefined;
    var c: usize = 0;
    // base {1,2} in local 0; stack [99, rec] for SPREAD (extras below record)
    code[c] = LOAD_CONST;
    writeU32(&code, c + 1, 0);
    c += 5;
    code[c] = LOAD_CONST;
    writeU32(&code, c + 1, 1);
    c += 5;
    code[c] = ALLOC_RECORD;
    writeU32(&code, c + 1, 0);
    c += 5;
    code[c] = STORE_LOCAL;
    writeU32(&code, c + 1, 0);
    c += 5;
    code[c] = LOAD_CONST;
    writeU32(&code, c + 1, 2);
    c += 5;
    code[c] = LOAD_LOCAL;
    writeU32(&code, c + 1, 0);
    c += 5;
    code[c] = SPREAD;
    writeU32(&code, c + 1, 1);
    c += 5;
    code[c] = GET_FIELD;
    writeU32(&code, c + 1, 2);
    c += 5;
    code[c] = RET;
    c += 1;

    const constants = [_]Value{ Value.int(1), Value.int(2), Value.int(99) };
    const code_owned = try a.dupe(u8, code[0..c]);
    const constants_owned = try a.alloc(Value, constants.len);
    @memcpy(constants_owned, &constants);

    var m = load_mod.Module{
        .code = code_owned,
        .constants = constants_owned,
        .functions = &[_]load_mod.FnEntry{},
        .shapes = shapes,
        .adts = &[_]load_mod.AdtEntry{},
        .strings = &[_]load_mod.StringEntry{},
        .string_slices = &[_][]const u8{},
        .float_objects = &[_][]u8{},
        .import_specifiers = &[_][]const u8{},
        .imported_functions = &[_]load_mod.ImportedFnEntry{},
        .globals = &[_]Value{},
        .file_data = file_data,
        .debug_files = &[_][]const u8{},
        .debug_entries = &[_]load_mod.DebugEntry{},
    };
    defer load_mod.freeModule(a, &m);

    var top: Value = undefined;
    try std.testing.expect(exec_mod.run(a, &m, "vm_bytecode_tests.ks", &top));
    try std.testing.expect(top.tag == .int);
    try std.testing.expect(Value.intTo(top) == 99);
}

test "bytecode CONSTRUCT and MATCH dispatch by ctor tag" {
    const a = std.testing.allocator;
    const ctor_names = try a.alloc([]const u8, 2);
    ctor_names[0] = "A";
    ctor_names[1] = "B";
    const adts = try a.alloc(load_mod.AdtEntry, 1);
    adts[0] = .{ .name = "T", .constructor_names = ctor_names };

    // 0: CONSTRUCT (13 B) | 13: MATCH + count + jt (13 B) | 26: arm0 | 32: arm1
    const match_pc: usize = 13;
    const arm0_pc: usize = 26;
    const arm1_pc: usize = 32;
    const off0 = @as(i32, @intCast(@as(isize, @intCast(arm0_pc)) - @as(isize, @intCast(match_pc))));
    const off1 = @as(i32, @intCast(@as(isize, @intCast(arm1_pc)) - @as(isize, @intCast(match_pc))));

    var code: [48]u8 = undefined;
    @memset(&code, 0);
    var c: usize = 0;
    code[c] = CONSTRUCT;
    writeU32(&code, c + 1, 0);
    writeU32(&code, c + 5, 1);
    writeU32(&code, c + 9, 0);
    c += 13;
    try std.testing.expect(c == match_pc);
    code[c] = MATCH;
    writeU32(&code, c + 1, 2);
    c += 5;
    writeI32(&code, c, off0);
    c += 4;
    writeI32(&code, c, off1);
    c += 4;
    try std.testing.expect(c == arm0_pc);
    code[c] = LOAD_CONST;
    writeU32(&code, c + 1, 0);
    c += 5;
    code[c] = RET;
    c += 1;
    try std.testing.expect(c == arm1_pc);
    code[c] = LOAD_CONST;
    writeU32(&code, c + 1, 1);
    c += 5;
    code[c] = RET;
    c += 1;

    const constants = [_]Value{ Value.int(10), Value.int(20) };
    const file_data = try a.alloc(u8, 0);
    const code_owned = try a.dupe(u8, code[0..c]);
    const constants_owned = try a.alloc(Value, constants.len);
    @memcpy(constants_owned, &constants);
    var m = load_mod.Module{
        .code = code_owned,
        .constants = constants_owned,
        .functions = &[_]load_mod.FnEntry{},
        .shapes = &[_]load_mod.ShapeEntry{},
        .adts = adts,
        .strings = &[_]load_mod.StringEntry{},
        .string_slices = &[_][]const u8{},
        .float_objects = &[_][]u8{},
        .import_specifiers = &[_][]const u8{},
        .imported_functions = &[_]load_mod.ImportedFnEntry{},
        .globals = &[_]Value{},
        .file_data = file_data,
        .debug_files = &[_][]const u8{},
        .debug_entries = &[_]load_mod.DebugEntry{},
    };
    defer load_mod.freeModule(a, &m);
    var top: Value = undefined;
    try std.testing.expect(exec_mod.run(a, &m, "vm_bytecode_tests.ks", &top));
    try std.testing.expect(top.tag == .int);
    try std.testing.expect(Value.intTo(top) == 20);
}

test "bytecode LOAD_FN and CALL_INDIRECT fn_ref" {
    const a = std.testing.allocator;
    const file_data = try a.alloc(u8, 0);
    const fns = try a.alloc(load_mod.FnEntry, 1);
    fns[0] = .{ .code_offset = 30, .arity = 2 };

    var code: [56]u8 = undefined;
    @memset(&code, 0);
    var c: usize = 0;
    // CALL_INDIRECT expects stack [fn_ref, arg0, arg1] (callee lowest)
    code[c] = LOAD_FN;
    writeU32(&code, c + 1, 0);
    c += 5;
    code[c] = LOAD_CONST;
    writeU32(&code, c + 1, 0);
    c += 5;
    code[c] = LOAD_CONST;
    writeU32(&code, c + 1, 1);
    c += 5;
    code[c] = CALL_INDIRECT;
    writeU32(&code, c + 1, 2);
    c += 5;
    code[c] = RET;
    c += 1;
    c = 30;
    code[c] = LOAD_LOCAL;
    writeU32(&code, c + 1, 0);
    c += 5;
    code[c] = LOAD_LOCAL;
    writeU32(&code, c + 1, 1);
    c += 5;
    code[c] = ADD;
    c += 1;
    code[c] = RET;
    c += 1;

    const constants = [_]Value{ Value.int(100), Value.int(23) };
    const code_owned = try a.dupe(u8, code[0..]);
    const constants_owned = try a.alloc(Value, constants.len);
    @memcpy(constants_owned, &constants);
    var m = load_mod.Module{
        .code = code_owned,
        .constants = constants_owned,
        .functions = fns,
        .shapes = &[_]load_mod.ShapeEntry{},
        .adts = &[_]load_mod.AdtEntry{},
        .strings = &[_]load_mod.StringEntry{},
        .string_slices = &[_][]const u8{},
        .float_objects = &[_][]u8{},
        .import_specifiers = &[_][]const u8{},
        .imported_functions = &[_]load_mod.ImportedFnEntry{},
        .globals = &[_]Value{},
        .file_data = file_data,
        .debug_files = &[_][]const u8{},
        .debug_entries = &[_]load_mod.DebugEntry{},
    };
    defer load_mod.freeModule(a, &m);
    var top: Value = undefined;
    try std.testing.expect(exec_mod.run(a, &m, "vm_bytecode_tests.ks", &top));
    try std.testing.expect(top.tag == .int);
    try std.testing.expect(Value.intTo(top) == 123);
}

test "bytecode MAKE_CLOSURE and CALL_INDIRECT" {
    const a = std.testing.allocator;
    const file_data = try a.alloc(u8, 0);
    const names = try a.alloc([]const u8, 1);
    names[0] = "e";
    const shapes = try a.alloc(load_mod.ShapeEntry, 1);
    shapes[0] = .{ .field_count = 1, .field_names = names };
    const fns = try a.alloc(load_mod.FnEntry, 1);
    fns[0] = .{ .code_offset = 40, .arity = 2 };

    var code: [64]u8 = undefined;
    @memset(&code, 0);
    var c: usize = 0;
    code[c] = LOAD_CONST;
    writeU32(&code, c + 1, 0);
    c += 5;
    code[c] = ALLOC_RECORD;
    writeU32(&code, c + 1, 0);
    c += 5;
    code[c] = MAKE_CLOSURE;
    writeU32(&code, c + 1, 0);
    c += 5;
    code[c] = LOAD_CONST;
    writeU32(&code, c + 1, 1);
    c += 5;
    code[c] = CALL_INDIRECT;
    writeU32(&code, c + 1, 1);
    c += 5;
    code[c] = RET;
    c += 1;

    c = 40;
    code[c] = LOAD_LOCAL;
    writeU32(&code, c + 1, 0);
    c += 5;
    code[c] = GET_FIELD;
    writeU32(&code, c + 1, 0);
    c += 5;
    code[c] = LOAD_LOCAL;
    writeU32(&code, c + 1, 1);
    c += 5;
    code[c] = ADD;
    c += 1;
    code[c] = RET;
    c += 1;

    const constants = [_]Value{ Value.int(5), Value.int(7) };
    const code_owned = try a.dupe(u8, code[0..]);
    const constants_owned = try a.alloc(Value, constants.len);
    @memcpy(constants_owned, &constants);
    var m = load_mod.Module{
        .code = code_owned,
        .constants = constants_owned,
        .functions = fns,
        .shapes = shapes,
        .adts = &[_]load_mod.AdtEntry{},
        .strings = &[_]load_mod.StringEntry{},
        .string_slices = &[_][]const u8{},
        .float_objects = &[_][]u8{},
        .import_specifiers = &[_][]const u8{},
        .imported_functions = &[_]load_mod.ImportedFnEntry{},
        .globals = &[_]Value{},
        .file_data = file_data,
        .debug_files = &[_][]const u8{},
        .debug_entries = &[_]load_mod.DebugEntry{},
    };
    defer load_mod.freeModule(a, &m);
    var top: Value = undefined;
    try std.testing.expect(exec_mod.run(a, &m, "vm_bytecode_tests.ks", &top));
    try std.testing.expect(top.tag == .int);
    try std.testing.expect(Value.intTo(top) == 12);
}

test "bytecode TRY catch DivideByZero" {
    const a = std.testing.allocator;
    const ctor_names = try a.alloc([]const u8, 1);
    ctor_names[0] = "E";
    const adts = try a.alloc(load_mod.AdtEntry, 1);
    adts[0] = .{ .name = "DivideByZero", .constructor_names = ctor_names };

    var code: [48]u8 = undefined;
    @memset(&code, 0);
    const try_pc: usize = 0;
    var c: usize = try_pc;
    code[c] = TRY;
    const catch_pc: usize = 20;
    writeI32(&code, c + 1, @intCast(@as(isize, @intCast(catch_pc)) - @as(isize, @intCast(try_pc))));
    c += 5;
    code[c] = LOAD_CONST;
    writeU32(&code, c + 1, 0);
    c += 5;
    code[c] = LOAD_CONST;
    writeU32(&code, c + 1, 1);
    c += 5;
    code[c] = DIV;
    c += 1;
    code[c] = LOAD_CONST;
    writeU32(&code, c + 1, 2);
    c += 5;
    code[c] = RET;
    c += 1;

    c = catch_pc;
    code[c] = LOAD_CONST;
    writeU32(&code, c + 1, 3);
    c += 5;
    code[c] = END_TRY;
    c += 1;
    code[c] = RET;
    c += 1;

    const constants = [_]Value{ Value.int(1), Value.int(0), Value.int(999), Value.int(42) };
    const file_data = try a.alloc(u8, 0);
    const code_owned = try a.dupe(u8, code[0..c]);
    const constants_owned = try a.alloc(Value, constants.len);
    @memcpy(constants_owned, &constants);
    var m = load_mod.Module{
        .code = code_owned,
        .constants = constants_owned,
        .functions = &[_]load_mod.FnEntry{},
        .shapes = &[_]load_mod.ShapeEntry{},
        .adts = adts,
        .strings = &[_]load_mod.StringEntry{},
        .string_slices = &[_][]const u8{},
        .float_objects = &[_][]u8{},
        .import_specifiers = &[_][]const u8{},
        .imported_functions = &[_]load_mod.ImportedFnEntry{},
        .globals = &[_]Value{},
        .file_data = file_data,
        .debug_files = &[_][]const u8{},
        .debug_entries = &[_]load_mod.DebugEntry{},
    };
    defer load_mod.freeModule(a, &m);
    var top: Value = undefined;
    try std.testing.expect(exec_mod.run(a, &m, "vm_bytecode_tests.ks", &top));
    try std.testing.expect(top.tag == .int);
    try std.testing.expect(Value.intTo(top) == 42);
}

test "bytecode TRY END_TRY no throw" {
    const a = std.testing.allocator;
    var code: [24]u8 = undefined;
    var c: usize = 0;
    code[c] = TRY;
    writeI32(&code, c + 1, 20); // unused catch
    c += 5;
    code[c] = LOAD_CONST;
    writeU32(&code, c + 1, 0);
    c += 5;
    code[c] = END_TRY;
    c += 1;
    code[c] = RET;
    c += 1;

    const constants = [_]Value{Value.int(77)};
    try expectIntTop(a, code[0..c], &constants, &[_]load_mod.ShapeEntry{}, &[_]load_mod.AdtEntry{}, 77);
}

test "bytecode THROW uncaught fails run" {
    const a = std.testing.allocator;
    const ctor_names = try a.alloc([]const u8, 1);
    ctor_names[0] = "E";
    const adts = try a.alloc(load_mod.AdtEntry, 1);
    adts[0] = .{ .name = "Ex", .constructor_names = ctor_names };

    var code: [24]u8 = undefined;
    var c: usize = 0;
    code[c] = CONSTRUCT;
    writeU32(&code, c + 1, 0);
    writeU32(&code, c + 5, 0);
    writeU32(&code, c + 9, 0);
    c += 13;
    code[c] = THROW;
    c += 1;

    const file_data = try a.alloc(u8, 0);
    const code_owned = try a.dupe(u8, code[0..c]);
    const constants_empty = try a.alloc(Value, 0);
    var m = load_mod.Module{
        .code = code_owned,
        .constants = constants_empty,
        .functions = &[_]load_mod.FnEntry{},
        .shapes = &[_]load_mod.ShapeEntry{},
        .adts = adts,
        .strings = &[_]load_mod.StringEntry{},
        .string_slices = &[_][]const u8{},
        .float_objects = &[_][]u8{},
        .import_specifiers = &[_][]const u8{},
        .imported_functions = &[_]load_mod.ImportedFnEntry{},
        .globals = &[_]Value{},
        .file_data = file_data,
        .debug_files = &[_][]const u8{},
        .debug_entries = &[_]load_mod.DebugEntry{},
    };
    defer load_mod.freeModule(a, &m);
    try std.testing.expect(!exec_mod.run(a, &m, "vm_bytecode_tests.ks", null));
}
