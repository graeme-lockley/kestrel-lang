/**
 * Convert AST Type to InternalType (with fresh vars for unresolved idents).
 */
import type { Type } from '../ast/nodes.js';
import type { InternalType } from './internal.js';
import type { PrimName } from './internal.js';
import { freshVar, prim } from './internal.js';

/** Resolver for namespace-qualified types (e.g. Lib.PublicToken). Returns undefined if not found. */
export type ResolveQualifiedType = (namespace: string, name: string) => InternalType | undefined;

/**
 * Convert AST type to InternalType using a shared scope so the same type variable
 * name (e.g. S in params and return) maps to the same internal var. Used for function signatures.
 */
export function astTypeToInternalWithScope(
  ast: Type,
  scope: Map<string, InternalType>,
  typeAliases?: Map<string, InternalType>,
  resolveQualified?: ResolveQualifiedType
): InternalType {
  switch (ast.kind) {
    case 'PrimType':
      return prim(ast.name as PrimName);
    case 'IdentType': {
      if (ast.name === 'Value') return { kind: 'app', name: 'Value', args: [] };
      const alias = typeAliases?.get(ast.name);
      if (alias != null) return alias;
      let t = scope.get(ast.name);
      if (t == null) {
        t = freshVar();
        scope.set(ast.name, t);
      }
      return t;
    }
    case 'QualifiedType': {
      const resolved = resolveQualified?.(ast.namespace, ast.name);
      if (resolved != null) return resolved;
      return freshVar();
    }
    case 'ArrowType':
      return {
        kind: 'arrow',
        params: ast.params.map((p) => astTypeToInternalWithScope(p, scope, typeAliases, resolveQualified)),
        return: astTypeToInternalWithScope(ast.return, scope, typeAliases, resolveQualified),
      };
    case 'RecordType':
      return {
        kind: 'record',
        fields: ast.fields.map((f) => ({
          name: f.name,
          mut: f.mut,
          type: astTypeToInternalWithScope(f.type, scope, typeAliases, resolveQualified),
        })),
      };
    case 'RowVarType':
      return freshVar();
    case 'AppType':
      return { kind: 'app', name: ast.name, args: ast.args.map((a) => astTypeToInternalWithScope(a, scope, typeAliases, resolveQualified)) };
    case 'UnionType':
      return {
        kind: 'union',
        left: astTypeToInternalWithScope(ast.left, scope, typeAliases, resolveQualified),
        right: astTypeToInternalWithScope(ast.right, scope, typeAliases, resolveQualified),
      };
    case 'InterType':
      return {
        kind: 'inter',
        left: astTypeToInternalWithScope(ast.left, scope, typeAliases, resolveQualified),
        right: astTypeToInternalWithScope(ast.right, scope, typeAliases, resolveQualified),
      };
    case 'TupleType':
      return { kind: 'tuple', elements: ast.elements.map((e) => astTypeToInternalWithScope(e, scope, typeAliases, resolveQualified)) };
    default:
      return freshVar();
  }
}

export function astTypeToInternal(ast: Type, typeAliases?: Map<string, InternalType>, resolveQualified?: ResolveQualifiedType): InternalType {
  switch (ast.kind) {
    case 'PrimType':
      return prim(ast.name as PrimName);
    case 'IdentType':
      if (ast.name === 'Value') return { kind: 'app', name: 'Value', args: [] };
      // Look up user-defined types (including ADTs)
      if (typeAliases && typeAliases.has(ast.name)) {
        return typeAliases.get(ast.name)!;
      }
      return freshVar();
    case 'QualifiedType': {
      const resolved = resolveQualified?.(ast.namespace, ast.name);
      if (resolved != null) return resolved;
      return freshVar();
    }
    case 'ArrowType':
      return {
        kind: 'arrow',
        params: ast.params.map((p) => astTypeToInternal(p, typeAliases, resolveQualified)),
        return: astTypeToInternal(ast.return, typeAliases, resolveQualified),
      };
    case 'RecordType':
      return {
        kind: 'record',
        fields: ast.fields.map((f) => ({
          name: f.name,
          mut: f.mut,
          type: astTypeToInternal(f.type, typeAliases, resolveQualified),
        })),
      };
    case 'RowVarType':
      return freshVar();
    case 'AppType':
      return { kind: 'app', name: ast.name, args: ast.args.map((a) => astTypeToInternal(a, typeAliases, resolveQualified)) };
    case 'UnionType':
      return { kind: 'union', left: astTypeToInternal(ast.left, typeAliases, resolveQualified), right: astTypeToInternal(ast.right, typeAliases, resolveQualified) };
    case 'InterType':
      return { kind: 'inter', left: astTypeToInternal(ast.left, typeAliases, resolveQualified), right: astTypeToInternal(ast.right, typeAliases, resolveQualified) };
    case 'TupleType':
      return { kind: 'tuple', elements: ast.elements.map((e) => astTypeToInternal(e, typeAliases, resolveQualified)) };
    default:
      return freshVar();
  }
}
