// Tagged value and heap representation (spec 05 §1, §2).
const std = @import("std");

pub const Tag = enum(u3) {
    int,
    bool,
    unit,
    char,
    ptr,
    fn_ref,
    _reserved1,
    _reserved2,
};

pub const Value = packed struct(u64) {
    tag: Tag,
    payload: u61,

    pub fn int(v: i64) Value {
        const truncated = @as(u64, @bitCast(v)) & 0x1FFFFFFFFFFFFFFF;
        return .{ .tag = .int, .payload = @truncate(truncated) };
    }
    pub fn intTo(v: Value) i64 {
        if (v.tag != .int) return 0;
        const u = @as(u64, v.payload) << 3;
        return @as(i64, @bitCast(u)) >> 3;
    }
    pub fn boolVal(v: bool) Value {
        return .{ .tag = .bool, .payload = if (v) 1 else 0 };
    }
    pub fn unit() Value {
        return .{ .tag = .unit, .payload = 0 };
    }
    pub fn char(c: u32) Value {
        return .{ .tag = .char, .payload = c };
    }
    /// Store heap pointer (must be 8-byte aligned). PTR tag.
    pub fn ptr(p: usize) Value {
        return .{ .tag = .ptr, .payload = @truncate(p >> 3) };
    }
    pub fn ptrTo(v: Value) usize {
        if (v.tag != .ptr) return 0;
        return @as(usize, v.payload) << 3;
    }

    /// Encode a function reference: module_index (upper 16 bits of payload) + fn_index (lower 32 bits).
    pub fn fnRef(module_index: u16, fn_index: u32) Value {
        const payload: u61 = (@as(u61, module_index) << 32) | @as(u61, fn_index);
        return .{ .tag = .fn_ref, .payload = payload };
    }
    pub fn fnRefModule(v: Value) u16 {
        if (v.tag != .fn_ref) return 0;
        return @truncate(v.payload >> 32);
    }
    pub fn fnRefIndex(v: Value) u32 {
        if (v.tag != .fn_ref) return 0;
        return @truncate(v.payload);
    }
};

test "value size" {
    try std.testing.expect(@sizeOf(Value) == 8);
}

test "int round-trip 61-bit extrema" {
    const hi: i64 = (1 << 60) - 1;
    const lo: i64 = -(@as(i64, 1) << 60);
    try std.testing.expect(Value.intTo(Value.int(hi)) == hi);
    try std.testing.expect(Value.intTo(Value.int(lo)) == lo);
}

test "bool unit char ptr fn_ref round-trip" {
    const t = Value.boolVal(true);
    try std.testing.expect(t.tag == .bool);
    try std.testing.expect(t.payload != 0);
    try std.testing.expect(Value.boolVal(false).payload == 0);
    try std.testing.expect(Value.unit().tag == .unit);
    try std.testing.expect(Value.char(0x1F600).payload == 0x1F600);
    const addr: usize = 0x1000;
    try std.testing.expect(Value.ptrTo(Value.ptr(addr)) == addr);
    const fr = Value.fnRef(0xABCD, 0x12345678);
    try std.testing.expect(Value.fnRefModule(fr) == 0xABCD);
    try std.testing.expect(Value.fnRefIndex(fr) == 0x12345678);
}
