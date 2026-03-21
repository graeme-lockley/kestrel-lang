/**
 * JVM .class file writer. Target version 50 (Java 6) — no StackMapTable.
 */
import {
  JvmOp,
  ACC_PUBLIC,
  ACC_STATIC,
  ACC_PRIVATE,
  ACC_FINAL,
  ACC_SUPER,
  ACC_ABSTRACT,
} from './opcodes.js';

const MAGIC = 0xcafebabe;
const VERSION_MAJOR = 51; // Java 7 — StackMapTable required
const VERSION_MINOR = 0;
const SAME_FRAME_EXTENDED = 247;
const FULL_FRAME = 255;
const VERIFICATION_OBJECT = 7;
const VERIFICATION_TOP = 0;

const CP_UTF8 = 1;
const CP_INTEGER = 3;
const CP_FLOAT = 4;
const CP_LONG = 5;
const CP_DOUBLE = 6;
const CP_CLASS = 7;
const CP_STRING = 8;
const CP_FIELDREF = 9;
const CP_METHODREF = 10;
const CP_INTERFACE_METHODREF = 11;
const CP_NAME_AND_TYPE = 12;

function encodeUtf8(s: string): Uint8Array {
  const buf: number[] = [];
  for (let i = 0; i < s.length; i++) {
    let c = s.charCodeAt(i);
    if (c < 0x80) {
      buf.push(c);
    } else if (c < 0x800) {
      buf.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
    } else if (c >= 0xd800 && c <= 0xdbff && i + 1 < s.length) {
      const c2 = s.charCodeAt(i + 1);
      if (c2 >= 0xdc00 && c2 <= 0xdfff) {
        const u = ((c - 0xd800) << 10) + (c2 - 0xdc00) + 0x10000;
        buf.push(0xf0 | (u >> 18), 0x80 | ((u >> 12) & 0x3f), 0x80 | ((u >> 6) & 0x3f), 0x80 | (u & 0x3f));
        i++;
      } else {
        buf.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
      }
    } else {
      buf.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
    }
  }
  return new Uint8Array(buf);
}

function u8(buf: number[], v: number): void {
  buf.push(v & 0xff);
}
function u16(buf: number[], v: number): void {
  buf.push((v >> 8) & 0xff, v & 0xff);
}
function u32(buf: number[], v: number): void {
  const x = v >>> 0;
  buf.push((x >> 24) & 0xff, (x >> 16) & 0xff, (x >> 8) & 0xff, x & 0xff);
}

/** Frame state at a branch target: which local slots hold Object (rest are top); optional stack depth (default 0). */
export interface StackMapFrameState {
  numLocals: number;
  objectSlots: Set<number>;
  /** Number of stack slots at this target (all emitted as Object when > 0). */
  stackDepth?: number;
}

/** Frame state for "only params are Object" (e.g. at else start after condition). Use when merging with other targets at same offset. */
export function paramOnlyFrame(paramCount: number): StackMapFrameState {
  const objectSlots = new Set<number>();
  for (let k = 0; k < paramCount; k++) objectSlots.add(k);
  return { numLocals: Math.max(paramCount, 1), objectSlots };
}

/** Count parameter slots from a JVM method descriptor (e.g. "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;" -> 2). */
function countMethodParams(descriptor: string): number {
  if (descriptor[0] !== '(') return 0;
  let i = 1;
  let count = 0;
  while (i < descriptor.length && descriptor[i] !== ')') {
    const c = descriptor[i];
    if (c === 'L') {
      const end = descriptor.indexOf(';', i);
      i = end >= 0 ? end + 1 : descriptor.length;
      count++;
    } else if (c === '[') {
      while (descriptor[i] === '[') i++;
      if (descriptor[i] === 'L') {
        const end = descriptor.indexOf(';', i);
        i = end >= 0 ? end + 1 : descriptor.length;
      } else {
        i++;
      }
      count++;
    } else {
      i++;
      count++;
    }
  }
  return count;
}

/** Build StackMapTable: same_frame at 0; at branch targets use full_frame.
 * JVMS 4.7.4: offset = previous_offset + offset_delta + 1 (first explicit frame uses offset_delta as the offset).
 * If frameStateMap is provided, use it to emit Object only for slots in objectSlots and VERIFICATION_TOP for others.
 * When state is missing for an offset, use paramCount so only param slots are Object (conservative for merging). */
function buildStackMapTable(
  branchTargets: number[],
  maxLocals: number,
  objectClassCpIndex: number,
  frameStateMap?: Map<number, StackMapFrameState>,
  paramCount: number = 0
): { count: number; bytes: number[] } {
  const sorted = [...new Set(branchTargets)].sort((a, b) => a - b);
  const uniq: number[] = [];
  for (const o of sorted) {
    if (uniq.length === 0 || uniq[uniq.length - 1] !== o) uniq.push(o);
  }
  const out: number[] = [];
  out.push(0); // same_frame at offset 0 (required first entry)
  let prevOffset = 0;
  let firstFullFrame = true;
  for (let i = 0; i < uniq.length; i++) {
    const offset = uniq[i]!;
    if (offset === 0) continue;
    const delta = offset - prevOffset - 1;
    prevOffset = offset;
    const state = frameStateMap?.get(offset);
    const nLocals = state ? Math.min(state.numLocals, 0xff) : Math.min(maxLocals, 0xff);
    const objectSlots = state?.objectSlots;
    const useParamOnly = !objectSlots && paramCount >= 0;
    out.push(FULL_FRAME);
    out.push((delta >> 8) & 0xff, delta & 0xff);
    out.push((nLocals >> 8) & 0xff, nLocals & 0xff);
    for (let j = 0; j < nLocals; j++) {
      const isObject = objectSlots
        ? objectSlots.has(j)
        : useParamOnly && j < paramCount;
      if (isObject) {
        out.push(VERIFICATION_OBJECT);
        out.push((objectClassCpIndex >> 8) & 0xff, objectClassCpIndex & 0xff);
      } else {
        out.push(VERIFICATION_TOP);
      }
    }
    const nStack = state?.stackDepth ?? 0;
    out.push((nStack >> 8) & 0xff, nStack & 0xff);
    for (let k = 0; k < nStack; k++) {
      out.push(VERIFICATION_OBJECT);
      out.push((objectClassCpIndex >> 8) & 0xff, objectClassCpIndex & 0xff);
    }
  }
  const count = 1 + uniq.filter((o) => o > 0).length;
  return { count, bytes: out };
}

export interface MethodBuilder {
  /** Emit single byte opcode. */
  emit1(op: JvmOp): void;
  /** Emit opcode + 1 byte operand. */
  emit1b(op: JvmOp, b: number): void;
  /** Emit opcode + 2 byte operand (big-endian). */
  emit1s(op: JvmOp, s: number): void;
  /** Emit opcode + 4 byte operand (big-endian). */
  emit1i(op: JvmOp, i: number): void;
  /** Push raw byte (for invokeinterface padding etc.). */
  pushByte(b: number): void;
  /** Push raw 2 bytes big-endian. */
  pushShort(s: number): void;
  /** Current bytecode length. */
  length(): number;
  /** Underlying code array (for patching branch offsets). */
  getCode(): number[];
  /** Add exception table entry: [startPc, endPc) -> handlerPc for catchType (0 = catch all). */
  addException(startPc: number, endPc: number, handlerPc: number, catchType: number): void;
  /** Register a branch target offset for StackMapTable (required on Java 7+). Call for every offset that is the target of a branch, plus 0 for method start. Optionally pass frame state so uninitialized slots are emitted as top. */
  addBranchTarget(offset: number, frameState?: StackMapFrameState): void;
  /** Parameter slot count for current method (for conservative merge at else start). */
  getParamCount(): number;
  /** Set max stack/locals (call before finish). */
  setMaxs(maxStack: number, maxLocals: number): void;
}

export class ClassFileBuilder {
  private className: string;
  private superName: string;
  private accessFlags: number;
  private interfaces: number[] = [];
  private constantPool: number[] = [];
  private poolIndex = 1; // 1-based, 0 unused
  private utf8Cache = new Map<string, number>();
  private classCache = new Map<string, number>();
  private nameTypeCache = new Map<string, number>();
  private fieldRefCache = new Map<string, number>();
  private methodRefCache = new Map<string, number>();
  private ifaceMethodRefCache = new Map<string, number>();
  private stringCache = new Map<string, number>();
  private fields: { access: number; nameIdx: number; descIdx: number; constantValue?: number }[] = [];
  private methods: {
    access: number;
    nameIdx: number;
    descIdx: number;
    paramCount: number;
    code: number[];
    maxStack: number;
    maxLocals: number;
    exceptions: { startPc: number; endPc: number; handlerPc: number; catchType: number }[];
    branchTargets: number[];
    branchTargetFrameState?: Map<number, StackMapFrameState>;
  }[] = [];
  private currentMethod: {
    paramCount: number;
    code: number[];
    maxStack: number;
    maxLocals: number;
    exceptions: { startPc: number; endPc: number; handlerPc: number; catchType: number }[];
    branchTargets: number[];
    branchTargetFrameState?: Map<number, StackMapFrameState>;
  } | null = null;
  private currentMethodNameIdx = 0;
  private currentMethodDescIdx = 0;
  private currentMethodAccess = ACC_PUBLIC | ACC_STATIC;

  constructor(className: string, superName: string = 'java/lang/Object', access: number = ACC_PUBLIC | ACC_SUPER) {
    this.className = className.replace(/\./g, '/');
    this.superName = superName.replace(/\./g, '/');
    this.accessFlags = access;
  }

  addInterface(ifaceName: string): number {
    const idx = this.classRef(ifaceName.replace(/\./g, '/'));
    this.interfaces.push(idx);
    return idx;
  }

  /** Get constant pool index for a Utf8 string. */
  utf8(s: string): number {
    let idx = this.utf8Cache.get(s);
    if (idx != null) return idx;
    idx = this.poolIndex;
    this.constantPool.push(CP_UTF8);
    const enc = encodeUtf8(s);
    this.constantPool.push((enc.length >> 8) & 0xff, enc.length & 0xff);
    for (let i = 0; i < enc.length; i++) this.constantPool.push(enc[i]);
    this.poolIndex++;
    this.utf8Cache.set(s, idx);
    return idx;
  }

  /** Get constant pool index for a Class (internal name). */
  classRef(internalName: string): number {
    let idx = this.classCache.get(internalName);
    if (idx != null) return idx;
    const nameIdx = this.utf8(internalName);
    idx = this.poolIndex;
    this.constantPool.push(CP_CLASS);
    this.constantPool.push((nameIdx >> 8) & 0xff, nameIdx & 0xff);
    this.poolIndex++;
    this.classCache.set(internalName, idx);
    return idx;
  }

  /** Get constant pool index for NameAndType. */
  nameAndType(name: string, descriptor: string): number {
    const key = `${name}\0${descriptor}`;
    let idx = this.nameTypeCache.get(key);
    if (idx != null) return idx;
    const nameIdx = this.utf8(name);
    const descIdx = this.utf8(descriptor);
    idx = this.poolIndex;
    this.constantPool.push(CP_NAME_AND_TYPE);
    this.constantPool.push((nameIdx >> 8) & 0xff, nameIdx & 0xff);
    this.constantPool.push((descIdx >> 8) & 0xff, descIdx & 0xff);
    this.poolIndex++;
    this.nameTypeCache.set(key, idx);
    return idx;
  }

  /** Get constant pool index for Fieldref. */
  fieldref(className: string, name: string, descriptor: string): number {
    const key = `${className}\0${name}\0${descriptor}`;
    let idx = this.fieldRefCache.get(key);
    if (idx != null) return idx;
    const classIdx = this.classRef(className.replace(/\./g, '/'));
    const ntIdx = this.nameAndType(name, descriptor);
    idx = this.poolIndex;
    this.constantPool.push(CP_FIELDREF);
    this.constantPool.push((classIdx >> 8) & 0xff, classIdx & 0xff);
    this.constantPool.push((ntIdx >> 8) & 0xff, ntIdx & 0xff);
    this.poolIndex++;
    this.fieldRefCache.set(key, idx);
    return idx;
  }

  /** Get constant pool index for Methodref. */
  methodref(className: string, name: string, descriptor: string): number {
    const key = `${className}\0${name}\0${descriptor}`;
    let idx = this.methodRefCache.get(key);
    if (idx != null) return idx;
    const classIdx = this.classRef(className.replace(/\./g, '/'));
    const ntIdx = this.nameAndType(name, descriptor);
    idx = this.poolIndex;
    this.constantPool.push(CP_METHODREF);
    this.constantPool.push((classIdx >> 8) & 0xff, classIdx & 0xff);
    this.constantPool.push((ntIdx >> 8) & 0xff, ntIdx & 0xff);
    this.poolIndex++;
    this.methodRefCache.set(key, idx);
    return idx;
  }

  /** Get constant pool index for InterfaceMethodref. */
  interfaceMethodref(className: string, name: string, descriptor: string): number {
    const key = `${className}\0${name}\0${descriptor}`;
    let idx = this.ifaceMethodRefCache.get(key);
    if (idx != null) return idx;
    const classIdx = this.classRef(className.replace(/\./g, '/'));
    const ntIdx = this.nameAndType(name, descriptor);
    idx = this.poolIndex;
    this.constantPool.push(CP_INTERFACE_METHODREF);
    this.constantPool.push((classIdx >> 8) & 0xff, classIdx & 0xff);
    this.constantPool.push((ntIdx >> 8) & 0xff, ntIdx & 0xff);
    this.poolIndex++;
    this.ifaceMethodRefCache.set(key, idx);
    return idx;
  }

  /** Get constant pool index for String (reference to Utf8). */
  string(s: string): number {
    let idx = this.stringCache.get(s);
    if (idx != null) return idx;
    const utf8Idx = this.utf8(s);
    idx = this.poolIndex;
    this.constantPool.push(CP_STRING);
    this.constantPool.push((utf8Idx >> 8) & 0xff, utf8Idx & 0xff);
    this.poolIndex++;
    this.stringCache.set(s, idx);
    return idx;
  }

  /** Get constant pool index for int (for LDC). */
  constantInt(v: number): number {
    const idx = this.poolIndex;
    this.constantPool.push(CP_INTEGER);
    const x = v >>> 0;
    this.constantPool.push((x >> 24) & 0xff, (x >> 16) & 0xff, (x >> 8) & 0xff, x & 0xff);
    this.poolIndex++;
    return idx;
  }

  /** Get constant pool index for long (takes 2 slots). */
  constantLong(v: bigint): number {
    const idx = this.poolIndex;
    this.constantPool.push(CP_LONG);
    const lo = Number(v & 0xffffffffn) >>> 0;
    const hi = Number((v >> 32n) & 0xffffffffn) >>> 0;
    this.constantPool.push((hi >> 24) & 0xff, (hi >> 16) & 0xff, (hi >> 8) & 0xff, hi & 0xff);
    this.constantPool.push((lo >> 24) & 0xff, (lo >> 16) & 0xff, (lo >> 8) & 0xff, lo & 0xff);
    this.poolIndex += 2;
    return idx;
  }

  /** Get constant pool index for float. */
  constantFloat(v: number): number {
    const idx = this.poolIndex;
    this.constantPool.push(CP_FLOAT);
    const buf = new ArrayBuffer(4);
    new DataView(buf).setFloat32(0, v, false);
    const bytes = new Uint8Array(buf);
    for (let i = 0; i < 4; i++) this.constantPool.push(bytes[i]);
    this.poolIndex++;
    return idx;
  }

  /** Get constant pool index for double (takes 2 slots). */
  constantDouble(v: number): number {
    const idx = this.poolIndex;
    this.constantPool.push(CP_DOUBLE);
    const buf = new ArrayBuffer(8);
    new DataView(buf).setFloat64(0, v, false);
    const bytes = new Uint8Array(buf);
    for (let i = 0; i < 8; i++) this.constantPool.push(bytes[i]);
    this.poolIndex += 2;
    return idx;
  }

  addField(name: string, descriptor: string, access: number = ACC_PRIVATE | ACC_STATIC, constantValue?: number): void {
    this.fields.push({
      access,
      nameIdx: this.utf8(name),
      descIdx: this.utf8(descriptor),
      constantValue,
    });
  }

  addMethod(
    name: string,
    descriptor: string,
    access: number = ACC_PUBLIC | ACC_STATIC
  ): MethodBuilder {
    if (this.currentMethod) {
      this.methods.push({
        access: this.currentMethodAccess,
        nameIdx: this.currentMethodNameIdx,
        descIdx: this.currentMethodDescIdx,
        paramCount: this.currentMethod.paramCount,
        code: this.currentMethod.code,
        maxStack: this.currentMethod.maxStack,
        maxLocals: this.currentMethod.maxLocals,
        exceptions: this.currentMethod.exceptions,
        branchTargets: this.currentMethod.branchTargets,
        branchTargetFrameState: this.currentMethod.branchTargetFrameState,
      });
    }
    const code: number[] = [];
    const exceptions: { startPc: number; endPc: number; handlerPc: number; catchType: number }[] = [];
    const branchTargets: number[] = [0]; // offset 0 = method start (required for first frame)
    const branchTargetFrameState = new Map<number, StackMapFrameState>();
    const paramCount = countMethodParams(descriptor);
    this.currentMethod = { paramCount, code, maxStack: 1, maxLocals: 0, exceptions, branchTargets, branchTargetFrameState };
    this.currentMethodNameIdx = this.utf8(name);
    this.currentMethodDescIdx = this.utf8(descriptor);
    this.currentMethodAccess = access;

    const self = this;
    const mb: MethodBuilder = {
      emit1(op: JvmOp) {
        code.push(op);
      },
      emit1b(op: JvmOp, b: number) {
        code.push(op, b & 0xff);
      },
      emit1s(op: JvmOp, s: number) {
        code.push(op, (s >> 8) & 0xff, s & 0xff);
      },
      emit1i(op: JvmOp, i: number) {
        code.push(op, (i >> 24) & 0xff, (i >> 16) & 0xff, (i >> 8) & 0xff, i & 0xff);
      },
      pushByte(b: number) {
        code.push(b & 0xff);
      },
      pushShort(s: number) {
        code.push((s >> 8) & 0xff, s & 0xff);
      },
      length() {
        return code.length;
      },
      getCode() {
        return code;
      },
      addException(startPc: number, endPc: number, handlerPc: number, catchType: number) {
        exceptions.push({ startPc, endPc, handlerPc, catchType });
      },
      addBranchTarget(offset: number, frameState?: StackMapFrameState) {
        if (!branchTargets.includes(offset)) branchTargets.push(offset);
        if (frameState) {
          const existing = branchTargetFrameState.get(offset);
          if (existing) {
            // Merge: only declare Object where all paths have Object (intersect objectSlots).
            const mergedSlots = new Set<number>();
            for (const s of existing.objectSlots) {
              if (frameState.objectSlots.has(s)) mergedSlots.add(s);
            }
            const stackDepth = frameState.stackDepth ?? existing.stackDepth;
            branchTargetFrameState.set(offset, {
              numLocals: Math.max(existing.numLocals, frameState.numLocals),
              objectSlots: mergedSlots,
              ...(stackDepth !== undefined && { stackDepth }),
            });
          } else {
            branchTargetFrameState.set(offset, frameState);
          }
        }
      },
      getParamCount() {
        return paramCount;
      },
      setMaxs(maxStack: number, maxLocals: number) {
        self.currentMethod!.maxStack = maxStack;
        self.currentMethod!.maxLocals = maxLocals;
      },
    };
    return mb;
  }

  /** Must be called after the last method is built to flush it. */
  flushLastMethod(): void {
    if (!this.currentMethod) return;
    this.methods.push({
      access: this.currentMethodAccess,
      nameIdx: this.currentMethodNameIdx,
      descIdx: this.currentMethodDescIdx,
      paramCount: this.currentMethod.paramCount,
      code: this.currentMethod.code,
      maxStack: this.currentMethod.maxStack,
      maxLocals: this.currentMethod.maxLocals,
      exceptions: this.currentMethod.exceptions,
      branchTargets: this.currentMethod.branchTargets,
      branchTargetFrameState: this.currentMethod.branchTargetFrameState,
    });
    this.currentMethod = null;
  }

  toBytes(): Uint8Array {
    this.flushLastMethod();
    this.utf8('Code'); // ensure "Code" is in constant pool before we serialize
    this.utf8('StackMapTable');
    // Ensure all refs used in the class file are in the pool before we write it
    const thisClassIdx = this.classRef(this.className);
    const superClassIdx = this.classRef(this.superName);
    const codeAttrNameIdx = this.utf8('Code');
    const stackMapTableNameIdx = this.utf8('StackMapTable');
    const objectClassIdx = this.classRef('java/lang/Object');
    const constantValueAttrIdx = this.utf8('ConstantValue');

    const out: number[] = [];
    // Header
    u32(out, MAGIC);
    u16(out, VERSION_MINOR);
    u16(out, VERSION_MAJOR);
    // Constant pool
    u16(out, this.poolIndex);
    out.push(...this.constantPool);
    // Class header
    u16(out, this.accessFlags);
    u16(out, thisClassIdx);
    u16(out, superClassIdx);
    u16(out, this.interfaces.length);
    for (const i of this.interfaces) u16(out, i);
    // Fields
    u16(out, this.fields.length);
    for (const f of this.fields) {
      u16(out, f.access);
      u16(out, f.nameIdx);
      u16(out, f.descIdx);
      const attrCount = f.constantValue != null ? 1 : 0;
      u16(out, attrCount);
      if (f.constantValue != null) {
        u16(out, constantValueAttrIdx);
        u32(out, 2);
        u16(out, f.constantValue);
      }
    }
    // Methods
    u16(out, this.methods.length);
    for (const m of this.methods) {
      u16(out, m.access);
      u16(out, m.nameIdx);
      u16(out, m.descIdx);
      u16(out, 1); // one attribute: Code
      u16(out, codeAttrNameIdx);
      const codeLen = m.code.length;
      const excLen = m.exceptions.length;
      const stackMap = buildStackMapTable(m.branchTargets, m.maxLocals, objectClassIdx, m.branchTargetFrameState, m.paramCount);
      const stackMapAttrLen = 2 + stackMap.bytes.length;
      const attrLen = 8 + codeLen + 2 + excLen * 8 + 2 + (4 + 2 + stackMapAttrLen);
      u32(out, attrLen);
      u16(out, m.maxStack);
      u16(out, m.maxLocals);
      u32(out, codeLen);
      out.push(...m.code);
      u16(out, excLen);
      for (const e of m.exceptions) {
        u16(out, e.startPc);
        u16(out, e.endPc);
        u16(out, e.handlerPc);
        u16(out, e.catchType);
      }
      u16(out, 1); // one sub-attribute: StackMapTable
      u16(out, stackMapTableNameIdx);
      u32(out, stackMapAttrLen);
      u16(out, stackMap.count);
      out.push(...stackMap.bytes);
    }
    // Class attributes
    u16(out, 0);
    return new Uint8Array(out);
  }

  /** Return internal class name (e.g. "pkg/MyClass"). */
  getClassName(): string {
    return this.className;
  }
}
