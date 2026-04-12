import { Suite, group, eq, isTrue } from "kestrel:dev/test"
import * as Dict from "kestrel:data/dict"
import * as Lst from "kestrel:data/list"
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
    })
  })