/**
 * Convert AST Type to InternalType (with fresh vars for unresolved idents).
 */
import type { Type } from '../ast/nodes.js';
import type { InternalType } from './internal.js';
import type { PrimName } from './internal.js';
import { freshVar, prim } from './internal.js';

export function astTypeToInternal(ast: Type): InternalType {
  switch (ast.kind) {
    case 'PrimType':
      return prim(ast.name as PrimName);
    case 'IdentType':
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
