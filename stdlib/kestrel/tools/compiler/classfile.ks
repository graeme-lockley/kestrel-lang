//! JVM .class file writer — port of compiler/src/jvm-codegen/classfile.ts.
//!
//! Manages the constant pool, field/method tables, attributes (Code, StackMapTable),
//! and serialises the complete class structure to a ByteArray.
//!
//! Usage:
//! ```kestrel
//!   val cf = newClassFile("my/Pkg/MyClass", "java/lang/Object", Acc.public_ | Acc.super_)
//!   val mb = cfAddMethod(cf, "myMethod", "(Ljava/lang/Object;)Ljava/lang/Object;", Acc.public_ | Acc.static_)
//!   mbEmit1(mb, Op.JvmOp.aload0)
//!   mbEmit1(mb, Op.JvmOp.areturn)
//!   mbSetMaxs(mb, 1, 1)
//!   val bytes = cfToBytes(cf)   // ByteArray containing the .class file
//! ```
import * as Arr from "kestrel:data/array"
import * as BA from "kestrel:data/bytearray"
import * as Dict from "kestrel:data/dict"
import * as Lst from "kestrel:data/list"
import * as Opt from "kestrel:data/option"
import * as Str from "kestrel:data/string"

// ---------------------------------------------------------------------------
// KRuntime helpers for float bit conversion
// ---------------------------------------------------------------------------

extern fun doubleToRawLongBits(d: Float): Int =
  jvm("kestrel.runtime.KRuntime#doubleToRawLongBits(java.lang.Object)")

extern fun floatToRawIntBits(f: Float): Int =
  jvm("kestrel.runtime.KRuntime#floatToRawIntBits(java.lang.Object)")

// ---------------------------------------------------------------------------
// Bitwise operations (not natively supported as language operators on Int)
// ---------------------------------------------------------------------------

extern fun bAnd(a: Int, b: Int): Int =
  jvm("kestrel.runtime.KRuntime#bitwiseAnd(java.lang.Object,java.lang.Object)")

extern fun bOr(a: Int, b: Int): Int =
  jvm("kestrel.runtime.KRuntime#bitwiseOr(java.lang.Object,java.lang.Object)")

extern fun bXor(a: Int, b: Int): Int =
  jvm("kestrel.runtime.KRuntime#bitwiseXor(java.lang.Object,java.lang.Object)")

extern fun bNot(a: Int): Int =
  jvm("kestrel.runtime.KRuntime#bitwiseNot(java.lang.Object)")

extern fun bShr(a: Int, n: Int): Int =
  jvm("kestrel.runtime.KRuntime#shiftRight(java.lang.Object,java.lang.Object)")

extern fun bUshr(a: Int, n: Int): Int =
  jvm("kestrel.runtime.KRuntime#unsignedShiftRight(java.lang.Object,java.lang.Object)")

extern fun bShl(a: Int, n: Int): Int =
  jvm("kestrel.runtime.KRuntime#shiftLeft(java.lang.Object,java.lang.Object)")

// ---------------------------------------------------------------------------
// JVM classfile constants
// ---------------------------------------------------------------------------

val cfMagic       = 0xCAFEBABE  // -889275714 as signed 32-bit, fine as Kestrel Int (64-bit)
val cfVersionMajor = 51         // Java 7 — StackMapTable required
val cfVersionMinor = 0

val cpUtf8           = 1
val cpInteger        = 3
val cpFloat          = 4
val cpLong           = 5
val cpDouble         = 6
val cpClass          = 7
val cpString         = 8
val cpFieldref       = 9
val cpMethodref      = 10
val cpIfaceMethodref = 11
val cpNameAndType    = 12

val sameFrameExtended  = 247
val fullFrame          = 255
val verificationObject = 7
val verificationTop    = 0

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Frame state at a branch target: which local slots hold Object (rest are top);
/// optional stack depth (default 0).
export type StackMapFrameState = {
  numLocals: Int,
  objectSlots: List<Int>,
  stackDepth: Int,
  stackItemCpIdx: Int   // 0 means "use objectClassIdx"
}

/// Exception table row.
type ExcEntry = { startPc: Int, endPc: Int, handlerPc: Int, catchType: Int }

/// Field entry.
type FieldEntry = { access: Int, nameIdx: Int, descIdx: Int, constantValue: Int }  // constantValue 0 = absent

/// Per-method mutable accumulation state.
type MethodState = {
  paramCount: Int,
  code: mut Array<Int>,
  exceptions: mut Array<ExcEntry>,
  branchTargets: mut Array<Int>,
  branchTargetFrameStates: mut Dict<Int, StackMapFrameState>,
  maxStack: mut Int,
  maxLocals: mut Int,
  nameIdx: Int,
  descIdx: Int,
  access: Int
}

/// Sealed data stored in ClassFileBuilder (passed by reference, mutable).
type ClassFileState = {
  className: String,
  superName: String,
  accessFlags: Int,
  interfaces: mut Array<Int>,
  constantPool: mut Array<Int>,
  poolIndex: mut Int,
  utf8Cache: mut Dict<String, Int>,
  classCache: mut Dict<String, Int>,
  nameTypeCache: mut Dict<String, Int>,
  fieldRefCache: mut Dict<String, Int>,
  methodRefCache: mut Dict<String, Int>,
  ifaceMethodRefCache: mut Dict<String, Int>,
  stringCache: mut Dict<String, Int>,
  fields: mut Array<FieldEntry>,
  methods: mut Array<MethodState>,
  currentMethod: mut Option<MethodState>
}

/// Builder for a JVM .class file.
export type ClassFileBuilder = ClassFileState

/// Builder for a single JVM method. Borrows the ClassFileState.
export type MethodBuilder = (ClassFileState, MethodState)

// ---------------------------------------------------------------------------
// StackMapFrameState helpers
// ---------------------------------------------------------------------------

/// Create a frame state where only parameter slots hold Object references.
export fun paramOnlyFrame(paramCount: Int): StackMapFrameState = {
  val slots = slotList(0, paramCount, [])
  { numLocals = paramCount, objectSlots = slots, stackDepth = 0, stackItemCpIdx = 0 }
}

fun slotList(i: Int, count: Int, acc: List<Int>): List<Int> =
  if (i >= count) Lst.reverse(acc) else slotList(i + 1, count, i :: acc)

// ---------------------------------------------------------------------------
// ClassFileBuilder constructor
// ---------------------------------------------------------------------------

/// Create a new class file builder.
export fun newClassFile(className: String, superName: String, accessFlags: Int): ClassFileBuilder =
  {
    className = Str.replace(className, ".", "/"),
    superName = Str.replace(superName, ".", "/"),
    accessFlags = accessFlags,
    mut interfaces = Arr.new(),
    mut constantPool = Arr.new(),
    mut poolIndex = 1,
    mut utf8Cache = Dict.emptyStringDict(),
    mut classCache = Dict.emptyStringDict(),
    mut nameTypeCache = Dict.emptyStringDict(),
    mut fieldRefCache = Dict.emptyStringDict(),
    mut methodRefCache = Dict.emptyStringDict(),
    mut ifaceMethodRefCache = Dict.emptyStringDict(),
    mut stringCache = Dict.emptyStringDict(),
    mut fields = Arr.new(),
    mut methods = Arr.new(),
    mut currentMethod = None
  }

// ---------------------------------------------------------------------------
// Modified UTF-8 encoding
// ---------------------------------------------------------------------------

/// Encode a String as JVM modified UTF-8 bytes (returned as List<Int> of 0–255).
fun encodeUtf8Bytes(s: String): List<Int> =
  encodeUtf8Loop(s, 0, Str.length(s), [])

fun encodeUtf8Loop(s: String, i: Int, len: Int, acc: List<Int>): List<Int> =
  if (i >= len) Lst.reverse(acc)
  else {
    val c = Str.codePointAt(s, i)
    val bytes =
      if (c == 0)
        0xC0 :: 0x80 :: acc
      else if (c <= 0x7F)
        c :: acc
      else if (c <= 0x7FF)
        bOr(0xC0, bShr(c, 6)) :: bOr(0x80, bAnd(c, 0x3F)) :: acc
      else
        bOr(0xE0, bShr(c, 12)) :: bOr(0x80, bAnd(bShr(c, 6), 0x3F)) :: bOr(0x80, bAnd(c, 0x3F)) :: acc
    encodeUtf8Loop(s, i + 1, len, bytes)
  }

// ---------------------------------------------------------------------------
// Byte-buffer helpers (write into Array<Int>)
// ---------------------------------------------------------------------------

fun bufU8(buf: Array<Int>, v: Int): Unit  = Arr.push(buf, bAnd(v, 0xFF))
fun bufU16(buf: Array<Int>, v: Int): Unit = { Arr.push(buf, bAnd(bShr(v, 8), 0xFF)); Arr.push(buf, bAnd(v, 0xFF)) }
fun bufU32(buf: Array<Int>, v: Int): Unit = {
  Arr.push(buf, bAnd(bShr(v, 24), 0xFF));
  Arr.push(buf, bAnd(bShr(v, 16), 0xFF));
  Arr.push(buf, bAnd(bShr(v, 8), 0xFF));
  Arr.push(buf, bAnd(v, 0xFF))
}

fun bufAppendList(buf: Array<Int>, bytes: List<Int>): Unit =
  match (bytes) {
    [] => ()
    b :: rest => { Arr.push(buf, b); bufAppendList(buf, rest) }
  }

fun bufAppendArr(dst: Array<Int>, src: Array<Int>): Unit =
  bufAppendArrLoop(dst, src, 0, Arr.length(src))

fun bufAppendArrLoop(dst: Array<Int>, src: Array<Int>, i: Int, len: Int): Unit =
  if (i >= len) ()
  else { Arr.push(dst, Arr.get(src, i)); bufAppendArrLoop(dst, src, i + 1, len) }

// ---------------------------------------------------------------------------
// Constant pool helpers
// ---------------------------------------------------------------------------

/// Return (or allocate) the constant pool index for a UTF-8 string.
export fun cfUtf8(cf: ClassFileBuilder, s: String): Int = {
  val cached = Dict.get(cf.utf8Cache, s)
  match (cached) {
    Some(idx) => idx
    None => {
      val idx = cf.poolIndex
      val encoded = encodeUtf8Bytes(s)
      val encLen = Lst.length(encoded)
      bufU8(cf.constantPool, cpUtf8);
      bufU16(cf.constantPool, encLen);
      bufAppendList(cf.constantPool, encoded);
      cf.poolIndex := cf.poolIndex + 1;
      cf.utf8Cache := Dict.insert(cf.utf8Cache, s, idx);
      idx
    }
  }
}

/// Return (or allocate) the constant pool index for a Class entry.
export fun cfClassRef(cf: ClassFileBuilder, internalName: String): Int = {
  val name = Str.replace(internalName, ".", "/")
  val cached = Dict.get(cf.classCache, name)
  match (cached) {
    Some(idx) => idx
    None => {
      val nameIdx = cfUtf8(cf, name)
      val idx = cf.poolIndex
      bufU8(cf.constantPool, cpClass);
      bufU16(cf.constantPool, nameIdx);
      cf.poolIndex := cf.poolIndex + 1;
      cf.classCache := Dict.insert(cf.classCache, name, idx);
      idx
    }
  }
}

/// Return (or allocate) the constant pool index for a NameAndType entry.
export fun cfNameAndType(cf: ClassFileBuilder, name: String, descriptor: String): Int = {
  val key = "${name}|${descriptor}"
  val cached = Dict.get(cf.nameTypeCache, key)
  match (cached) {
    Some(idx) => idx
    None => {
      val nameIdx = cfUtf8(cf, name)
      val descIdx = cfUtf8(cf, descriptor)
      val idx = cf.poolIndex
      bufU8(cf.constantPool, cpNameAndType);
      bufU16(cf.constantPool, nameIdx);
      bufU16(cf.constantPool, descIdx);
      cf.poolIndex := cf.poolIndex + 1;
      cf.nameTypeCache := Dict.insert(cf.nameTypeCache, key, idx);
      idx
    }
  }
}

fun cfRef(cf: ClassFileBuilder, cache: Dict<String, Int>, tag: Int, className: String, name: String, descriptor: String): (Dict<String, Int>, Int) = {
  val key = "${className}|${name}|${descriptor}"
  val cached = Dict.get(cache, key)
  match (cached) {
    Some(idx) => (cache, idx)
    None => {
      val classIdx = cfClassRef(cf, className)
      val ntIdx = cfNameAndType(cf, name, descriptor)
      val idx = cf.poolIndex
      bufU8(cf.constantPool, tag);
      bufU16(cf.constantPool, classIdx);
      bufU16(cf.constantPool, ntIdx);
      cf.poolIndex := cf.poolIndex + 1;
      (Dict.insert(cache, key, idx), idx)
    }
  }
}

/// Return (or allocate) the constant pool index for a Fieldref.
export fun cfFieldref(cf: ClassFileBuilder, className: String, name: String, descriptor: String): Int = {
  val result = cfRef(cf, cf.fieldRefCache, cpFieldref, className, name, descriptor)
  cf.fieldRefCache := result.0;
  result.1
}

/// Return (or allocate) the constant pool index for a Methodref.
export fun cfMethodref(cf: ClassFileBuilder, className: String, name: String, descriptor: String): Int = {
  val result = cfRef(cf, cf.methodRefCache, cpMethodref, className, name, descriptor)
  cf.methodRefCache := result.0;
  result.1
}

/// Return (or allocate) the constant pool index for an InterfaceMethodref.
export fun cfIfaceMethodref(cf: ClassFileBuilder, className: String, name: String, descriptor: String): Int = {
  val result = cfRef(cf, cf.ifaceMethodRefCache, cpIfaceMethodref, className, name, descriptor)
  cf.ifaceMethodRefCache := result.0;
  result.1
}

/// Return (or allocate) the constant pool index for a String constant.
export fun cfString(cf: ClassFileBuilder, s: String): Int = {
  val cached = Dict.get(cf.stringCache, s)
  match (cached) {
    Some(idx) => idx
    None => {
      val utf8Idx = cfUtf8(cf, s)
      val idx = cf.poolIndex
      bufU8(cf.constantPool, cpString);
      bufU16(cf.constantPool, utf8Idx);
      cf.poolIndex := cf.poolIndex + 1;
      cf.stringCache := Dict.insert(cf.stringCache, s, idx);
      idx
    }
  }
}

/// Allocate a constant pool index for an integer constant (no dedup—each call adds).
export fun cfConstantInt(cf: ClassFileBuilder, v: Int): Int = {
  val idx = cf.poolIndex
  bufU8(cf.constantPool, cpInteger);
  bufU32(cf.constantPool, v);
  cf.poolIndex := cf.poolIndex + 1;
  idx
}

/// Allocate a constant pool index for a long constant (occupies 2 slots).
export fun cfConstantLong(cf: ClassFileBuilder, v: Int): Int = {
  val idx = cf.poolIndex
  val hi = bAnd(bShr(v, 32), 0xFFFFFFFF)
  val lo = bAnd(v, 0xFFFFFFFF)
  bufU8(cf.constantPool, cpLong);
  bufU32(cf.constantPool, hi);
  bufU32(cf.constantPool, lo);
  cf.poolIndex := cf.poolIndex + 2;
  idx
}

/// Allocate a constant pool index for a float constant (4-byte IEEE 754).
export fun cfConstantFloat(cf: ClassFileBuilder, v: Float): Int = {
  val bits = floatToRawIntBits(v)
  val idx = cf.poolIndex
  bufU8(cf.constantPool, cpFloat);
  bufU32(cf.constantPool, bits);
  cf.poolIndex := cf.poolIndex + 1;
  idx
}

/// Allocate a constant pool index for a double constant (8-byte IEEE 754, occupies 2 slots).
export fun cfConstantDouble(cf: ClassFileBuilder, v: Float): Int = {
  val bits = doubleToRawLongBits(v)
  val hi = bAnd(bShr(bits, 32), 0xFFFFFFFF)
  val lo = bAnd(bits, 0xFFFFFFFF)
  val idx = cf.poolIndex
  bufU8(cf.constantPool, cpDouble);
  bufU32(cf.constantPool, hi);
  bufU32(cf.constantPool, lo);
  cf.poolIndex := cf.poolIndex + 2;
  idx
}

// ---------------------------------------------------------------------------
// Field and interface helpers
// ---------------------------------------------------------------------------

/// Add a static field declaration to the class.
export fun cfAddField(cf: ClassFileBuilder, name: String, descriptor: String, access: Int): Unit = {
  val nameIdx = cfUtf8(cf, name)
  val descIdx = cfUtf8(cf, descriptor)
  Arr.push(cf.fields, { access = access, nameIdx = nameIdx, descIdx = descIdx, constantValue = 0 })
}

/// Add an interface to the class's implements list.
export fun cfAddInterface(cf: ClassFileBuilder, ifaceName: String): Unit = {
  val idx = cfClassRef(cf, Str.replace(ifaceName, ".", "/"))
  Arr.push(cf.interfaces, idx)
}

/// Return the internal class name (e.g. "pkg/MyClass").
export fun cfGetClassName(cf: ClassFileBuilder): String = cf.className

// ---------------------------------------------------------------------------
// Count parameter slots from a JVM method descriptor
// ---------------------------------------------------------------------------

fun countMethodParams(descriptor: String): Int =
  if (Str.length(descriptor) == 0 | Str.slice(descriptor, 0, 1) != "(") 0
  else countParamsLoop(descriptor, 1, 0)

fun countParamsLoop(desc: String, i: Int, count: Int): Int = {
  val len = Str.length(desc)
  if (i >= len | Str.slice(desc, i, i + 1) == ")") count
  else {
    val c = Str.slice(desc, i, i + 1)
    if (c == "L") {
      val endIdx = Str.indexOfFrom(desc, ";", i)
      val next = if (endIdx < 0) len else endIdx + 1
      countParamsLoop(desc, next, count + 1)
    } else if (c == "[") {
      countParamsLoop(desc, i + 1, count)
    } else
      countParamsLoop(desc, i + 1, count + 1)
  }
}

// ---------------------------------------------------------------------------
// Method management
// ---------------------------------------------------------------------------

fun newMethodState(nameIdx: Int, descIdx: Int, access: Int, paramCount: Int): MethodState = {
  paramCount = paramCount,
  mut code = Arr.new(),
  mut exceptions = Arr.new(),
  mut branchTargets = Arr.fromList([0]),
  mut branchTargetFrameStates = Dict.emptyIntDict(),
  mut maxStack = 1,
  mut maxLocals = 0,
  nameIdx = nameIdx,
  descIdx = descIdx,
  access = access
}

/// Flush the current method (if any) into the methods list. Called automatically by cfAddMethod.
export fun cfFlushLastMethod(cf: ClassFileBuilder): Unit =
  match (cf.currentMethod) {
    None => ()
    Some(ms) => {
      Arr.push(cf.methods, ms);
      cf.currentMethod := None
    }
  }

/// Start a new method, returning a MethodBuilder that accumulates bytecode.
/// Automatically flushes the previous method first.
export fun cfAddMethod(cf: ClassFileBuilder, name: String, descriptor: String, access: Int): MethodBuilder = {
  cfFlushLastMethod(cf);
  val nameIdx = cfUtf8(cf, name)
  val descIdx = cfUtf8(cf, descriptor)
  val paramCount = countMethodParams(descriptor)
  val ms = newMethodState(nameIdx, descIdx, access, paramCount)
  cf.currentMethod := Some(ms);
  (cf, ms)
}

// ---------------------------------------------------------------------------
// MethodBuilder API
// ---------------------------------------------------------------------------

/// Emit a single-byte opcode.
export fun mbEmit1(mb: MethodBuilder, op: Int): Unit = Arr.push(mb.1.code, op)

/// Emit opcode + 1 byte operand.
export fun mbEmit1b(mb: MethodBuilder, op: Int, b: Int): Unit = {
  Arr.push(mb.1.code, op);
  Arr.push(mb.1.code, bAnd(b, 0xFF))
}

/// Emit opcode + 2-byte big-endian operand.
export fun mbEmit1s(mb: MethodBuilder, op: Int, s: Int): Unit = {
  Arr.push(mb.1.code, op);
  Arr.push(mb.1.code, bAnd(bShr(s, 8), 0xFF));
  Arr.push(mb.1.code, bAnd(s, 0xFF))
}

/// Emit opcode + 4-byte big-endian operand.
export fun mbEmit1i(mb: MethodBuilder, op: Int, i: Int): Unit = {
  Arr.push(mb.1.code, op);
  Arr.push(mb.1.code, bAnd(bShr(i, 24), 0xFF));
  Arr.push(mb.1.code, bAnd(bShr(i, 16), 0xFF));
  Arr.push(mb.1.code, bAnd(bShr(i, 8), 0xFF));
  Arr.push(mb.1.code, bAnd(i, 0xFF))
}

/// Push a raw byte (for invokeinterface nargs/0 bytes etc.).
export fun mbPushByte(mb: MethodBuilder, b: Int): Unit = Arr.push(mb.1.code, bAnd(b, 0xFF))

/// Push a raw 2-byte big-endian value.
export fun mbPushShort(mb: MethodBuilder, s: Int): Unit = {
  Arr.push(mb.1.code, bAnd(bShr(s, 8), 0xFF));
  Arr.push(mb.1.code, bAnd(s, 0xFF))
}

/// Return the current bytecode length (used to compute branch offsets).
export fun mbLength(mb: MethodBuilder): Int = Arr.length(mb.1.code)

/// Expose the mutable code buffer for patching branch operands.
export fun mbGetCode(mb: MethodBuilder): Array<Int> = mb.1.code

/// Add an exception table entry: [startPc, endPc) → handlerPc for catchType (0 = catch-all).
export fun mbAddException(mb: MethodBuilder, startPc: Int, endPc: Int, handlerPc: Int, catchType: Int): Unit =
  Arr.push(mb.1.exceptions, { startPc = startPc, endPc = endPc, handlerPc = handlerPc, catchType = catchType })

/// Register a branch target offset for StackMapTable generation.
/// Call for every offset that is the destination of a branch instruction, and for handler PCs.
export fun mbAddBranchTarget(mb: MethodBuilder, offset: Int, frameState: Option<StackMapFrameState>): Unit = {
  if (!arrContains(mb.1.branchTargets, offset)) Arr.push(mb.1.branchTargets, offset) else ();
  match (frameState) {
    None => ()
    Some(fs) => {
      val existing = Dict.get(mb.1.branchTargetFrameStates, offset)
      val merged =
        match (existing) {
          Some(ex) => mergeFrameState(ex, fs)
          None => fs
        }
      mb.1.branchTargetFrameStates := Dict.insert(mb.1.branchTargetFrameStates, offset, merged)
    }
  }
}

fun arrContains(arr: Array<Int>, v: Int): Bool =
  arrContainsLoop(arr, v, 0, Arr.length(arr))

fun arrContainsLoop(arr: Array<Int>, v: Int, i: Int, len: Int): Bool =
  if (i >= len) False
  else if (Arr.get(arr, i) == v) True
  else arrContainsLoop(arr, v, i + 1, len)

fun mergeFrameState(ex: StackMapFrameState, fs: StackMapFrameState): StackMapFrameState =
  // Conservative and verifier-stable: latest observed state wins.
  fs

/// Return the parameter slot count for this method (used for conservative frame merges).
export fun mbGetParamCount(mb: MethodBuilder): Int = mb.1.paramCount

/// Set the maximum stack depth and local variable count. Must be called before cfToBytes.
export fun mbSetMaxs(mb: MethodBuilder, maxStack: Int, maxLocals: Int): Unit = {
  mb.1.maxStack := maxStack;
  mb.1.maxLocals := maxLocals
}

// ---------------------------------------------------------------------------
// StackMapTable generation
// ---------------------------------------------------------------------------

fun sortBranchTargets(arr: Array<Int>): List<Int> =
  Lst.filter(
    Lst.sort(Arr.toList(arr)),
    (x: Int) => x >= 0
  )

fun intListPair(a: Int, b: List<Int>): (Int, List<Int>) = (a, b)

fun buildStackMapTable(
  branchTargets: Array<Int>,
  maxLocals: Int,
  objectClassCpIdx: Int,
  frameStates: Dict<Int, StackMapFrameState>,
  paramCount: Int
): (Int, List<Int>) = {
  val sorted = sortBranchTargets(branchTargets)
  val uniq = dedup(sorted, -1, [])
  val bytes = 0 :: buildFrames(uniq, 0, maxLocals, objectClassCpIdx, frameStates, paramCount, [])
  // count: 1 (same_frame at 0) + number of offsets > 0
  intListPair(1 + Lst.length(Lst.filter(uniq, (o: Int) => o > 0)), Lst.reverse(bytes))
}

fun dedup(xs: List<Int>, prev: Int, acc: List<Int>): List<Int> =
  match (xs) {
    [] => Lst.reverse(acc)
    h :: rest =>
      if (h == prev) dedup(rest, prev, acc)
      else dedup(rest, h, h :: acc)
  }

fun buildFrames(
  offsets: List<Int>,
  prevOffset: Int,
  maxLocals: Int,
  objectClassCpIdx: Int,
  frameStates: Dict<Int, StackMapFrameState>,
  paramCount: Int,
  acc: List<Int>
): List<Int> =
  match (offsets) {
    [] => acc
    offset :: rest =>
      if (offset == 0)
        buildFrames(rest, prevOffset, maxLocals, objectClassCpIdx, frameStates, paramCount, acc)
      else {
        val delta = offset - prevOffset - 1
        val state = Dict.get(frameStates, offset)
        val frame = buildFullFrame(delta, maxLocals, objectClassCpIdx, paramCount, state)
        buildFrames(rest, offset, maxLocals, objectClassCpIdx, frameStates, paramCount, appendAll(frame, acc))
      }
  }

fun appendAll(xs: List<Int>, acc: List<Int>): List<Int> =
  match (xs) {
    [] => acc
    h :: rest => appendAll(rest, h :: acc)
  }

fun buildFullFrame(
  delta: Int,
  maxLocals: Int,
  objectClassCpIdx: Int,
  paramCount: Int,
  stateOpt: Option<StackMapFrameState>
): List<Int> = {
  val nLocals =
    match (stateOpt) {
      Some(s) => if (s.numLocals < 0xFF) s.numLocals else 0xFF
      None => if (maxLocals < 0xFF) maxLocals else 0xFF
    }
  val objectSlots =
    match (stateOpt) {
      Some(s) => s.objectSlots
      None => slotList(0, paramCount, [])
    }
  val nStack =
    match (stateOpt) {
      Some(s) => s.stackDepth
      None => 0
    }
  val stackCpIdx =
    match (stateOpt) {
      Some(s) => s.stackItemCpIdx
      None => 0
    }
  val header = [fullFrame, bAnd(bShr(delta, 8), 0xFF), bAnd(delta, 0xFF), bAnd(bShr(nLocals, 8), 0xFF), bAnd(nLocals, 0xFF)]
  val localBytes = buildLocalBytes(0, nLocals, objectSlots, objectClassCpIdx, [])
  val stackHeader = [bAnd(bShr(nStack, 8), 0xFF), bAnd(nStack, 0xFF)]
  val stackBytes = buildStackBytes(nStack, stackCpIdx, objectClassCpIdx, [])
  Lst.append(header, Lst.append(Lst.reverse(localBytes), Lst.append(stackHeader, Lst.reverse(stackBytes))))
}

fun buildLocalBytes(j: Int, nLocals: Int, objectSlots: List<Int>, objCpIdx: Int, acc: List<Int>): List<Int> =
  if (j >= nLocals) acc
  else if (Lst.member(objectSlots, j))
    buildLocalBytes(j + 1, nLocals, objectSlots, objCpIdx, bAnd(objCpIdx, 0xFF) :: bAnd(bShr(objCpIdx, 8), 0xFF) :: verificationObject :: acc)
  else
    buildLocalBytes(j + 1, nLocals, objectSlots, objCpIdx, verificationTop :: acc)

fun buildStackBytes(nStack: Int, stackCpIdx: Int, objCpIdx: Int, acc: List<Int>): List<Int> =
  if (nStack == 0) acc
  else if (nStack == 1 & stackCpIdx != 0)
    bAnd(stackCpIdx, 0xFF) :: bAnd(bShr(stackCpIdx, 8), 0xFF) :: verificationObject :: acc
  else
    buildObjectStackBytes(nStack, objCpIdx, acc)

fun buildObjectStackBytes(n: Int, objCpIdx: Int, acc: List<Int>): List<Int> =
  if (n == 0) acc
  else buildObjectStackBytes(n - 1, objCpIdx, bAnd(objCpIdx, 0xFF) :: bAnd(bShr(objCpIdx, 8), 0xFF) :: verificationObject :: acc)

// ---------------------------------------------------------------------------
// Serialization helpers
// ---------------------------------------------------------------------------

fun serializeExceptions(exceptions: Array<ExcEntry>, out: Array<Int>): Unit = {
  val n = Arr.length(exceptions)
  bufU16(out, n);
  serializeExcLoop(exceptions, out, 0, n)
}

fun serializeExcLoop(exceptions: Array<ExcEntry>, out: Array<Int>, i: Int, n: Int): Unit =
  if (i >= n) ()
  else {
    val e = Arr.get(exceptions, i)
    bufU16(out, e.startPc);
    bufU16(out, e.endPc);
    bufU16(out, e.handlerPc);
    bufU16(out, e.catchType);
    serializeExcLoop(exceptions, out, i + 1, n)
  }

fun serializeMethod(ms: MethodState, codeAttrNameIdx: Int, stackMapTableNameIdx: Int, objectClassCpIdx: Int, out: Array<Int>): Unit = {
  bufU16(out, ms.access);
  bufU16(out, ms.nameIdx);
  bufU16(out, ms.descIdx);
  bufU16(out, 1);  // one attribute: Code
  bufU16(out, codeAttrNameIdx);
  val codeLen = Arr.length(ms.code)
  val excCount = Arr.length(ms.exceptions)
  val stackMap = buildStackMapTable(ms.branchTargets, ms.maxLocals, objectClassCpIdx, ms.branchTargetFrameStates, ms.paramCount)
  val stackMapCount = stackMap.0
  val stackMapBytes = stackMap.1
  val stackMapBytesLen = Lst.length(stackMapBytes)
  // stackMapAttrLen = 2 (count u16) + stackMapBytesLen
  val stackMapAttrLen = 2 + stackMapBytesLen
  // attrLen = 2 (maxStack) + 2 (maxLocals) + 4 (codeLen) + codeLen + 2 (excCount) + excCount*8 + 2 (subAttrCount) + 2 (attrNameIdx) + 4 (attrLen) + stackMapAttrLen
  val attrLen = 8 + codeLen + 2 + excCount * 8 + 2 + 4 + 2 + stackMapAttrLen
  bufU32(out, attrLen);
  bufU16(out, ms.maxStack);
  bufU16(out, ms.maxLocals);
  bufU32(out, codeLen);
  bufAppendArr(out, ms.code);
  serializeExceptions(ms.exceptions, out);
  bufU16(out, 1);  // one sub-attribute: StackMapTable
  bufU16(out, stackMapTableNameIdx);
  bufU32(out, stackMapAttrLen);
  bufU16(out, stackMapCount);
  bufAppendList(out, stackMapBytes)
}

fun serializeMethodLoop(methods: Array<MethodState>, codeAttrNameIdx: Int, stackMapTableNameIdx: Int, objectClassCpIdx: Int, out: Array<Int>, i: Int, n: Int): Unit =
  if (i >= n) ()
  else {
    serializeMethod(Arr.get(methods, i), codeAttrNameIdx, stackMapTableNameIdx, objectClassCpIdx, out);
    serializeMethodLoop(methods, codeAttrNameIdx, stackMapTableNameIdx, objectClassCpIdx, out, i + 1, n)
  }

fun serializeFieldLoop(fields: Array<FieldEntry>, out: Array<Int>, i: Int, n: Int): Unit =
  if (i >= n) ()
  else {
    val f = Arr.get(fields, i)
    bufU16(out, f.access);
    bufU16(out, f.nameIdx);
    bufU16(out, f.descIdx);
    bufU16(out, 0);  // no attributes (ignoring ConstantValue for now)
    serializeFieldLoop(fields, out, i + 1, n)
  }

fun serializeInterfaceLoop(interfaces: Array<Int>, out: Array<Int>, i: Int, n: Int): Unit =
  if (i >= n) ()
  else { bufU16(out, Arr.get(interfaces, i)); serializeInterfaceLoop(interfaces, out, i + 1, n) }

// ---------------------------------------------------------------------------
// cfToBytes: serialize the complete class file
// ---------------------------------------------------------------------------

/// Serialize the class file to a ByteArray.
/// Must be called after all methods and fields have been added.
export fun cfToBytes(cf: ClassFileBuilder): ByteArray = {
  cfFlushLastMethod(cf);
  // Ensure well-known strings are in the pool
  val codeAttrNameIdx = cfUtf8(cf, "Code")
  val stackMapTableNameIdx = cfUtf8(cf, "StackMapTable")
  val thisClassIdx = cfClassRef(cf, cf.className)
  val superClassIdx = cfClassRef(cf, cf.superName)
  val objectClassCpIdx = cfClassRef(cf, "java/lang/Object")
  val out = Arr.new()
  // Header
  bufU32(out, cfMagic);
  bufU16(out, cfVersionMinor);
  bufU16(out, cfVersionMajor);
  // Constant pool (poolIndex is count of entries + 1 due to 1-based indexing)
  bufU16(out, cf.poolIndex);
  bufAppendArr(out, cf.constantPool);
  // Class info
  bufU16(out, cf.accessFlags);
  bufU16(out, thisClassIdx);
  bufU16(out, superClassIdx);
  // Interfaces
  bufU16(out, Arr.length(cf.interfaces));
  serializeInterfaceLoop(cf.interfaces, out, 0, Arr.length(cf.interfaces));
  // Fields
  bufU16(out, Arr.length(cf.fields));
  serializeFieldLoop(cf.fields, out, 0, Arr.length(cf.fields));
  // Methods
  bufU16(out, Arr.length(cf.methods));
  serializeMethodLoop(cf.methods, codeAttrNameIdx, stackMapTableNameIdx, objectClassCpIdx, out, 0, Arr.length(cf.methods));
  // Class attributes (none)
  bufU16(out, 0);
  BA.fromList(Arr.toList(out))
}
