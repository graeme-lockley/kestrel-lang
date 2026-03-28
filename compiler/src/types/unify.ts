/**
 * Unification with occurs check (spec 06 §3).
 */
import type { InternalType } from './internal.js';

export class UnifyError extends Error {
  constructor(
    public left: InternalType,
    public right: InternalType,
    message?: string
  ) {
    super(message ?? 'Cannot unify types');
    this.name = 'UnifyError';
  }
}

/** Substitute type variable id with type replacement in t. Returns new type (immutable). */
export function substitute(t: InternalType, id: number, replacement: InternalType): InternalType {
  if (t.kind === 'var' && t.id === id) return replacement;
  if (t.kind === 'prim') return t;
  if (t.kind === 'arrow') {
    return {
      kind: 'arrow',
      params: t.params.map((p) => substitute(p, id, replacement)),
      return: substitute(t.return, id, replacement),
    };
  }
  if (t.kind === 'record') {
    return {
      kind: 'record',
      fields: t.fields.map((f) => ({ ...f, type: substitute(f.type, id, replacement) })),
      row: t.row ? substitute(t.row, id, replacement) : undefined,
    };
  }
  if (t.kind === 'app') {
    return { kind: 'app', name: t.name, args: t.args.map((a) => substitute(a, id, replacement)) };
  }
  if (t.kind === 'tuple') {
    return { kind: 'tuple', elements: t.elements.map((e) => substitute(e, id, replacement)) };
  }
  if (t.kind === 'union') {
    return { kind: 'union', left: substitute(t.left, id, replacement), right: substitute(t.right, id, replacement) };
  }
  if (t.kind === 'inter') {
    return { kind: 'inter', left: substitute(t.left, id, replacement), right: substitute(t.right, id, replacement) };
  }
  if (t.kind === 'scheme') {
    // Don't substitute bound variables
    if (t.vars.includes(id)) return t;
    return { kind: 'scheme', vars: t.vars, body: substitute(t.body, id, replacement) };
  }
  if (t.kind === 'namespace') return t;
  return t;
}

const _applySubstExpanding = new Set<number>();

/** Apply substitution map to t (all var ids in map replaced). */
export function applySubst(t: InternalType, subst: Map<number, InternalType>): InternalType {
  if (t == null) {
    throw new Error('applySubst called with null or undefined type');
  }
  if (t.kind === 'var') {
    const s = subst.get(t.id);
    if (s != null) {
      if (_applySubstExpanding.has(t.id)) return t;
      _applySubstExpanding.add(t.id);
      if (s === undefined) {
        throw new Error('substitution map contains undefined for var id ' + t.id);
      }
      const result = applySubst(s, subst);
      _applySubstExpanding.delete(t.id);
      return result;
    }
    return t;
  }
  if (t.kind === 'prim') return t;
  if (t.kind === 'arrow') {
    return {
      kind: 'arrow',
      params: t.params.map((p) => applySubst(p, subst)),
      return: applySubst(t.return, subst),
    };
  }
  if (t.kind === 'record') {
    return {
      kind: 'record',
      fields: t.fields.map((f) => ({ ...f, type: applySubst(f.type, subst) })),
      row: t.row ? applySubst(t.row, subst) : undefined,
    };
  }
  if (t.kind === 'app') {
    return { kind: 'app', name: t.name, args: t.args.map((a) => applySubst(a, subst)) };
  }
  if (t.kind === 'tuple') {
    return { kind: 'tuple', elements: t.elements.map((e) => applySubst(e, subst)) };
  }
  if (t.kind === 'union') {
    return { kind: 'union', left: applySubst(t.left, subst), right: applySubst(t.right, subst) };
  }
  if (t.kind === 'inter') {
    return { kind: 'inter', left: applySubst(t.left, subst), right: applySubst(t.right, subst) };
  }
  if (t.kind === 'scheme') {
    // Schemes should not appear in unification; they are instantiated first
    return t;
  }
  if (t.kind === 'namespace') return t;
  return t;
}

function occurs(id: number, t: InternalType): boolean {
  if (t.kind === 'var') return t.id === id;
  if (t.kind === 'prim') return false;
  if (t.kind === 'arrow') return t.params.some((p) => occurs(id, p)) || occurs(id, t.return);
  if (t.kind === 'record') {
    const fieldsOccur = t.fields.some((f) => occurs(id, f.type));
    const rowOccurs = t.row ? occurs(id, t.row) : false;
    return fieldsOccur || rowOccurs;
  }
  if (t.kind === 'app') return t.args.some((a) => occurs(id, a));
  if (t.kind === 'tuple') return t.elements.some((e) => occurs(id, e));
  if (t.kind === 'union') return occurs(id, t.left) || occurs(id, t.right);
  if (t.kind === 'inter') return occurs(id, t.left) || occurs(id, t.right);
  if (t.kind === 'scheme') {
    // Don't check bound variables
    if (t.vars.includes(id)) return false;
    return occurs(id, t.body);
  }
  if (t.kind === 'namespace') return false;
  return false;
}

/** Generic type aliases: expand `App(name, args)` to body during unification (and field access). */
export type GenericTypeAliasDefs = Map<string, { paramVarIds: number[]; body: InternalType }>;

function expandGenericAliasAppOnce(
  t: InternalType,
  subst: Map<number, InternalType>,
  defs: GenericTypeAliasDefs | undefined
): InternalType {
  if (defs == null || t.kind !== 'app') return t;
  const def = defs.get(t.name);
  if (!def || def.paramVarIds.length !== t.args.length) return t;
  const m = new Map<number, InternalType>();
  for (let i = 0; i < def.paramVarIds.length; i++) {
    m.set(def.paramVarIds[i]!, applySubst(t.args[i]!, subst));
  }
  return applySubst(def.body, m);
}

/** Apply substitution then expand generic alias heads (up to two layers). */
export function expandGenericAliasHead(
  t: InternalType,
  subst: Map<number, InternalType>,
  defs: GenericTypeAliasDefs | undefined
): InternalType {
  let a = applySubst(t, subst);
  a = expandGenericAliasAppOnce(a, subst, defs);
  a = expandGenericAliasAppOnce(a, subst, defs);
  return a;
}

/** How arrow types combine in a unification (call vs fun body use different variance). */
export type UnifyArrowMode = 'symmetric' | 'call' | 'fun_check';

export type UnifyOptions = {
  arrowMode?: UnifyArrowMode;
};

function cloneSubstMap(subst: Map<number, InternalType>): Map<number, InternalType> {
  return new Map(subst);
}

function copySubstInto(target: Map<number, InternalType>, from: Map<number, InternalType>): void {
  target.clear();
  for (const [k, v] of from) target.set(k, v);
}

/**
 * Subtyping check for inference: `actual` must be assignable to `expected` (spec 06 §1, §4).
 * Union on the expected side: any arm; union on the actual side: every arm; intersection on
 * expected: actual must match each conjunct; function types use contravariant parameters and
 * covariant return.
 */
export function unifySubtype(
  actual: InternalType,
  expected: InternalType,
  subst: Map<number, InternalType>,
  genericAliases?: GenericTypeAliasDefs
): void {
  if (actual == null || expected == null) {
    throw new Error('unifySubtype called with null or undefined type');
  }
  const a = expandGenericAliasHead(actual, subst, genericAliases);
  const e = expandGenericAliasHead(expected, subst, genericAliases);

  if (e.kind === 'inter') {
    unifySubtype(a, e.left, subst, genericAliases);
    unifySubtype(a, e.right, subst, genericAliases);
    return;
  }
  if (a.kind === 'inter') {
    unifySubtype(a.left, e, subst, genericAliases);
    unifySubtype(a.right, e, subst, genericAliases);
    return;
  }
  if (e.kind === 'union') {
    const saved = cloneSubstMap(subst);
    try {
      unifySubtype(a, e.left, subst, genericAliases);
      return;
    } catch (err) {
      if (!(err instanceof UnifyError)) throw err;
      copySubstInto(subst, saved);
      unifySubtype(a, e.right, subst, genericAliases);
      return;
    }
  }
  if (a.kind === 'union') {
    unifySubtype(a.left, e, subst, genericAliases);
    unifySubtype(a.right, e, subst, genericAliases);
    return;
  }

  if (a.kind === 'var') {
    if (e.kind === 'var' && e.id === a.id) return;
    if (occurs(a.id, e)) {
      subst.set(a.id, e);
      return;
    }
    subst.set(a.id, e);
    return;
  }
  if (e.kind === 'var') {
    if (occurs(e.id, a)) {
      subst.set(e.id, a);
      return;
    }
    subst.set(e.id, a);
    return;
  }

  if (a.kind === 'arrow' && e.kind === 'arrow') {
    if (a.params.length !== e.params.length) throw new UnifyError(actual, expected);
    for (let i = 0; i < a.params.length; i++) {
      unifySubtype(e.params[i]!, a.params[i]!, subst, genericAliases);
    }
    unifySubtype(a.return, e.return, subst, genericAliases);
    return;
  }

  if (a.kind === 'namespace' || e.kind === 'namespace') {
    throw new UnifyError(actual, expected, 'Namespace type cannot be unified with value type');
  }

  unify(actual, expected, subst, genericAliases, undefined);
}

/**
 * Unify two types; mutates subst. On success, after return, applySubst(left, subst) === applySubst(right, subst).
 */
export function unify(
  left: InternalType,
  right: InternalType,
  subst: Map<number, InternalType>,
  genericAliases?: GenericTypeAliasDefs,
  options?: UnifyOptions
): void {
  if (left == null || right == null) {
    throw new Error('unify called with null or undefined type');
  }
  const l = expandGenericAliasHead(left, subst, genericAliases);
  const r = expandGenericAliasHead(right, subst, genericAliases);

  if (l.kind === 'var') {
    if (r.kind === 'var' && r.id === l.id) return;
    if (occurs(l.id, r)) {
      // Allow equi-recursive types: just bind without occurs check
      subst.set(l.id, r);
      return;
    }
    subst.set(l.id, r);
    return;
  }
  if (r.kind === 'var') {
    if (occurs(r.id, l)) {
      subst.set(r.id, l);
      return;
    }
    subst.set(r.id, l);
    return;
  }

  if (l.kind === 'prim' && r.kind === 'prim') {
    if (l.name !== r.name) throw new UnifyError(left, right);
    return;
  }
  if (l.kind === 'arrow' && r.kind === 'arrow') {
    if (l.params.length !== r.params.length) throw new UnifyError(left, right);
    const arrowMode = options?.arrowMode ?? 'symmetric';
    if (arrowMode === 'call') {
      // Prefer symmetric unification for parameters so polymorphic calls (e.g. eq's two X args)
      // share one type variable correctly; fall back to subtyping so Int can match Int|Bool.
      for (let i = 0; i < l.params.length; i++) {
        try {
          unify(l.params[i]!, r.params[i]!, subst, genericAliases, undefined);
        } catch (err) {
          if (!(err instanceof UnifyError)) throw err;
          unifySubtype(r.params[i]!, l.params[i]!, subst, genericAliases);
        }
      }
      try {
        unify(l.return, r.return, subst, genericAliases, undefined);
      } catch (err) {
        if (!(err instanceof UnifyError)) throw err;
        const calleeRet = applySubst(l.return, subst);
        const retSynth = r.return;
        if (
          retSynth.kind === 'var' &&
          (calleeRet.kind === 'union' || calleeRet.kind === 'inter')
        ) {
          subst.set(retSynth.id, calleeRet);
        } else {
          unifySubtype(r.return, l.return, subst, genericAliases);
        }
      }
      return;
    }
    if (arrowMode === 'fun_check') {
      // Parameter types must match exactly; subtype only at the outer function's body return.
      for (let i = 0; i < l.params.length; i++) {
        unify(l.params[i]!, r.params[i]!, subst, genericAliases, undefined);
      }
      unifySubtype(l.return, r.return, subst, genericAliases);
      return;
    }
    for (let i = 0; i < l.params.length; i++) {
      unify(l.params[i]!, r.params[i]!, subst, genericAliases, options);
    }
    unify(l.return, r.return, subst, genericAliases, options);
    return;
  }
  if (l.kind === 'tuple' && r.kind === 'tuple') {
    if (l.elements.length !== r.elements.length) throw new UnifyError(left, right);
    for (let i = 0; i < l.elements.length; i++) {
      unify(l.elements[i]!, r.elements[i]!, subst, genericAliases, options);
    }
    return;
  }
  if (l.kind === 'app' && r.kind === 'app') {
    if (l.name !== r.name || l.args.length !== r.args.length) throw new UnifyError(left, right);
    for (let i = 0; i < l.args.length; i++) {
      unify(l.args[i]!, r.args[i]!, subst, genericAliases, options);
    }
    return;
  }

  if (l.kind === 'record' && r.kind === 'record') {
    // Row polymorphism: unify records field by field
    // Algorithm:
    // 1. Find common fields and unify their types
    // 2. Handle remaining fields via row variables

    const lFields = new Map(l.fields.map(f => [f.name, f]));
    const rFields = new Map(r.fields.map(f => [f.name, f]));

    // Unify common fields
    for (const [name, lField] of lFields) {
      const rField = rFields.get(name);
      if (rField) {
        // Common field - must have same mutability
        if (lField.mut !== rField.mut) {
          throw new UnifyError(left, right, `Field '${name}' mutability mismatch`);
        }
        // Unify field types
        unify(lField.type, rField.type, subst, genericAliases, options);
      }
    }

    // Handle extra fields via row variables
    const lOnly = l.fields.filter(f => !rFields.has(f.name));
    const rOnly = r.fields.filter(f => !lFields.has(f.name));

    // If l has extra fields, they must be absorbed by r's row variable
    if (lOnly.length > 0) {
      if (!r.row) {
        throw new UnifyError(left, right, `Record missing fields: ${lOnly.map(f => f.name).join(', ')}`);
      }
      // Unify r's row with a record containing l's extra fields
      const lExtra: InternalType = { kind: 'record', fields: lOnly, row: l.row };
      unify(r.row, lExtra, subst, genericAliases, options);
      return;
    }

    // If r has extra fields, they must be absorbed by l's row variable
    if (rOnly.length > 0) {
      if (!l.row) {
        throw new UnifyError(left, right, `Record missing fields: ${rOnly.map(f => f.name).join(', ')}`);
      }
      // Unify l's row with a record containing r's extra fields
      const rExtra: InternalType = { kind: 'record', fields: rOnly, row: r.row };
      unify(l.row, rExtra, subst, genericAliases, options);
      return;
    }

    // Both have same fields, unify row variables if present
    if (l.row && r.row) {
      unify(l.row, r.row, subst, genericAliases, options);
    } else if (l.row && !r.row) {
      // l's row must be empty (closed record)
      const emptyRow: InternalType = { kind: 'record', fields: [] };
      unify(l.row, emptyRow, subst, genericAliases, options);
    } else if (!l.row && r.row) {
      // r's row must be empty (closed record)
      const emptyRow: InternalType = { kind: 'record', fields: [] };
      unify(r.row, emptyRow, subst, genericAliases, options);
    }
    // else both closed records with same fields - success
    return;
  }

  if (l.kind === 'namespace' || r.kind === 'namespace') {
    throw new UnifyError(left, right, 'Namespace type cannot be unified with value type');
  }

  throw new UnifyError(left, right);
}
