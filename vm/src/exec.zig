// Execution loop (spec 04). Stack, locals, LOAD_CONST, STORE_LOCAL, RET, arithmetic, branches.
const std = @import("std");
const Value = @import("value.zig").Value;
const GC = @import("gc.zig").GC;
const primitives = @import("primitives.zig");

fn binopInt(stack: *[4096]Value, sp: *usize, op: *const fn (i64, i64) i64) void {
    if (sp.* >= 2) {
        const b = stack[sp.* - 1];
        const a = stack[sp.* - 2];
        if (a.tag == .int and b.tag == .int) {
            stack[sp.* - 2] = Value.int(op(Value.intTo(a), Value.intTo(b)));
            sp.* -= 1;
        }
    }
}

const CmpOp = enum { eq, ne, lt, le, gt, ge };
fn binopCmp(stack: *[4096]Value, sp: *usize, op: CmpOp) void {
    if (sp.* >= 2) {
        const b = stack[sp.* - 1];
        const a = stack[sp.* - 2];
        var result = false;
        if (a.tag == .int and b.tag == .int) {
            const ai = Value.intTo(a);
            const bi = Value.intTo(b);
            result = switch (op) {
                .eq => ai == bi,
                .ne => ai != bi,
                .lt => ai < bi,
                .le => ai <= bi,
                .gt => ai > bi,
                .ge => ai >= bi,
            };
        } else if (a.tag == .bool and b.tag == .bool) {
            const ab = a.payload != 0;
            const bb = b.payload != 0;
            result = switch (op) {
                .eq => ab == bb,
                .ne => ab != bb,
                else => false,
            };
        }
        stack[sp.* - 2] = Value.boolVal(result);
        sp.* -= 1;
    }
}

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
const JUMP: u8 = 0x12;
const JUMP_IF_FALSE: u8 = 0x13;
const CONSTRUCT: u8 = 0x14;
const MATCH: u8 = 0x15;
const ALLOC_RECORD: u8 = 0x16;
const GET_FIELD: u8 = 0x17;
const SET_FIELD: u8 = 0x18;
const RET: u8 = 0x11;
const THROW: u8 = 0x1A;
const TRY: u8 = 0x1B;
const END_TRY: u8 = 0x1C;
const AWAIT: u8 = 0x1D;

const RECORD_KIND: u8 = 1;
const ADT_KIND: u8 = 2;
const TASK_KIND: u8 = 3;
const max_frames = 32;
const max_locals = 128;
const max_handlers = 32;

const ExceptionHandler = struct {
    handler_pc: usize,
    stack_sp: usize,
    frame_depth: usize,
};

pub fn run(allocator: std.mem.Allocator, module: anytype) void {
    const code = module.code;
    const constants = module.constants;
    const functions = module.functions;
    const shapes = module.shapes;
    var stack: [4096]Value = undefined;
    var sp: usize = 0;
    var locals: [max_locals]Value = undefined;
    for (&locals) |*v| v.* = Value.unit();
    var return_pc: [max_frames]usize = undefined;
    var saved_locals: [max_frames][max_locals]Value = undefined;
    var frame_sp: usize = 0;
    var pc: usize = 0;

    // Exception handler stack
    var handlers: [max_handlers]ExceptionHandler = undefined;
    var handler_sp: usize = 0;

    // Initialize GC
    var gc = GC.init(allocator);
    defer gc.deinit();

    while (pc < code.len) {
        // Periodic GC check
        if (gc.bytes_allocated >= gc.next_gc) {
            gc.collect(stack[0..sp], locals[0..max_locals]);
        }

        const op = code[pc];
        pc += 1;
        switch (op) {
            LOAD_CONST => {
                const idx = std.mem.readInt(u32, code[pc..][0..4], .little);
                pc += 4;
                if (idx < constants.len) {
                    stack[sp] = constants[idx];
                    sp += 1;
                }
            },
            LOAD_LOCAL => {
                const idx = std.mem.readInt(u32, code[pc..][0..4], .little);
                pc += 4;
                if (idx < max_locals) {
                    stack[sp] = locals[idx];
                    sp += 1;
                }
            },
            STORE_LOCAL => {
                const idx = std.mem.readInt(u32, code[pc..][0..4], .little);
                pc += 4;
                if (sp > 0 and idx < max_locals) {
                    sp -= 1;
                    locals[idx] = stack[sp];
                }
            },
            CALL => {
                const fn_id = std.mem.readInt(u32, code[pc..][0..4], .little);
                const arity = std.mem.readInt(u32, code[pc + 4 ..][0..4], .little);
                pc += 8;

                // Check for primitive function (fn_id 0 = print)
                if (fn_id == 0) {
                    // Primitive: print (arity 1)
                    if (sp >= 1) {
                        const arg = stack[sp - 1];
                        sp -= 1;
                        primitives.print(arg);
                        // Push unit as result
                        stack[sp] = Value.unit();
                        sp += 1;
                    }
                    continue;
                }

                // Regular function call
                if (frame_sp >= max_frames or fn_id >= functions.len) continue;
                const entry = functions[fn_id];
                if (sp < arity) continue;
                return_pc[frame_sp] = pc;
                for (saved_locals[frame_sp][0..max_locals], locals) |*s, l| s.* = l;
                frame_sp += 1;
                var i: usize = 0;
                while (i < arity) : (i += 1) {
                    locals[i] = stack[sp - arity + i];
                }
                sp -= arity;
                pc = entry.code_offset;
            },
            ADD => binopInt(&stack, &sp, (struct { fn f(a: i64, b: i64) i64 { return a + b; } }).f),
            SUB => binopInt(&stack, &sp, (struct { fn f(a: i64, b: i64) i64 { return a - b; } }).f),
            MUL => binopInt(&stack, &sp, (struct { fn f(a: i64, b: i64) i64 { return a * b; } }).f),
            DIV => binopInt(&stack, &sp, (struct { fn f(a: i64, b: i64) i64 { if (b == 0) return 0; return @divTrunc(a, b); } }).f),
            MOD => binopInt(&stack, &sp, (struct { fn f(a: i64, b: i64) i64 { if (b == 0) return 0; return @mod(a, b); } }).f),
            POW => binopInt(&stack, &sp, (struct { fn f(a: i64, b: i64) i64 { return std.math.powi(i64, a, @intCast(b)) catch 0; } }).f),
            EQ => binopCmp(&stack, &sp, .eq),
            NE => binopCmp(&stack, &sp, .ne),
            LT => binopCmp(&stack, &sp, .lt),
            LE => binopCmp(&stack, &sp, .le),
            GT => binopCmp(&stack, &sp, .gt),
            GE => binopCmp(&stack, &sp, .ge),
            JUMP => {
                const offset = std.mem.readInt(i32, code[pc..][0..4], .little);
                pc += 4;
                pc = @as(usize, @intCast(@as(isize, @intCast(pc)) + offset));
            },
            JUMP_IF_FALSE => {
                const offset = std.mem.readInt(i32, code[pc..][0..4], .little);
                pc += 4;
                if (sp > 0) {
                    sp -= 1;
                    const v = stack[sp];
                    const is_false = (v.tag == .bool and v.payload == 0);
                    if (is_false) pc = @as(usize, @intCast(@as(isize, @intCast(pc)) + offset));
                }
            },
            ALLOC_RECORD => {
                const shape_id = std.mem.readInt(u32, code[pc..][0..4], .little);
                pc += 4;
                if (shape_id >= shapes.len or sp < shapes[shape_id].field_count) continue;
                const n = shapes[shape_id].field_count;
                const rec = gc.allocObject(8 + n * 8) catch continue;
                @memset(rec, 0);
                rec[0] = RECORD_KIND;
                rec[1] = 0; // mark bit
                std.mem.writeInt(u32, rec[4..8], n, .little);
                const fields_ptr = @as([*]Value, @alignCast(@ptrCast(rec.ptr + 8)));
                var i: usize = 0;
                while (i < n) : (i += 1) {
                    fields_ptr[i] = stack[sp - n + i];
                }
                sp -= n;
                const addr = @intFromPtr(rec.ptr);
                stack[sp] = Value.ptr(addr);
                sp += 1;
            },
            GET_FIELD => {
                const slot = std.mem.readInt(u32, code[pc..][0..4], .little);
                pc += 4;
                if (sp == 0) continue;
                const v = stack[sp - 1];
                sp -= 1;
                if (v.tag != .ptr) continue;
                const addr = Value.ptrTo(v);
                const base = @as([*]const u8, @ptrFromInt(addr));
                const field_offset = 8 + slot * 8;
                const field_ptr = @as(*const Value, @alignCast(@ptrCast(base + field_offset)));
                stack[sp] = field_ptr.*;
                sp += 1;
            },
            SET_FIELD => {
                const slot = std.mem.readInt(u32, code[pc..][0..4], .little);
                pc += 4;
                if (sp < 2) continue;
                const val = stack[sp - 1];
                const rec = stack[sp - 2];
                sp -= 2;
                if (rec.tag != .ptr) continue;
                const addr = Value.ptrTo(rec);
                const base = @as([*]u8, @ptrFromInt(addr));
                const field_offset = 8 + slot * 8;
                const field_ptr = @as(*Value, @alignCast(@ptrCast(base + field_offset)));
                field_ptr.* = val;
                stack[sp] = Value.unit();
                sp += 1;
            },
            CONSTRUCT => {
                const adt_id = std.mem.readInt(u32, code[pc..][0..4], .little);
                const ctor = std.mem.readInt(u32, code[pc + 4 ..][0..4], .little);
                const arity = std.mem.readInt(u32, code[pc + 8 ..][0..4], .little);
                pc += 12;
                _ = adt_id; // Not used for now, ADT info in module (future)
                if (sp < arity) continue;
                // Allocate ADT: kind(1) + mark(1) + pad(2) + ctor_tag(4) + arity * 8 bytes
                const adt = gc.allocObject(8 + arity * 8) catch continue;
                @memset(adt, 0);
                adt[0] = ADT_KIND;
                adt[1] = 0; // mark bit
                std.mem.writeInt(u32, adt[4..8], ctor, .little);
                const fields_ptr = @as([*]Value, @alignCast(@ptrCast(adt.ptr + 8)));
                var i: usize = 0;
                while (i < arity) : (i += 1) {
                    fields_ptr[i] = stack[sp - arity + i];
                }
                sp -= arity;
                const addr = @intFromPtr(adt.ptr);
                stack[sp] = Value.ptr(addr);
                sp += 1;
            },
            MATCH => {
                const count = std.mem.readInt(u32, code[pc..][0..4], .little);
                pc += 4;
                if (sp == 0) {
                    pc += count * 4; // Skip jump table
                    continue;
                }
                const val = stack[sp - 1];
                sp -= 1;
                if (val.tag != .ptr) {
                    pc += count * 4;
                    continue;
                }
                const addr = Value.ptrTo(val);
                const base = @as([*]const u8, @ptrFromInt(addr));
                const kind = base[0];
                if (kind != ADT_KIND) {
                    pc += count * 4;
                    continue;
                }
                const ctor_tag = std.mem.readInt(u32, base[4..8], .little);
                if (ctor_tag >= count) {
                    pc += count * 4;
                    continue;
                }
                // Read the jump offset for this constructor tag
                const match_start = pc - 5; // MATCH opcode is at pc-5 (1 byte op + 4 bytes count)
                const offset_pos = pc + ctor_tag * 4;
                const offset = std.mem.readInt(i32, code[offset_pos..][0..4], .little);
                pc = @as(usize, @intCast(@as(isize, @intCast(match_start)) + offset));
            },
            THROW => {
                // Pop exception value
                if (sp == 0) return;
                const exception = stack[sp - 1];
                sp -= 1;

                // Unwind to nearest exception handler
                if (handler_sp == 0) {
                    // No handler: terminate execution
                    return;
                }

                // Pop handler and restore state
                handler_sp -= 1;
                const handler = handlers[handler_sp];
                pc = handler.handler_pc;
                sp = handler.stack_sp;
                // Push exception value for catch block
                stack[sp] = exception;
                sp += 1;
            },
            TRY => {
                // Read handler offset
                const handler_offset = std.mem.readInt(i32, code[pc..][0..4], .little);
                pc += 4;
                if (handler_sp >= max_handlers) continue;

                // Calculate handler address (relative to TRY instruction start)
                const try_start = pc - 5; // TRY opcode is at pc-5 (1 byte + 4 bytes offset)
                const handler_addr = @as(usize, @intCast(@as(isize, @intCast(try_start)) + handler_offset));

                // Push exception handler
                handlers[handler_sp] = ExceptionHandler{
                    .handler_pc = handler_addr,
                    .stack_sp = sp,
                    .frame_depth = frame_sp,
                };
                handler_sp += 1;
            },
            END_TRY => {
                // Pop exception handler (try block completed normally)
                if (handler_sp > 0) {
                    handler_sp -= 1;
                }
            },
            AWAIT => {
                // Pop task from stack
                if (sp == 0) continue;
                const task_val = stack[sp - 1];
                sp -= 1;

                // Check if it's a PTR to a TASK object
                if (task_val.tag != .ptr) {
                    // Not a task: push unit and continue
                    stack[sp] = Value.unit();
                    sp += 1;
                    continue;
                }

                const addr = Value.ptrTo(task_val);
                const base = @as([*]const u8, @ptrFromInt(addr));
                const kind = base[0];

                if (kind != TASK_KIND) {
                    // Not a task: push unit
                    stack[sp] = Value.unit();
                    sp += 1;
                    continue;
                }

                // Task layout: kind(1) + mark(1) + status(1) + pad(1) + unused(4) + result(8)
                // status: 0 = pending, 1 = completed
                const status = base[2];

                if (status == 1) {
                    // Task completed: push result
                    const result_ptr = @as(*const Value, @alignCast(@ptrCast(base + 8)));
                    stack[sp] = result_ptr.*;
                    sp += 1;
                } else {
                    // Task pending: for now, just push unit (no actual suspension)
                    // A full implementation would suspend the frame here
                    stack[sp] = Value.unit();
                    sp += 1;
                }
            },
            RET => {
                if (sp == 0) return;
                const ret_val = stack[sp - 1];
                sp -= 1;
                if (frame_sp == 0) {
                    return;
                }
                frame_sp -= 1;
                for (locals[0..max_locals], saved_locals[frame_sp]) |*l, s| l.* = s;
                pc = return_pc[frame_sp];
                stack[sp] = ret_val;
                sp += 1;
            },
            else => return, // unknown opcode: stop execution
        }
    }
}
