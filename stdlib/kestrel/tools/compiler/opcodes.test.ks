import { Suite, group, eq } from "kestrel:dev/test"
import * as Op from "kestrel:tools/compiler/opcodes"
import * as Ty from "kestrel:dev/typecheck/types"

// Tests for kestrel:tools/compiler/opcodes

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:tools/compiler/opcodes", (s1: Suite) => {
    group(s1, "opcode constants", (sg: Suite) => {
      eq(sg, "nop = 0",           Op.JvmOp.nop, 0)
      eq(sg, "areturn = 0xB0",    Op.JvmOp.areturn, 176)
      eq(sg, "invokevirtual = 0xB6", Op.JvmOp.invokevirtual, 182)
      eq(sg, "invokestatic = 0xB8",  Op.JvmOp.invokestatic, 184)
      eq(sg, "aload0 = 0x2A",     Op.JvmOp.aload0, 42)
      eq(sg, "return_ = 0xB1",    Op.JvmOp.return_, 177)
    });

    group(s1, "access flag constants", (sg: Suite) => {
      eq(sg, "accPublic = 1",     Op.Acc.public_, 1)
      eq(sg, "accStatic = 8",     Op.Acc.static_, 8)
      eq(sg, "accFinal = 16",     Op.Acc.final_, 16)
      eq(sg, "accInterface = 512", Op.Acc.interface_, 512)
    });

    group(s1, "descriptorForType primitives", (sg: Suite) => {
      eq(sg, "Int -> J",          Op.descriptorForType(Ty.tInt),    "J")
      eq(sg, "Float -> D",        Op.descriptorForType(Ty.tFloat),  "D")
      eq(sg, "Bool -> Boolean",   Op.descriptorForType(Ty.tBool),   "Ljava/lang/Boolean;")
      eq(sg, "String -> String",  Op.descriptorForType(Ty.tString), "Ljava/lang/String;")
      eq(sg, "Unit -> V",         Op.descriptorForType(Ty.tUnit),   "V")
      eq(sg, "Char -> I",         Op.descriptorForType(Ty.tChar),   "I")
    });

    group(s1, "descriptorForType non-primitive", (sg: Suite) => {
      val arrow = Ty.TArrow([Ty.tInt], Ty.tString)
      eq(sg, "arrow -> Object",   Op.descriptorForType(arrow), "Ljava/lang/Object;")
    });

    group(s1, "methodDescriptor", (sg: Suite) => {
      eq(sg, "(J)Ljava/lang/String;",
        Op.methodDescriptor([Ty.tInt], Ty.tString), "(J)Ljava/lang/String;")
      eq(sg, "no params, Unit return",
        Op.methodDescriptor([], Ty.tUnit), "()V")
      eq(sg, "two params",
        Op.methodDescriptor([Ty.tBool, Ty.tString], Ty.tInt),
        "(Ljava/lang/Boolean;Ljava/lang/String;)J")
    });

    group(s1, "jvmSlotSize", (sg: Suite) => {
      eq(sg, "Int -> 2",    Op.jvmSlotSize(Ty.tInt),    2)
      eq(sg, "Float -> 2",  Op.jvmSlotSize(Ty.tFloat),  2)
      eq(sg, "Bool -> 1",   Op.jvmSlotSize(Ty.tBool),   1)
      eq(sg, "String -> 1", Op.jvmSlotSize(Ty.tString), 1)
      eq(sg, "Unit -> 1",   Op.jvmSlotSize(Ty.tUnit),   1)
    })
  })

