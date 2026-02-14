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
  return t;
}

/** Apply substitution map to t (all var ids in map replaced). */
export function applySubst(t: InternalType, subst: Map<number, InternalType>): InternalType {
  if (t.kind === 'var') {
    const s = subst.get(t.id);
    if (s != null) return applySubst(s, subst);
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
  return false;
}

/**
 * Unify two types; mutates subst. On success, after return, applySubst(left, subst) === applySubst(right, subst).
 */
export function unify(left: InternalType, right: InternalType, subst: Map<number, InternalType>): void {
  const l = applySubst(left, subst);
  const r = applySubst(right, subst);

  if (l.kind === 'var') {
    if (r.kind === 'var' && r.id === l.id) return;
    if (occurs(l.id, r)) throw new UnifyError(left, right, 'Occurs check failed');
    subst.set(l.id, r);
    return;
  }
  if (r.kind === 'var') {
    if (occurs(r.id, l)) throw new UnifyError(left, right, 'Occurs check failed');
    subst.set(r.id, l);
    return;
  }

  if (l.kind === 'prim' && r.kind === 'prim') {
    if (l.name !== r.name) throw new UnifyError(left, right);
    return;
  }
  if (l.kind === 'arrow' && r.kind === 'arrow') {
    if (l.params.length !== r.params.length) throw new UnifyError(left, right);
    for (let i = 0; i < l.params.length; i++) unify(l.params[i]!, r.params[i]!, subst);
    unify(l.return, r.return, subst);
    return;
  }
  if (l.kind === 'tuple' && r.kind === 'tuple') {
    if (l.elements.length !== r.elements.length) throw new UnifyError(left, right);
    for (let i = 0; i < l.elements.length; i++) unify(l.elements[i]!, r.elements[i]!, subst);
    return;
  }
  if (l.kind === 'app' && r.kind === 'app') {
    if (l.name !== r.name || l.args.length !== r.args.length) throw new UnifyError(left, right);
    for (let i = 0; i < l.args.length; i++) unify(l.args[i]!, r.args[i]!, subst);
    return;
  }

  throw new UnifyError(left, right);
}
