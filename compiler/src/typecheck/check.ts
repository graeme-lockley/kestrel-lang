/**
 * Type-checker: infer types and unify (spec 06). With generalization and instantiation.
 */
import type { Program, Expr, TopLevelDecl, TopLevelStmt } from '../ast/nodes.js';
import type { InternalType } from '../types/internal.js';
import { freshVar, prim, tInt, tFloat, tBool, tString, tUnit, resetVarId, freeVars, generalize, instantiate } from '../types/internal.js';
import { astTypeToInternal, astTypeToInternalWithScope } from '../types/from-ast.js';
import type { ResolveQualifiedType } from '../types/from-ast.js';
import { unify, unifySubtype, applySubst, UnifyError, expandGenericAliasHead } from '../types/unify.js';
import type { UnifyArrowMode } from '../types/unify.js';
import type { Diagnostic } from '../diagnostics/types.js';
import { CODES, locationFromSpan, locationFileOnly } from '../diagnostics/types.js';
import type { Span } from '../lexer/types.js';

const TypedExpr = Symbol('inferredType');
declare module '../ast/nodes.js' {
  interface NodeBase {
    [TypedExpr]?: InternalType;
  }
}

export function setInferredType(node: { span?: unknown }, t: InternalType): void {
  (node as Record<symbol, InternalType>)[TypedExpr] = t;
}
export function getInferredType(node: { span?: unknown }): InternalType | undefined {
  return (node as Record<symbol, InternalType>)[TypedExpr];
}

/** Populated while typechecking `IsExpr`; read by codegen for lowering. */
const narrowingByIsExpr = new WeakMap<
  import('../ast/nodes.js').IsExpr,
  { bindingName: string; narrowed: InternalType }
>();

export function getNarrowingFromIsCond(cond: Expr): { bindingName: string; narrowed: InternalType } | undefined {
  if (cond.kind === 'IsExpr') return narrowingByIsExpr.get(cond);
  return undefined;
}

export class TypeCheckError extends Error {
  constructor(
    message: string,
    public node?: unknown,
    public suggestion?: string,
    public diagnosticCode?: string
  ) {
    super(message);
    this.name = 'TypeCheckError';
  }
}

/** Snapshot of a dependency module’s public exports (after its typecheck). Used for re-exports (07 §3). */
export interface DependencyExportSnapshot {
  exports: Map<string, InternalType>;
  exportedTypeAliases: Map<string, InternalType>;
  exportedConstructors: Map<string, InternalType>;
  exportedTypeVisibility: Map<string, 'local' | 'opaque' | 'export'>;
}

export interface TypecheckOptions {
  /** Import bindings (localName -> type) to add to scope before typechecking. */
  importBindings?: Map<string, InternalType>;
  /** Imported type aliases (localName -> type) to resolve in function signatures. */
  typeAliasBindings?: Map<string, InternalType>;
  /** Names of imported types that are opaque (cannot construct or pattern-match). */
  importOpaqueTypes?: Set<string>;
  /** Source file path for diagnostics (spec 10). */
  sourceFile?: string;
  /** Source content for endLine/endColumn in diagnostics. */
  sourceContent?: string;
  /** Per-specifier export maps for resolved dependencies (re-export merge + conflicts). */
  dependencyExportsBySpec?: Map<string, DependencyExportSnapshot>;
}

export function typecheck(program: Program, options?: TypecheckOptions): {
  ok: true;
  exports: Map<string, InternalType>;
  exportedTypeAliases: Map<string, InternalType>;
  exportedTypeVisibility: Map<string, 'local' | 'opaque' | 'export'>;
  exportedConstructors: Map<string, InternalType>;
  reexports: { exportName: string; spec: string; external: string }[];
} | { ok: false; diagnostics: Diagnostic[] } {
  resetVarId();
  const diagnostics: Diagnostic[] = [];
  const subst = new Map<number, InternalType>();
  const env = new Map<string, InternalType>();
  const typeAliases = new Map<string, InternalType>();
  /** Generic type aliases (e.g. `type Dict<K,V> = { ... }`): expand `App` to body for unify / field access. */
  const genericTypeAliasDefs = new Map<string, { paramVarIds: number[]; body: InternalType }>();
  const adtConstructors = new Map<string, { name: string; arity: number }[]>();
  /** Exported ADT constructor names -> type scheme (for namespace importers). */
  const exportedConstructors = new Map<string, InternalType>();
  const opaqueTypes = new Set<string>();
  const exportedTypeVisibility = new Map<string, 'local' | 'opaque' | 'export'>();
  let loopDepth = 0;
  const sourceFile = options?.sourceFile ?? '';
  const sourceContent = options?.sourceContent;
  /** Current expression for UnifyError location (spec 10). */
  let currentExpr: Expr | undefined;

  function locFor(node: unknown): { file: string; line: number; column: number; offset?: number; endOffset?: number; endLine?: number; endColumn?: number } {
    const span = (node as { span?: Span })?.span;
    if (span) return locationFromSpan(sourceFile, span, sourceContent);
    return locationFileOnly(sourceFile);
  }

  /** Call unify or subtype-unify; on UnifyError attach blameNode (and optional relatedNode) for diagnostics. */
  function unifyWithBlame(
    left: InternalType,
    right: InternalType,
    blameNode: unknown,
    relatedNode?: unknown,
    unification?: { relation?: 'eq' | 'subtype'; arrowMode?: UnifyArrowMode }
  ): void {
    if (left == null || right == null) {
      const which = left == null ? 'left' : 'right';
      throw new TypeCheckError(
        `Internal error: unify ${which} is null or undefined`,
        blameNode && typeof blameNode === 'object' && 'span' in blameNode ? blameNode : undefined
      );
    }
    try {
      if (unification?.relation === 'subtype') {
        unifySubtype(left, right, subst, genericTypeAliasDefs);
      } else {
        unify(left, right, subst, genericTypeAliasDefs, { arrowMode: unification?.arrowMode });
      }
    } catch (e) {
      if (e instanceof UnifyError) {
        const err = e as UnifyError & { blameNode?: unknown; relatedNode?: unknown };
        err.blameNode = blameNode;
        if (relatedNode !== undefined) err.relatedNode = relatedNode;
      }
      throw e;
    }
  }

  // Add import bindings first (so they can be used in the module)
  const importBindings = options?.importBindings;
  if (importBindings) {
    for (const [name, t] of importBindings) env.set(name, t);
  }

  // Add imported type aliases so they resolve in function signatures
  const typeAliasBindings = options?.typeAliasBindings;
  if (typeAliasBindings) {
    for (const [name, t] of typeAliasBindings) {
      typeAliases.set(name, t);
      env.set(name, t);
    }
  }

  // Add imported opaque types - these restrict constructor access from other modules
  const importOpaqueTypes = options?.importOpaqueTypes;
  if (importOpaqueTypes) {
    for (const name of importOpaqueTypes) {
      opaqueTypes.add(name);
    }
  }

  const resolveQualified: ResolveQualifiedType = (ns, name) => {
    const t = env.get(ns);
    if (t && t.kind === 'namespace') {
      const b = t.bindings.get(name);
      if (b != null) return instantiate(b);
    }
    return undefined;
  };

  const builtinTypeNames = new Set(['Int', 'Float', 'Bool', 'String', 'Unit', 'Char', 'Rune', 'Array', 'Task', 'Option', 'Result', 'List']);

  function assertKnownTypeNames(
    ast: import('../ast/nodes.js').Type,
    blameNode: unknown,
    localTypeParams?: Set<string>
  ): void {
    switch (ast.kind) {
      case 'PrimType':
        return;
      case 'IdentType':
        if (builtinTypeNames.has(ast.name) || typeAliases.has(ast.name) || localTypeParams?.has(ast.name)) return;
        throw new TypeCheckError(`Unknown type: ${ast.name}`, blameNode);
      case 'QualifiedType':
        if (resolveQualified(ast.namespace, ast.name) != null) return;
        throw new TypeCheckError(`Unknown qualified type: ${ast.namespace}.${ast.name}`, blameNode);
      case 'ArrowType':
        for (const p of ast.params) assertKnownTypeNames(p, blameNode, localTypeParams);
        assertKnownTypeNames(ast.return, blameNode, localTypeParams);
        return;
      case 'RecordType':
        for (const f of ast.fields) assertKnownTypeNames(f.type, blameNode, localTypeParams);
        return;
      case 'AppType':
        if (!(builtinTypeNames.has(ast.name) || typeAliases.has(ast.name) || localTypeParams?.has(ast.name))) {
          throw new TypeCheckError(`Unknown type: ${ast.name}`, blameNode);
        }
        for (const a of ast.args) assertKnownTypeNames(a, blameNode, localTypeParams);
        return;
      case 'UnionType':
      case 'InterType':
        assertKnownTypeNames(ast.left, blameNode, localTypeParams);
        assertKnownTypeNames(ast.right, blameNode, localTypeParams);
        return;
      case 'TupleType':
        for (const e of ast.elements) assertKnownTypeNames(e, blameNode, localTypeParams);
        return;
      case 'RowVarType':
        return;
    }
  }

  // Add builtin primitives to environment (variadic: ≥1 arg, Unit)
  // print / println: typechecked at call site as (T1, T2, ...) -> Unit with args.length >= 1
  const printTypeVar = freshVar();
  env.set('print', generalize({
    kind: 'arrow',
    params: [printTypeVar],
    return: { kind: 'prim', name: 'Unit' }
  }, new Set()));
  env.set('println', generalize({
    kind: 'arrow',
    params: [printTypeVar],
    return: { kind: 'prim', name: 'Unit' }
  }, new Set()));
  env.set('exit', generalize({
    kind: 'arrow',
    params: [tInt],
    return: { kind: 'prim', name: 'Unit' },
  }, new Set()));

  // Built-in ADT constructors (Option, Result) so they type-check without import
  const optT = freshVar();
  env.set('None', generalize({ kind: 'app', name: 'Option', args: [optT] }, new Set()));
  const someT = freshVar();
  env.set('Some', generalize({
    kind: 'arrow',
    params: [someT],
    return: { kind: 'app', name: 'Option', args: [someT] },
  }, new Set()));
  const resT = freshVar();
  const resE = freshVar();
  env.set('Ok', generalize({
    kind: 'arrow',
    params: [resT],
    return: { kind: 'app', name: 'Result', args: [resT, resE] },
  }, new Set()));
  env.set('Err', generalize({
    kind: 'arrow',
    params: [resE],
    return: { kind: 'app', name: 'Result', args: [resT, resE] },
  }, new Set()));
  const processRetT = freshVar();
  env.set('__get_process', generalize({
    kind: 'arrow',
    params: [],
    return: processRetT,
  }, new Set()));

  function apply(t: InternalType): InternalType {
    return applySubst(t, subst);
  }

  function cloneSubst(): Map<number, InternalType> {
    return new Map(subst);
  }

  /** Resolve RHS of `e is T`: type syntax, or a constructor name (`None`, `Red`, `Some<Int>`). */
  function resolveTypeForIsRhs(ast: import('../ast/nodes.js').Type): InternalType {
    if (ast.kind === 'AppType') {
      const sch = env.get(ast.name);
      if (sch != null) {
        const b = apply(instantiate(sch));
        if (b.kind === 'arrow' && b.params.length === ast.args.length) {
          const trial = cloneSubst();
          try {
            for (let i = 0; i < ast.args.length; i++) {
              const pi = astTypeToInternal(ast.args[i]!, typeAliases, resolveQualified);
              unify(
                applySubst(b.params[i]!, trial),
                applySubst(pi, trial),
                trial,
                genericTypeAliasDefs
              );
            }
            return applySubst(b.return, trial);
          } catch {
            // fall through
          }
        }
      }
    }
    if (ast.kind === 'IdentType') {
      const sch = env.get(ast.name);
      if (sch != null) {
        const b = apply(instantiate(sch));
        if (b.kind === 'app') return b;
        if (b.kind === 'arrow' && b.params.length === 0) return b.return;
        // Unary+ constructor as type name (`Some` → Option<α>); arity-specific `is` uses `AppType`.
        if (b.kind === 'arrow' && b.params.length >= 1) return b.return;
      }
    }
    return astTypeToInternal(ast, typeAliases, resolveQualified);
  }

  function checkOpaqueIsRule(scrutApplied: InternalType, rhsAst: import('../ast/nodes.js').Type, node: Expr): void {
    if (scrutApplied.kind !== 'app') return;
    if (!opaqueTypes.has(scrutApplied.name)) return;
    const ok =
      (rhsAst.kind === 'IdentType' && rhsAst.name === scrutApplied.name) ||
      (rhsAst.kind === 'QualifiedType' && rhsAst.name === scrutApplied.name);
    if (!ok) {
      throw new TypeCheckError(
        `Cannot narrow imported opaque ADT ${scrutApplied.name} except to the type name itself`,
        node,
        undefined,
        CODES.type.narrow_opaque
      );
    }
  }

  function tryMeetArm(sArm: InternalType, tApplied: InternalType): InternalType | null {
    const trial = cloneSubst();
    try {
      unify(
        applySubst(sArm, trial),
        applySubst(tApplied, trial),
        trial,
        genericTypeAliasDefs
      );
      return applySubst(tApplied, trial);
    } catch {
      return null;
    }
  }

  /** `{ x: A, y: B }` refines by `{ x: A }`: overlap when RHS fields exist on LHS with unifiable types. */
  function tryRecordSubsetMeet(s: InternalType, t: InternalType): InternalType | null {
    const sA = apply(s);
    const tA = apply(t);
    if (sA.kind !== 'record' || tA.kind !== 'record') return null;
    const trial = cloneSubst();
    for (const tf of tA.fields) {
      const sf = sA.fields.find((f) => f.name === tf.name);
      if (sf == null) return null;
      try {
        unify(applySubst(sf.type, trial), applySubst(tf.type, trial), trial, genericTypeAliasDefs);
      } catch {
        return null;
      }
    }
    return applySubst(sA, trial);
  }

  function refinementMeetScrutTarget(s: InternalType, t: InternalType): InternalType | null {
    const trial = cloneSubst();
    const s0 = applySubst(s, trial);
    const t0 = applySubst(t, trial);
    try {
      unify(s0, t0, trial, genericTypeAliasDefs);
      return applySubst(t0, trial);
    } catch {
      const rs = tryRecordSubsetMeet(s, t);
      if (rs != null) return rs;
      const sA = apply(s);
      const tA = apply(t);
      if (sA.kind === 'union') {
        const m1 = tryMeetArm(sA.left, tA);
        const m2 = tryMeetArm(sA.right, tA);
        if (m1 != null && m2 == null) return m1;
        if (m1 == null && m2 != null) return m2;
        return null;
      }
      return null;
    }
  }

  /** Get free variables from all types in environment */
  function envFreeVars(): Set<number> {
    const free = new Set<number>();
    for (const t of env.values()) {
      for (const v of freeVars(apply(t))) {
        free.add(v);
      }
    }
    return free;
  }

  /** Check if a match is exhaustive for a given type */
  function checkExhaustive(scrutineeType: InternalType, cases: import('../ast/nodes.js').Case[], expr: unknown): void {
    const coveredCtors = new Set<string>();
    let hasCatchAll = false;
    const literalKinds = new Set<string>();

    for (const c of cases) {
      if (c.pattern.kind === 'WildcardPattern' || c.pattern.kind === 'VarPattern') {
        hasCatchAll = true;
      } else if (c.pattern.kind === 'LiteralPattern') {
        literalKinds.add(c.pattern.literal);
      } else if (c.pattern.kind === 'ConstructorPattern') {
        coveredCtors.add(c.pattern.name);
      } else if (c.pattern.kind === 'ListPattern') {
        if (c.pattern.elements.length === 0) {
          coveredCtors.add('Nil');
        } else {
          coveredCtors.add('Cons');
        }
      } else if (c.pattern.kind === 'ConsPattern') {
        coveredCtors.add('Cons');
      }
    }

    const appType = apply(scrutineeType);
    if (appType.kind === 'prim' && literalKinds.size > 0) {
      if (appType.name === 'Unit') {
        const hasUnitPattern = cases.some(
          c => c.pattern.kind === 'LiteralPattern' && c.pattern.literal === 'unit'
        );
        if (!hasUnitPattern && !hasCatchAll) {
          diagnostics.push({
            severity: 'error',
            code: CODES.type.non_exhaustive_match,
            message: 'Non-exhaustive match: missing Unit pattern `()`',
            location: locFor(expr),
          });
        }
        return;
      }
      if (appType.name === 'Int' || appType.name === 'Float' || appType.name === 'String' || appType.name === 'Char') {
        if (!hasCatchAll) {
          diagnostics.push({
            severity: 'error',
            code: CODES.type.non_exhaustive_match,
            message: `Non-exhaustive match: literal patterns on ${appType.name} require a catch-all pattern`,
            location: locFor(expr),
          });
        }
        return;
      }
    }

    if (appType.kind === 'tuple') {
      function tuplePatternLeavesTotal(p: import('../ast/nodes.js').Pattern): boolean {
        if (p.kind === 'VarPattern' || p.kind === 'WildcardPattern') return true;
        if (p.kind === 'TuplePattern') return p.elements.every(tuplePatternLeavesTotal);
        return false;
      }
      if (hasCatchAll) return;
      const hasTotalTupleArm = cases.some(
        c => c.pattern.kind === 'TuplePattern' && tuplePatternLeavesTotal(c.pattern)
      );
      if (hasTotalTupleArm) return;
      diagnostics.push({
        severity: 'error',
        code: CODES.type.non_exhaustive_match,
        message:
          'Non-exhaustive match: add a catch-all (`_` or variable pattern) or a tuple pattern `(x, y, ...)` that only binds variables (no literals in tuple slots)',
        location: locFor(expr),
      });
      return;
    }

    if (appType.kind !== 'app') return;
    
    // Check hardcoded built-in ADTs first, then user-defined
    const requiredSets: Record<string, Set<string>> = {
      List: new Set(['Nil', 'Cons']),
      Option: new Set(['None', 'Some']),
      Result: new Set(['Err', 'Ok']),
    };
    
    let required: Set<string> | undefined = requiredSets[appType.name];
    if (!required) {
      // Check user-defined ADTs
      const userCtor = adtConstructors.get(appType.name);
      if (userCtor) {
        required = new Set(userCtor.map(c => c.name));
      }
    }
    
    if (required) {
      const missing = [...required].filter(c => !coveredCtors.has(c));
      if (missing.length > 0 && !hasCatchAll) {
        diagnostics.push({
          severity: 'error',
          code: CODES.type.non_exhaustive_match,
          message: `Non-exhaustive match: missing constructors: ${missing.join(', ')}`,
          location: locFor(expr),
        });
      }
    }
  }

  /**
   * Walk a record's row chain to find a field by name.
   * If the field is found, returns its type. If not found and the chain
   * ends in a row variable, extends the row with the field and returns
   * the fresh field type. Returns null only if the record is closed.
   */
  function findFieldInRecord(rec: InternalType & { kind: 'record' }, name: string, blame: unknown): InternalType | null {
    const field = rec.fields.find((f) => f.name === name);
    if (field != null) return field.type;
    if (rec.row == null) return null;
    const rowApplied = apply(rec.row);
    if (rowApplied.kind === 'var') {
      const fieldType = freshVar();
      const newRowVar = freshVar();
      const extension: InternalType = {
        kind: 'record',
        fields: [{ name, mut: false, type: fieldType }],
        row: newRowVar,
      };
      unifyWithBlame(rowApplied, extension, blame);
      return fieldType;
    }
    if (rowApplied.kind === 'record') {
      return findFieldInRecord(rowApplied, name, blame);
    }
    return null;
  }

  function inferExpr(expr: Expr, asyncCtx: boolean): InternalType {
    if (expr == null) {
      throw new TypeCheckError(
        'Internal error: expression is null or undefined',
        { span: { line: 1, column: 1, start: 0, end: 0 } } as unknown as Parameters<typeof locFor>[0]
      );
    }
    currentExpr = expr;
    let result: InternalType;
    switch (expr.kind) {
      case 'LiteralExpr':
        switch (expr.literal) {
          case 'int': result = tInt; break;
          case 'float': result = tFloat; break;
          case 'string': result = tString; break;
          case 'char': result = prim('Char' as const); break;
          case 'true':
          case 'false': result = tBool; break;
          case 'unit': result = tUnit; break;
          default: result = freshVar();
        }
        setInferredType(expr, result);
        return result;
      case 'IdentExpr': {
        const t = env.get(expr.name);
        if (t == null) {
          const suggestion = closestName(expr.name, [...env.keys()]);
          throw new TypeCheckError(
            `Unknown variable: ${expr.name}`,
            expr,
            suggestion != null ? `Did you mean \`${suggestion}\`?` : undefined
          );
        }
        // Instantiate if it's a scheme (polymorphic)
        result = apply(instantiate(t));
        setInferredType(expr, result);
        return result;
      }
      case 'IsExpr': {
        const sRaw = inferExpr(expr.expr, asyncCtx);
        const tRaw = resolveTypeForIsRhs(expr.testedType);
        checkOpaqueIsRule(apply(sRaw), expr.testedType, expr);
        const narrowed = refinementMeetScrutTarget(sRaw, tRaw);
        if (narrowed == null) {
          throw new TypeCheckError(
            `Cannot narrow: scrutinee type does not overlap \`is\` target (${typeStr(apply(sRaw))} vs ${typeStr(apply(tRaw))})`,
            expr,
            undefined,
            CODES.type.narrow_impossible
          );
        }
        if (expr.expr.kind === 'IdentExpr') {
          narrowingByIsExpr.set(expr, { bindingName: expr.expr.name, narrowed });
        }
        setInferredType(expr, tBool);
        return tBool;
      }
      case 'IfExpr': {
        const condT = inferExpr(expr.cond, asyncCtx);
        unifyWithBlame(condT, tBool, expr);
        const nar = expr.cond.kind === 'IsExpr' ? narrowingByIsExpr.get(expr.cond) : undefined;
        let thenT: InternalType;
        if (nar) {
          const prev = env.get(nar.bindingName);
          env.set(nar.bindingName, nar.narrowed);
          try {
            thenT = inferExpr(expr.then, asyncCtx);
          } finally {
            if (prev !== undefined) env.set(nar.bindingName, prev);
            else env.delete(nar.bindingName);
          }
        } else {
          thenT = inferExpr(expr.then, asyncCtx);
        }
        if (expr.else !== undefined) {
          const elseT = inferExpr(expr.else, asyncCtx);
          unifyWithBlame(thenT, elseT, expr);
          result = apply(thenT);
        } else {
          unifyWithBlame(thenT, tUnit, expr);
          result = tUnit;
        }
        setInferredType(expr, result);
        return result;
      }
      case 'WhileExpr': {
        const condT = inferExpr(expr.cond, asyncCtx);
        unifyWithBlame(condT, tBool, expr);
        const nar = expr.cond.kind === 'IsExpr' ? narrowingByIsExpr.get(expr.cond) : undefined;
        loopDepth++;
        if (nar) {
          const prev = env.get(nar.bindingName);
          env.set(nar.bindingName, nar.narrowed);
          try {
            inferExpr(expr.body, asyncCtx);
          } finally {
            if (prev !== undefined) env.set(nar.bindingName, prev);
            else env.delete(nar.bindingName);
          }
        } else {
          inferExpr(expr.body, asyncCtx);
        }
        loopDepth--;
        setInferredType(expr, tUnit);
        return tUnit;
      }
      case 'BinaryExpr': {
        const l = inferExpr(expr.left, asyncCtx);
        const r = inferExpr(expr.right, asyncCtx);
        if (['+', '-', '*', '/', '%', '**'].includes(expr.op)) {
          unifyWithBlame(l, r, expr);
          const numType = apply(l);
          if (numType.kind === 'prim' && numType.name !== 'Int' && numType.name !== 'Float') {
            throw new TypeCheckError(
              `Arithmetic operands must have type Int or Float, not ${typeStr(numType)}`,
              expr
            );
          }
          result = numType;
        } else if (['==', '!=', '<', '>', '<=', '>='].includes(expr.op)) {
          unifyWithBlame(l, r, expr);
          result = tBool;
        } else if (expr.op === '|' || expr.op === '&') {
          unifyWithBlame(l, tBool, expr);
          unifyWithBlame(r, tBool, expr);
          result = tBool;
        } else {
          result = freshVar();
        }
        setInferredType(expr, result);
        return result;
      }
      case 'UnaryExpr': {
        const operandType = inferExpr(expr.operand, asyncCtx);
        if (expr.op === '-' || expr.op === '+') {
          unifyWithBlame(operandType, tInt, expr);
          result = tInt;
        } else if (expr.op === '!') {
          unifyWithBlame(operandType, tBool, expr);
          result = tBool;
        } else {
          result = freshVar();
        }
        setInferredType(expr, result);
        return result;
      }
      case 'CallExpr': {
        // Built-in variadic print/println: (a, b, ...) -> Unit, require at least one arg
        if (expr.callee.kind === 'IdentExpr' && (expr.callee.name === 'print' || expr.callee.name === 'println')) {
          if (expr.args.length < 1) {
            throw new TypeCheckError('print and println require at least one argument', expr);
          }
          for (const arg of expr.args) inferExpr(arg, asyncCtx);
          result = { kind: 'prim', name: 'Unit' };
          setInferredType(expr, result);
          return result;
        }
        const calleeT = inferExpr(expr.callee, asyncCtx);
        const argTs = expr.args.map((a) => inferExpr(a, asyncCtx));
        const ret = freshVar();
        const arrow = { kind: 'arrow' as const, params: argTs, return: ret };
        unifyWithBlame(calleeT, arrow, expr, undefined, { arrowMode: 'call' });
        result = apply(ret);
        setInferredType(expr, result);
        return result;
      }
      case 'TupleExpr': {
        const elements = expr.elements.map((e) => inferExpr(e, asyncCtx));
        result = apply({ kind: 'tuple', elements });
        setInferredType(expr, result);
        return result;
      }
      case 'BlockExpr': {
        // Phase 1: pre-bind all FunStmt names so bodies can reference each other (self- and mutual recursion)
        for (const stmt of expr.stmts) {
          if (stmt.kind === 'FunStmt') {
            const scope = new Map<string, InternalType>();
            if (stmt.typeParams) {
              for (const tp of stmt.typeParams) {
                scope.set(tp, freshVar());
              }
            }
            const paramTs = stmt.params.map((p) =>
              p.type ? astTypeToInternalWithScope(p.type, scope, typeAliases, resolveQualified) : freshVar()
            );
            const returnT = astTypeToInternalWithScope(stmt.returnType, scope, typeAliases, resolveQualified);
            const arrowT: InternalType = { kind: 'arrow', params: paramTs, return: returnT };
            env.set(stmt.name, arrowT);
          }
        }
        for (const stmt of expr.stmts) {
          if (stmt.kind === 'ValStmt') {
            const t = apply(inferExpr(stmt.value, asyncCtx));
            if (stmt.type) {
              unifyWithBlame(t, astTypeToInternal(stmt.type, typeAliases, resolveQualified), stmt.value, undefined, {
                relation: 'subtype',
              });
            }
            const scheme = generalize(apply(t), envFreeVars());
            env.set(stmt.name, scheme);
          } else if (stmt.kind === 'FunStmt') {
            const arrowT = env.get(stmt.name) as InternalType;
            if (arrowT?.kind === 'arrow') {
              // Validate async return type must be Task<T>
              if (stmt.async) {
                const rt = apply(arrowT.return);
                if (!(rt.kind === 'app' && rt.name === 'Task')) {
                  diagnostics.push({
                    severity: 'error',
                    code: CODES.type.check,
                    message: `Async function ${stmt.name} must return Task<T>`,
                    location: locFor(stmt),
                  });
                }
              }
              for (let i = 0; i < stmt.params.length; i++) {
                env.set(stmt.params[i]!.name, arrowT.params[i]!);
              }
              const bodyT = inferExpr(stmt.body, stmt.async ?? false);
              // For async block-local funs: unify body against inner T, not Task<T>
              const returnApplied = apply(arrowT.return);
              if (stmt.async && returnApplied.kind === 'app' && returnApplied.name === 'Task' && returnApplied.args.length === 1) {
                unifyWithBlame(bodyT, returnApplied.args[0]!, stmt.body, undefined, { relation: 'subtype' });
              } else {
                const inferredArrow: InternalType = { kind: 'arrow', params: arrowT.params, return: apply(bodyT) };
                unifyWithBlame(inferredArrow, arrowT, stmt.body, undefined, { arrowMode: 'fun_check' });
              }
              const scheme = generalize(apply(arrowT), envFreeVars());
              env.set(stmt.name, scheme);
              for (let i = 0; i < stmt.params.length; i++) {
                env.delete(stmt.params[i]!.name);
              }
            }
          } else if (stmt.kind === 'VarStmt') {
            const t = apply(inferExpr(stmt.value, asyncCtx));
            if (stmt.type) {
              unifyWithBlame(t, astTypeToInternal(stmt.type, typeAliases, resolveQualified), stmt.value, undefined, {
                relation: 'subtype',
              });
            }
            env.set(stmt.name, apply(t));
          } else if (stmt.kind === 'ExprStmt') {
            inferExpr(stmt.expr, asyncCtx);
          } else if (stmt.kind === 'BreakStmt') {
            if (loopDepth <= 0) {
              throw new TypeCheckError(
                '`break` may only be used inside a loop body',
                stmt,
                undefined,
                CODES.type.break_outside_loop
              );
            }
            setInferredType(stmt, tUnit);
          } else if (stmt.kind === 'ContinueStmt') {
            if (loopDepth <= 0) {
              throw new TypeCheckError(
                '`continue` may only be used inside a loop body',
                stmt,
                undefined,
                CODES.type.continue_outside_loop
              );
            }
            setInferredType(stmt, tUnit);
          } else if (stmt.kind === 'AssignStmt') {
            const targetT = inferExpr(stmt.target, asyncCtx);
            const valueT = inferExpr(stmt.value, asyncCtx);
            const target = stmt.target;
            if (target.kind === 'FieldExpr') {
              const objT = apply(getInferredType(target.object) ?? targetT);
              if (objT.kind === 'record') {
                const field = objT.fields.find((f) => f.name === target.field);
                if (field == null) throw new TypeCheckError(`Unknown field: ${target.field}`, target);
                if (!field.mut) throw new TypeCheckError(`Cannot assign to immutable field: ${target.field}`, target);
                unifyWithBlame(valueT, field.type, stmt.value, target, { relation: 'subtype' });
              }
            } else if (target.kind === 'IdentExpr') {
              const lhs = env.get(target.name);
              if (lhs != null) unifyWithBlame(valueT, lhs, stmt.value, target, { relation: 'subtype' });
            }
          }
        }
        result = inferExpr(expr.result, asyncCtx);
        setInferredType(expr, result);
        return result;
      }
      case 'LambdaExpr': {
        const scope = new Map<string, InternalType>();
        if (expr.typeParams) {
          for (const tp of expr.typeParams) {
            scope.set(tp, freshVar());
          }
        }
        const paramTs = expr.params.map((p) =>
          p.type ? astTypeToInternalWithScope(p.type, scope, typeAliases, resolveQualified) : freshVar()
        );
        for (let i = 0; i < expr.params.length; i++) {
          env.set(expr.params[i]!.name, paramTs[i]!);
        }
        let bodyT: InternalType;
        try {
          bodyT = inferExpr(expr.body, expr.async);
        } finally {
          for (let i = 0; i < expr.params.length; i++) {
            env.delete(expr.params[i]!.name);
          }
        }
        const returnT = expr.async ? ({ kind: 'app', name: 'Task', args: [bodyT] } as InternalType) : bodyT;
        result = apply({ kind: 'arrow', params: paramTs, return: returnT });
        setInferredType(expr, result);
        return result;
      }
      case 'RecordExpr': {
        if (expr.spread != null) {
          // Record spread: { ...r, x = e } — infer r as record, extend with new fields
          const spreadT = inferExpr(expr.spread, asyncCtx);
          let spreadApplied = apply(spreadT);
          if (spreadApplied.kind !== 'record') {
            const rowVar = freshVar();
            unifyWithBlame(spreadT, { kind: 'record', fields: [], row: rowVar }, expr.spread);
            spreadApplied = apply(spreadT);
          }
          if (spreadApplied.kind !== 'record') {
            throw new TypeCheckError('Spread target must be a record type', expr.spread);
          }
          const newFields: { name: string; mut: boolean; type: InternalType }[] = [];
          const newNames = new Set(expr.fields.map((f) => f.name));
          for (const f of spreadApplied.fields) {
            if (!newNames.has(f.name)) newFields.push(f);
          }
          for (const f of expr.fields) {
            const ft = inferExpr(f.value, asyncCtx);
            newFields.push({ name: f.name, mut: f.mut ?? false, type: ft });
          }
          result = apply({ kind: 'record', fields: newFields, row: spreadApplied.row ?? undefined });
          setInferredType(expr, result);
          return result;
        }
        const fields: { name: string; mut: boolean; type: InternalType }[] = [];
        for (const f of expr.fields) {
          const ft = inferExpr(f.value, asyncCtx);
          fields.push({ name: f.name, mut: f.mut ?? false, type: ft });
        }
        // Create a closed record (no row variable) since we know all fields
        result = apply({ kind: 'record', fields });
        setInferredType(expr, result);
        return result;
      }
      case 'FieldExpr': {
        const objT = inferExpr(expr.object, asyncCtx);
        let applied = apply(objT);

        if (applied.kind === 'app' && opaqueTypes.has(applied.name)) {
          throw new TypeCheckError(
            `Cannot access field '${expr.field}' on opaque type ${applied.name}`,
            expr
          );
        }
        applied = expandGenericAliasHead(objT, subst, genericTypeAliasDefs);

        if (applied.kind === 'namespace') {
          const fieldType = applied.bindings.get(expr.field);
          if (fieldType == null) {
            throw new TypeCheckError(`Namespace does not export '${expr.field}'`, expr);
          }
          result = apply(instantiate(fieldType));
          setInferredType(expr, result);
          return result;
        }

        if (applied.kind === 'tuple') {
          const i = parseInt(expr.field, 10);
          if (!(i >= 0 && i < applied.elements.length)) {
            throw new TypeCheckError(`Tuple index out of range: ${expr.field}`, expr);
          }
          result = apply(applied.elements[i]!);
          setInferredType(expr, result);
          return result;
        }

        // For record field access with row polymorphism
        if (applied.kind === 'var') {
          // If the object type is a variable, constrain it to be a record with this field
          const fieldType = freshVar();
          const rowVar = freshVar();
          const recordType: InternalType = {
            kind: 'record',
            fields: [{ name: expr.field, mut: false, type: fieldType }],
            row: rowVar
          };
          try {
            unifyWithBlame(applied, recordType, expr);
          } catch (e) {
            if (e instanceof UnifyError) {
              throw new TypeCheckError(`Cannot access field '${expr.field}' on non-record type`, expr);
            }
            throw e;
          }
          result = apply(fieldType);
          setInferredType(expr, result);
          return result;
        }

        if (applied.kind !== 'record') {
          throw new TypeCheckError(`Expected record or tuple type, got ${applied.kind}`, expr);
        }

        const found = findFieldInRecord(applied, expr.field, expr);
        if (found != null) {
          result = apply(found);
          setInferredType(expr, result);
          return result;
        }
        throw new TypeCheckError(`Unknown field: ${expr.field}`, expr);
      }
      case 'MatchExpr': {
        const scrutT = inferExpr(expr.scrutinee, asyncCtx);
        // Check if we're matching on an opaque type from another module
        const appliedScrutT = apply(scrutT);
        if (appliedScrutT.kind === 'app' && opaqueTypes.has(appliedScrutT.name)) {
          throw new TypeCheckError(`Cannot pattern-match on opaque type ${appliedScrutT.name}`, expr);
        }
        checkExhaustive(scrutT, expr.cases, expr);

        // Helper to bind pattern variables
        function bindPattern(pattern: import('../ast/nodes.js').Pattern, patternType: InternalType): string[] {
          const bound: string[] = [];
          if (pattern.kind === 'VarPattern') {
            env.set(pattern.name, patternType);
            bound.push(pattern.name);
          } else if (pattern.kind === 'WildcardPattern') {
            // no bindings
          } else if (pattern.kind === 'TuplePattern') {
            const applied = apply(patternType);
            if (applied.kind !== 'tuple') {
              throw new TypeCheckError(
                `Expected tuple type for tuple pattern, got ${typeStr(applied)}`,
                pattern
              );
            }
            if (applied.elements.length !== pattern.elements.length) {
              throw new TypeCheckError(
                `Tuple pattern has ${pattern.elements.length} components but scrutinee has type ${typeStr(applied)}`,
                pattern
              );
            }
            for (let i = 0; i < pattern.elements.length; i++) {
              bound.push(...bindPattern(pattern.elements[i]!, applied.elements[i]!));
            }
          } else if (pattern.kind === 'ConsPattern') {
            const applied = apply(patternType);
            if (applied.kind === 'app' && applied.name === 'List' && applied.args.length === 1) {
              const elemType = applied.args[0]!;
              bound.push(...bindPattern(pattern.head, elemType));
              bound.push(...bindPattern(pattern.tail, patternType));
            }
          } else if (pattern.kind === 'LiteralPattern') {
            let literalType: InternalType;
            switch (pattern.literal) {
              case 'int':
                literalType = tInt;
                break;
              case 'float':
                literalType = tFloat;
                break;
              case 'string':
                literalType = tString;
                break;
              case 'char':
                literalType = prim('Char');
                break;
              case 'unit':
                literalType = tUnit;
                break;
              case 'true':
              case 'false':
                literalType = tBool;
                break;
              default:
                literalType = freshVar();
            }
            unifyWithBlame(patternType, literalType, pattern);
          } else if (pattern.kind === 'ConstructorPattern') {
            const applied = apply(patternType);
            if (applied.kind === 'app') {
              // Handle built-in ADTs
              if (applied.name === 'Option' && applied.args.length === 1) {
                const payloadT = applied.args[0]!;
                for (const field of pattern.fields || []) {
                  if (field.pattern) bound.push(...bindPattern(field.pattern, payloadT));
                }
              } else if (applied.name === 'Result' && applied.args.length === 2) {
                const t = applied.args[0]!;
                const e = applied.args[1]!;
                const payloadT = pattern.name === 'Ok' ? t : e;
                for (const field of pattern.fields || []) {
                  if (field.pattern) bound.push(...bindPattern(field.pattern, payloadT));
                }
              } else {
                // User-defined ADT - look up constructor arity
                const adtCtors = adtConstructors.get(applied.name);
                if (adtCtors) {
                  const ctor = adtCtors.find(c => c.name === pattern.name);
                  if (ctor && ctor.arity > 0) {
                    // For positional constructors, bind variables using field names from the pattern
                    for (const field of pattern.fields || []) {
                      if (field.pattern && field.pattern.kind === 'VarPattern') {
                        env.set(field.pattern.name, freshVar());
                        bound.push(field.pattern.name);
                      }
                    }
                  }
                } else {
                  // Imported ADT — look up constructor type from env to derive payload types
                  const ctorScheme = env.get(pattern.name);
                  if (ctorScheme != null) {
                    const ctorType = instantiate(ctorScheme);
                    if (ctorType.kind === 'arrow' && ctorType.params.length > 0) {
                      const fields = pattern.fields || [];
                      for (let fi = 0; fi < fields.length; fi++) {
                        const field = fields[fi]!;
                        if (field.pattern && field.pattern.kind === 'VarPattern') {
                          const payloadT = ctorType.params[fi] ?? freshVar();
                          env.set(field.pattern.name, payloadT);
                          bound.push(field.pattern.name);
                        } else if (field.pattern) {
                          const payloadT = ctorType.params[fi] ?? freshVar();
                          bound.push(...bindPattern(field.pattern, payloadT));
                        }
                      }
                    }
                  }
                }
              }
            }
          }
          return bound;
        }

        // Type check all cases and unify their result types
        if (expr.cases.length === 0) {
          result = freshVar();
        } else {
          // Infer type of first case body
          const firstCase = expr.cases[0]!;
          const boundVars = bindPattern(firstCase.pattern, scrutT);
          const firstT = inferExpr(firstCase.body, asyncCtx);
          if (firstT == null) {
            throw new TypeCheckError('Match first case body inferred as null/undefined', firstCase.body);
          }
          boundVars.forEach(v => env.delete(v));

          // Check remaining cases unify with first
          for (let i = 1; i < expr.cases.length; i++) {
            const c = expr.cases[i]!;
            const caseVars = bindPattern(c.pattern, scrutT);
            const caseT = inferExpr(c.body, asyncCtx);
            if (caseT == null) {
              throw new TypeCheckError('Match case body inferred as null/undefined', c.body);
            }
            caseVars.forEach(v => env.delete(v));
            unifyWithBlame(firstT, caseT, c.body);
          }
          result = apply(firstT);
          if (result == null) {
            throw new TypeCheckError('Match result type resolved to null/undefined (subst may contain undefined)', expr);
          }
        }
        setInferredType(expr, result);
        return result;
      }
      case 'AwaitExpr': {
        if (!asyncCtx) {
          throw new TypeCheckError(
            'await can only be used in async contexts (async functions or async lambdas)',
            expr
          );
        }
        const taskT = inferExpr(expr.value, asyncCtx);
        const applied = apply(taskT);
        // Expect Task<T>
        if (applied.kind === 'app' && applied.name === 'Task' && applied.args.length === 1) {
          result = apply(applied.args[0]!);
        } else {
          throw new TypeCheckError(`await expects Task<T> but got ${typeStr(applied)}`, expr);
        }
        setInferredType(expr, result);
        return result;
      }
      case 'ThrowExpr': {
        // For now, accept any type for throw (should be exception type)
        inferExpr(expr.value, asyncCtx);
        // Throw has bottom type (never returns)
        result = freshVar();
        setInferredType(expr, result);
        return result;
      }
      case 'TryExpr': {
        const blockT = inferExpr(expr.body, asyncCtx);
        // Type check catch cases similar to match
        for (const c of expr.cases) {
          if (c.pattern.kind === 'VarPattern') {
            env.set(c.pattern.name, freshVar()); // Exception type
          }
          const caseT = inferExpr(c.body, asyncCtx);
          if (c.pattern.kind === 'VarPattern') {
            env.delete(c.pattern.name);
          }
          unifyWithBlame(blockT, caseT, c.body);
        }
        result = apply(blockT);
        setInferredType(expr, result);
        return result;
      }
      case 'ListExpr': {
        // List literal: all elements must have same type
        if (expr.elements.length === 0) {
          // Empty list has type List<α> for fresh α
          const elemT = freshVar();
          result = { kind: 'app', name: 'List', args: [elemT] };
        } else {
          // Infer first element type
          const firstElem = expr.elements[0];
          if (typeof firstElem === 'object' && 'spread' in firstElem) {
            // Spread element
            result = freshVar();
          } else {
            const firstT = inferExpr(firstElem as Expr, asyncCtx);
            // Unify all other elements with first
            for (let i = 1; i < expr.elements.length; i++) {
              const elem = expr.elements[i];
              if (!(typeof elem === 'object' && 'spread' in elem)) {
                const elemT = inferExpr(elem as Expr, asyncCtx);
                unifyWithBlame(firstT, elemT, elem as Expr);
              }
            }
            result = { kind: 'app', name: 'List', args: [apply(firstT)] };
          }
        }
        setInferredType(expr, result);
        return result;
      }
      case 'ConsExpr': {
        // head :: tail where tail is List<T> and head is T
        const headT = inferExpr(expr.head, asyncCtx);
        const tailT = inferExpr(expr.tail, asyncCtx);
        const applied = apply(tailT);
        if (applied.kind === 'app' && applied.name === 'List' && applied.args.length === 1) {
          unifyWithBlame(headT, applied.args[0]!, expr);
          result = applied;
        } else {
          // Try to unify with List<α>
          const elemT = freshVar();
          unifyWithBlame(tailT, { kind: 'app', name: 'List', args: [elemT] }, expr);
          unifyWithBlame(headT, elemT, expr);
          result = apply({ kind: 'app', name: 'List', args: [elemT] });
        }
        setInferredType(expr, result);
        return result;
      }
      case 'PipeExpr': {
        // Spec: `a |> f(x)` ≡ `f(a, x)`; `f(x) <| b` ≡ `f(x, b)` (piped value first or last arg).
        if (expr.op === '|>') {
          if (expr.right.kind === 'CallExpr') {
            const merged: Expr = {
              kind: 'CallExpr',
              callee: expr.right.callee,
              args: [expr.left, ...expr.right.args],
              span: expr.span,
            };
            result = apply(inferExpr(merged, asyncCtx));
            setInferredType(expr, result);
            return result;
          }
          const leftT = apply(inferExpr(expr.left, asyncCtx));
          const rightT = apply(inferExpr(expr.right, asyncCtx));
          result = freshVar();
          unifyWithBlame(rightT, { kind: 'arrow', params: [leftT], return: result }, expr, undefined, {
            arrowMode: 'call',
          });
          result = apply(result);
          setInferredType(expr, result);
          return result;
        }
        if (expr.left.kind === 'CallExpr') {
          const merged: Expr = {
            kind: 'CallExpr',
            callee: expr.left.callee,
            args: [...expr.left.args, expr.right],
            span: expr.span,
          };
          result = apply(inferExpr(merged, asyncCtx));
          setInferredType(expr, result);
          return result;
        }
        const leftT = apply(inferExpr(expr.left, asyncCtx));
        const rightT = apply(inferExpr(expr.right, asyncCtx));
        result = freshVar();
        unifyWithBlame(leftT, { kind: 'arrow', params: [rightT], return: result }, expr, undefined, {
          arrowMode: 'call',
        });
        result = apply(result);
        setInferredType(expr, result);
        return result;
      }
      case 'TemplateExpr': {
        for (const part of expr.parts) {
          if (part.type !== 'literal') {
            inferExpr(part.expr, asyncCtx);
          }
        }
        result = tString;
        setInferredType(expr, result);
        return result;
      }
      case 'NeverExpr': {
        // Polymorphic "bottom": unifies with whatever context expects (e.g. function return type).
        result = freshVar();
        setInferredType(expr, result);
        return result;
      }
      default:
        result = freshVar();
        setInferredType(expr, result);
        return result;
    }
  }

  /** Primary expression for this body node (for UnifyError location when unify runs after inferExpr returns). */
  function mainExpr(node: TopLevelDecl | TopLevelStmt): Expr | undefined {
    if (node.kind === 'FunDecl') return node.body;
    if (node.kind === 'ExprStmt') return node.expr;
    if (node.kind === 'ValStmt' || node.kind === 'VarStmt' || node.kind === 'ValDecl' || node.kind === 'VarDecl') return node.value;
    if (node.kind === 'AssignStmt') return node.value;
    return undefined;
  }

  try {
    // First pass: pre-bind all top-level function names so any function body can call any other (mutual recursion)
    for (const node of program.body) {
      if (!node) continue;
      if (node.kind === 'FunDecl') env.set(node.name, freshVar());
      if (node.kind === 'ExternFunDecl') env.set(node.name, freshVar());
      if (node.kind === 'ExportDecl' && (node as { inner?: { kind?: string; name?: string } }).inner?.kind === 'FunDecl') {
        const inner = (node as { inner: { name: string } }).inner;
        env.set(inner.name, freshVar());
      }
    }

    // Second pre-pass: pre-register all ADT type names so type aliases that
    // forward-reference an ADT (e.g. `type Case_ = { body: Expr }` before
    // `type Expr = ...`) resolve to the correct `App(name, [])` instead of a
    // fresh variable that can collide across module boundaries.
    for (const node of program.body) {
      if (!node) continue;
      const typeNode = node.kind === 'TypeDecl' ? node
        : (node.kind === 'ExportDecl' && (node as { inner?: { kind?: string } }).inner?.kind === 'TypeDecl')
          ? (node as { inner: import('../ast/nodes.js').TypeDecl }).inner
          : null;
      if (typeNode && typeNode.body?.kind === 'ADTBody') {
        if (!typeAliases.has(typeNode.name)) {
          const adtTypeParams = (typeNode.typeParams || []).map(() => freshVar());
          const adtType = { kind: 'app' as const, name: typeNode.name, args: adtTypeParams };
          typeAliases.set(typeNode.name, adtType);
        }
      }
    }

    for (const node of program.body) {
      if (!node) continue;
      const primary = mainExpr(node);
      if (primary != null) currentExpr = primary;
      if (node.kind === 'FunDecl') {
        const sigScope = new Map<string, InternalType>();
        if (node.typeParams) {
          for (const tp of node.typeParams) {
            sigScope.set(tp, freshVar());
          }
        }
        const paramTs = node.params.map((p) =>
          p.type ? astTypeToInternalWithScope(p.type, sigScope, typeAliases, resolveQualified) : freshVar()
        );
        const returnT = astTypeToInternalWithScope(node.returnType, sigScope, typeAliases, resolveQualified);

        // Check if async function: return type must be Task<T>
        if (node.async) {
          const rt = apply(returnT);
          if (!(rt.kind === 'app' && rt.name === 'Task')) {
            diagnostics.push({
              severity: 'error',
              code: CODES.type.check,
              message: `Async function ${node.name} must return Task<T>`,
              location: locFor(node),
            });
          }
        }

        // Use pre-bound function name from first pass (enables mutual recursion); if missing (e.g. ExportDecl not unfolded), bind now
        let fnVar = env.get(node.name);
        if (fnVar == null) {
          fnVar = freshVar();
          env.set(node.name, fnVar);
        }
        // Check body with parameters in scope
        for (let i = 0; i < node.params.length; i++) {
          env.set(node.params[i]!.name, paramTs[i]!);
        }

        const bodyT = inferExpr(node.body, node.async);
        // If body type is a type variable that appears in the return type of a parameter
        // (e.g. S in f: T -> S), the declared return type must be that variable, not a different type.
        const paramReturnVarIds = new Set<number>();
        for (const p of paramTs) {
          const pa = apply(p);
          if (pa.kind === 'arrow') {
            for (const v of freeVars(pa.return)) paramReturnVarIds.add(v);
          }
        }
        if (bodyT == null) {
          throw new TypeCheckError('Function body inferred type is null or undefined', node.body);
        }
        if (returnT == null) {
          throw new TypeCheckError('Function return type resolved to null or undefined', node);
        }
        const bodyApplied = apply(bodyT);
        const returnApplied = apply(returnT);
        // Reject when body type is a type var from a parameter's return type (e.g. S in f: T -> S)
        // but the declared return type is not that same variable (e.g. Int, or a different var like T).
        if (bodyApplied.kind === 'var' && paramReturnVarIds.has(bodyApplied.id)) {
          if (returnApplied.kind !== 'var' || returnApplied.id !== bodyApplied.id) {
            throw new TypeCheckError(
              `Return type must be the same as the body type (from parameter types), not ${typeStr(returnT)}`,
              node
            );
          }
        }
        if (
          node.async &&
          returnApplied.kind === 'app' &&
          returnApplied.name === 'Task' &&
          returnApplied.args.length === 1
        ) {
          unifyWithBlame(bodyT, returnApplied.args[0]!, node.body, undefined, { relation: 'subtype' });
        } else {
          unifyWithBlame(bodyT, returnT, node.body, undefined, { relation: 'subtype' });
        }

        const fnType = { kind: 'arrow' as const, params: paramTs, return: returnT };
        unifyWithBlame(fnVar, fnType, node.body);
        // Clean up parameter bindings
        for (let i = 0; i < node.params.length; i++) {
          env.delete(node.params[i]!.name);
        }
        // Generalize: quantify type vars that are not free in the rest of the environment.
        // Temporarily remove current function so its type vars (e.g. β in (β)->β) are not
        // considered "in env" and get correctly quantified for polymorphism.
        env.delete(node.name);
        const appliedFnType = apply(fnType);
        const envForGen = envFreeVars();
        // Explicit function type parameters must always be quantified; they can appear in envFreeVars()
        // via other bindings' inferred types and would otherwise leak as raw var ids into exported signatures.
        if (node.typeParams) {
          for (const tp of node.typeParams) {
            const tv = sigScope.get(tp);
            if (tv?.kind === 'var') envForGen.delete(tv.id);
          }
        }
        const scheme = generalize(appliedFnType, envForGen);
        env.set(node.name, scheme);
      } else if (node.kind === 'ExternFunDecl') {
        const sigScope = new Map<string, InternalType>();
        const localTypeParams = new Set<string>();
        if (node.typeParams) {
          for (const tp of node.typeParams) {
            sigScope.set(tp, freshVar());
            localTypeParams.add(tp);
          }
        }
        for (const p of node.params) {
          if (p.type) assertKnownTypeNames(p.type, node, localTypeParams);
        }
        assertKnownTypeNames(node.returnType, node, localTypeParams);
        const paramTs = node.params.map((p) =>
          p.type ? astTypeToInternalWithScope(p.type, sigScope, typeAliases, resolveQualified) : freshVar()
        );
        const returnT = astTypeToInternalWithScope(node.returnType, sigScope, typeAliases, resolveQualified);
        const fnType = { kind: 'arrow' as const, params: paramTs, return: returnT };
        const fnVar = env.get(node.name);
        if (fnVar != null) unifyWithBlame(fnVar, fnType, node);
        const appliedFnType = apply(fnType);
        // Remove self from env before computing envFreeVars so that this function's type
        // variable does not prevent its own type params from being generalized (mirrors FunDecl).
        env.delete(node.name);
        const envForGen = envFreeVars();
        // Explicit type params must always be quantified even if their vars appear elsewhere
        // in the environment (mirrors the FunDecl treatment of typeParams).
        if (node.typeParams) {
          for (const tp of node.typeParams) {
            const tv = sigScope.get(tp);
            if (tv?.kind === 'var') envForGen.delete(tv.id);
          }
        }
        const scheme = generalize(appliedFnType, envForGen);
        env.set(node.name, scheme);
      } else if (node.kind === 'TypeDecl') {
        // Opaque types from the current module are fully accessible within that module
        // (no need to add to opaqueTypes - that's only for imported opaque types)
        if (node.body.kind === 'TypeAliasBody') {
          // Treat opaque alias same as regular alias within the module
          // The opacity is enforced at export/import boundary
          if (node.typeParams && node.typeParams.length > 0) {
            const paramVarIds: number[] = [];
            const scope = new Map<string, InternalType>();
            for (const tp of node.typeParams) {
              const v = freshVar();
              if (v.kind !== 'var') throw new TypeCheckError('Internal error: freshVar expected var', node);
              paramVarIds.push(v.id);
              scope.set(tp, v);
            }
            const aliasType = astTypeToInternalWithScope(node.body.type, scope, typeAliases, resolveQualified);
            genericTypeAliasDefs.set(node.name, { paramVarIds, body: aliasType });
            const templateApp: InternalType = {
              kind: 'app',
              name: node.name,
              args: paramVarIds.map((id) => ({ kind: 'var', id })),
            };
            // Do not env.set the type name: template vars would pollute envFreeVars() and break
            // generalization of functions that use this alias (e.g. diff<K,V,B>).
            typeAliases.set(node.name, templateApp);
          } else {
            const aliasType = astTypeToInternal(node.body.type, typeAliases, resolveQualified);
            env.set(node.name, aliasType);
            typeAliases.set(node.name, aliasType);
          }
        } else if (node.body.kind === 'ADTBody') {
          // Reuse pre-registered ADT type if available (from the pre-pass above);
          // otherwise create fresh.  Pre-registration ensures type aliases that
          // forward-reference this ADT already resolved to the correct App node.
          const preReg = typeAliases.get(node.name);
          let adtTypeParams: InternalType[];
          let adtType: InternalType & { kind: 'app' };
          if (preReg && preReg.kind === 'app' && preReg.name === node.name) {
            adtType = preReg as InternalType & { kind: 'app' };
            adtTypeParams = adtType.args;
          } else {
            adtTypeParams = (node.typeParams || []).map(() => freshVar());
            adtType = { kind: 'app' as const, name: node.name, args: adtTypeParams };
          }
          env.set(node.name, adtType);
          typeAliases.set(node.name, adtType);
          
          const adtScope = new Map<string, InternalType>();
          for (let i = 0; i < (node.typeParams || []).length; i++) {
            adtScope.set(node.typeParams![i], adtTypeParams[i]);
          }
          
          for (const ctor of node.body.constructors) {
            const paramTypes = ctor.params.map(p => astTypeToInternalWithScope(p, adtScope, typeAliases, resolveQualified));
            const ctorType = paramTypes.length === 0 
              ? adtType 
              : { kind: 'arrow' as const, params: paramTypes, return: adtType };
            const ctorScheme = generalize(apply(ctorType), new Set());
            env.set(ctor.name, ctorScheme);
          }
          
          adtConstructors.set(node.name, node.body.constructors.map(c => ({ name: c.name, arity: c.params.length })));
          if (node.visibility === 'export') {
            for (const ctor of node.body.constructors) {
              const ct = env.get(ctor.name);
              if (ct != null) exportedConstructors.set(ctor.name, apply(ct));
            }
          }
        }
      } else if (node.kind === 'ExternTypeDecl') {
        if (typeAliases.has(node.name) || genericTypeAliasDefs.has(node.name) || adtConstructors.has(node.name)) {
          throw new TypeCheckError(`Duplicate type declaration: ${node.name}`, node);
        }
        if (node.typeParams && node.typeParams.length > 0) {
          const paramVarIds: number[] = [];
          for (const _tp of node.typeParams) {
            const v = freshVar();
            if (v.kind !== 'var') throw new TypeCheckError('Internal error: freshVar expected var', node);
            paramVarIds.push(v.id);
          }
          const templateApp: InternalType = {
            kind: 'app',
            name: node.name,
            args: paramVarIds.map((id) => ({ kind: 'var', id })),
          };
          genericTypeAliasDefs.set(node.name, { paramVarIds, body: templateApp });
          typeAliases.set(node.name, templateApp);
        } else {
          const externType: InternalType = { kind: 'app', name: node.name, args: [] };
          env.set(node.name, externType);
          typeAliases.set(node.name, externType);
        }
      } else if (node.kind === 'ExceptionDecl') {
        const adtType: InternalType = { kind: 'app', name: node.name, args: [] };
        // Register exception type in typeAliases so it resolves correctly in type annotations
        // (without this, `fun f(...): ParseError` creates a fresh var instead of App("ParseError",[]))
        typeAliases.set(node.name, adtType);
        const ctorType: InternalType =
          node.fields && node.fields.length > 0
            ? {
                kind: 'arrow',
                params: node.fields.map((f) => astTypeToInternal(f.type, typeAliases, resolveQualified)),
                return: adtType,
              }
            : adtType;
        const scheme = generalize(apply(ctorType), envFreeVars());
        env.set(node.name, scheme);
      } else if (node.kind === 'ValStmt') {
        const t = apply(inferExpr(node.value, false));
        const scheme = generalize(t, envFreeVars());
        env.set(node.name, scheme);
      } else if (node.kind === 'VarStmt') {
        const t = apply(inferExpr(node.value, false));
        // Var bindings not generalized
        env.set(node.name, t);
      } else if (node.kind === 'ValDecl') {
        const valueT = inferExpr(node.value, false);
        if (node.type) {
          unifyWithBlame(valueT, astTypeToInternal(node.type, typeAliases, resolveQualified), node.value, undefined, {
            relation: 'subtype',
          });
        }
        const t = apply(valueT);
        const scheme = generalize(t, envFreeVars());
        env.set(node.name, scheme);
      } else if (node.kind === 'VarDecl') {
        const valueT = inferExpr(node.value, false);
        if (node.type) {
          unifyWithBlame(valueT, astTypeToInternal(node.type, typeAliases, resolveQualified), node.value, undefined, {
            relation: 'subtype',
          });
        }
        const t = apply(valueT);
        env.set(node.name, t);
      } else if (node.kind === 'ExprStmt') {
        inferExpr(node.expr, false);
      } else if (node.kind === 'AssignStmt') {
        const targetT = inferExpr(node.target, false);
        const valueT = inferExpr(node.value, false);
        const target = node.target;
        if (target.kind === 'FieldExpr') {
          const objT = apply(getInferredType(target.object) ?? targetT);
          if (objT.kind === 'record') {
            const field = objT.fields.find((f) => f.name === target.field);
            if (field == null) throw new TypeCheckError(`Unknown field: ${target.field}`, target);
            if (!field.mut) throw new TypeCheckError(`Cannot assign to immutable field: ${target.field}`, target);
            unifyWithBlame(valueT, field.type, node.value, target, { relation: 'subtype' });
          }
        } else if (target.kind === 'IdentExpr') {
          const lhs = env.get(target.name);
          if (lhs != null) unifyWithBlame(valueT, lhs, node.value, target, { relation: 'subtype' });
        }
      }
    }
    // Resolve all inferred types (apply subst) so codegen sees concrete types
    function resolveNode(node: unknown): void {
      if (node == null || typeof node !== 'object') return;
      const n = node as Record<symbol, InternalType | undefined>;
      const t = n[TypedExpr];
      if (t != null) {
        // Expand generic type aliases (e.g. Dict<K,V>) to records so codegen FieldExpr can resolve slots.
        n[TypedExpr] = apply(expandGenericAliasHead(t, subst, genericTypeAliasDefs));
      }
      if ('kind' in node && node !== null) {
        const n2 = node as { kind: string; [k: string]: unknown };
        if (n2.kind === 'Program' && Array.isArray(n2.body)) n2.body.forEach((el) => { if (el != null) resolveNode(el); });
        if (n2.kind === 'ValStmt' || n2.kind === 'VarStmt' || n2.kind === 'ValDecl' || n2.kind === 'VarDecl') { resolveNode(n2.value); }
        if (n2.kind === 'ExprStmt') { resolveNode(n2.expr); }
        if (n2.kind === 'FunStmt') resolveNode(n2.body);
        if (n2.kind === 'FunDecl') resolveNode(n2.body);
        if (n2.kind === 'BlockExpr') {
          (n2.stmts as unknown[]).forEach(resolveNode);
          resolveNode(n2.result);
        }
        if (n2.kind === 'IfExpr') { resolveNode(n2.cond); resolveNode(n2.then); if (n2.else !== undefined) resolveNode(n2.else); }
        if (n2.kind === 'IsExpr') resolveNode(n2.expr);
        if (n2.kind === 'WhileExpr') { resolveNode(n2.cond); resolveNode(n2.body); }
        if (n2.kind === 'BinaryExpr') { resolveNode(n2.left); resolveNode(n2.right); }
        if (n2.kind === 'UnaryExpr') { resolveNode(n2.operand); }
        if (n2.kind === 'CallExpr') { resolveNode(n2.callee); (n2.args as unknown[]).forEach(resolveNode); }
        if (n2.kind === 'RecordExpr') (n2.fields as { value: unknown }[]).forEach((f) => resolveNode(f.value));
        if (n2.kind === 'TupleExpr') (n2.elements as unknown[]).forEach(resolveNode);
        if (n2.kind === 'FieldExpr') resolveNode(n2.object);
        if (n2.kind === 'TemplateExpr') (n2.parts as { type: string; expr?: unknown }[]).forEach((p) => { if (p.expr) resolveNode(p.expr); });
        if (n2.kind === 'ListExpr') (n2.elements as unknown[]).forEach(resolveNode);
        if (n2.kind === 'ConsExpr') { resolveNode(n2.head); resolveNode(n2.tail); }
        if (n2.kind === 'MatchExpr') { resolveNode(n2.scrutinee); (n2.cases as { body: unknown }[]).forEach((c) => resolveNode(c.body)); }
        if (n2.kind === 'ThrowExpr') resolveNode(n2.value);
        if (n2.kind === 'TryExpr') { resolveNode(n2.body); (n2.cases as { body: unknown }[]).forEach((c) => resolveNode(c.body)); }
        if (n2.kind === 'AwaitExpr') resolveNode(n2.value);
        if (n2.kind === 'PipeExpr') { resolveNode(n2.left); resolveNode(n2.right); }
        if (n2.kind === 'AssignStmt') { resolveNode(n2.target); resolveNode(n2.value); }
        if (n2.kind === 'LambdaExpr') resolveNode(n2.body);
      }
    }
    resolveNode(program);

    function publicExportNames(dep: DependencyExportSnapshot): Set<string> {
      const s = new Set<string>();
      for (const k of dep.exports.keys()) s.add(k);
      for (const k of dep.exportedConstructors.keys()) s.add(k);
      return s;
    }

    function hasReexportSyntax(p: Program): boolean {
      for (const n of p.body) {
        if (n?.kind !== 'ExportDecl') continue;
        const inner = n.inner;
        if (inner.kind === 'ExportStar' || inner.kind === 'ExportNamed') return true;
      }
      return false;
    }

    const depExportsBySpec = options?.dependencyExportsBySpec;
    if (hasReexportSyntax(program) && depExportsBySpec == null) {
      diagnostics.push({
        severity: 'error',
        code: CODES.type.check,
        message:
          'Re-exports require dependency export metadata (internal error: dependencyExportsBySpec missing).',
        location: locationFileOnly(sourceFile),
      });
    }

    const exports = new Map<string, InternalType>();
    const exportedTypeAliases = new Map<string, InternalType>();
    const exportSourceByName = new Map<string, 'local' | string>();
    const firstExportSpan = new Map<string, Span>();
    const reexports: { exportName: string; spec: string; external: string }[] = [];

    function registerExportSource(name: string, source: 'local' | string, span?: Span): boolean {
      const prev = exportSourceByName.get(name);
      if (prev !== undefined && prev !== source) {
        const prevLoc = firstExportSpan.get(name);
        const prevLabel = prev === 'local' ? 'this module' : `"${prev}"`;
        const srcLabel = source === 'local' ? 'this module' : `"${source}"`;
        diagnostics.push({
          severity: 'error',
          code: CODES.export.reexport_conflict,
          message: `Duplicate export '${name}': already exported from ${prevLabel} and cannot also be exported from ${srcLabel}.`,
          location: span != null ? locFor({ span } as TopLevelDecl) : locationFileOnly(sourceFile),
          related:
            prevLoc != null
              ? [{ message: 'Previous export', location: locFor({ span: prevLoc } as TopLevelDecl) }]
              : undefined,
        });
        return false;
      }
      if (prev === undefined) {
        exportSourceByName.set(name, source);
        if (span != null) firstExportSpan.set(name, span);
      }
      return true;
    }

    function mergeFromDep(
      exportName: string,
      externalName: string,
      spec: string,
      dep: DependencyExportSnapshot,
      span?: Span
    ): void {
      const pub = publicExportNames(dep);
      if (!pub.has(externalName)) {
        diagnostics.push({
          severity: 'error',
          code: CODES.export.not_exported,
          message: `Module ${spec} does not export '${externalName}'`,
          location: span != null ? locFor({ span } as TopLevelDecl) : locationFileOnly(sourceFile),
        });
        return;
      }
      if (!registerExportSource(exportName, spec, span)) return;

      reexports.push({ exportName, spec, external: externalName });

      if (dep.exportedConstructors.has(externalName)) {
        exportedConstructors.set(exportName, dep.exportedConstructors.get(externalName)!);
      }
      if (dep.exportedTypeAliases.has(externalName)) {
        const t = dep.exportedTypeAliases.get(externalName)!;
        exportedTypeAliases.set(exportName, t);
        exports.set(exportName, t);
      } else if (dep.exports.has(externalName)) {
        exports.set(exportName, dep.exports.get(externalName)!);
      }
      const vis = dep.exportedTypeVisibility.get(externalName);
      if (vis !== undefined) {
        exportedTypeVisibility.set(exportName, vis);
      }
    }

    for (const node of program.body) {
      if (!node) continue;

      if (node.kind === 'ExportDecl') {
        const inner = node.inner;
        if (inner.kind === 'ExportStar') {
          const dep = depExportsBySpec?.get(inner.spec);
          if (dep != null) {
            for (const name of publicExportNames(dep)) {
              mergeFromDep(name, name, inner.spec, dep, inner.span ?? node.span);
            }
          }
        } else if (inner.kind === 'ExportNamed') {
          const dep = depExportsBySpec?.get(inner.spec);
          if (dep != null) {
            for (const { external, local } of inner.specs) {
              mergeFromDep(local, external, inner.spec, dep, inner.span ?? node.span);
            }
          }
        }
        continue;
      }

      if (node.kind === 'FunDecl' && node.exported) {
        if (!registerExportSource(node.name, 'local', node.span)) continue;
        const t = env.get(node.name);
        if (t != null) exports.set(node.name, apply(t));
      } else if (node.kind === 'ExternFunDecl' && node.exported) {
        if (!registerExportSource(node.name, 'local', node.span)) continue;
        const t = env.get(node.name);
        if (t != null) exports.set(node.name, apply(t));
      } else if (node.kind === 'ValDecl' || node.kind === 'VarDecl') {
        if (!registerExportSource(node.name, 'local', node.span)) continue;
        const t = env.get(node.name);
        if (t != null) exports.set(node.name, apply(t));
      } else if (node.kind === 'TypeDecl' && (node.visibility === 'export' || node.visibility === 'opaque')) {
        if (!registerExportSource(node.name, 'local', node.span)) continue;
        const genDef = genericTypeAliasDefs.get(node.name);
        if (genDef != null) {
          const exportArgs = genDef.paramVarIds.map((id) => ({ kind: 'var' as const, id }));
          const exportApp: InternalType = { kind: 'app', name: node.name, args: exportArgs };
          exports.set(node.name, apply(exportApp));
          exportedTypeAliases.set(node.name, apply(exportApp));
        } else {
          const t = typeAliases.get(node.name);
          if (t != null) {
            exports.set(node.name, apply(t));
            exportedTypeAliases.set(node.name, apply(t));
          }
        }
        if (node.visibility === 'export' && node.body.kind === 'ADTBody') {
          for (const c of node.body.constructors) {
            registerExportSource(c.name, 'local', c.span ?? node.span);
          }
        }
      } else if (node.kind === 'ExternTypeDecl' && (node.visibility === 'export' || node.visibility === 'opaque')) {
        if (!registerExportSource(node.name, 'local', node.span)) continue;
        const genDef = genericTypeAliasDefs.get(node.name);
        if (genDef != null) {
          const exportArgs = genDef.paramVarIds.map((id) => ({ kind: 'var' as const, id }));
          const exportApp: InternalType = { kind: 'app', name: node.name, args: exportArgs };
          exports.set(node.name, apply(exportApp));
          exportedTypeAliases.set(node.name, apply(exportApp));
        } else {
          const t = typeAliases.get(node.name);
          if (t != null) {
            exports.set(node.name, apply(t));
            exportedTypeAliases.set(node.name, apply(t));
          }
        }
      } else if (node.kind === 'ExceptionDecl' && node.exported) {
        if (!registerExportSource(node.name, 'local', node.span)) continue;
        const t = env.get(node.name);
        if (t != null) exports.set(node.name, apply(t));
      }

      if (node.kind === 'TypeDecl' || node.kind === 'ExternTypeDecl') {
        exportedTypeVisibility.set(node.name, node.visibility);
      }
    }
    if (diagnostics.length > 0) return { ok: false, diagnostics };
    return { ok: true, exports, exportedTypeAliases, exportedTypeVisibility, exportedConstructors, reexports };
  } catch (e) {
    if (e instanceof UnifyError) {
      const err = e as UnifyError & { blameNode?: unknown; relatedNode?: unknown };
      const blame = err.blameNode ?? currentExpr;
      const related = err.relatedNode != null
        ? [{ message: 'expected type from here', location: locFor(err.relatedNode) }]
        : undefined;
      diagnostics.push({
        severity: 'error',
        code: CODES.type.unify,
        message: e.message,
        location: locFor(blame),
        hint: `${typeStr(e.left)} vs ${typeStr(e.right)}`,
        related,
      });
    } else if (e instanceof TypeCheckError) {
      diagnostics.push({
        severity: 'error',
        code:
          e.diagnosticCode ??
          (e.suggestion != null ? CODES.type.unknown_variable : CODES.type.check),
        message: e.message,
        location: locFor(e.node),
        suggestion: e.suggestion,
      });
    } else {
      diagnostics.push({
        severity: 'error',
        code: CODES.type.check,
        message: (e as Error).message,
        location: locationFileOnly(sourceFile),
      });
    }
    return { ok: false, diagnostics };
  }
}

const MAX_SUGGESTION_DISTANCE = 2;

/** Levenshtein distance between two strings. */
function editDistance(a: string, b: string): number {
  const m = a.length;
  const n = b.length;
  const dp: number[][] = Array(m + 1).fill(null).map(() => Array(n + 1).fill(0));
  for (let i = 0; i <= m; i++) dp[i]![0] = i;
  for (let j = 0; j <= n; j++) dp[0]![j] = j;
  for (let i = 1; i <= m; i++) {
    for (let j = 1; j <= n; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1;
      dp[i]![j] = Math.min(
        dp[i - 1]![j]! + 1,
        dp[i]![j - 1]! + 1,
        dp[i - 1]![j - 1]! + cost
      );
    }
  }
  return dp[m]![n]!;
}

/** Return the closest name from candidates within MAX_SUGGESTION_DISTANCE, or undefined. */
function closestName(name: string, candidates: string[]): string | undefined {
  let best: string | undefined;
  let bestDist = MAX_SUGGESTION_DISTANCE + 1;
  for (const c of candidates) {
    const d = editDistance(name, c);
    if (d < bestDist) {
      bestDist = d;
      best = c;
    }
  }
  return best;
}

function typeStr(t: InternalType): string {
  if (t.kind === 'var') return `α${t.id}`;
  if (t.kind === 'prim') return t.name;
  if (t.kind === 'arrow') return `(${t.params.map(typeStr).join(',')}) -> ${typeStr(t.return)}`;
  if (t.kind === 'tuple') return `(${t.elements.map(typeStr).join(' * ')})`;
  if (t.kind === 'app') return `${t.name}<${t.args.map(typeStr).join(',')}>`;
  if (t.kind === 'record') {
    const fields = t.fields.map((f) => f.name + ':' + typeStr(f.type)).join(',');
    return t.row ? `{${fields},...${typeStr(t.row)}}` : `{${fields}}`;
  }
  if (t.kind === 'union') return `${typeStr(t.left)} | ${typeStr(t.right)}`;
  if (t.kind === 'inter') return `${typeStr(t.left)} & ${typeStr(t.right)}`;
  if (t.kind === 'scheme') return `∀[${t.vars.join(',')}].${typeStr(t.body)}`;
  return '?';
}
