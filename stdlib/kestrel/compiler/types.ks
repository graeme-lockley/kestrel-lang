import * as Dict from "kestrel:data/dict"
import * as Lst from "kestrel:data/list"
import * as Opt from "kestrel:data/option"

export type TypeField = { name: String, mut_: Bool, type_: InternalType }

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

val counter = { mut nextVarId = 0 }

export fun freshVar(): InternalType = {
  val out = TVar(counter.nextVarId)
  counter.nextVarId := counter.nextVarId + 1;
  out
}

export fun resetVarId(): Unit = {
  counter.nextVarId := 0;
  ()
}

export fun prim(name: String): InternalType = TPrim(name)

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
