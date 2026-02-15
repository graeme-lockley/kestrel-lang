/**
 * Convert AST Type to InternalType (with fresh vars for unresolved idents).
 */
import type { Type } from '../ast/nodes.js';
import type { InternalType } from './internal.js';
import type { PrimName } from './internal.js';
import { freshVar, prim } from './internal.js';

/**
 * Convert AST type to InternalType using a shared scope so the same type variable
 * name (e.g. S in params and return) maps to the same internal var. Used for function signatures.
 */
export function astTypeToInternalWithScope(
  ast: Type,
  scope: Map<string, InternalType>
): InternalType {
  switch (ast.kind) {
    case 'PrimType':
      return prim(ast.name as PrimName);
    case 'IdentType': {
      if (ast.name === 'Value') return { kind: 'app', name: 'Value', args: [] };
      let t = scope.get(ast.name);
      if (t == null) {
        t = freshVar();
        scope.set(ast.name, t);
      }
      return t;
    }
    case 'ArrowType':
      return {
        kind: 'arrow',
        params: ast.params.map((p) => astTypeToInternalWithScope(p, scope)),
        return: astTypeToInternalWithScope(ast.return, scope),
      };
    case 'RecordType':
      return {
        kind: 'record',
        fields: ast.fields.map((f) => ({
          name: f.name,
          mut: f.mut,
          type: astTypeToInternalWithScope(f.type, scope),
        })),
      };
    case 'RowVarType':
      return freshVar();
    case 'AppType':
      return { kind: 'app', name: ast.name, args: ast.args.map((a) => astTypeToInternalWithScope(a, scope)) };
    case 'UnionType':
      return {
        kind: 'union',
        left: astTypeToInternalWithScope(ast.left, scope),
        right: astTypeToInternalWithScope(ast.right, scope),
      };
    case 'InterType':
      return {
        kind: 'inter',
        left: astTypeToInternalWithScope(ast.left, scope),
        right: astTypeToInternalWithScope(ast.right, scope),
      };
    case 'TupleType':
      return { kind: 'tuple', elements: ast.elements.map((e) => astTypeToInternalWithScope(e, scope)) };
    default:
      return freshVar();
  }
}

export function astTypeToInternal(ast: Type): InternalType {
  switch (ast.kind) {
    case 'PrimType':
      return prim(ast.name as PrimName);
    case 'IdentType':
      if (ast.name === 'Value') return { kind: 'app', name: 'Value', args: [] };
      return freshVar();
    case 'ArrowType':
      return {
        kind: 'arrow',
        params: ast.params.map(astTypeToInternal),
        return: astTypeToInternal(ast.return),
      };
    case 'RecordType':
      return {
        kind: 'record',
        fields: ast.fields.map((f) => ({
          name: f.name,
          mut: f.mut,
          type: astTypeToInternal(f.type),
        })),
      };
    case 'RowVarType':
      return freshVar();
    case 'AppType':
      return { kind: 'app', name: ast.name, args: ast.args.map(astTypeToInternal) };
    case 'UnionType':
      return { kind: 'union', left: astTypeToInternal(ast.left), right: astTypeToInternal(ast.right) };
    case 'InterType':
      return { kind: 'inter', left: astTypeToInternal(ast.left), right: astTypeToInternal(ast.right) };
    case 'TupleType':
      return { kind: 'tuple', elements: ast.elements.map(astTypeToInternal) };
    default:
      return freshVar();
  }
}
