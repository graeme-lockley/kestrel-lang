import { Suite, group, isTrue, eq } from "kestrel:dev/test"
import * as BA from "kestrel:data/bytearray"
import * as Dict from "kestrel:data/dict"
import * as Lst from "kestrel:data/list"
import * as Lex from "kestrel:dev/parser/lexer"
import * as CG from "kestrel:tools/compiler/codegen"
import { parseFromList } from "kestrel:dev/parser/parser"

fun seqStartsWith(xs: List<Int>, prefix: List<Int>): Bool =
  match (prefix) {
    [] => True
    p :: restP => match (xs) {
      [] => False
      x :: restX => if (x == p) seqStartsWith(restX, restP) else False
    }
  }

fun seqContains(haystack: List<Int>, needle: List<Int>): Bool =
  if (Lst.isEmpty(needle)) True
  else match (haystack) {
    [] => False
    _ :: rest =>
      if (seqStartsWith(haystack, needle)) True
      else seqContains(rest, needle)
  }

fun compileModule(moduleName: String, src: String): CG.JvmCodegenResult =
  match (parseFromList(Lex.lex(src))) {
    Ok(prog) => {
      val mctx = CG.buildModuleContext(moduleName, prog, CG.emptyJvmCodegenOptions())
      CG.jvmCodegen(mctx, prog, CG.noTypeInfo)
    }
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
    });

    group(s1, "extern type declaration", (sg: Suite) => {
      val result = compileModule("test/DeclExternType", "export extern type Foo = jvm(\"java.lang.Object\")")
      isTrue(sg, "main class emitted", hasNonEmptyClass(result, "test/DeclExternType"));
      eq(sg, "no extra classes for extern type", Dict.size(result.classes), 1)
    });

    group(s1, "extern import declaration", (sg: Suite) => {
      val src = "extern import \"java:java.lang.StringBuilder\" as SB {\n  fun append(sb: String, s: String): String\n  fun clear(sb: String): String\n}"
      val result = compileModule("test/DeclExternImport", src)
      isTrue(sg, "main class emitted", hasNonEmptyClass(result, "test/DeclExternImport"));
      eq(sg, "no extra classes for extern import", Dict.size(result.classes), 1)
    });

    group(s1, "re-export declarations", (sg: Suite) => {
      // export * from produces no extra classes (pure linkage in KTI)
      val starResult = compileModule("test/DeclReexportStar", "export * from \"kestrel:some/dep\"")
      isTrue(sg, "export-star main class emitted", hasNonEmptyClass(starResult, "test/DeclReexportStar"));
      eq(sg, "export-star no extra classes", Dict.size(starResult.classes), 1);

      // export { x } from produces no extra classes
      val namedResult = compileModule("test/DeclReexportNamed", "export { foo, Bar } from \"kestrel:some/dep\"")
      isTrue(sg, "export-named main class emitted", hasNonEmptyClass(namedResult, "test/DeclReexportNamed"));
      eq(sg, "export-named no extra classes", Dict.size(namedResult.classes), 1)
    });

    group(s1, "nullary ctor has INSTANCE field", (sg: Suite) => {
      val result = compileModule("test/DeclCtorInst", "type Color = Red | Green")
      val redCtorName = "Red"
      val redKey = "test/DeclCtorInst$${redCtorName}"
      isTrue(sg, "module class emitted", hasNonEmptyClass(result, "test/DeclCtorInst"));
      isTrue(sg, "Red ctor class emitted", hasNonEmptyClass(result, redKey));
      // The ctor class bytes should contain UTF-8 for "INSTANCE" = [73, 78, 83, 84, 65, 78, 67, 69]
      match (Dict.get(result.classes, redKey)) {
        None => isTrue(sg, "Red class bytes exist", False)
        Some(bytes) => {
          val bs = BA.toList(bytes)
          isTrue(sg, "nullary ctor has INSTANCE in classfile",
            seqContains(bs, [73, 78, 83, 84, 65, 78, 67, 69]))
        }
      }
    });

    group(s1, "global val declaration", (sg: Suite) => {
      val result = compileModule("test/DeclVal", "val x: Int = 1")
      isTrue(sg, "module class emitted", hasNonEmptyClass(result, "test/DeclVal"))
    });

    group(s1, "global var declaration", (sg: Suite) => {
      val result = compileModule("test/DeclVar", "var y: Int = 2")
      isTrue(sg, "module class emitted", hasNonEmptyClass(result, "test/DeclVar"))
    })
  })
