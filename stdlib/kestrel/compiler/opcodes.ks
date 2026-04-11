import * as Lst from "kestrel:data/list"
import * as Opt from "kestrel:data/option"
import * as Ty from "kestrel:compiler/types"

// JVM bytecode opcode constants (subset needed for Kestrel codegen).
// Mirrors compiler/src/jvm-codegen/opcodes.ts.
// Access as Op.JvmOp.nop, Op.JvmOp.invokevirtual, etc.

export val JvmOp = {
  nop              = 0,
  aconstNull       = 1,
  iconstM1         = 2,
  iconst0          = 3,
  iconst1          = 4,
  iconst2          = 5,
  iconst3          = 6,
  iconst4          = 7,
  iconst5          = 8,
  lconst0          = 9,
  lconst1          = 10,
  dconst0          = 14,
  dconst1          = 15,
  bipush           = 16,
  sipush           = 17,
  ldc              = 18,
  ldcW             = 19,
  ldc2W            = 20,
  iload            = 21,
  lload            = 22,
  fload            = 23,
  dload            = 24,
  aload            = 25,
  iload0           = 26,
  iload1           = 27,
  iload2           = 28,
  iload3           = 29,
  lload0           = 30,
  lload1           = 31,
  lload2           = 32,
  lload3           = 33,
  aload0           = 42,
  aload1           = 43,
  aload2           = 44,
  aload3           = 45,
  iaload           = 46,
  laload           = 47,
  aaload           = 50,
  aastore          = 83,
  istore           = 54,
  lstore           = 55,
  fstore           = 56,
  dstore           = 57,
  astore           = 58,
  istore0          = 59,
  istore1          = 60,
  istore2          = 61,
  istore3          = 62,
  lstore0          = 63,
  lstore1          = 64,
  lstore2          = 65,
  lstore3          = 66,
  astore0          = 75,
  astore1          = 76,
  astore2          = 77,
  astore3          = 78,
  pop              = 87,
  pop2             = 88,
  dup              = 89,
  dupX1            = 90,
  dupX2            = 91,
  dup2             = 92,
  dup2X1           = 93,
  dup2X2           = 94,
  swap             = 95,
  iadd             = 96,
  ladd             = 97,
  fadd             = 98,
  dadd             = 99,
  isub             = 100,
  lsub             = 101,
  fsub             = 102,
  dsub             = 103,
  imul             = 104,
  lmul             = 105,
  fmul             = 106,
  dmul             = 107,
  idiv             = 108,
  ldiv             = 109,
  fdiv             = 110,
  ddiv             = 111,
  irem             = 112,
  lrem             = 113,
  frem             = 114,
  drem             = 115,
  ineg             = 116,
  lneg             = 117,
  fneg             = 118,
  dneg             = 119,
  ishl             = 120,
  lshl             = 121,
  ishr             = 122,
  lshr             = 123,
  iushr            = 124,
  lushr            = 125,
  iand             = 126,
  land             = 127,
  ior              = 128,
  lor              = 129,
  ixor             = 130,
  lxor             = 131,
  i2l              = 133,
  i2f              = 134,
  i2d              = 135,
  l2i              = 136,
  l2f              = 137,
  l2d              = 138,
  f2i              = 139,
  f2l              = 140,
  f2d              = 141,
  d2i              = 142,
  d2l              = 143,
  d2f              = 144,
  i2b              = 145,
  i2c              = 146,
  i2s              = 147,
  lcmp             = 148,
  fcmpl            = 149,
  fcmpg            = 150,
  dcmpl            = 151,
  dcmpg            = 152,
  ifeq             = 153,
  ifne             = 154,
  iflt             = 155,
  ifge             = 156,
  ifgt             = 157,
  ifle             = 158,
  ifIcmpeq         = 159,
  ifIcmpne         = 160,
  ifIcmplt         = 161,
  ifIcmpge         = 162,
  ifIcmpgt         = 163,
  ifIcmple         = 164,
  ifAcmpeq         = 165,
  ifAcmpne         = 166,
  goto_            = 167,
  gotoW            = 200,
  ireturn          = 172,
  lreturn          = 173,
  freturn          = 174,
  dreturn          = 175,
  areturn          = 176,
  return_          = 177,
  getstatic        = 178,
  putstatic        = 179,
  getfield         = 180,
  putfield         = 181,
  invokevirtual    = 182,
  invokespecial    = 183,
  invokestatic     = 184,
  invokeinterface  = 185,
  new_             = 187,
  newarray         = 188,
  anewarray        = 189,
  arraylength      = 190,
  athrow           = 191,
  checkcast        = 192,
  instanceof_      = 193,
  monitorenter     = 194,
  monitorexit      = 195,
  wide             = 196,
  multianewarray   = 197,
  ifnull           = 198,
  ifnonnull        = 199
}

// JVM class/member access flags.
// Access as Op.Acc.public_, Op.Acc.static_, etc.

export val Acc = {
  public_       = 1,
  private_      = 2,
  protected_    = 4,
  static_       = 8,
  final_        = 16,
  super_        = 32,
  synchronized_ = 32,   // method
  volatile_     = 64,
  bridge_       = 64,   // method
  transient_    = 128,
  varargs_      = 128,  // method
  native_       = 256,
  interface_    = 512,
  abstract_     = 1024,
  strict_       = 2048,
  synthetic_    = 4096,
  annotation_   = 8192,
  enum_         = 16384
}

/// Return the JVM type descriptor string for a Kestrel InternalType.
/// Primitives Int and Float are unboxed (J, D); Char/Rune are unboxed (I).
/// Bool and String are boxed references. All other types map to Object.
export fun descriptorForType(t: Ty.InternalType): String = {
  val pn = Ty.primName(t)
  if (pn == None)
    "Ljava/lang/Object;"
  else
    descriptorForPrim(Opt.getOrElse(pn, ""))
}

fun descriptorForPrim(name: String): String =
  if (name == "Int")    "J"
  else if (name == "Float")  "D"
  else if (name == "Bool")   "Ljava/lang/Boolean;"
  else if (name == "String") "Ljava/lang/String;"
  else if (name == "Unit")   "V"
  else if (name == "Char")   "I"
  else if (name == "Rune")   "I"
  else "Ljava/lang/Object;"

fun buildParams(parts: List<Ty.InternalType>): String =
  match (parts) {
    [] => ""
    h :: rest => "${descriptorForType(h)}${buildParams(rest)}"
  }

/// Build a JVM method descriptor string, e.g. "(J)Ljava/lang/String;".
export fun methodDescriptor(params: List<Ty.InternalType>, ret: Ty.InternalType): String =
  "(${buildParams(params)})${descriptorForType(ret)}"

/// Return the number of JVM local variable slots a type occupies.
/// long (Int) and double (Float) take 2; everything else takes 1.
export fun jvmSlotSize(t: Ty.InternalType): Int = {
  val pn = Ty.primName(t)
  if (pn == None)
    1
  else {
    val name = Opt.getOrElse(pn, "")
    if (name == "Int" | name == "Float") 2 else 1
  }
}
