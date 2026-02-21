/**
 * Instruction encoding (spec 04 §4). Little-endian; offsets relative to instruction start.
 */
export const enum Op {
  LOAD_CONST = 0x01,
  LOAD_LOCAL = 0x02,
  STORE_LOCAL = 0x03,
  ADD = 0x04,
  SUB = 0x05,
  MUL = 0x06,
  DIV = 0x07,
  MOD = 0x08,
  POW = 0x09,
  EQ = 0x0a,
  NE = 0x0b,
  LT = 0x0c,
  LE = 0x0d,
  GT = 0x0e,
  GE = 0x0f,
  CALL = 0x10,
  RET = 0x11,
  JUMP = 0x12,
  JUMP_IF_FALSE = 0x13,
  CONSTRUCT = 0x14,
  MATCH = 0x15,
  ALLOC_RECORD = 0x16,
  GET_FIELD = 0x17,
  SET_FIELD = 0x18,
  SPREAD = 0x19,
  THROW = 0x1a,
  TRY = 0x1b,
  END_TRY = 0x1c,
  AWAIT = 0x1d,
  LOAD_GLOBAL = 0x1e,
}

const code: number[] = [];

function u8(v: number): void {
  code.push(v & 0xff);
}

function u32(v: number): void {
  const x = v >>> 0;
  code.push(x & 0xff, (x >> 8) & 0xff, (x >> 16) & 0xff, (x >> 24) & 0xff);
}

function i32(v: number): void {
  const x = v | 0;
  code.push(x & 0xff, (x >> 8) & 0xff, (x >> 16) & 0xff, (x >> 24) & 0xff);
}

/** Start a new code buffer (e.g. for module or function). */
export function codeStart(): void {
  code.length = 0;
}

/** Append LOAD_CONST idx. */
export function emitLoadConst(idx: number): void {
  u8(Op.LOAD_CONST);
  u32(idx);
}

/** Append LOAD_LOCAL idx. */
export function emitLoadLocal(idx: number): void {
  u8(Op.LOAD_LOCAL);
  u32(idx);
}

/** Append STORE_LOCAL idx. */
export function emitStoreLocal(idx: number): void {
  u8(Op.STORE_LOCAL);
  u32(idx);
}

/** Append LOAD_GLOBAL idx (load from module globals; used by export var getters). */
export function emitLoadGlobal(idx: number): void {
  u8(Op.LOAD_GLOBAL);
  u32(idx);
}

/** Append RET. */
export function emitRet(): void {
  u8(Op.RET);
}

/** Append ADD, SUB, MUL, etc. */
export function emitAdd(): void { u8(Op.ADD); }
export function emitSub(): void { u8(Op.SUB); }
export function emitMul(): void { u8(Op.MUL); }
export function emitDiv(): void { u8(Op.DIV); }
export function emitMod(): void { u8(Op.MOD); }
export function emitPow(): void { u8(Op.POW); }
export function emitEq(): void { u8(Op.EQ); }
export function emitNe(): void { u8(Op.NE); }
export function emitLt(): void { u8(Op.LT); }
export function emitLe(): void { u8(Op.LE); }
export function emitGt(): void { u8(Op.GT); }
export function emitGe(): void { u8(Op.GE); }

/** Append JUMP offset (relative to start of this JUMP). */
export function emitJump(offset: number): void {
  u8(Op.JUMP);
  i32(offset);
}

/** Append JUMP_IF_FALSE offset. */
export function emitJumpIfFalse(offset: number): void {
  u8(Op.JUMP_IF_FALSE);
  i32(offset);
}

/** Append CALL fn_id, arity. */
export function emitCall(fnId: number, arity: number): void {
  u8(Op.CALL);
  u32(fnId);
  u32(arity);
}

/** Append CONSTRUCT adt_id, ctor, arity. */
export function emitConstruct(adtId: number, ctor: number, arity: number): void {
  u8(Op.CONSTRUCT);
  u32(adtId);
  u32(ctor);
  u32(arity);
}

/** Append MATCH with jump table (offsets relative to MATCH opcode). */
export function emitMatch(offsets: number[]): void {
  u8(Op.MATCH);
  u32(offsets.length);
  for (const o of offsets) i32(o);
}

/** Append ALLOC_RECORD shape_id. */
export function emitAllocRecord(shapeId: number): void {
  u8(Op.ALLOC_RECORD);
  u32(shapeId);
}

/** Append GET_FIELD slot. */
export function emitGetField(slot: number): void {
  u8(Op.GET_FIELD);
  u32(slot);
}

/** Append SET_FIELD slot. */
export function emitSetField(slot: number): void {
  u8(Op.SET_FIELD);
  u32(slot);
}

/** Append SPREAD shape_id. */
export function emitSpread(shapeId: number): void {
  u8(Op.SPREAD);
  u32(shapeId);
}

/** Append THROW, END_TRY, AWAIT. */
export function emitThrow(): void { u8(Op.THROW); }
export function emitEndTry(): void { u8(Op.END_TRY); }
export function emitAwait(): void { u8(Op.AWAIT); }

/** Append TRY handler_offset. */
export function emitTry(handlerOffset: number): void {
  u8(Op.TRY);
  i32(handlerOffset);
}

/** Return current code length (for computing jump offsets). */
export function codeOffset(): number {
  return code.length;
}

/** Patch i32 at byte offset (for forward jumps). */
export function patchI32(offset: number, value: number): void {
  const x = value | 0;
  code[offset] = x & 0xff;
  code[offset + 1] = (x >> 8) & 0xff;
  code[offset + 2] = (x >> 16) & 0xff;
  code[offset + 3] = (x >> 24) & 0xff;
}

/** Copy emitted bytes. */
export function codeSlice(): Uint8Array {
  return new Uint8Array(code);
}
