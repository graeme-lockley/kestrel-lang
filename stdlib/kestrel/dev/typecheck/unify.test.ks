import { Suite, group, eq } from "kestrel:dev/test"
import * as Dict from "kestrel:data/dict"
import * as Opt from "kestrel:data/option"
import * as Ast from "kestrel:dev/parser/ast"
import * as FA from "kestrel:dev/typecheck/from-ast"
import * as Ty from "kestrel:dev/typecheck/types"

fun emptySubst(): Dict<Int, Ty.InternalType> = Dict.emptyIntDict()

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:dev/typecheck/unify", (s1: Suite) => {
    group(s1, "unify primitives", (sg: Suite) => {
      val same = Ty.unify(emptySubst(), Ty.tInt, Ty.tInt)
      eq(sg, "identical primitive is Ok", match (same) { Ok(_) => True, Err(_) => False }, True)

      val mismatch = Ty.unify(emptySubst(), Ty.tInt, Ty.tBool)
      eq(sg, "different primitive is Err", match (mismatch) { Ok(_) => False, Err(_) => True }, True)
    });

    group(s1, "unify vars", (sg: Suite) => {
      val out = Ty.unify(emptySubst(), Ty.TVar(7), Ty.tInt)
      val isSingleton = match (out) {
        Err(_) => False
        Ok(s2) => {
          val got = Dict.get(s2, 7)
          if (got == None) False else Opt.getOrElse(got, Ty.tBool) == Ty.tInt
        }
      }
      eq(sg, "var unified with primitive", isSingleton, True)
    });

    group(s1, "occurs check", (sg: Suite) => {
      val cyc = Ty.unify(emptySubst(), Ty.TVar(1), Ty.TApp("Box", [Ty.TVar(1)]))
      eq(sg, "var occurs in app arg => Err", match (cyc) { Ok(_) => False, Err(_) => True }, True)
    });

    group(s1, "astTypeToInternal", (sg: Suite) => {
      Ty.resetVarId()
      val scope: Dict<String, Ty.InternalType> = Dict.emptyStringDict()

      val intTy = FA.astTypeToInternal(Ast.ATPrim("Int"), scope)
      eq(sg, "ATPrim(Int) => tInt", intTy, Ty.tInt)

      val fnTy = FA.astTypeToInternal(
        Ast.ATArrow([Ast.ATPrim("Int")], Ast.ATPrim("Bool")),
        scope
      )
      eq(sg, "ATArrow maps to TArrow", Ty.typeToString(fnTy), "(Int) -> Bool")
    })
  })
