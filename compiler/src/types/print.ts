import type { InternalType } from './internal.js';

function typeVarName(id: number, names: Map<number, string>): string {
  const existing = names.get(id);
  if (existing != null) {
    return existing;
  }

  const index = names.size;
  const letter = String.fromCharCode(97 + (index % 26));
  const suffix = Math.floor(index / 26);
  const next = `'${letter}${suffix === 0 ? '' : suffix}`;
  names.set(id, next);
  return next;
}

function printTypeInner(t: InternalType, names: Map<number, string>): string {
  switch (t.kind) {
    case 'var':
      return typeVarName(t.id, names);
    case 'prim':
      return t.name;
    case 'arrow': {
      const params = t.params.map((p) => printTypeInner(p, names)).join(', ');
      return `(${params}) -> ${printTypeInner(t.return, names)}`;
    }
    case 'record': {
      const fields = t.fields
        .map((f) => `${f.mut ? 'mut ' : ''}${f.name}: ${printTypeInner(f.type, names)}`)
        .join(', ');
      if (t.row != null) {
        return `{ ${fields} | ${printTypeInner(t.row, names)} }`;
      }
      return `{ ${fields} }`;
    }
    case 'app': {
      if (t.args.length === 0) {
        return t.name;
      }
      return `${t.name}<${t.args.map((a) => printTypeInner(a, names)).join(', ')}>`;
    }
    case 'tuple':
      return `(${t.elements.map((e) => printTypeInner(e, names)).join(', ')})`;
    case 'union':
      return `${printTypeInner(t.left, names)} | ${printTypeInner(t.right, names)}`;
    case 'inter':
      return `${printTypeInner(t.left, names)} & ${printTypeInner(t.right, names)}`;
    case 'scheme':
      return printTypeInner(t.body, names);
    case 'namespace':
      return 'Namespace';
    default:
      return 'Unknown';
  }
}

export function printType(t: InternalType): string {
  return printTypeInner(t, new Map());
}
