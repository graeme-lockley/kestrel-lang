import { Suite, group, eq, isTrue } from "kestrel:dev/test"
import * as Dict from "kestrel:data/dict"
import * as Lex from "kestrel:dev/parser/lexer"
import { parseFromList } from "kestrel:dev/parser/parser"
import * as Ast from "kestrel:dev/parser/ast"
import * as Driver from "kestrel:tools/compiler/driver"
import * as Kti from "kestrel:tools/compiler/kti"
import * as Ty from "kestrel:dev/typecheck/types"

fun program(src: String): Ast.Program =
  match (parseFromList(Lex.lex(src))) {
    Ok(p) => p
    Err(e) => throw e
  }

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:tools/compiler/driver", (s1: Suite) => {
    group(s1, "freshness helper", (sg: Suite) => {
      val p = program("export fun id(x: Int): Int = x")
      val kti = Kti.buildKtiV4(p, Dict.insert(Dict.emptyStringDict(), "id", Ty.TArrow([Ty.tInt], Ty.tInt)), "src", Dict.emptyStringDict())
      val fresh = Driver.isFresh(kti, kti.sourceHash, Dict.emptyStringDict())
      val staleSrc = Driver.isFresh(kti, "different", Dict.emptyStringDict())
      val staleDeps = Driver.isFresh(kti, kti.sourceHash, Dict.insert(Dict.emptyStringDict(), "dep", "h"))
      eq(sg, "fresh true", fresh, True)
      eq(sg, "stale source false", staleSrc, False)
      eq(sg, "stale deps false", staleDeps, False)
    })

    group(s1, "compile options shape", (sg: Suite) => {
      val opts = {
        outDir = "/tmp/out",
        stdlibDir = "/tmp/stdlib",
        cacheRoot = "/tmp/cache",
        allowHttp = False,
        writeKti = True
      }
      isTrue(sg, "options outDir set", opts.outDir == "/tmp/out")
      isTrue(sg, "options allowHttp set", opts.allowHttp == False)
    })
  })
