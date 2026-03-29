// Execution loop (spec 04). Stack, locals, LOAD_CONST, STORE_LOCAL, RET, arithmetic, branches.
const std = @import("std");
const Value = @import("value.zig").Value;
const GC = @import("gc.zig").GC;
const gc_mod = @import("gc.zig");
const load_mod = @import("load.zig");
const primitives = @import("primitives.zig");

/// 61-bit signed integer range (spec 05 §1): payload is 61 bits, so value must fit.
const INT61_MIN: i64 = -(1 << 60);
const INT61_MAX: i64 = (1 << 60) - 1;

/// Allocate a 0-ary exception ADT value from `module`'s ADT table (by type name).
fn allocExceptionValue(gc: *GC, module: *const load_mod.Module, name: []const u8) ?Value {
    for (module.adts, 0..) |adt, adt_id| {
        if (std.mem.eql(u8, adt.name, name)) {
            const adt_obj = gc.allocObject(gc_mod.ADT_HEADER) catch return null;
            @memset(adt_obj, 0);
            adt_obj[0] = ADT_KIND;
            adt_obj[1] = 0;
            adt_obj[2] = 1;
            std.mem.writeInt(u32, adt_obj[4..8], module.module_index, .little);
            std.mem.writeInt(u32, adt_obj[8..12], @as(u32, @intCast(adt_id)), .little);
            std.mem.writeInt(u32, adt_obj[12..16], 0, .little); // ctor 0
            std.mem.writeInt(u32, adt_obj[16..20], 0, .little); // arity 0
            return Value.ptr(@intFromPtr(adt_obj.ptr));
        }
    }
    return null;
}

fn isStdlibRuntimeKbcPath(path: []const u8) bool {
    if (std.mem.indexOf(u8, path, "kestrel/runtime.kbc") != null) return true;
    if (std.mem.indexOf(u8, path, "kestrel\\runtime.kbc") != null) return true;
    return false;
}

/// Integer overflow / divide-by-zero: prefer current module, then `kestrel:runtime` (stdlib).
fn allocRuntimeException(gc: *GC, current_module: *const load_mod.Module, name: []const u8, module_ptrs: []const *const load_mod.Module) ?Value {
    if (allocExceptionValue(gc, current_module, name)) |v| return v;
    for (module_ptrs) |mp| {
        const p = mp.source_path orelse continue;
        if (!isStdlibRuntimeKbcPath(p)) continue;
        if (allocExceptionValue(gc, mp, name)) |v| return v;
    }
    return null;
}

/// Load `kestrel:runtime` if `.deps` lists it so overflow/divzero can use canonical ADT ids.
fn ensureStdlibRuntimeModule(
    allocator: std.mem.Allocator,
    entry_kbc_path: []const u8,
    module_ptrs: *std.ArrayListUnmanaged(*const load_mod.Module),
    path_to_module: *std.StringHashMap(*load_mod.Module),
    dependency_cache: *std.ArrayListUnmanaged(load_mod.Module),
    path_keys: *std.ArrayList([]const u8),
) void {
    const dep_path = resolveImportPath(allocator, "kestrel:runtime", entry_kbc_path) catch return;
    defer allocator.free(dep_path);
    if (path_to_module.get(dep_path)) |_| return;
    dependency_cache.ensureTotalCapacity(allocator, dependency_cache.items.len + 1) catch return;
    const loaded = load_mod.load(allocator, dep_path) catch return;
    dependency_cache.appendAssumeCapacity(loaded);
    const ptr = &dependency_cache.items[dependency_cache.items.len - 1];
    module_ptrs.ensureTotalCapacity(allocator, module_ptrs.items.len + 1) catch return;
    ptr.module_index = @intCast(module_ptrs.items.len);
    module_ptrs.appendAssumeCapacity(ptr);
    ptr.source_path = allocator.dupe(u8, dep_path) catch null;
    const path_key = allocator.dupe(u8, dep_path) catch return;
    path_keys.append(allocator, path_key) catch {
        allocator.free(path_key);
        return;
    };
    path_to_module.put(path_key, ptr) catch {
        _ = path_keys.pop();
        allocator.free(path_key);
        return;
    };
}

fn binopInt(stack: *[operand_stack_slots]Value, sp: *usize, op: *const fn (i64, i64) i64) void {
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
fn binopCmp(stack: *[operand_stack_slots]Value, sp: *usize, op: CmpOp, modules: []const *const load_mod.Module) void {
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
        } else if (a.tag == .unit and b.tag == .unit) {
            result = switch (op) {
                .eq => true,
                .ne => false,
                else => false,
            };
        } else if (a.tag == .char and b.tag == .char) {
            const ac: u32 = @truncate(a.payload);
            const bc: u32 = @truncate(b.payload);
            result = switch (op) {
                .eq => ac == bc,
                .ne => ac != bc,
                .lt => ac < bc,
                .le => ac <= bc,
                .gt => ac > bc,
                .ge => ac >= bc,
            };
        } else if (valueToF64(a)) |af| {
            if (valueToF64(b)) |bf| {
                const anan = std.math.isNan(af);
                const bnan = std.math.isNan(bf);
                result = switch (op) {
                    .eq => !anan and !bnan and af == bf,
                    .ne => anan or bnan or af != bf,
                    .lt => !anan and !bnan and af < bf,
                    .le => !anan and !bnan and af <= bf,
                    .gt => !anan and !bnan and af > bf,
                    .ge => !anan and !bnan and af >= bf,
                };
            }
        } else if (a.tag == .ptr and b.tag == .ptr) {
            if (primitives.getStringSlice(a)) |sa| {
                if (primitives.getStringSlice(b)) |sb| {
                    result = switch (op) {
                        .eq => std.mem.eql(u8, sa, sb),
                        .ne => !std.mem.eql(u8, sa, sb),
                        .lt => std.mem.lessThan(u8, sa, sb),
                        .le => !std.mem.lessThan(u8, sb, sa),
                        .gt => std.mem.lessThan(u8, sb, sa),
                        .ge => !std.mem.lessThan(u8, sa, sb),
                    };
                }
            } else {
                // Non-string PTR types: only equality is defined via deep equality
                result = switch (op) {
                    .eq => primitives.deepEqualWithModules(a, b, modules),
                    .ne => !primitives.deepEqualWithModules(a, b, modules),
                    else => false,
                };
            }
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
const SPREAD: u8 = 0x19;
const RET: u8 = 0x11;
const THROW: u8 = 0x1A;
const TRY: u8 = 0x1B;
const END_TRY: u8 = 0x1C;
const AWAIT: u8 = 0x1D;
const LOAD_GLOBAL: u8 = 0x1E;
const STORE_GLOBAL: u8 = 0x1F;
const CALL_INDIRECT: u8 = 0x20;
const LOAD_FN: u8 = 0x21;
const MAKE_CLOSURE: u8 = 0x22;
const LOAD_IMPORTED_FN: u8 = 0x23;
const CONSTRUCT_IMPORT: u8 = 0x24;
const KIND_IS: u8 = 0x25;

const RECORD_KIND: u8 = 1;
const ADT_KIND: u8 = 2;
const TASK_KIND: u8 = 3;
const STRING_KIND: u8 = 4;
const CLOSURE_KIND: u8 = gc_mod.CLOSURE_KIND;
const FLOAT_KIND: u8 = gc_mod.FLOAT_KIND;
const max_frames = 8192;
/// Operand stack depth limit (implementation-defined; spec 05 §1.3).
pub const operand_stack_slots = 4096;

/// If v is a PTR to a FLOAT heap object, return the f64; else null.
fn valueToF64(v: Value) ?f64 {
    if (v.tag != .ptr) return null;
    const addr = Value.ptrTo(v);
    if (addr == 0) return null;
    const base = @as([*]const u8, @ptrFromInt(addr));
    if (base[0] != FLOAT_KIND) return null;
    return @as(*const f64, @ptrCast(@alignCast(base + gc_mod.FLOAT_HEADER))).*;
}
const max_locals = 128;
const max_handlers = 32;

const ExceptionHandler = struct {
    handler_pc: usize,
    stack_sp: usize,
    frame_depth: usize,
    /// Module whose `code` contains `handler_pc` (the module active when TRY executed). Call frames store the *caller* module, so we must not restore from `call_frames[frame_depth].module` here.
    handler_module: *load_mod.Module,
    /// True when `TRY` ran with `current_locals` pointing at `handler_module.globals` (module init / top-level), not `saved_locals[frame_depth]`.
    locals_are_globals: bool,
};

const CallFrame = struct {
    pc: usize,
    module: *load_mod.Module,
    saved_sp: usize,
    /// When true, RET should restore sp and not push the return value (module init run for side effects only).
    discard_return: bool = false,
};

/// Look up (file, line) for a code offset using debug section (03 §8). Binary search for last entry where code_offset <= target.
fn lookupDebugLine(module: *const load_mod.Module, code_offset: usize) ?struct { file: []const u8, line: u32 } {
    const entries = module.debug_entries;
    if (entries.len == 0) return null;
    var lo: usize = 0;
    var hi: usize = entries.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (entries[mid].code_offset <= code_offset) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    if (lo == 0) return null;
    const entry = entries[lo - 1];
    if (entry.file_index >= module.debug_files.len) return null;
    return .{ .file = module.debug_files[entry.file_index], .line = entry.line };
}

/// Print uncaught exception and stack trace to stderr using debug section for file:line.
fn printUncaughtException(
    exception: Value,
    throw_pc: usize,
    current_module: *const load_mod.Module,
    call_frames: []const CallFrame,
    frame_sp: usize,
    module_ptrs: []const *const load_mod.Module,
) void {
    var buf: [512]u8 = undefined;
    const name = primitives.formatOne(exception, &buf, module_ptrs);
    std.debug.print("Uncaught exception: {s}\n", .{name});
    var i: usize = frame_sp;
    const code_offset = @as(usize, @intCast(throw_pc));
    if (lookupDebugLine(current_module, code_offset)) |loc| {
        std.debug.print("  at {s}:{d}\n", .{ loc.file, loc.line });
    }
    while (i > 0) {
        i -= 1;
        const frame = call_frames[i];
        if (lookupDebugLine(frame.module, frame.pc)) |loc| {
            std.debug.print("  at {s}:{d}\n", .{ loc.file, loc.line });
        }
    }
}

fn pushOperand(stack: *[operand_stack_slots]Value, sp: *usize, val: Value) bool {
    if (sp.* >= operand_stack_slots) return false;
    stack[sp.*] = val;
    sp.* += 1;
    return true;
}

/// Same stack trace shape as uncaught-exception reporting (spec 05 §5).
fn operandStackOverflowReport(
    fault_pc: usize,
    current_module: *const load_mod.Module,
    call_frames: []const CallFrame,
    frame_sp: usize,
) void {
    std.debug.print("Operand stack overflow (limit {d} entries)\n", .{operand_stack_slots});
    var i: usize = frame_sp;
    if (lookupDebugLine(current_module, fault_pc)) |loc| {
        std.debug.print("  at {s}:{d}\n", .{ loc.file, loc.line });
    }
    while (i > 0) {
        i -= 1;
        const frame = call_frames[i];
        if (lookupDebugLine(frame.module, frame.pc)) |loc| {
            std.debug.print("  at {s}:{d}\n", .{ loc.file, loc.line });
        }
    }
}

/// Normalize path: resolve "." and ".." so the same file has a single canonical key for the module cache.
fn normalizePath(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const is_absolute = path.len > 0 and path[0] == '/';
    var list = std.ArrayList([]const u8).initCapacity(allocator, 32) catch return error.OutOfMemory;
    defer list.deinit(allocator);
    var it = std.mem.splitScalar(u8, path, '/');
    while (it.next()) |segment| {
        if (segment.len == 0 or std.mem.eql(u8, segment, ".")) continue;
        if (std.mem.eql(u8, segment, "..")) {
            if (list.items.len > 0) list.shrinkRetainingCapacity(list.items.len - 1);
            continue;
        }
        list.append(allocator, segment) catch return error.OutOfMemory;
    }
    const rest = try std.fs.path.join(allocator, list.items);
    errdefer allocator.free(rest);
    if (is_absolute and list.items.len > 0) {
        const with_root = try std.fmt.allocPrint(allocator, "/{s}", .{rest});
        allocator.free(rest);
        return with_root;
    }
    return rest;
}

/// Resolve import specifier to .kbc path: same directory as entry_path, specifier with .ks replaced by .kbc (07 §9 cache mirror).
fn resolveImportPath(allocator: std.mem.Allocator, specifier: []const u8, entry_path: []const u8) ![]const u8 {
    if (specifier.len > 8 and std.mem.eql(u8, specifier[0..8], "kestrel:")) {
        const mod_name = specifier[8..];
        const deps_path = try std.fmt.allocPrint(allocator, "{s}.deps", .{entry_path});
        defer allocator.free(deps_path);
        const deps_file = std.fs.cwd().openFile(deps_path, .{}) catch {
            return error.StdlibImportNotResolved;
        };
        defer deps_file.close();
        const deps_content = deps_file.readToEndAlloc(allocator, 1024 * 1024) catch {
            return error.StdlibImportNotResolved;
        };
        defer allocator.free(deps_content);
        const needle = try std.fmt.allocPrint(allocator, "/kestrel/{s}.ks", .{mod_name});
        defer allocator.free(needle);
        var lines = std.mem.splitScalar(u8, deps_content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;
            if (std.mem.endsWith(u8, trimmed, needle)) {
                const home = std.posix.getenv("HOME") orelse "/tmp";
                const env_cache = std.posix.getenv("KESTREL_CACHE");
                const cache_root = env_cache orelse try std.fmt.allocPrint(allocator, "{s}/.kestrel/kbc", .{home});
                defer if (env_cache == null) allocator.free(cache_root);
                const base = trimmed[0 .. trimmed.len - 3];
                return std.fmt.allocPrint(allocator, "{s}{s}.kbc", .{ cache_root, base });
            }
        }
        return error.StdlibImportNotResolved;
    }
    const base_len = if (std.mem.endsWith(u8, specifier, ".ks")) specifier.len - 3 else specifier.len;
    const base = specifier[0..base_len];
    if (specifier[0] == '/') {
        const home = std.posix.getenv("HOME") orelse "/tmp";
        const env_cache = std.posix.getenv("KESTREL_CACHE");
        const cache_root = env_cache orelse try std.fmt.allocPrint(allocator, "{s}/.kestrel/kbc", .{home});
        defer if (env_cache == null) allocator.free(cache_root);
        return std.fmt.allocPrint(allocator, "{s}{s}.kbc", .{ cache_root, base });
    }
    const entry_dir = std.fs.path.dirname(entry_path) orelse ".";
    const kbc_name = try std.fmt.allocPrint(allocator, "{s}.kbc", .{base});
    defer allocator.free(kbc_name);
    const raw = try std.fs.path.join(allocator, &[_][]const u8{ entry_dir, kbc_name });
    errdefer allocator.free(raw);
    const result = try normalizePath(allocator, raw);
    allocator.free(raw);
    return result;
}

/// Returns true if execution completed normally, false if terminated by uncaught exception.
/// When `out_top` is non-null and execution completes at the outermost `RET`, writes the top
/// stack slot (or unit if empty) for test harnesses.
pub fn run(allocator: std.mem.Allocator, module: *load_mod.Module, entry_path: []const u8, out_top: ?*Value) bool {
    module.source_path = allocator.dupe(u8, entry_path) catch return false;
    var current_module = module;
    var code = current_module.code;
    var constants = current_module.constants;
    var functions = current_module.functions;
    var shapes = current_module.shapes;
    var stack: [operand_stack_slots]Value = undefined;
    for (&stack) |*v| v.* = Value.unit();
    var sp: usize = 0;
    var locals: [max_locals]Value = undefined;
    for (&locals) |*v| v.* = Value.unit();
    // Init and export-var getters use module.globals; regular functions use saved_locals
    var current_locals: []Value = if (current_module.globals.len > 0) current_module.globals else locals[0..];
    const call_frames = allocator.alloc(CallFrame, max_frames) catch return false;
    defer allocator.free(call_frames);
    for (call_frames) |*f| {
        f.* = .{ .pc = 0, .module = module, .saved_sp = 0, .discard_return = false };
    }
    const SavedLocalsRow = [max_locals]Value;
    const saved_locals = allocator.alloc(SavedLocalsRow, max_frames + 1) catch return false;
    defer allocator.free(saved_locals);
    for (saved_locals) |*frame| {
        for (&frame.*) |*v| v.* = Value.unit();
    }
    var frame_sp: usize = 0;
    var pc: usize = 0;

    var module_ptrs = std.ArrayListUnmanaged(*const load_mod.Module){};
    defer module_ptrs.deinit(allocator);
    module_ptrs.ensureTotalCapacity(allocator, 32) catch return false;
    module.module_index = 0;
    module_ptrs.appendAssumeCapacity(module);
    var dependency_cache = std.ArrayListUnmanaged(load_mod.Module){};
    dependency_cache.ensureTotalCapacity(allocator, 32) catch return false;
    defer {
        for (dependency_cache.items) |*m| load_mod.freeModule(allocator, m);
        dependency_cache.deinit(allocator);
    }
    var path_to_module = std.StringHashMap(*load_mod.Module).init(allocator);
    var path_keys = std.ArrayList([]const u8).initCapacity(allocator, 32) catch return false;
    var path_deps_to_free = std.ArrayList([]const u8).initCapacity(allocator, 512) catch return false;
    defer {
        for (path_keys.items) |k| allocator.free(k);
        path_keys.deinit(allocator);
        for (path_deps_to_free.items) |p| allocator.free(p);
        path_deps_to_free.deinit(allocator);
        path_to_module.deinit();
    }

    // Exception handler stack
    var handlers: [max_handlers]ExceptionHandler = undefined;
    for (&handlers) |*h| h.* = .{ .handler_pc = 0, .stack_sp = 0, .frame_depth = 0, .handler_module = module, .locals_are_globals = false };
    var handler_sp: usize = 0;

    // Pending runtime exception (overflow, divide-by-zero) to throw at next loop iteration
    var pending_exception: ?Value = null;

    // Load kestrel:runtime when listed in entry .deps so VM arithmetic traps use stdlib exception ADTs.
    ensureStdlibRuntimeModule(allocator, entry_path, &module_ptrs, &path_to_module, &dependency_cache, &path_keys);

    // Initialize GC
    var gc = GC.init(allocator);
    defer gc.deinit();

    while (pc < code.len) {
        // Handle pending runtime exception (same semantics as THROW)
        if (pending_exception) |exception| {
            pending_exception = null;
            if (handler_sp == 0) {
                printUncaughtException(exception, pc, current_module, call_frames, frame_sp, module_ptrs.items);
                return false;
            }
            handler_sp -= 1;
            const handler = handlers[handler_sp];
            frame_sp = handler.frame_depth;
            current_module = handler.handler_module;
            code = current_module.code;
            constants = current_module.constants;
            functions = current_module.functions;
            shapes = current_module.shapes;
            current_locals = if (handler.locals_are_globals and current_module.globals.len > 0)
                current_module.globals
            else
                saved_locals[frame_sp][0..];
            pc = handler.handler_pc;
            sp = handler.stack_sp;
            if (!pushOperand(&stack, &sp, exception)) {
                operandStackOverflowReport(pc, current_module, call_frames, frame_sp);
                return false;
            }
            continue;
        }

        // Periodic GC check — mark from stack, all call frames, and all module globals as roots
        if (gc.bytes_allocated >= gc.next_gc) {
            const local_slices = allocator.alloc([]const Value, frame_sp + 1) catch continue;
            defer allocator.free(local_slices);
            for (0..frame_sp + 1) |i| {
                local_slices[i] = saved_locals[i][0..];
            }
            var global_slices_buf: [32][]const Value = undefined;
            var n_global_slices: usize = 0;
            for (module_ptrs.items) |m| {
                if (n_global_slices >= 32) break;
                global_slices_buf[n_global_slices] = m.globals;
                n_global_slices += 1;
            }
            gc.collect(stack[0..sp], local_slices[0 .. frame_sp + 1], global_slices_buf[0..n_global_slices]);
        }

        const instr_pc = pc;
        const op = code[instr_pc];
        pc += 1;
        switch (op) {
            LOAD_CONST => {
                const idx = std.mem.readInt(u32, code[pc..][0..4], .little);
                pc += 4;
                if (idx < constants.len) {
                    if (!pushOperand(&stack, &sp, constants[idx])) {
                        operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                        return false;
                    }
                }
            },
            LOAD_LOCAL => {
                const idx = std.mem.readInt(u32, code[pc..][0..4], .little);
                pc += 4;
                if (idx < current_locals.len) {
                    if (!pushOperand(&stack, &sp, current_locals[idx])) {
                        operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                        return false;
                    }
                }
            },
            LOAD_GLOBAL => {
                const idx = std.mem.readInt(u32, code[pc..][0..4], .little);
                pc += 4;
                if (idx < current_module.globals.len) {
                    if (!pushOperand(&stack, &sp, current_module.globals[idx])) {
                        operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                        return false;
                    }
                }
            },
            STORE_GLOBAL => {
                const idx = std.mem.readInt(u32, code[pc..][0..4], .little);
                pc += 4;
                if (sp > 0 and idx < current_module.globals.len) {
                    sp -= 1;
                    current_module.globals[idx] = stack[sp];
                }
            },
            LOAD_FN => {
                const fn_idx = std.mem.readInt(u32, code[pc..][0..4], .little);
                pc += 4;
                if (!pushOperand(&stack, &sp, Value.fnRef(@intCast(current_module.module_index), fn_idx))) {
                    operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                    return false;
                }
            },
            LOAD_IMPORTED_FN => {
                const instr_start = pc - 1; // start of the LOAD_IMPORTED_FN opcode byte
                const imported_fn_idx = std.mem.readInt(u32, code[pc..][0..4], .little);
                pc += 4;

                if (imported_fn_idx >= current_module.imported_functions.len) {
                    if (!pushOperand(&stack, &sp, Value.unit())) {
                        operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                        return false;
                    }
                    continue;
                }

                const imp_entry = current_module.imported_functions[imported_fn_idx];
                if (imp_entry.import_index >= current_module.import_specifiers.len) {
                    if (!pushOperand(&stack, &sp, Value.unit())) {
                        operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                        return false;
                    }
                    continue;
                }

                const specifier = current_module.import_specifiers[imp_entry.import_index];
                const base_path = current_module.source_path orelse entry_path;
                const dep_path = resolveImportPath(allocator, specifier, base_path) catch {
                    if (!pushOperand(&stack, &sp, Value.unit())) {
                        operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                        return false;
                    }
                    continue;
                };

                path_deps_to_free.ensureTotalCapacity(allocator, path_deps_to_free.items.len + 1) catch {
                    allocator.free(dep_path);
                    if (!pushOperand(&stack, &sp, Value.unit())) {
                        operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                        return false;
                    }
                    continue;
                };
                path_deps_to_free.appendAssumeCapacity(dep_path);

                const already_loaded = path_to_module.get(dep_path) != null;
                var dep_module_ptr: *load_mod.Module = undefined;
                if (path_to_module.get(dep_path)) |ptr| {
                    dep_module_ptr = ptr;
                } else {
                    dependency_cache.ensureTotalCapacity(allocator, dependency_cache.items.len + 1) catch {
                        if (!pushOperand(&stack, &sp, Value.unit())) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    };
                    const loaded = load_mod.load(allocator, dep_path) catch {
                        if (!pushOperand(&stack, &sp, Value.unit())) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    };
                    dependency_cache.appendAssumeCapacity(loaded);
                    const ptr = &dependency_cache.items[dependency_cache.items.len - 1];

                    module_ptrs.ensureTotalCapacity(allocator, module_ptrs.items.len + 1) catch {
                        if (!pushOperand(&stack, &sp, Value.unit())) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    };

                    ptr.module_index = @intCast(module_ptrs.items.len);
                    module_ptrs.appendAssumeCapacity(ptr);
                    ptr.source_path = allocator.dupe(u8, dep_path) catch null;

                    const path_key = allocator.dupe(u8, dep_path) catch {
                        if (!pushOperand(&stack, &sp, Value.unit())) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    };
                    path_keys.append(allocator, path_key) catch {
                        allocator.free(path_key);
                        if (!pushOperand(&stack, &sp, Value.unit())) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    };
                    path_to_module.put(path_key, ptr) catch {
                        if (!pushOperand(&stack, &sp, Value.unit())) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    };
                    dep_module_ptr = ptr;
                }

                // If a dependency is first loaded, run its module initializer before we can create a valid fn_ref.
                if (!already_loaded) {
                    if (frame_sp >= max_frames) {
                        std.debug.print("kestrel: stack overflow (exceeded {d} call frames)\n", .{max_frames});
                        return false;
                    }
                    call_frames[frame_sp] = .{ .pc = instr_start, .module = current_module, .saved_sp = sp, .discard_return = true };
                    for (0..max_locals) |i| {
                        saved_locals[frame_sp][i] = if (i < current_locals.len) current_locals[i] else Value.unit();
                    }
                    frame_sp += 1;
                    current_module = dep_module_ptr;
                    code = current_module.code;
                    constants = current_module.constants;
                    functions = current_module.functions;
                    shapes = current_module.shapes;
                    current_locals = if (dep_module_ptr.globals.len > 0) dep_module_ptr.globals else saved_locals[frame_sp][0..];
                    pc = 0;
                    continue;
                }

                if (imp_entry.function_index >= dep_module_ptr.functions.len) {
                    if (!pushOperand(&stack, &sp, Value.unit())) {
                        operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                        return false;
                    }
                    continue;
                }
                if (!pushOperand(&stack, &sp, Value.fnRef(@intCast(dep_module_ptr.module_index), imp_entry.function_index))) {
                    operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                    return false;
                }
            },
            MAKE_CLOSURE => {
                const fn_idx = std.mem.readInt(u32, code[pc..][0..4], .little);
                pc += 4;
                if (sp == 0) continue;
                sp -= 1;
                const env_val = stack[sp];
                if (env_val.tag != .ptr) continue;
                const env_addr = Value.ptrTo(env_val);
                const env_base = @as([*]const u8, @ptrFromInt(env_addr));
                if (env_base[0] != RECORD_KIND) continue;
                const closure_mem = gc.allocObject(gc_mod.CLOSURE_HEADER) catch continue;
                @memset(closure_mem, 0);
                closure_mem[0] = CLOSURE_KIND;
                closure_mem[1] = 0;
                std.mem.writeInt(u32, closure_mem[4..8], current_module.module_index, .little);
                std.mem.writeInt(u32, closure_mem[8..12], fn_idx, .little);
                std.mem.writeInt(usize, closure_mem[16..24], env_addr, .little);
                const closure_addr = @intFromPtr(closure_mem.ptr);
                if (!pushOperand(&stack, &sp, Value.ptr(closure_addr))) {
                    operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                    return false;
                }
            },
            STORE_LOCAL => {
                const idx = std.mem.readInt(u32, code[pc..][0..4], .little);
                pc += 4;
                if (sp > 0 and idx < current_locals.len) {
                    sp -= 1;
                    current_locals[idx] = stack[sp];
                }
            },
            CALL => {
                const fn_id = std.mem.readInt(u32, code[pc..][0..4], .little);
                const arity = std.mem.readInt(u32, code[pc + 4 ..][0..4], .little);
                pc += 8;

                // Check for primitive functions (0xFFFFFF00 range)
                if (fn_id >= 0xFFFFFF00 and fn_id <= 0xFFFFFF26 and sp >= arity) {
                    if (fn_id == 0xFFFFFF00 and arity >= 1) {
                        const args = stack[sp - arity .. sp];
                        primitives.printN(args, false, module_ptrs.items);
                        sp -= arity;
                        if (!pushOperand(&stack, &sp, Value.unit())) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF01 and arity >= 1) {
                        const args = stack[sp - arity .. sp];
                        primitives.printN(args, true, module_ptrs.items);
                        sp -= arity;
                        if (!pushOperand(&stack, &sp, Value.unit())) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF02 and arity == 1) {
                        const code_val = stack[sp - 1];
                        sp -= 1;
                        const exit_code = Value.intTo(code_val);
                        std.process.exit(@intCast(exit_code));
                    } else if (fn_id == 0xFFFFFF03 and arity == 1) {
                        const val = stack[sp - 1];
                        sp -= 1;
                        var format_buf: [4096]u8 = undefined;
                        const slice = primitives.formatOne(val, &format_buf, module_ptrs.items);
                        const total = 8 + slice.len;
                        const obj = gc.allocObject(total) catch {
                            if (!pushOperand(&stack, &sp, Value.unit())) {
                                operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                                return false;
                            }
                            continue;
                        };
                        @memset(obj, 0);
                        obj[0] = STRING_KIND;
                        std.mem.writeInt(u32, obj[4..8], @as(u32, @intCast(slice.len)), .little);
                        @memcpy(obj[8..][0..slice.len], slice);
                        if (!pushOperand(&stack, &sp, Value.ptr(@intFromPtr(obj.ptr)))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF04 and arity == 2) {
                        const b = stack[sp - 1];
                        const a = stack[sp - 2];
                        sp -= 2;
                        var buf_a: [4096]u8 = undefined;
                        var buf_b: [4096]u8 = undefined;
                        const slice_a = primitives.getStringSlice(a) orelse primitives.formatOne(a, &buf_a, module_ptrs.items);
                        const slice_b = primitives.getStringSlice(b) orelse primitives.formatOne(b, &buf_b, module_ptrs.items);
                        const total_len = slice_a.len + slice_b.len;
                        const obj = gc.allocObject(8 + total_len) catch {
                            if (!pushOperand(&stack, &sp, Value.unit())) {
                                operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                                return false;
                            }
                            continue;
                        };
                        @memset(obj, 0);
                        obj[0] = STRING_KIND;
                        std.mem.writeInt(u32, obj[4..8], @as(u32, @intCast(total_len)), .little);
                        @memcpy(obj[8..][0..slice_a.len], slice_a);
                        @memcpy(obj[8 + slice_a.len ..][0..slice_b.len], slice_b);
                        if (!pushOperand(&stack, &sp, Value.ptr(@intFromPtr(obj.ptr)))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF05 and arity == 1) {
                        const arg = stack[sp - 1];
                        sp -= 1;
                        if (!pushOperand(&stack, &sp, primitives.jsonParse(&gc, arg, current_module.module_index))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF06 and arity == 1) {
                        const arg = stack[sp - 1];
                        sp -= 1;
                        if (!pushOperand(&stack, &sp, primitives.jsonStringify(&gc, arg))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF07 and arity == 1) {
                        const arg = stack[sp - 1];
                        sp -= 1;
                        if (!pushOperand(&stack, &sp, primitives.readFileAsync(&gc, arg))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF08 and arity == 0) {
                        if (!pushOperand(&stack, &sp, primitives.nowMs())) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF09 and arity == 1) {
                        const arg = stack[sp - 1];
                        sp -= 1;
                        if (!pushOperand(&stack, &sp, primitives.stringLength(arg))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF0A and arity == 3) {
                        const end_v = stack[sp - 1];
                        const start_v = stack[sp - 2];
                        const s_v = stack[sp - 3];
                        sp -= 3;
                        if (!pushOperand(&stack, &sp, primitives.stringSlice(&gc, s_v, start_v, end_v))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF0B and arity == 2) {
                        const sub = stack[sp - 1];
                        const s = stack[sp - 2];
                        sp -= 2;
                        if (!pushOperand(&stack, &sp, primitives.stringIndexOf(s, sub))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF0C and arity == 2) {
                        const b = stack[sp - 1];
                        const a = stack[sp - 2];
                        sp -= 2;
                        if (!pushOperand(&stack, &sp, primitives.stringEquals(a, b))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF0D and arity == 1) {
                        const arg = stack[sp - 1];
                        sp -= 1;
                        if (!pushOperand(&stack, &sp, primitives.stringUpper(&gc, arg))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF0E and arity == 2) {
                        const b = stack[sp - 1];
                        const a = stack[sp - 2];
                        sp -= 2;
                        if (!pushOperand(&stack, &sp, primitives.equals(a, b, module_ptrs.items))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF0F and arity == 0) {
                        if (!pushOperand(&stack, &sp, primitives.getProcess(&gc, current_module))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF10 and arity == 1) {
                        const arg = stack[sp - 1];
                        sp -= 1;
                        if (!pushOperand(&stack, &sp, primitives.listDir(&gc, arg))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF11 and arity == 2) {
                        const content = stack[sp - 1];
                        const path = stack[sp - 2];
                        sp -= 2;
                        primitives.writeText(path, content);
                        if (!pushOperand(&stack, &sp, Value.unit())) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF12 and arity == 2) {
                        const args_val = stack[sp - 1];
                        const prog = stack[sp - 2];
                        sp -= 2;
                        if (!pushOperand(&stack, &sp, primitives.runProcess(prog, args_val))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF13 and arity == 0) {
                        if (!pushOperand(&stack, &sp, primitives.getOs(&gc))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF14 and arity == 0) {
                        if (!pushOperand(&stack, &sp, primitives.getArgs(&gc))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF15 and arity == 0) {
                        if (!pushOperand(&stack, &sp, primitives.getCwd(&gc))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF16 and arity == 1) {
                        const arg = stack[sp - 1];
                        sp -= 1;
                        if (!pushOperand(&stack, &sp, primitives.stringTrim(&gc, arg))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF17 and arity == 2) {
                        const idx_v = stack[sp - 1];
                        const s_v = stack[sp - 2];
                        sp -= 2;
                        if (!pushOperand(&stack, &sp, primitives.stringCodePointAt(s_v, idx_v))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF18 and arity == 1) {
                        const c_v = stack[sp - 1];
                        sp -= 1;
                        if (!pushOperand(&stack, &sp, primitives.charCodePoint(c_v))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF19 and arity == 2) {
                        const idx_v = stack[sp - 1];
                        const s_v = stack[sp - 2];
                        sp -= 2;
                        if (!pushOperand(&stack, &sp, primitives.stringCharAt(s_v, idx_v))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF1a and arity == 1) {
                        const c_v = stack[sp - 1];
                        sp -= 1;
                        if (!pushOperand(&stack, &sp, primitives.charToString(&gc, c_v))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF1b and arity == 1) {
                        const arg = stack[sp - 1];
                        sp -= 1;
                        if (!pushOperand(&stack, &sp, primitives.stringLower(&gc, arg))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF1c and arity == 1) {
                        const arg = stack[sp - 1];
                        sp -= 1;
                        if (!pushOperand(&stack, &sp, primitives.intToFloat(&gc, arg))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF1d and arity == 1) {
                        const arg = stack[sp - 1];
                        sp -= 1;
                        if (!pushOperand(&stack, &sp, primitives.floatToInt(arg))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF1e and arity == 1) {
                        const arg = stack[sp - 1];
                        sp -= 1;
                        if (!pushOperand(&stack, &sp, primitives.floatFloor(arg))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF1f and arity == 1) {
                        const arg = stack[sp - 1];
                        sp -= 1;
                        if (!pushOperand(&stack, &sp, primitives.floatCeil(arg))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF20 and arity == 1) {
                        const arg = stack[sp - 1];
                        sp -= 1;
                        if (!pushOperand(&stack, &sp, primitives.floatRound(arg))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF21 and arity == 1) {
                        const arg = stack[sp - 1];
                        sp -= 1;
                        if (!pushOperand(&stack, &sp, primitives.floatSqrt(&gc, arg))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF22 and arity == 1) {
                        const arg = stack[sp - 1];
                        sp -= 1;
                        if (!pushOperand(&stack, &sp, primitives.floatIsNan(arg))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF23 and arity == 1) {
                        const arg = stack[sp - 1];
                        sp -= 1;
                        if (!pushOperand(&stack, &sp, primitives.floatIsInfinite(arg))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF24 and arity == 1) {
                        const arg = stack[sp - 1];
                        sp -= 1;
                        if (!pushOperand(&stack, &sp, primitives.floatAbs(&gc, arg))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF25 and arity == 1) {
                        const arg = stack[sp - 1];
                        sp -= 1;
                        if (!pushOperand(&stack, &sp, primitives.charFromCode(arg))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    } else if (fn_id == 0xFFFFFF26 and arity == 1) {
                        const arg = stack[sp - 1];
                        sp -= 1;
                        if (!pushOperand(&stack, &sp, primitives.taskReturnUnit(&gc, arg))) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    }
                }

                // Imported function call (03 §6.6). On any failure we pop args and push Unit to keep stack consistent.
                if (fn_id >= functions.len) {
                    const k: usize = fn_id - functions.len;
                    if (frame_sp >= max_frames) {
                        std.debug.print("kestrel: stack overflow (exceeded {d} call frames)\n", .{max_frames});
                        return false;
                    }
                    if (k >= current_module.imported_functions.len or sp < arity) {
                        sp -= arity;
                        if (!pushOperand(&stack, &sp, Value.unit())) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    }
                    const imp_entry = current_module.imported_functions[k];
                    if (imp_entry.import_index >= current_module.import_specifiers.len) {
                        sp -= arity;
                        if (!pushOperand(&stack, &sp, Value.unit())) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    }
                    const specifier = current_module.import_specifiers[imp_entry.import_index];
                    const base_path = current_module.source_path orelse entry_path;
                    const dep_path = resolveImportPath(allocator, specifier, base_path) catch {
                        sp -= arity;
                        if (!pushOperand(&stack, &sp, Value.unit())) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    };
                    path_deps_to_free.ensureTotalCapacity(allocator, path_deps_to_free.items.len + 1) catch {
                        allocator.free(dep_path);
                        sp -= arity;
                        if (!pushOperand(&stack, &sp, Value.unit())) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    };
                    path_deps_to_free.appendAssumeCapacity(dep_path);
                    const already_loaded = path_to_module.get(dep_path) != null;
                    const dep_module = blk: {
                        if (path_to_module.get(dep_path)) |ptr| break :blk ptr;
                        dependency_cache.ensureTotalCapacity(allocator, dependency_cache.items.len + 1) catch {
                            sp -= arity;
                            if (!pushOperand(&stack, &sp, Value.unit())) {
                                operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                                return false;
                            }
                            continue;
                        };
                        const loaded = load_mod.load(allocator, dep_path) catch {
                            sp -= arity;
                            if (!pushOperand(&stack, &sp, Value.unit())) {
                                operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                                return false;
                            }
                            continue;
                        };
                        dependency_cache.appendAssumeCapacity(loaded);
                        const ptr = &dependency_cache.items[dependency_cache.items.len - 1];
                        module_ptrs.ensureTotalCapacity(allocator, module_ptrs.items.len + 1) catch {
                            sp -= arity;
                            if (!pushOperand(&stack, &sp, Value.unit())) {
                                operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                                return false;
                            }
                            continue;
                        };
                        ptr.module_index = @intCast(module_ptrs.items.len);
                        module_ptrs.appendAssumeCapacity(ptr);
                        ptr.source_path = allocator.dupe(u8, dep_path) catch null;
                        const path_key = allocator.dupe(u8, dep_path) catch {
                            sp -= arity;
                            if (!pushOperand(&stack, &sp, Value.unit())) {
                                operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                                return false;
                            }
                            continue;
                        };
                        path_keys.append(allocator, path_key) catch {
                            allocator.free(path_key);
                            sp -= arity;
                            if (!pushOperand(&stack, &sp, Value.unit())) {
                                operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                                return false;
                            }
                            continue;
                        };
                        path_to_module.put(path_key, ptr) catch {
                            sp -= arity;
                            if (!pushOperand(&stack, &sp, Value.unit())) {
                                operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                                return false;
                            }
                            continue;
                        };
                        break :blk ptr;
                    };
                    // When a package is first loaded, run its module initializer (top-level code at offset 0) before calling into it.
                    if (!already_loaded) {
                        call_frames[frame_sp] = .{ .pc = pc - 9, .module = current_module, .saved_sp = sp, .discard_return = true };
                        for (0..max_locals) |i| {
                            saved_locals[frame_sp][i] = if (i < current_locals.len) current_locals[i] else Value.unit();
                        }
                        frame_sp += 1;
                        current_module = dep_module;
                        code = current_module.code;
                        constants = current_module.constants;
                        functions = current_module.functions;
                        shapes = current_module.shapes;
                        current_locals = if (dep_module.globals.len > 0) dep_module.globals else saved_locals[frame_sp][0..];
                        pc = 0;
                        continue;
                    }
                    if (imp_entry.function_index >= dep_module.functions.len) {
                        sp -= arity;
                        if (!pushOperand(&stack, &sp, Value.unit())) {
                            operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                            return false;
                        }
                        continue;
                    }
                    const target_entry = dep_module.functions[imp_entry.function_index];
                    call_frames[frame_sp] = .{ .pc = pc, .module = current_module, .saved_sp = sp - arity };
                    for (0..max_locals) |i| {
                        saved_locals[frame_sp][i] = if (i < current_locals.len) current_locals[i] else Value.unit();
                    }
                    frame_sp += 1;
                    current_locals = saved_locals[frame_sp][0..];
                    var i: usize = 0;
                    while (i < arity) : (i += 1) {
                        current_locals[i] = stack[sp - arity + i];
                    }
                    sp -= arity;
                    current_module = dep_module;
                    code = current_module.code;
                    constants = current_module.constants;
                    functions = current_module.functions;
                    shapes = current_module.shapes;
                    pc = target_entry.code_offset;
                    continue;
                }

                // Local function call
                if (frame_sp >= max_frames) {
                    std.debug.print("kestrel: stack overflow (exceeded {d} call frames)\n", .{max_frames});
                    return false;
                }
                const entry = functions[fn_id];
                if (sp < arity) continue;
                call_frames[frame_sp] = .{ .pc = pc, .module = current_module, .saved_sp = sp - arity };
                for (0..max_locals) |i| {
                    saved_locals[frame_sp][i] = if (i < current_locals.len) current_locals[i] else Value.unit();
                }
                frame_sp += 1;
                current_locals = saved_locals[frame_sp][0..];
                var i: usize = 0;
                while (i < arity) : (i += 1) {
                    current_locals[i] = stack[sp - arity + i];
                }
                sp -= arity;
                pc = entry.code_offset;
            },
            CALL_INDIRECT => {
                const arity = std.mem.readInt(u32, code[pc..][0..4], .little);
                pc += 4;

                if (frame_sp >= max_frames) {
                    std.debug.print("kestrel: stack overflow (exceeded {d} call frames)\n", .{max_frames});
                    return false;
                }
                if (sp < arity + 1) continue;
                const fn_val = stack[sp - arity - 1];
                const target_mod_idx: u16 = blk: {
                    if (fn_val.tag == .fn_ref) {
                        break :blk Value.fnRefModule(fn_val);
                    } else if (fn_val.tag == .ptr) {
                        const addr = Value.ptrTo(fn_val);
                        const base = @as([*]const u8, @ptrFromInt(addr));
                        if (base[0] != CLOSURE_KIND) continue;
                        const mod_idx = std.mem.readInt(u32, base[4..8], .little);
                        break :blk @intCast(mod_idx);
                    } else continue;
                };
                const fn_id: u32 = blk: {
                    if (fn_val.tag == .fn_ref) {
                        break :blk Value.fnRefIndex(fn_val);
                    } else {
                        const addr = Value.ptrTo(fn_val);
                        const base = @as([*]const u8, @ptrFromInt(addr));
                        break :blk std.mem.readInt(u32, base[8..12], .little);
                    }
                };
                const target_module: *load_mod.Module = if (target_mod_idx < module_ptrs.items.len) @constCast(module_ptrs.items[target_mod_idx]) else continue;
                if (fn_id >= target_module.functions.len) continue;
                const entry = target_module.functions[fn_id];
                var call_arity = arity;
                if (fn_val.tag == .ptr) {
                    const addr = Value.ptrTo(fn_val);
                    const base = @as([*]const u8, @ptrFromInt(addr));
                    const env_addr = std.mem.readInt(usize, base[16..24], .little);
                    stack[sp - arity - 1] = Value.ptr(env_addr);
                    call_arity = arity + 1;
                }
                call_frames[frame_sp] = .{ .pc = pc, .module = current_module, .saved_sp = sp - arity - 1 };
                for (0..max_locals) |ci| {
                    saved_locals[frame_sp][ci] = if (ci < current_locals.len) current_locals[ci] else Value.unit();
                }
                frame_sp += 1;
                current_locals = saved_locals[frame_sp][0..];
                var i: usize = 0;
                while (i < call_arity) : (i += 1) {
                    current_locals[i] = stack[sp - call_arity + i];
                }
                sp -= arity + 1;
                current_module = target_module;
                code = current_module.code;
                constants = current_module.constants;
                functions = current_module.functions;
                shapes = current_module.shapes;
                pc = entry.code_offset;
            },
            ADD => {
                if (sp >= 2) {
                    const b_val = stack[sp - 1];
                    const a_val = stack[sp - 2];
                    if (valueToF64(a_val)) |af| {
                        if (valueToF64(b_val)) |bf| {
                            const result = gc.allocFloat(af + bf) catch continue;
                            sp -= 1;
                            stack[sp - 1] = result;
                            continue;
                        }
                    }
                    if (a_val.tag == .int and b_val.tag == .int) {
                        const a = Value.intTo(a_val);
                        const b = Value.intTo(b_val);
                        var overflow = false;
                        const sum = @addWithOverflow(a, b);
                        if (sum[1] != 0 or sum[0] < INT61_MIN or sum[0] > INT61_MAX) overflow = true;
                        if (overflow) {
                            if (allocRuntimeException(&gc, current_module, "ArithmeticOverflow", module_ptrs.items)) |exc| {
                                pending_exception = exc;
                            }
                            sp -= 2;
                            continue;
                        }
                        stack[sp - 2] = Value.int(sum[0]);
                        sp -= 1;
                    }
                }
            },
            SUB => {
                if (sp >= 2) {
                    const b_val = stack[sp - 1];
                    const a_val = stack[sp - 2];
                    if (valueToF64(a_val)) |af| {
                        if (valueToF64(b_val)) |bf| {
                            const result = gc.allocFloat(af - bf) catch continue;
                            sp -= 1;
                            stack[sp - 1] = result;
                            continue;
                        }
                    }
                    if (a_val.tag == .int and b_val.tag == .int) {
                        const a = Value.intTo(a_val);
                        const b = Value.intTo(b_val);
                        var overflow = false;
                        const diff = @subWithOverflow(a, b);
                        if (diff[1] != 0 or diff[0] < INT61_MIN or diff[0] > INT61_MAX) overflow = true;
                        if (overflow) {
                            if (allocRuntimeException(&gc, current_module, "ArithmeticOverflow", module_ptrs.items)) |exc| {
                                pending_exception = exc;
                            }
                            sp -= 2;
                            continue;
                        }
                        stack[sp - 2] = Value.int(diff[0]);
                        sp -= 1;
                    }
                }
            },
            MUL => {
                if (sp >= 2) {
                    const b_val = stack[sp - 1];
                    const a_val = stack[sp - 2];
                    if (valueToF64(a_val)) |af| {
                        if (valueToF64(b_val)) |bf| {
                            const result = gc.allocFloat(af * bf) catch continue;
                            sp -= 1;
                            stack[sp - 1] = result;
                            continue;
                        }
                    }
                    if (a_val.tag == .int and b_val.tag == .int) {
                        const a = Value.intTo(a_val);
                        const b = Value.intTo(b_val);
                        var overflow = false;
                        const prod = @mulWithOverflow(a, b);
                        if (prod[1] != 0 or prod[0] < INT61_MIN or prod[0] > INT61_MAX) overflow = true;
                        if (overflow) {
                            if (allocRuntimeException(&gc, current_module, "ArithmeticOverflow", module_ptrs.items)) |exc| {
                                pending_exception = exc;
                            }
                            sp -= 2;
                            continue;
                        }
                        stack[sp - 2] = Value.int(prod[0]);
                        sp -= 1;
                    }
                }
            },
            DIV => {
                if (sp >= 2) {
                    const b_val = stack[sp - 1];
                    const a_val = stack[sp - 2];
                    if (valueToF64(a_val)) |af| {
                        if (valueToF64(b_val)) |bf| {
                            const div_result: f64 = if (bf == 0) std.math.nan(f64) else af / bf;
                            const result = gc.allocFloat(div_result) catch continue;
                            sp -= 1;
                            stack[sp - 1] = result;
                            continue;
                        }
                    }
                    if (a_val.tag == .int and b_val.tag == .int) {
                        const b = Value.intTo(b_val);
                        if (b == 0) {
                            if (allocRuntimeException(&gc, current_module, "DivideByZero", module_ptrs.items)) |exc| {
                                pending_exception = exc;
                            }
                            sp -= 2;
                            continue;
                        }
                        const a = Value.intTo(a_val);
                        const q = @divTrunc(a, b);
                        if (q < INT61_MIN or q > INT61_MAX) {
                            if (allocRuntimeException(&gc, current_module, "ArithmeticOverflow", module_ptrs.items)) |exc| {
                                pending_exception = exc;
                            }
                            sp -= 2;
                            continue;
                        }
                        stack[sp - 2] = Value.int(q);
                        sp -= 1;
                    }
                }
            },
            MOD => {
                if (sp >= 2) {
                    const b_val = stack[sp - 1];
                    const a_val = stack[sp - 2];
                    if (valueToF64(a_val)) |af| {
                        if (valueToF64(b_val)) |bf| {
                            const mod_result: f64 = if (bf == 0) std.math.nan(f64) else af - @trunc(af / bf) * bf;
                            const result = gc.allocFloat(mod_result) catch continue;
                            sp -= 1;
                            stack[sp - 1] = result;
                            continue;
                        }
                    }
                    if (a_val.tag == .int and b_val.tag == .int) {
                        const b = Value.intTo(b_val);
                        if (b == 0) {
                            if (allocRuntimeException(&gc, current_module, "DivideByZero", module_ptrs.items)) |exc| {
                                pending_exception = exc;
                            }
                            sp -= 2;
                            continue;
                        }
                        const a = Value.intTo(a_val);
                        const r = @mod(a, b);
                        if (r < INT61_MIN or r > INT61_MAX) {
                            if (allocRuntimeException(&gc, current_module, "ArithmeticOverflow", module_ptrs.items)) |exc| {
                                pending_exception = exc;
                            }
                            sp -= 2;
                            continue;
                        }
                        stack[sp - 2] = Value.int(r);
                        sp -= 1;
                    }
                }
            },
            POW => {
                if (sp >= 2) {
                    const b_val = stack[sp - 1];
                    const a_val = stack[sp - 2];
                    if (valueToF64(a_val)) |af| {
                        if (valueToF64(b_val)) |bf| {
                            const pow_result = std.math.pow(f64, af, bf);
                            const result = gc.allocFloat(pow_result) catch continue;
                            sp -= 1;
                            stack[sp - 1] = result;
                            continue;
                        }
                    }
                    if (a_val.tag == .int and b_val.tag == .int) {
                        const a = Value.intTo(a_val);
                        const b = Value.intTo(b_val);
                        const pow_result = std.math.powi(i64, a, @intCast(b)) catch {
                            if (allocRuntimeException(&gc, current_module, "ArithmeticOverflow", module_ptrs.items)) |exc| {
                                pending_exception = exc;
                            }
                            sp -= 2;
                            continue;
                        };
                        if (pow_result < INT61_MIN or pow_result > INT61_MAX) {
                            if (allocRuntimeException(&gc, current_module, "ArithmeticOverflow", module_ptrs.items)) |exc| {
                                pending_exception = exc;
                            }
                            sp -= 2;
                            continue;
                        }
                        stack[sp - 2] = Value.int(pow_result);
                        sp -= 1;
                    }
                }
            },
            EQ => binopCmp(&stack, &sp, .eq, module_ptrs.items),
            NE => binopCmp(&stack, &sp, .ne, module_ptrs.items),
            LT => binopCmp(&stack, &sp, .lt, module_ptrs.items),
            LE => binopCmp(&stack, &sp, .le, module_ptrs.items),
            GT => binopCmp(&stack, &sp, .gt, module_ptrs.items),
            GE => binopCmp(&stack, &sp, .ge, module_ptrs.items),
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
                const rec = gc.allocObject(gc_mod.RECORD_HEADER + n * 8) catch continue;
                @memset(rec, 0);
                rec[0] = RECORD_KIND;
                rec[1] = 0; // mark bit
                std.mem.writeInt(u32, rec[4..8], current_module.module_index, .little);
                std.mem.writeInt(u32, rec[8..12], shape_id, .little);
                std.mem.writeInt(u32, rec[12..16], n, .little);
                const fields_ptr = @as([*]Value, @ptrCast(@alignCast(rec.ptr + gc_mod.RECORD_HEADER)));
                var i: usize = 0;
                while (i < n) : (i += 1) {
                    fields_ptr[i] = stack[sp - n + i];
                }
                sp -= n;
                const addr = @intFromPtr(rec.ptr);
                if (!pushOperand(&stack, &sp, Value.ptr(addr))) {
                    operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                    return false;
                }
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
                const kind = base[0];
                const header_size: usize = if (kind == gc_mod.ADT_KIND) gc_mod.ADT_HEADER else gc_mod.RECORD_HEADER;
                const field_offset = header_size + slot * 8;
                const field_ptr = @as(*const Value, @ptrCast(@alignCast(base + field_offset)));
                if (!pushOperand(&stack, &sp, field_ptr.*)) {
                    operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                    return false;
                }
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
                const kind = base[0];
                const header_size: usize = if (kind == gc_mod.ADT_KIND) gc_mod.ADT_HEADER else gc_mod.RECORD_HEADER;
                const field_offset = header_size + slot * 8;
                const field_ptr = @as(*Value, @ptrCast(@alignCast(base + field_offset)));
                field_ptr.* = val;
                if (!pushOperand(&stack, &sp, Value.unit())) {
                    operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                    return false;
                }
            },
            SPREAD => {
                const shape_id = std.mem.readInt(u32, code[pc..][0..4], .little);
                pc += 4;
                if (sp < 1) continue;
                const base_rec_val = stack[sp - 1];
                sp -= 1;
                if (base_rec_val.tag != .ptr) continue;
                const base_addr = Value.ptrTo(base_rec_val);
                const base_ptr = @as([*]const u8, @ptrFromInt(base_addr));
                if (base_ptr[0] != RECORD_KIND) continue;
                const base_field_count = std.mem.readInt(u32, base_ptr[12..16], .little);
                if (shape_id >= shapes.len) continue;
                const extended_count = shapes[shape_id].field_count;
                if (extended_count < base_field_count) continue;
                const n_extra = extended_count - base_field_count;
                if (sp < n_extra) continue;
                const rec = gc.allocObject(gc_mod.RECORD_HEADER + extended_count * 8) catch continue;
                @memset(rec, 0);
                rec[0] = RECORD_KIND;
                rec[1] = 0;
                std.mem.writeInt(u32, rec[4..8], current_module.module_index, .little);
                std.mem.writeInt(u32, rec[8..12], shape_id, .little);
                std.mem.writeInt(u32, rec[12..16], extended_count, .little);
                const new_fields_ptr = @as([*]Value, @ptrCast(@alignCast(rec.ptr + gc_mod.RECORD_HEADER)));
                const base_fields_ptr = @as([*]const Value, @ptrCast(@alignCast(base_ptr + gc_mod.RECORD_HEADER)));
                var i: usize = 0;
                while (i < base_field_count) : (i += 1) {
                    new_fields_ptr[i] = base_fields_ptr[i];
                }
                i = 0;
                while (i < n_extra) : (i += 1) {
                    new_fields_ptr[base_field_count + i] = stack[sp - n_extra + i];
                }
                sp -= n_extra;
                const new_addr = @intFromPtr(rec.ptr);
                if (!pushOperand(&stack, &sp, Value.ptr(new_addr))) {
                    operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                    return false;
                }
            },
            CONSTRUCT => {
                const adt_id = std.mem.readInt(u32, code[pc..][0..4], .little);
                const ctor = std.mem.readInt(u32, code[pc + 4 ..][0..4], .little);
                const arity = std.mem.readInt(u32, code[pc + 8 ..][0..4], .little);
                pc += 12;
                if (sp < arity) continue;
                const adt = gc.allocObject(gc_mod.ADT_HEADER + arity * 8) catch continue;
                @memset(adt, 0);
                adt[0] = ADT_KIND;
                adt[1] = 0; // mark bit
                adt[2] = 1; // layout version 1 (has module_index, adt_id for formatting)
                std.mem.writeInt(u32, adt[4..8], current_module.module_index, .little);
                std.mem.writeInt(u32, adt[8..12], adt_id, .little);
                std.mem.writeInt(u32, adt[12..16], ctor, .little);
                std.mem.writeInt(u32, adt[16..20], arity, .little);
                const fields_ptr = @as([*]Value, @ptrCast(@alignCast(adt.ptr + gc_mod.ADT_HEADER)));
                var i: usize = 0;
                while (i < arity) : (i += 1) {
                    fields_ptr[i] = stack[sp - arity + i];
                }

                sp -= arity;
                const addr = @intFromPtr(adt.ptr);
                if (!pushOperand(&stack, &sp, Value.ptr(addr))) {
                    operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                    return false;
                }
            },
            CONSTRUCT_IMPORT => {
                const construct_import_pc = pc - 1;
                const import_idx = std.mem.readInt(u32, code[pc..][0..4], .little);
                const adt_id = std.mem.readInt(u32, code[pc + 4 ..][0..4], .little);
                const ctor = std.mem.readInt(u32, code[pc + 8 ..][0..4], .little);
                const arity = std.mem.readInt(u32, code[pc + 12 ..][0..4], .little);
                pc += 16;
                if (sp < arity) return false;
                if (import_idx >= current_module.import_specifiers.len) return false;

                const specifier = current_module.import_specifiers[import_idx];
                const base_path = current_module.source_path orelse entry_path;
                const dep_path = resolveImportPath(allocator, specifier, base_path) catch return false;

                path_deps_to_free.ensureTotalCapacity(allocator, path_deps_to_free.items.len + 1) catch {
                    allocator.free(dep_path);
                    return false;
                };
                path_deps_to_free.appendAssumeCapacity(dep_path);

                const already_loaded = path_to_module.get(dep_path) != null;
                var dep_module_ptr: *load_mod.Module = undefined;
                if (path_to_module.get(dep_path)) |ptr| {
                    dep_module_ptr = ptr;
                } else {
                    dependency_cache.ensureTotalCapacity(allocator, dependency_cache.items.len + 1) catch return false;
                    const loaded = load_mod.load(allocator, dep_path) catch return false;
                    dependency_cache.appendAssumeCapacity(loaded);
                    const ptr = &dependency_cache.items[dependency_cache.items.len - 1];

                    module_ptrs.ensureTotalCapacity(allocator, module_ptrs.items.len + 1) catch return false;

                    ptr.module_index = @intCast(module_ptrs.items.len);
                    module_ptrs.appendAssumeCapacity(ptr);
                    ptr.source_path = allocator.dupe(u8, dep_path) catch null;

                    const path_key = allocator.dupe(u8, dep_path) catch return false;
                    path_keys.append(allocator, path_key) catch {
                        allocator.free(path_key);
                        return false;
                    };
                    path_to_module.put(path_key, ptr) catch {
                        allocator.free(path_key);
                        return false;
                    };
                    dep_module_ptr = ptr;
                }

                if (!already_loaded) {
                    if (frame_sp >= max_frames) {
                        std.debug.print("kestrel: stack overflow (exceeded {d} call frames)\n", .{max_frames});
                        return false;
                    }
                    call_frames[frame_sp] = .{ .pc = construct_import_pc, .module = current_module, .saved_sp = sp, .discard_return = true };
                    for (0..max_locals) |i| {
                        saved_locals[frame_sp][i] = if (i < current_locals.len) current_locals[i] else Value.unit();
                    }
                    frame_sp += 1;
                    current_module = dep_module_ptr;
                    code = current_module.code;
                    constants = current_module.constants;
                    functions = current_module.functions;
                    shapes = current_module.shapes;
                    current_locals = if (dep_module_ptr.globals.len > 0) dep_module_ptr.globals else saved_locals[frame_sp][0..];
                    pc = 0;
                    continue;
                }

                const adt = gc.allocObject(gc_mod.ADT_HEADER + arity * 8) catch return false;
                @memset(adt, 0);
                adt[0] = ADT_KIND;
                adt[1] = 0;
                adt[2] = 1;
                std.mem.writeInt(u32, adt[4..8], dep_module_ptr.module_index, .little);
                std.mem.writeInt(u32, adt[8..12], adt_id, .little);
                std.mem.writeInt(u32, adt[12..16], ctor, .little);
                std.mem.writeInt(u32, adt[16..20], arity, .little);
                const fields_ptr = @as([*]Value, @ptrCast(@alignCast(adt.ptr + gc_mod.ADT_HEADER)));
                var i: usize = 0;
                while (i < arity) : (i += 1) {
                    fields_ptr[i] = stack[sp - arity + i];
                }

                sp -= arity;
                const addr = @intFromPtr(adt.ptr);
                if (!pushOperand(&stack, &sp, Value.ptr(addr))) {
                    operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                    return false;
                }
            },
            KIND_IS => {
                const disc = std.mem.readInt(u32, code[pc..][0..4], .little);
                pc += 4;
                if (sp == 0) continue;
                const v = stack[sp - 1];
                sp -= 1;
                const ok: bool = switch (disc) {
                    0 => v.tag == .int,
                    1 => v.tag == .bool,
                    2 => v.tag == .unit,
                    3 => v.tag == .char,
                    4 => blk: {
                        if (v.tag != .ptr) break :blk false;
                        const addr = Value.ptrTo(v);
                        if (addr == 0) break :blk false;
                        const base = @as([*]const u8, @ptrFromInt(addr));
                        break :blk base[0] == gc_mod.STRING_KIND;
                    },
                    5 => blk: {
                        if (v.tag != .ptr) break :blk false;
                        const addr = Value.ptrTo(v);
                        if (addr == 0) break :blk false;
                        const base = @as([*]const u8, @ptrFromInt(addr));
                        break :blk base[0] == gc_mod.FLOAT_KIND;
                    },
                    6 => blk: {
                        if (v.tag != .ptr) break :blk false;
                        const addr = Value.ptrTo(v);
                        if (addr == 0) break :blk false;
                        const base = @as([*]const u8, @ptrFromInt(addr));
                        break :blk base[0] == RECORD_KIND;
                    },
                    else => false,
                };
                if (!pushOperand(&stack, &sp, Value.boolVal(ok))) {
                    operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                    return false;
                }
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

                // Handle boolean matching: True = tag 1, False = tag 0
                if (val.tag == .bool) {
                    const ctor_tag: u32 = if (val.payload != 0) 1 else 0;
                    if (ctor_tag >= count) {
                        pc += count * 4;
                        continue;
                    }
                    const match_start = pc - 5;
                    const offset_pos = pc + ctor_tag * 4;
                    const offset = std.mem.readInt(i32, code[offset_pos..][0..4], .little);
                    pc = @as(usize, @intCast(@as(isize, @intCast(match_start)) + offset));
                    continue;
                }

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
                const ctor_tag = std.mem.readInt(u32, base[12..16], .little);
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
                if (sp == 0) return false;
                const exception = stack[sp - 1];
                sp -= 1;

                // Unwind to nearest exception handler
                if (handler_sp == 0) {
                    printUncaughtException(exception, pc, current_module, call_frames, frame_sp, module_ptrs.items);
                    return false;
                }

                // Pop handler and restore state
                handler_sp -= 1;
                const handler = handlers[handler_sp];

                // Restore frame state to where TRY was executed
                frame_sp = handler.frame_depth;
                current_module = handler.handler_module;
                code = current_module.code;
                constants = current_module.constants;
                functions = current_module.functions;
                shapes = current_module.shapes;
                current_locals = if (handler.locals_are_globals and current_module.globals.len > 0)
                    current_module.globals
                else
                    saved_locals[frame_sp][0..];

                // Restore stack pointer and PC
                pc = handler.handler_pc;
                sp = handler.stack_sp;

                // Push exception value for catch block
                if (!pushOperand(&stack, &sp, exception)) {
                    operandStackOverflowReport(pc, current_module, call_frames, frame_sp);
                    return false;
                }
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
                    .handler_module = current_module,
                    .locals_are_globals = current_module.globals.len > 0 and current_locals.ptr == current_module.globals.ptr,
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
                    if (!pushOperand(&stack, &sp, Value.unit())) {
                        operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                        return false;
                    }
                    continue;
                }

                const addr = Value.ptrTo(task_val);
                const base = @as([*]const u8, @ptrFromInt(addr));
                const kind = base[0];

                if (kind != TASK_KIND) {
                    // Not a task: push unit
                    if (!pushOperand(&stack, &sp, Value.unit())) {
                        operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                        return false;
                    }
                    continue;
                }

                // Task layout: kind(1) + mark(1) + status(1) + pad(1) + unused(4) + result(8)
                // status: 0 = pending, 1 = completed
                const status = base[2];

                if (status == 1) {
                    // Task completed: push result
                    const result_ptr = @as(*const Value, @ptrCast(@alignCast(base + 8)));
                    if (!pushOperand(&stack, &sp, result_ptr.*)) {
                        operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                        return false;
                    }
                } else {
                    // Task pending: for now, just push unit (no actual suspension)
                    // A full implementation would suspend the frame here
                    if (!pushOperand(&stack, &sp, Value.unit())) {
                        operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                        return false;
                    }
                }
            },
            RET => {
                if (frame_sp == 0) {
                    if (out_top) |p| {
                        p.* = if (sp > 0) stack[sp - 1] else Value.unit();
                    }
                    return true;
                }
                const ret_val = if (sp > 0) blk: {
                    sp -= 1;
                    break :blk stack[sp];
                } else Value.unit();
                frame_sp -= 1;
                const frame = call_frames[frame_sp];
                current_module = frame.module;
                code = current_module.code;
                constants = current_module.constants;
                functions = current_module.functions;
                shapes = current_module.shapes;
                current_locals = saved_locals[frame_sp][0..];
                pc = frame.pc;
                sp = frame.saved_sp;
                if (!frame.discard_return) {
                    if (!pushOperand(&stack, &sp, ret_val)) {
                        operandStackOverflowReport(instr_pc, current_module, call_frames, frame_sp);
                        return false;
                    }
                }
            },
            else => return false,
        }
    }
    if (out_top) |p| {
        p.* = if (sp > 0) stack[sp - 1] else Value.unit();
    }
    return true;
}

test "pushOperand rejects one past capacity" {
    var stack: [operand_stack_slots]Value = undefined;
    for (&stack) |*v| v.* = Value.unit();
    var sp: usize = 0;
    for (0..operand_stack_slots) |_| {
        try std.testing.expect(pushOperand(&stack, &sp, Value.int(0)));
    }
    try std.testing.expect(!pushOperand(&stack, &sp, Value.int(0)));
}

test "run stops on operand stack overflow bytecode" {
    const a = std.testing.allocator;
    const n_push = operand_stack_slots + 1;
    const code = try a.alloc(u8, n_push * 5 + 1);
    var off: usize = 0;
    for (0..n_push) |_| {
        code[off] = LOAD_CONST;
        std.mem.writeInt(u32, code[off + 1 ..][0..4], 0, .little);
        off += 5;
    }
    code[off] = RET;

    const constants = try a.alloc(Value, 1);
    constants[0] = Value.int(0);

    const file_data = try a.alloc(u8, 0);
    var m = load_mod.Module{
        .code = code,
        .constants = constants,
        .functions = &[_]load_mod.FnEntry{},
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
    const ok = run(a, &m, "operand_overflow_test.ks", null);
    try std.testing.expect(!ok);
}
