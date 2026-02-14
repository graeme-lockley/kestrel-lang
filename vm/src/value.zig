// Tagged value and heap representation (spec 05 §1, §2).
const std = @import("std");

pub const Tag = enum(u3) {
    int,
    bool,
    unit,
    char,
    ptr,
    _reserved1,
    _reserved2,
    _reserved3,
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
};

test "value size" {
    try std.testing.expect(@sizeOf(Value) == 8);
}
