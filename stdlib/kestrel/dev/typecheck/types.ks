//! Hindley-Milner internal type representation and manipulation.
//!
//! Defines `InternalType` — the ADT used by the type checker — together with
//! substitution, generalisation, instantiation, and free-variable utilities.
import * as Dict from "kestrel:data/dict"
import * as Lst from "kestrel:data/list"
import * as Opt from "kestrel:data/option"
import * as Res from "kestrel:data/result"

/// A record field descriptor: field name, mutability flag, and field type.
export type TypeField = { name: String, mut_: Bool, type_: InternalType }

/// The internal type representation used throughout the Kestrel type checker.
///
/// - `TVar(id)` — unification variable with a unique integer id
/// - `TPrim(name)` — primitive type (`Int`, `Float`, `Bool`, `String`, `Unit`, `Char`, `Rune`)
/// - `TArrow(params, ret)` — function type
/// - `TRecord(fields, rowVar?)` — record type; row variable is `Some(TVar(_))` for open records
/// - `TApp(name, args)` — parameterised type application, e.g. `List<Int>`
/// - `TTuple(elements)` — tuple type
/// - `TUnion(l, r)` / `TInter(l, r)` — union / intersection types
/// - `TScheme(vars, body)` — universally-quantified scheme (result of `generalize`)
/// - `TNamespace(_)` — a module namespace; not a first-class value type
export type InternalType =
    TVar(Int)
  | TPrim(String)
  | TArrow(List<InternalType>, InternalType)
  | TRecord(List<TypeField>, Option<InternalType>)
  | TApp(String, List<InternalType>)
  | TTuple(List<InternalType>)
  | TUnion(InternalType, InternalType)
  | TInter(InternalType, InternalType)
  | TScheme(List<Int>, InternalType)
  | TNamespace(Dict<String, InternalType>)

/// Structured unification error payload as (leftType, rightType).
fun mkUnifyError(left: InternalType, right: InternalType): (InternalType, InternalType) =
  (left, right)

val counter = { mut nextVarId = 0 }

/// Allocate a fresh unification variable with a globally unique integer id.
export fun freshVar(): InternalType = {
  val out = TVar(counter.nextVarId)
  counter.nextVarId := counter.nextVarId + 1;
  out
}

/// Reset the global unification-variable counter to 0.
/// Call at the start of each type-check run to keep ids small and deterministic.
export fun resetVarId(): Unit = {
  counter.nextVarId := 0;
  ()
}

/// Construct a `TPrim` by name. Prefer the pre-built constants below.
export fun prim(name: String): InternalType = TPrim(name)

/// Pre-built `InternalType` constants for the seven Kestrel primitives.
export val tInt: InternalType = prim("Int")
export val tFloat: InternalType = prim("Float")
export val tBool: InternalType = prim("Bool")
export val tString: InternalType = prim("String")
export val tUnit: InternalType = prim("Unit")
export val tChar: InternalType = prim("Char")
export val tRune: InternalType = prim("Rune")

fun setEmpty(): Dict<Int, Unit> = Dict.emptyIntDict()

fun setInsert(s: Dict<Int, Unit>, x: Int): Dict<Int, Unit> = Dict.insert(s, x, ())

fun setMember(s: Dict<Int, Unit>, x: Int): Bool =
  match (Dict.get(s, x)) {
    Some(_) => True
    None => False
  }

fun setUnion(a: Dict<Int, Unit>, b: Dict<Int, Unit>): Dict<Int, Unit> = {
  val keys = Dict.keys(b)
  Lst.foldl(keys, a, (acc: Dict<Int, Unit>, k: Int) => setInsert(acc, k))
}

fun freeVarsMany(ts: List<InternalType>, bound: Dict<Int, Unit>): Dict<Int, Unit> =
  match (ts) {
    [] => setEmpty()
    h :: rest => setUnion(freeVarsWithBound(h, bound), freeVarsMany(rest, bound))
  }

fun freeVarsFields(fs: List<TypeField>, bound: Dict<Int, Unit>): Dict<Int, Unit> =
  match (fs) {
    [] => setEmpty()
    f :: rest => setUnion(freeVarsWithBound(f.type_, bound), freeVarsFields(rest, bound))
  }

fun freeVarsRecord(fields: List<TypeField>, rowOpt: Option<InternalType>, bound: Dict<Int, Unit>): Dict<Int, Unit> =
  if (rowOpt == None)
    freeVarsFields(fields, bound)
  else {
    val rowVars = freeVarsWithBound(Opt.getOrElse(rowOpt, tUnit), bound)
    setUnion(freeVarsFields(fields, bound), rowVars)
  }

fun freeVarsScheme(vars: List<Int>, body: InternalType, bound: Dict<Int, Unit>): Dict<Int, Unit> = {
  val bound2 = Lst.foldl(vars, bound, (acc: Dict<Int, Unit>, v: Int) => setInsert(acc, v))
  freeVarsWithBound(body, bound2)
}

fun freeVarsWithBound(t: InternalType, bound: Dict<Int, Unit>): Dict<Int, Unit> =
  match (t) {
    TVar(id) =>
      if (setMember(bound, id)) setEmpty() else setInsert(setEmpty(), id)
    TPrim(_) => setEmpty()
    TArrow(params, ret) => setUnion(freeVarsMany(params, bound), freeVarsWithBound(ret, bound))
    TRecord(fields, rowOpt) => freeVarsRecord(fields, rowOpt, bound)
    TApp(_, args) => freeVarsMany(args, bound)
    TTuple(elements) => freeVarsMany(elements, bound)
    TUnion(left, right) => setUnion(freeVarsWithBound(left, bound), freeVarsWithBound(right, bound))
    TInter(left, right) => setUnion(freeVarsWithBound(left, bound), freeVarsWithBound(right, bound))
    TScheme(vars, body) => freeVarsScheme(vars, body, bound)
    TNamespace(_) => setEmpty()
  }

/// Collect all free variables in a type.
export fun freeVars(t: InternalType): Dict<Int, Unit> =
  freeVarsWithBound(t, setEmpty())

/// If t is a TPrim, return Some(primitiveName); otherwise None.
export fun primName(t: InternalType): Option<String> =
  match (t) {
    TPrim(name) => Some(name)
    _ => None
  }

/// If t is a TVar, return Some(varId); otherwise None.
export fun varId(t: InternalType): Option<Int> =
  match (t) {
    TVar(id) => Some(id)
    _ => None
  }

fun envFreeVars(env: Dict<String, InternalType>): Dict<Int, Unit> = {
  val vals = Dict.values(env)
  Lst.foldl(vals, setEmpty(), (acc: Dict<Int, Unit>, t: InternalType) => setUnion(acc, freeVars(t)))
}

fun applySubstFields(subst: Dict<Int, InternalType>, fs: List<TypeField>): List<TypeField> =
  Lst.map(fs, (f: TypeField) => { name = f.name, mut_ = f.mut_, type_ = applySubst(subst, f.type_) })

fun applySubstRecord(subst: Dict<Int, InternalType>, fields: List<TypeField>, rowOpt: Option<InternalType>): InternalType = {
  val fields2 = applySubstFields(subst, fields)
  val row2 =
    if (rowOpt == None)
      None
    else
      Some(applySubst(subst, Opt.getOrElse(rowOpt, tUnit)))
  TRecord(fields2, row2)
}

fun applySubstMany(subst: Dict<Int, InternalType>, ts: List<InternalType>): List<InternalType> =
  match (ts) {
    [] => []
    h :: rest => applySubst(subst, h) :: applySubstMany(subst, rest)
  }

/// Apply a substitution map to all free variables in a type.
export fun applySubst(subst: Dict<Int, InternalType>, t: InternalType): InternalType =
  match (t) {
    TVar(id) => {
      val found = Dict.get(subst, id)
      if (found == None) t else Opt.getOrElse(found, t)
    }
    TPrim(_) => t
    TArrow(params, ret) => TArrow(applySubstMany(subst, params), applySubst(subst, ret))
    TRecord(fields, rowOpt) => applySubstRecord(subst, fields, rowOpt)
    TApp(name, args) => TApp(name, applySubstMany(subst, args))
    TTuple(elements) => TTuple(applySubstMany(subst, elements))
    TUnion(left, right) => TUnion(applySubst(subst, left), applySubst(subst, right))
    TInter(left, right) => TInter(applySubst(subst, left), applySubst(subst, right))
    TScheme(vars, body) => TScheme(vars, body)
    TNamespace(_) => t
  }

/// Quantify free vars in `t` that are not free in `env`.
export fun generalize(env: Dict<String, InternalType>, t: InternalType): InternalType = {
  val envVars = envFreeVars(env)
  val typeVars = freeVars(t)
  val ids = Dict.keys(typeVars)
  val quantify = Lst.filter(ids, (id: Int) => !setMember(envVars, id))
  if (Lst.isEmpty(quantify)) t else TScheme(quantify, t)
}

fun substFromVars(vars: List<Int>): Dict<Int, InternalType> =
  Lst.foldl(vars, Dict.emptyIntDict(), (acc: Dict<Int, InternalType>, v: Int) => Dict.insert(acc, v, freshVar()))

/// Instantiate a quantified type scheme by replacing quantified vars with fresh vars.
export fun instantiate(t: InternalType): InternalType =
  match (t) {
    TScheme(vars, body) => applySubst(substFromVars(vars), body)
    _ => t
  }

fun joinTypeStrings(parts: List<InternalType>, sep: String): String =
  match (parts) {
    [] => ""
    one :: [] => typeToString(one)
    h :: t => "${typeToString(h)}${sep}${joinTypeStrings(t, sep)}"
  }

fun joinStrings(parts: List<String>, sep: String): String =
  match (parts) {
    [] => ""
    one :: [] => one
    h :: t => "${h}${sep}${joinStrings(t, sep)}"
  }

fun typeToStringRecord(fields: List<TypeField>, rowOpt: Option<InternalType>): String = {
  val inner = Lst.map(fields, (f: TypeField) => "${f.name}: ${typeToString(f.type_)}")
  val base = "{${joinStrings(inner, ", ")}}"
  if (rowOpt == None)
    base
  else {
    val rowText = typeToString(Opt.getOrElse(rowOpt, tUnit))
    "${base} | ${rowText}"
  }
}

/// Debug renderer for InternalType.
export fun typeToString(t: InternalType): String =
  match (t) {
    TVar(id) => "'${id}"
    TPrim(name) => name
    TArrow(params, ret) => "(${joinTypeStrings(params, ", ")}) -> ${typeToString(ret)}"
    TRecord(fields, rowOpt) => typeToStringRecord(fields, rowOpt)
    TApp(name, args) => "${name}<${joinTypeStrings(args, ", ")}>"
    TTuple(elements) => "(${joinTypeStrings(elements, " * ")})"
    TUnion(left, right) => "${typeToString(left)} | ${typeToString(right)}"
    TInter(left, right) => "${typeToString(left)} & ${typeToString(right)}"
    TScheme(vars, body) => "forall ${Lst.length(vars)} vars. ${typeToString(body)}"
    TNamespace(_) => "<namespace>"
  }

fun occurs(id: Int, t: InternalType): Bool =
  match (t) {
    TVar(v) => v == id
    TPrim(_) => False
    TArrow(ps, r) => Lst.any(ps, (p: InternalType) => occurs(id, p)) | occurs(id, r)
    TRecord(fields, rowOpt) => {
      val inFields = Lst.any(fields, (f: TypeField) => occurs(id, f.type_))
      if (rowOpt == None)
        inFields
      else
        inFields | occurs(id, Opt.getOrElse(rowOpt, tUnit))
    }
    TApp(_, args) => Lst.any(args, (a: InternalType) => occurs(id, a))
    TTuple(es) => Lst.any(es, (e: InternalType) => occurs(id, e))
    TUnion(l, r) => occurs(id, l) | occurs(id, r)
    TInter(l, r) => occurs(id, l) | occurs(id, r)
    TScheme(vars, body) => if (Lst.any(vars, (v: Int) => v == id)) False else occurs(id, body)
    TNamespace(_) => False
  }

/// Apply substitution and chase variable chains until fixed point.
export fun applySubstFull(subst: Dict<Int, InternalType>, t: InternalType): InternalType =
  match (t) {
    TVar(id) => {
      val found = Dict.get(subst, id)
      if (found == None)
        t
      else {
        val next = Opt.getOrElse(found, t)
        if (next == t) t else applySubstFull(subst, next)
      }
    }
    _ => applySubst(subst, t)
  }

fun bindVar(subst: Dict<Int, InternalType>, id: Int, t: InternalType): Result<Dict<Int, InternalType>, (InternalType, InternalType)> =
  if (t == TVar(id))
    Ok(subst)
  else if (occurs(id, t))
    Err(mkUnifyError(TVar(id), t))
  else
    Ok(Dict.insert(subst, id, t))

fun unifyMany(subst: Dict<Int, InternalType>, left: List<InternalType>, right: List<InternalType>): Result<Dict<Int, InternalType>, (InternalType, InternalType)> =
  match (left) {
    [] =>
      match (right) {
        [] => Ok(subst)
        _ => Err(mkUnifyError(TTuple(left), TTuple(right)))
      }
    lh :: lt =>
      match (right) {
        [] => Err(mkUnifyError(TTuple(left), TTuple(right)))
        rh :: rt =>
          Res.andThen(
            unify(subst, lh, rh),
            (s2: Dict<Int, InternalType>) => unifyMany(s2, lt, rt)
          )
      }
  }

fun unifyRecordFields(
  subst: Dict<Int, InternalType>,
  left: List<TypeField>,
  right: List<TypeField>
): Result<Dict<Int, InternalType>, (InternalType, InternalType)> =
  match (left) {
    [] =>
      match (right) {
        [] => Ok(subst)
        _ => Err(mkUnifyError(TRecord(left, None), TRecord(right, None)))
      }
    lf :: lt =>
      match (right) {
        [] => Err(mkUnifyError(TRecord(left, None), TRecord(right, None)))
        rf :: rt =>
          if (lf.name != rf.name | lf.mut_ != rf.mut_)
            Err(mkUnifyError(TRecord(left, None), TRecord(right, None)))
          else
            Res.andThen(
              unify(subst, lf.type_, rf.type_),
              (s2: Dict<Int, InternalType>) => unifyRecordFields(s2, lt, rt)
            )
      }
  }

/// Expand a generic alias head if present in aliases; otherwise keep application form.
export fun expandGenericAliasHead(
  name: String,
  args: List<InternalType>,
  aliases: Dict<String, InternalType>
): InternalType = {
  val found = Dict.get(aliases, name)
  if (found == None) TApp(name, args) else Opt.getOrElse(found, TApp(name, args))
}

/// Structural unification with occurs check.
export fun unify(subst: Dict<Int, InternalType>, t1: InternalType, t2: InternalType): Result<Dict<Int, InternalType>, (InternalType, InternalType)> = {
  val l = applySubstFull(subst, t1)
  val r = applySubstFull(subst, t2)
  match (l) {
    TVar(id) => bindVar(subst, id, r)
    _ =>
      match (r) {
        TVar(id) => bindVar(subst, id, l)
        _ =>
          match (l) {
            TPrim(a) =>
              match (r) {
                TPrim(b) => if (a == b) Ok(subst) else Err(mkUnifyError(l, r))
                _ => Err(mkUnifyError(l, r))
              }
            TArrow(lp, lr) =>
              match (r) {
                TArrow(rp, rr) =>
                  if (Lst.length(lp) != Lst.length(rp))
                    Err(mkUnifyError(l, r))
                  else
                    Res.andThen(
                      unifyMany(subst, lp, rp),
                      (s2: Dict<Int, InternalType>) => unify(s2, lr, rr)
                    )
                _ => Err(mkUnifyError(l, r))
              }
            TApp(ln, la) =>
              match (r) {
                TApp(rn, ra) =>
                  if (ln != rn | Lst.length(la) != Lst.length(ra))
                    Err(mkUnifyError(l, r))
                  else
                    unifyMany(subst, la, ra)
                _ => Err(mkUnifyError(l, r))
              }
            TTuple(le) =>
              match (r) {
                TTuple(re) =>
                  if (Lst.length(le) != Lst.length(re))
                    Err(mkUnifyError(l, r))
                  else
                    unifyMany(subst, le, re)
                _ => Err(mkUnifyError(l, r))
              }
            TUnion(ll, lr) =>
              match (r) {
                TUnion(rl, rr) => Res.andThen(unify(subst, ll, rl), (s2: Dict<Int, InternalType>) => unify(s2, lr, rr))
                _ => Err(mkUnifyError(l, r))
              }
            TInter(ll, lr) =>
              match (r) {
                TInter(rl, rr) => Res.andThen(unify(subst, ll, rl), (s2: Dict<Int, InternalType>) => unify(s2, lr, rr))
                _ => Err(mkUnifyError(l, r))
              }
            TRecord(lf, lrow) =>
              match (r) {
                TRecord(rf, rrow) => {
                  if (Lst.length(lf) != Lst.length(rf))
                    Err(mkUnifyError(l, r))
                  else
                    Res.andThen(
                      unifyRecordFields(subst, lf, rf),
                      (s2: Dict<Int, InternalType>) =>
                        if (lrow == None & rrow == None)
                          Ok(s2)
                        else if (lrow != None & rrow != None)
                          unify(s2, Opt.getOrElse(lrow, tUnit), Opt.getOrElse(rrow, tUnit))
                        else
                          Err(mkUnifyError(l, r))
                    )
                }
                _ => Err(mkUnifyError(l, r))
              }
            _ => Err(mkUnifyError(l, r))
          }
      }
  }
}

fun fieldTypeByName(fields: List<TypeField>, name: String): Option<InternalType> =
  match (fields) {
    [] => None
    f :: rest => if (f.name == name) Some(f.type_) else fieldTypeByName(rest, name)
  }

fun unifySubtypeFields(subst: Dict<Int, InternalType>, actualFields: List<TypeField>, expectedFields: List<TypeField>): Result<Dict<Int, InternalType>, (InternalType, InternalType)> =
  match (expectedFields) {
    [] => Ok(subst)
    ef :: tail => {
      val got = fieldTypeByName(actualFields, ef.name)
      if (got == None)
        Err(mkUnifyError(TRecord(actualFields, None), TRecord(expectedFields, None)))
      else
        Res.andThen(
          unifySubtype(subst, Opt.getOrElse(got, ef.type_), ef.type_),
          (s2: Dict<Int, InternalType>) => unifySubtypeFields(s2, actualFields, tail)
        )
    }
  }

/// Subtyping-focused unification for record extension and future checker rules.
export fun unifySubtype(subst: Dict<Int, InternalType>, t1: InternalType, t2: InternalType): Result<Dict<Int, InternalType>, (InternalType, InternalType)> = {
  val l = applySubstFull(subst, t1)
  val r = applySubstFull(subst, t2)
  match (l) {
    TRecord(lf, _) =>
      match (r) {
        TRecord(rf, _) => unifySubtypeFields(subst, lf, rf)
        _ => unify(subst, l, r)
      }
    _ => unify(subst, l, r)
  }
}
