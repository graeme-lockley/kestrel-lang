//! AST type-expression conversion for the self-hosted type checker.
//!
//! Converts parser-level `AstType` nodes into checker `InternalType` values
//! using a caller-provided scope for type variables and aliases.
import * as Dict from "kestrel:data/dict"
import * as Lst from "kestrel:data/list"
import * as Opt from "kestrel:data/option"
import * as Ast from "kestrel:dev/parser/ast"
import * as Ty from "kestrel:dev/typecheck/types"

fun lookupOrFresh(scope: Dict<String, Ty.InternalType>, name: String): Ty.InternalType = {
  val found = Dict.get(scope, name)
  if (found == None) Ty.freshVar() else Opt.getOrElse(found, Ty.freshVar())
}

/// Convert a parsed type node into an `InternalType` using `scope`.
///
/// Resolution rules:
///
/// - primitive nodes map to the corresponding `TPrim`
/// - identifiers resolve via `scope`, falling back to fresh vars
/// - qualified names map to `TApp("Ns.Name", [])`
/// - arrow, record, app, union/intersection, and tuple recurse structurally
/// - unsupported/unexpected forms fall back to a fresh type variable
export fun astTypeToInternalWithScope(
  node: Ast.AstType,
  scope: Dict<String, Ty.InternalType>,
  _typeParams: List<String>
): Ty.InternalType = {
  val tag = Ast.astTypeTag(node)
  if (tag == "prim") {
    Ty.prim(Opt.getOrElse(Ast.astTypePrimName(node), "Unit"))
  } else if (tag == "ident") {
    lookupOrFresh(scope, Opt.getOrElse(Ast.astTypeIdentName(node), "_"))
  } else if (tag == "qualified") {
    val q = Opt.getOrElse(Ast.astTypeQualifiedParts(node), ("", ""))
    Ty.TApp("${q.0}.${q.1}", [])
  } else if (tag == "arrow") {
    val ar = Opt.getOrElse(Ast.astTypeArrowParts(node), ([], Ast.ATPrim("Unit")))
    val params = Lst.map(ar.0, (p: Ast.AstType) => astTypeToInternalWithScope(p, scope, _typeParams))
    val ret = astTypeToInternalWithScope(ar.1, scope, _typeParams)
    Ty.TArrow(params, ret)
  } else if (tag == "record") {
    val fs = Opt.getOrElse(Ast.astTypeRecordFields(node), [])
    Ty.TRecord(
      Lst.map(fs, (f: Ast.TypeField) => {
        name = f.name,
        mut_ = f.mut_,
        type_ = astTypeToInternalWithScope(f.type_, scope, _typeParams)
      }),
      None
    )
  } else if (tag == "rowvar") {
    Ty.freshVar()
  } else if (tag == "app") {
    val ap = Opt.getOrElse(Ast.astTypeAppParts(node), ("", []))
    Ty.TApp(ap.0, Lst.map(ap.1, (a: Ast.AstType) => astTypeToInternalWithScope(a, scope, _typeParams)))
  } else if (tag == "union") {
    val u = Opt.getOrElse(Ast.astTypeUnionParts(node), (Ast.ATPrim("Unit"), Ast.ATPrim("Unit")))
    Ty.TUnion(
      astTypeToInternalWithScope(u.0, scope, _typeParams),
      astTypeToInternalWithScope(u.1, scope, _typeParams)
    )
  } else if (tag == "inter") {
    val i = Opt.getOrElse(Ast.astTypeInterParts(node), (Ast.ATPrim("Unit"), Ast.ATPrim("Unit")))
    Ty.TInter(
      astTypeToInternalWithScope(i.0, scope, _typeParams),
      astTypeToInternalWithScope(i.1, scope, _typeParams)
    )
  } else if (tag == "tuple") {
    val es = Opt.getOrElse(Ast.astTypeTupleElements(node), [])
    Ty.TTuple(Lst.map(es, (e: Ast.AstType) => astTypeToInternalWithScope(e, scope, _typeParams)))
  } else {
    Ty.freshVar()
  }
}

/// Convert a parsed type node with no extra type-parameter context.
///
/// Convenience wrapper over `astTypeToInternalWithScope`.
export fun astTypeToInternal(node: Ast.AstType, scope: Dict<String, Ty.InternalType>): Ty.InternalType =
  astTypeToInternalWithScope(node, scope, [])
