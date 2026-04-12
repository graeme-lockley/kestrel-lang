import { Suite, group, eq, isTrue } from "kestrel:dev/test"
import * as Dict from "kestrel:data/dict"
import * as Lst from "kestrel:data/list"
import * as Res from "kestrel:data/result"
import * as Lex from "kestrel:dev/parser/lexer"
import { parseFromList } from "kestrel:dev/parser/parser"
import * as Ast from "kestrel:dev/parser/ast"
import * as Kti from "kestrel:tools/compiler/kti"
import * as Ty from "kestrel:tools/compiler/types"

fun program(src: String): Ast.Program =
  match (parseFromList(Lex.lex(src))) {
    Ok(prog) => prog
    Err(e) => throw e
  }

fun baseExports(): Dict<String, Ty.InternalType> =
  Dict.insert(
    Dict.insert(Dict.emptyStringDict(), "id", Ty.TArrow([Ty.tInt], Ty.tInt)),
    "x",
    Ty.tInt
  )

export async fun run(s: Suite): Task<Unit> =
  {
    val rtProg = program("export fun id(x: Int): Int = x")
    val rtKti = Kti.buildKtiV4(rtProg, Dict.insert(Dict.emptyStringDict(), "id", Ty.TArrow([Ty.tInt], Ty.tInt)), "src", Dict.emptyStringDict())
    val rtPath = "/tmp/kestrel-kti-roundtrip.kti"
    val rtWrite = await Kti.writeKtiFile(rtPath, rtKti)
    val rtRead = await Kti.readKtiFile(rtPath)

    group(s, "kestrel:tools/compiler/kti", (s1: Suite) => {
    group(s1, "build v4 shape", (sg: Suite) => {
      val prog = program("export fun id(x: Int): Int = x\nexport val x: Int = 1")
      val kti = Kti.buildKtiV4(prog, baseExports(), "module source", Dict.emptyStringDict())
      eq(sg, "version", kti.version, 4)
      isTrue(sg, "functions include id", Dict.member(kti.functions, "id"))
      isTrue(sg, "sourceHash present", kti.sourceHash != "")
    })

    group(s1, "write/read round trip", (sg: Suite) => {
      eq(sg, "write ok", Res.isOk(rtWrite), True)
      eq(sg, "read ok", Res.isOk(rtRead), True)
      match (rtRead) {
        Ok(k2) => {
          eq(sg, "round-trip version", k2.version, 4)
          isTrue(sg, "round-trip function kept", Dict.member(k2.functions, "id"))
        }
        Err(_) => isTrue(sg, "unexpected read error", False)
      }
    })

    group(s1, "deserialize exports", (sg: Suite) => {
      val prog = program("export fun id(x: Int): Int = x")
      val kti = Kti.buildKtiV4(prog, Dict.insert(Dict.emptyStringDict(), "id", Ty.TArrow([Ty.tInt], Ty.tInt)), "src", Dict.emptyStringDict())
      val ex = Kti.deserializeExports(kti)
      match (Dict.get(ex, "id")) {
        Some(t) => eq(sg, "id type restored", Ty.typeToString(t), "(Int) -> Int")
        None => isTrue(sg, "missing id export", False)
      }
    })

    group(s1, "extract codegen meta", (sg: Suite) => {
      val src = "export fun f(x: Int): Int = x\nexport var c: Int = 0\ntype Color = Red | Green"
      val prog = program(src)
      val exports = Dict.insert(
        Dict.insert(Dict.emptyStringDict(), "f", Ty.TArrow([Ty.tInt], Ty.tInt)),
        "c",
        Ty.tInt
      )
      val meta = Kti.extractCodegenMeta(prog, exports)
      match (Dict.get(meta.funArities, "f")) {
        Some(n) => eq(sg, "arity tracked", n, 0)
        None => isTrue(sg, "missing arity", False)
      }
      isTrue(sg, "exported names tracked", Lst.member(meta.valOrVarNames, "c"))
    })
    })
  }
