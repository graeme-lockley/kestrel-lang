import { Suite, group, eq, isTrue } from "kestrel:dev/test"
import * as Str from "kestrel:data/string"
import * as Dict from "kestrel:data/dict"
import * as Lst from "kestrel:data/list"
import * as Opt from "kestrel:data/option"
import * as Lex from "kestrel:dev/parser/lexer"
import { parseFromList } from "kestrel:dev/parser/parser"
import * as Ast from "kestrel:dev/parser/ast"
import * as Diag from "kestrel:dev/typecheck/diagnostics"
import * as TC from "kestrel:dev/typecheck/typecheck"
import * as Ty from "kestrel:dev/typecheck/types"

fun program(src: String): Ast.Program =
  match (parseFromList(Lex.lex(src))) {
    Ok(prog) => prog
    Err(e) => throw e
  }

fun runTc(src: String): TC.TypecheckResult =
  TC.typecheck(program(src), {
    importBindings = None,
    typeAliasBindings = None,
    importOpaqueTypes = None,
    sourceFile = "typecheck.test.ks"
  })

fun findExportType(res: TC.TypecheckResult, name: String): String =
  match (Dict.get(res.exports.items, name)) {
    Some(t) => Ty.typeToString(t)
    None => "<missing>"
  }

fun hasDiagCode(diags: List<Diag.Diagnostic>, code: String): Bool =
  Lst.any(diags, (d: Diag.Diagnostic) => d.code == code)

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:dev/typecheck/typecheck", (s1: Suite) => {
    group(s1, "literals", (sg: Suite) => {
      Ty.resetVarId()
      val res = runTc("export val x: Int = 42")
      eq(sg, "literal program ok", res.ok, True);
      eq(sg, "literal export inferred", findExportType(res, "x"), "Int")
    });

    group(s1, "diagnostics", (sg: Suite) => {
      Ty.resetVarId()
      val res = runTc("val x = 1 + True")
      eq(sg, "bad arithmetic fails", res.ok, False);
      isTrue(sg, "has diagnostics", !Lst.isEmpty(res.diagnostics))
    });

    group(s1, "exported fun annotations", (sg: Suite) => {
      Ty.resetVarId()
      val res = runTc("export fun id(x: Int): Int = x")
      eq(sg, "annotated exported fun ok", res.ok, True);
      eq(sg, "exported type stored", findExportType(res, "id"), "(Int) -> Int")
    });

    group(s1, "let polymorphism", (sg: Suite) => {
      Ty.resetVarId()
      val src = "val id = (x) => x\nexport val a = id(1)\nexport val b = id(True)"
      val res = runTc(src)
      eq(sg, "polymorphic uses ok", res.ok, True);
      eq(sg, "a inferred Int", findExportType(res, "a"), "Int");
      eq(sg, "b inferred Bool", findExportType(res, "b"), "Bool")
    });

    group(s1, "match exhaustiveness", (sg: Suite) => {
      Ty.resetVarId()
      val src = "type Maybe<A> = None | Some(A)\nval x = match (Some(1)) { Some(v) => v }"
      val res = runTc(src)
      eq(sg, "non-exhaustive rejected", res.ok, False);
      isTrue(sg, "non-exhaustive code emitted", hasDiagCode(res.diagnostics, Diag.CODES.type_.nonExhaustiveMatch))
    });

    group(s1, "new expression forms", (sg: Suite) => {
      Ty.resetVarId();
      // record literal
      val rec = runTc("export val p = { x = 1, y = 2 }")
      eq(sg, "record literal ok", rec.ok, True);

      // cons expression
      val cons = runTc("export val xs: List<Int> = 1 :: [2, 3]")
      eq(sg, "cons ok", cons.ok, True);

      // unary operator
      val unary = runTc("export val n: Int = -5")
      eq(sg, "unary minus ok", unary.ok, True);

      // pipe |>
      val pipe = runTc("fun inc(x: Int): Int = x + 1\nexport val r: Int = 1 |> inc")
      eq(sg, "pipe ok", pipe.ok, True);

      // field access on record
      val field = runTc("val p = { x = 42 }\nexport val n: Int = p.x")
      eq(sg, "field access ok", field.ok, True)
    });

    group(s1, "await recursive direct call", (sg: Suite) => {
      Ty.resetVarId();
      // Regression: direct `await` on a recursive async call must be accepted.
      // The operand type is an unresolved TVar when first encountered; the type
      // checker must constrain it to Task<inner> via unification rather than
      // reporting "await expects Task<T>".
      val src = "import * as Lst from \"kestrel:data/list\"\nasync fun go(xs: List<Int>): Task<Int> =\n  match (xs) {\n    [] => 0\n    _ :: rest => await go(rest)\n  }"
      val res = runTc(src)
      eq(sg, "recursive direct await accepted", res.ok, True);
      isTrue(sg, "no diagnostics", Lst.isEmpty(res.diagnostics))
    });

    group(s1, "await outside async", (sg: Suite) => {
      Ty.resetVarId()
      val topLevel = runTc("async fun getTask(): Task<Int> = 1\nval x = await getTask()")
      eq(sg, "top-level await rejected", topLevel.ok, False);
      isTrue(sg, "top-level await has diagnostics", !Lst.isEmpty(topLevel.diagnostics))

      Ty.resetVarId()
      val localSync = runTc("async fun getTask(): Task<Int> = 1\nfun bad(): Int = await getTask()")
      eq(sg, "sync local fun await rejected", localSync.ok, False);
      isTrue(sg, "sync local fun has diagnostics", !Lst.isEmpty(localSync.diagnostics))
    });

    group(s1, "script val annotations", (sg: Suite) => {
      Ty.resetVarId()
      val mismatch = runTc("val s: String = 42")
      eq(sg, "script val annotation mismatch rejected", mismatch.ok, False);
      isTrue(sg, "script val mismatch has diagnostics", !Lst.isEmpty(mismatch.diagnostics))
    });

    group(s1, "extern fun declarations", (sg: Suite) => {
      // exported extern fun appears in exports with correct type
      Ty.resetVarId()
      val exportedExtern = runTc("export extern fun add(x: Int, y: Int): Int = jvm(\"(II)I\")")
      eq(sg, "exported extern fun ok", exportedExtern.ok, True);
      eq(sg, "exported extern fun in exports", findExportType(exportedExtern, "add"), "(Int, Int) -> Int");

      // non-exported extern fun does not appear in exports
      Ty.resetVarId()
      val localExtern = runTc("extern fun hidden(x: Int): Int = jvm(\"(I)I\")")
      eq(sg, "non-exported extern fun ok", localExtern.ok, True);
      eq(sg, "non-exported extern fun absent from exports", findExportType(localExtern, "hidden"), "<missing>");

      // generic extern fun generalizes correctly
      Ty.resetVarId()
      val genericExtern = runTc("export extern fun identity<A>(x: A): A = jvm(\"(Ljava/lang/Object;)Ljava/lang/Object;\")")
      eq(sg, "generic extern fun ok", genericExtern.ok, True);
      isTrue(sg, "generic extern fun type", Str.startsWith("forall 1 vars.", findExportType(genericExtern, "identity")));

      // downstream module using an extern fun imported from a prior module typechecks successfully
      Ty.resetVarId()
      val producer = runTc("export extern fun add(x: Int, y: Int): Int = jvm(\"(II)I\")")
      val consumer = TC.typecheck(program("export val result: Int = add(1, 2)"), {
        importBindings = Some(producer.exports),
        typeAliasBindings = None,
        importOpaqueTypes = None,
        sourceFile = "consumer.ks"
      })
      eq(sg, "downstream consumer ok", consumer.ok, True);
      eq(sg, "downstream consumer result type", findExportType(consumer, "result"), "Int")
    });

    group(s1, "extern type declarations", (sg: Suite) => {
      // non-exported extern type is accepted with no diagnostics
      Ty.resetVarId()
      val localExt = runTc("extern type Foo = jvm(\"java.lang.Object\")")
      eq(sg, "non-exported extern type ok", localExt.ok, True);
      isTrue(sg, "non-exported extern type no diagnostics", Lst.isEmpty(localExt.diagnostics));

      // exported extern type appears in exportedTypeVisibility as "export"
      Ty.resetVarId()
      val exportedExt = runTc("export extern type Bar = jvm(\"java.lang.Object\")")
      eq(sg, "exported extern type ok", exportedExt.ok, True);
      eq(sg, "exported extern type visibility", Opt.getOrElse(Dict.get(exportedExt.exportedTypeVisibility, "Bar"), "<missing>"), "export");

      // local (non-exported, non-opaque) extern type appears in exportedTypeVisibility as "local"
      Ty.resetVarId()
      val localExt2 = runTc("extern type Baz = jvm(\"java.lang.Object\")")
      eq(sg, "local extern type ok", localExt2.ok, True);
      eq(sg, "local extern type visibility recorded", Opt.getOrElse(Dict.get(localExt2.exportedTypeVisibility, "Baz"), "<missing>"), "local");

      // extern type with type params is accepted
      Ty.resetVarId()
      val paramExt = runTc("extern type Map<K, V> = jvm(\"java.util.Map\")")
      eq(sg, "parameterised extern type ok", paramExt.ok, True);
      isTrue(sg, "parameterised extern type no diagnostics", Lst.isEmpty(paramExt.diagnostics))
    });

    group(s1, "extern import declarations", (sg: Suite) => {
      // extern import with two overrides typechecks with no diagnostics
      Ty.resetVarId()
      val twoOverrides = runTc("extern import \"java:java.lang.StringBuilder\" as SB {\n  fun append(sb: String, s: String): String\n  fun clear(sb: String): String\n}")
      eq(sg, "two-override extern import ok", twoOverrides.ok, True);
      isTrue(sg, "two-override extern import no diagnostics", Lst.isEmpty(twoOverrides.diagnostics));

      // extern import override names are local — they do NOT appear in exports
      Ty.resetVarId()
      val localCheck = runTc("extern import \"java:java.lang.StringBuilder\" as SB {\n  fun append(sb: String, s: String): String\n}")
      eq(sg, "extern import local only ok", localCheck.ok, True);
      eq(sg, "extern import name absent from exports", findExportType(localCheck, "append"), "<missing>");

      // override names are accessible within the module: exported wrapper using override name typechecks
      Ty.resetVarId()
      val wrapperSrc = "extern import \"java:java.lang.StringBuilder\" as SB {\n  fun append(sb: String, s: String): String\n}\nexport fun wrapAppend(a: String, b: String): String = append(a, b)"
      val wrapResult = runTc(wrapperSrc)
      eq(sg, "exported wrapper using extern import name ok", wrapResult.ok, True);
      eq(sg, "wrapper export type correct", findExportType(wrapResult, "wrapAppend"), "(String, String) -> String")
    });

    group(s1, "exception declarations", (sg: Suite) => {
      // no-field exception typechecks with no diagnostics
      Ty.resetVarId()
      val noField = runTc("exception SimpleError")
      eq(sg, "no-field exception ok", noField.ok, True);
      isTrue(sg, "no-field exception no diagnostics", Lst.isEmpty(noField.diagnostics));

      // exception with fields typechecks with no diagnostics
      Ty.resetVarId()
      val withFields = runTc("exception MyError(message: String)")
      eq(sg, "exception with fields ok", withFields.ok, True);
      isTrue(sg, "exception with fields no diagnostics", Lst.isEmpty(withFields.diagnostics));

      // exported exception constructor appears in exports
      Ty.resetVarId()
      val exported = runTc("export exception MyError(message: String)")
      eq(sg, "exported exception ok", exported.ok, True);
      isTrue(sg, "exported exception ctor in exports", findExportType(exported, "MyError") != "<missing>");

      // non-exported exception constructor absent from exports
      Ty.resetVarId()
      val local = runTc("exception LocalErr(code: Int)")
      eq(sg, "non-exported exception ok", local.ok, True);
      eq(sg, "non-exported exception absent from exports", findExportType(local, "LocalErr"), "<missing>");

      // throw expression typechecks
      Ty.resetVarId()
      val throwRes = runTc("exception MyError(message: String)\nfun go(): Int = throw MyError(\"oops\")")
      eq(sg, "throw exception ok", throwRes.ok, True);
      isTrue(sg, "throw exception no diagnostics", Lst.isEmpty(throwRes.diagnostics));

      // try/catch with constructor pattern binds variables correctly
      Ty.resetVarId()
      val tryCatch = runTc("exception MyError(message: String)\nexport fun run(): Int = try { 1 } catch (MyError(m)) { m => 0 }")
      eq(sg, "try/catch exception ok", tryCatch.ok, True);
      isTrue(sg, "try/catch exception no diagnostics", Lst.isEmpty(tryCatch.diagnostics));

      // exported exception consumable cross-module via importBindings
      Ty.resetVarId()
      val producer = runTc("export exception MyError(message: String)")
      val consumer = TC.typecheck(program("export fun go(): Int = try { 1 } catch (MyError(m)) { m => 0 }"), {
        importBindings = Some(producer.exports),
        typeAliasBindings = None,
        importOpaqueTypes = None,
        sourceFile = "consumer.ks"
      })
      eq(sg, "cross-module exception consumer ok", consumer.ok, True);
      isTrue(sg, "cross-module exception no diagnostics", Lst.isEmpty(consumer.diagnostics))
    })
  })