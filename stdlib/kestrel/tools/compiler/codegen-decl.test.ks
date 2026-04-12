import { Suite, group, isTrue } from "kestrel:dev/test"
import * as BA from "kestrel:data/bytearray"
import * as Dict from "kestrel:data/dict"
import * as Lex from "kestrel:dev/parser/lexer"
import * as CG from "kestrel:tools/compiler/codegen"
import { parseFromList } from "kestrel:dev/parser/parser"

fun compileModule(moduleName: String, src: String): CG.JvmCodegenResult =
  match (parseFromList(Lex.lex(src))) {
    Ok(prog) => CG.jvmCodegen(moduleName, prog)
    Err(e) => throw e
  }

fun hasNonEmptyClass(result: CG.JvmCodegenResult, className: String): Bool =
  match (Dict.get(result.classes, className)) {
    Some(bytes) => BA.length(bytes) > 0
    None => False
  }

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:tools/compiler/codegen-decl", (s1: Suite) => {
    group(s1, "function declaration", (sg: Suite) => {
      val result = compileModule("test/DeclFun", "fun id(x: Int): Int = x")
      isTrue(sg, "main class emitted", hasNonEmptyClass(result, "test/DeclFun"))
    })

    group(s1, "tail recursion scaffold", (sg: Suite) => {
      val src = "fun loop(n: Int): Int = loop(n)"
      val result = compileModule("test/DeclTail", src)
      isTrue(sg, "tail-recursive module emits", hasNonEmptyClass(result, "test/DeclTail"))
    })

    group(s1, "async declaration and extern fun", (sg: Suite) => {
      val src = "async fun f(): Int = 1\nextern fun now(): Int = jvm(\"java.lang.System#currentTimeMillis()\")"
      val result = compileModule("test/DeclAsync", src)
      isTrue(sg, "async/extern module emits", hasNonEmptyClass(result, "test/DeclAsync"))
    })

    group(s1, "adt constructor classes", (sg: Suite) => {
      val result = compileModule("test/DeclType", "type Color = Red | Green")
      isTrue(sg, "module class emitted", hasNonEmptyClass(result, "test/DeclType"))
      isTrue(sg, "constructor classes emitted", Dict.size(result.classes) >= 3)
    })
  })
