import { Suite, group, eq, isTrue } from "kestrel:dev/test"
import * as Dict from "kestrel:data/dict"
import * as Ty from "kestrel:compiler/types"

export async fun run(s: Suite): Task<Unit> =
  group(s, "kestrel:compiler/types", (s1: Suite) => {
    group(s1, "fresh vars", (sg: Suite) => {
      Ty.resetVarId()
      val v1 = Ty.freshVar()
      val v2 = Ty.freshVar()
      eq(sg, "fresh ids differ", Ty.typeToString(v1) != Ty.typeToString(v2), True)
      Ty.resetVarId()
      eq(sg, "reset starts at 0", Ty.typeToString(Ty.freshVar()), "'0")
    });

    group(s1, "free vars concrete", (sg: Suite) => {
      val vars = Ty.freeVars(Ty.tInt)
      eq(sg, "no free vars", Dict.keys(vars), [])
    });

    group(s1, "applySubst", (sg: Suite) => {
      val subst = Dict.singletonIntDict(7, Ty.tBool)
      val out = Ty.applySubst(subst, Ty.TVar(7))
      eq(sg, "var replaced", out, Ty.tBool)
    });

    group(s1, "generalize and instantiate", (sg: Suite) => {
      val env: Dict<String, Ty.InternalType> = Dict.emptyStringDict()
      val t = Ty.TArrow([Ty.TVar(1)], Ty.TVar(1))
      val sch = Ty.generalize(env, t)
      val i1 = Ty.instantiate(sch)
      val i2 = Ty.instantiate(sch)
      val s1t = Ty.typeToString(i1)
      val s2t = Ty.typeToString(i2)
      isTrue(sg, "instantiation returns fresh ids", s1t != s2t)
    })
  })
