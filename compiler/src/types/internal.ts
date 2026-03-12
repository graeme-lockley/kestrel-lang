/**
 * Internal type representation for inference (spec 06).
 * Type variables for unification; row vars in progress.
 */
export type InternalType =
  | { kind: 'var'; id: number }
  | { kind: 'prim'; name: 'Int' | 'Float' | 'Bool' | 'String' | 'Unit' | 'Char' | 'Rune' }
  | { kind: 'arrow'; params: InternalType[]; return: InternalType }
  | { kind: 'record'; fields: { name: string; mut: boolean; type: InternalType }[]; row?: InternalType }
  | { kind: 'app'; name: string; args: InternalType[] }
  | { kind: 'tuple'; elements: InternalType[] }
  | { kind: 'union'; left: InternalType; right: InternalType }
  | { kind: 'inter'; left: InternalType; right: InternalType }
  | { kind: 'scheme'; vars: number[]; body: InternalType }
  | { kind: 'namespace'; bindings: Map<string, InternalType> };

let nextVarId = 0;
export function freshVar(): InternalType {
  return { kind: 'var', id: nextVarId++ };
}
export function resetVarId(): void {
  nextVarId = 0;
}

export type PrimName = 'Int' | 'Float' | 'Bool' | 'String' | 'Unit' | 'Char' | 'Rune';
export function prim(name: PrimName): InternalType {
  return { kind: 'prim', name };
}

export const tInt = prim('Int');
export const tFloat = prim('Float');
export const tBool = prim('Bool');
export const tString = prim('String');
export const tUnit = prim('Unit');

/**
 * Collect all free type variables in a type.
 */
export function freeVars(t: InternalType, bound: Set<number> = new Set()): Set<number> {
  if (t.kind === 'var') {
    return bound.has(t.id) ? new Set() : new Set([t.id]);
  }
  if (t.kind === 'prim') return new Set();
  if (t.kind === 'arrow') {
    const free = new Set<number>();
    for (const p of t.params) {
      for (const v of freeVars(p, bound)) free.add(v);
    }
    for (const v of freeVars(t.return, bound)) free.add(v);
    return free;
  }
  if (t.kind === 'record') {
    const free = new Set<number>();
    for (const f of t.fields) {
      for (const v of freeVars(f.type, bound)) free.add(v);
    }
    if (t.row) {
      for (const v of freeVars(t.row, bound)) free.add(v);
    }
    return free;
  }
  if (t.kind === 'app') {
    const free = new Set<number>();
    for (const a of t.args) {
      for (const v of freeVars(a, bound)) free.add(v);
    }
    return free;
  }
  if (t.kind === 'tuple') {
    const free = new Set<number>();
    for (const e of t.elements) {
      for (const v of freeVars(e, bound)) free.add(v);
    }
    return free;
  }
  if (t.kind === 'union' || t.kind === 'inter') {
    const free = new Set<number>();
    for (const v of freeVars(t.left, bound)) free.add(v);
    for (const v of freeVars(t.right, bound)) free.add(v);
    return free;
  }
  if (t.kind === 'scheme') {
    const newBound = new Set([...bound, ...t.vars]);
    return freeVars(t.body, newBound);
  }
  if (t.kind === 'namespace') return new Set();
  return new Set();
}

/**
 * Generalize a type: quantify all free variables not in environment.
 */
export function generalize(t: InternalType, envVars: Set<number>): InternalType {
  const free = freeVars(t);
  const toQuantify = [...free].filter((v) => !envVars.has(v));
  if (toQuantify.length === 0) return t;
  return { kind: 'scheme', vars: toQuantify, body: t };
}

/**
 * Instantiate a type scheme: replace quantified variables with fresh ones.
 */
export function instantiate(t: InternalType): InternalType {
  if (t.kind !== 'scheme') return t;
  const subst = new Map<number, InternalType>();
  for (const v of t.vars) {
    subst.set(v, freshVar());
  }
  return substituteMany(t.body, subst);
}

function substituteMany(t: InternalType, subst: Map<number, InternalType>): InternalType {
  if (t.kind === 'var') {
    const s = subst.get(t.id);
    return s ?? t;
  }
  if (t.kind === 'prim') return t;
  if (t.kind === 'arrow') {
    return {
      kind: 'arrow',
      params: t.params.map((p) => substituteMany(p, subst)),
      return: substituteMany(t.return, subst),
    };
  }
  if (t.kind === 'record') {
    return {
      kind: 'record',
      fields: t.fields.map((f) => ({ ...f, type: substituteMany(f.type, subst) })),
      row: t.row ? substituteMany(t.row, subst) : undefined,
    };
  }
  if (t.kind === 'app') {
    return { kind: 'app', name: t.name, args: t.args.map((a) => substituteMany(a, subst)) };
  }
  if (t.kind === 'tuple') {
    return { kind: 'tuple', elements: t.elements.map((e) => substituteMany(e, subst)) };
  }
  if (t.kind === 'union') {
    return { kind: 'union', left: substituteMany(t.left, subst), right: substituteMany(t.right, subst) };
  }
  if (t.kind === 'inter') {
    return { kind: 'inter', left: substituteMany(t.left, subst), right: substituteMany(t.right, subst) };
  }
  if (t.kind === 'scheme') {
    return t; // Should not happen in well-formed types
  }
  if (t.kind === 'namespace') return t;
  return t;
}
