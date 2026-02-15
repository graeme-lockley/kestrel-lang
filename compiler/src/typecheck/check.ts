/**
 * Type-checker: infer types and unify (spec 06). With generalization and instantiation.
 */
import type { Program, Expr, TopLevelDecl, TopLevelStmt } from '../ast/nodes.js';
import type { InternalType } from '../types/internal.js';
import { freshVar, prim, tInt, tFloat, tBool, tString, tUnit, resetVarId, freeVars, generalize, instantiate } from '../types/internal.js';
import { astTypeToInternal, astTypeToInternalWithScope } from '../types/from-ast.js';
import { unify, applySubst, UnifyError } from '../types/unify.js';

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

export class TypeCheckError extends Error {
  constructor(
    message: string,
    public node?: unknown
  ) {
    super(message);
    this.name = 'TypeCheckError';
  }
}

export interface TypecheckOptions {
  /** Import bindings (localName -> type) to add to scope before typechecking. */
  importBindings?: Map<string, InternalType>;
}

export function typecheck(program: Program, options?: TypecheckOptions): { ok: true; exports: Map<string, InternalType> } | { ok: false; errors: string[] } {
  resetVarId();
  const errors: string[] = [];
  const subst = new Map<number, InternalType>();
  const env = new Map<string, InternalType>();
  let inAsyncContext = false; // Track if we're in an async function

  // Add import bindings first (so they can be used in the module)
  const importBindings = options?.importBindings;
  if (importBindings) {
    for (const [name, t] of importBindings) env.set(name, t);
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

  function apply(t: InternalType): InternalType {
    return applySubst(t, subst);
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

    for (const c of cases) {
      if (c.pattern.kind === 'WildcardPattern' || c.pattern.kind === 'VarPattern') {
        hasCatchAll = true;
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

    // Check if it's a known ADT (for now, just List)
    const appType = apply(scrutineeType);
    if (appType.kind === 'app' && appType.name === 'List') {
      const required = new Set(['Nil', 'Cons']);
      const missing = [...required].filter(c => !coveredCtors.has(c));
      if (missing.length > 0 && !hasCatchAll) {
        errors.push(`Non-exhaustive match: missing constructors: ${missing.join(', ')}`);
      }
    }
  }

  function inferExpr(expr: Expr): InternalType {
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
        if (t == null) throw new TypeCheckError(`Unknown variable: ${expr.name}`, expr);
        // Instantiate if it's a scheme (polymorphic)
        result = apply(instantiate(t));
        setInferredType(expr, result);
        return result;
      }
      case 'IfExpr': {
        const condT = inferExpr(expr.cond);
        unify(condT, tBool, subst);
        const thenT = inferExpr(expr.then);
        const elseT = inferExpr(expr.else);
        unify(thenT, elseT, subst);
        result = apply(thenT);
        setInferredType(expr, result);
        return result;
      }
      case 'BinaryExpr': {
        const l = inferExpr(expr.left);
        const r = inferExpr(expr.right);
        if (['+', '-', '*', '/', '%', '**'].includes(expr.op)) {
          unify(l, r, subst);
          unify(l, tInt, subst);
          result = apply(l);
        } else if (['==', '!=', '<', '>', '<=', '>='].includes(expr.op)) {
          unify(l, r, subst);
          result = tBool;
        } else if (expr.op === '|' || expr.op === '&') {
          unify(l, tBool, subst);
          unify(r, tBool, subst);
          result = tBool;
        } else {
          result = freshVar();
        }
        setInferredType(expr, result);
        return result;
      }
      case 'UnaryExpr': {
        const operandType = inferExpr(expr.operand);
        if (expr.op === '-' || expr.op === '+') {
          unify(operandType, tInt, subst);
          result = tInt;
        } else if (expr.op === '!') {
          unify(operandType, tBool, subst);
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
          for (const arg of expr.args) inferExpr(arg);
          result = { kind: 'prim', name: 'Unit' };
          setInferredType(expr, result);
          return result;
        }
        const calleeT = inferExpr(expr.callee);
        const argTs = expr.args.map(inferExpr);
        const ret = freshVar();
        const arrow = { kind: 'arrow' as const, params: argTs, return: ret };
        unify(calleeT, arrow, subst);
        result = apply(ret);
        setInferredType(expr, result);
        return result;
      }
      case 'TupleExpr': {
        const elements = expr.elements.map(inferExpr);
        result = apply({ kind: 'tuple', elements });
        setInferredType(expr, result);
        return result;
      }
      case 'BlockExpr': {
        for (const stmt of expr.stmts) {
          if (stmt.kind === 'ValStmt') {
            const t = apply(inferExpr(stmt.value));
            // Generalize: quantify free vars not in environment
            const scheme = generalize(t, envFreeVars());
            env.set(stmt.name, scheme);
          } else if (stmt.kind === 'VarStmt') {
            const t = apply(inferExpr(stmt.value));
            // Var bindings are not generalized (mutable)
            env.set(stmt.name, t);
          } else if (stmt.kind === 'ExprStmt') {
            inferExpr(stmt.expr);
          } else {
            const targetT = inferExpr(stmt.target);
            const v = inferExpr(stmt.value);
            unify(targetT, v, subst);
          }
        }
        result = inferExpr(expr.result);
        setInferredType(expr, result);
        return result;
      }
      case 'LambdaExpr': {
        const paramTs = expr.params.map((p) => p.type ? astTypeToInternal(p.type) : freshVar());
        for (let i = 0; i < expr.params.length; i++) {
          env.set(expr.params[i]!.name, paramTs[i]!);
        }
        const bodyT = inferExpr(expr.body);
        for (let i = 0; i < expr.params.length; i++) {
          env.delete(expr.params[i]!.name);
        }
        result = apply({ kind: 'arrow', params: paramTs, return: bodyT });
        setInferredType(expr, result);
        return result;
      }
      case 'RecordExpr': {
        const fields: { name: string; mut: boolean; type: InternalType }[] = [];
        for (const f of expr.fields) {
          const ft = inferExpr(f.value);
          fields.push({ name: f.name, mut: f.mut ?? false, type: ft });
        }
        // Create a closed record (no row variable) since we know all fields
        result = apply({ kind: 'record', fields });
        setInferredType(expr, result);
        return result;
      }
      case 'FieldExpr': {
        const objT = inferExpr(expr.object);
        const applied = apply(objT);

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
            unify(applied, recordType, subst);
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

        const field = applied.fields.find((f) => f.name === expr.field);
        if (field == null) {
          throw new TypeCheckError(`Unknown field: ${expr.field}`, expr);
        }
        result = apply(field.type);
        setInferredType(expr, result);
        return result;
      }
      case 'MatchExpr': {
        const scrutT = inferExpr(expr.scrutinee);
        checkExhaustive(scrutT, expr.cases, expr);

        // Helper to bind pattern variables
        function bindPattern(pattern: import('../ast/nodes.js').Pattern, patternType: InternalType): string[] {
          const bound: string[] = [];
          if (pattern.kind === 'VarPattern') {
            env.set(pattern.name, patternType);
            bound.push(pattern.name);
          } else if (pattern.kind === 'ConsPattern') {
            // For head :: tail, scrutinee must be List<T>
            const applied = apply(patternType);
            if (applied.kind === 'app' && applied.name === 'List' && applied.args.length === 1) {
              const elemType = applied.args[0]!;
              bound.push(...bindPattern(pattern.head, elemType));
              bound.push(...bindPattern(pattern.tail, patternType)); // tail is also List<T>
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
          const firstT = inferExpr(firstCase.body);
          boundVars.forEach(v => env.delete(v));

          // Check remaining cases unify with first
          for (let i = 1; i < expr.cases.length; i++) {
            const c = expr.cases[i]!;
            const caseVars = bindPattern(c.pattern, scrutT);
            const caseT = inferExpr(c.body);
            caseVars.forEach(v => env.delete(v));
            unify(firstT, caseT, subst);
          }
          result = apply(firstT);
        }
        setInferredType(expr, result);
        return result;
      }
      case 'AwaitExpr': {
        if (!inAsyncContext) {
          throw new TypeCheckError('await can only be used in async functions', expr);
        }
        const taskT = inferExpr(expr.value);
        const applied = apply(taskT);
        // Expect Task<T>
        if (applied.kind === 'app' && applied.name === 'Task' && applied.args.length === 1) {
          result = apply(applied.args[0]!);
        } else {
          throw new TypeCheckError('await expects Task<T> type', expr);
        }
        setInferredType(expr, result);
        return result;
      }
      case 'ThrowExpr': {
        // For now, accept any type for throw (should be exception type)
        inferExpr(expr.value);
        // Throw has bottom type (never returns)
        result = freshVar();
        setInferredType(expr, result);
        return result;
      }
      case 'TryExpr': {
        const blockT = inferExpr(expr.body);
        // Type check catch cases similar to match
        for (const c of expr.cases) {
          if (c.pattern.kind === 'VarPattern') {
            env.set(c.pattern.name, freshVar()); // Exception type
          }
          const caseT = inferExpr(c.body);
          if (c.pattern.kind === 'VarPattern') {
            env.delete(c.pattern.name);
          }
          unify(blockT, caseT, subst);
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
            const firstT = inferExpr(firstElem as Expr);
            // Unify all other elements with first
            for (let i = 1; i < expr.elements.length; i++) {
              const elem = expr.elements[i];
              if (!(typeof elem === 'object' && 'spread' in elem)) {
                const elemT = inferExpr(elem as Expr);
                unify(firstT, elemT, subst);
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
        const headT = inferExpr(expr.head);
        const tailT = inferExpr(expr.tail);
        const applied = apply(tailT);
        if (applied.kind === 'app' && applied.name === 'List' && applied.args.length === 1) {
          unify(headT, applied.args[0]!, subst);
          result = applied;
        } else {
          // Try to unify with List<α>
          const elemT = freshVar();
          unify(tailT, { kind: 'app', name: 'List', args: [elemT] }, subst);
          unify(headT, elemT, subst);
          result = apply({ kind: 'app', name: 'List', args: [elemT] });
        }
        setInferredType(expr, result);
        return result;
      }
      case 'PipeExpr':
        result = freshVar();
        setInferredType(expr, result);
        return result;
      default:
        result = freshVar();
        setInferredType(expr, result);
        return result;
    }
  }

  try {
    for (const node of program.body) {
      if (node.kind === 'FunDecl') {
        const sigScope = new Map<string, InternalType>();
        const paramTs = node.params.map((p) =>
          p.type ? astTypeToInternalWithScope(p.type, sigScope) : freshVar()
        );
        const returnT = astTypeToInternalWithScope(node.returnType, sigScope);

        // Check if async function: return type must be Task<T>
        if (node.async) {
          const rt = apply(returnT);
          if (!(rt.kind === 'app' && rt.name === 'Task')) {
            errors.push(`Async function ${node.name} must return Task<T>`);
          }
        }

        // Pre-bind function name for recursion (will be generalized after body check)
        const fnVar = freshVar();
        env.set(node.name, fnVar);
        // Check body with parameters in scope
        for (let i = 0; i < node.params.length; i++) {
          env.set(node.params[i]!.name, paramTs[i]!);
        }

        // Set async context if this is an async function
        const wasAsync: boolean = inAsyncContext;
        if (node.async) inAsyncContext = true;

        const bodyT = inferExpr(node.body);
        // If body type is a type variable that appears in the return type of a parameter
        // (e.g. S in f: T -> S), the declared return type must be that variable, not a different type.
        const paramReturnVarIds = new Set<number>();
        for (const p of paramTs) {
          const pa = apply(p);
          if (pa.kind === 'arrow') {
            for (const v of freeVars(pa.return)) paramReturnVarIds.add(v);
          }
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
        unify(bodyT, returnT, subst);

        // Restore async context
        inAsyncContext = wasAsync;

        const fnType = { kind: 'arrow' as const, params: paramTs, return: returnT };
        unify(fnVar, fnType, subst);
        // Clean up parameter bindings
        for (let i = 0; i < node.params.length; i++) {
          env.delete(node.params[i]!.name);
        }
        // Generalize: quantify type vars that are not free in the rest of the environment.
        // Temporarily remove current function so its type vars (e.g. β in (β)->β) are not
        // considered "in env" and get correctly quantified for polymorphism.
        env.delete(node.name);
        const appliedFnType = apply(fnType);
        const scheme = generalize(appliedFnType, envFreeVars());
        env.set(node.name, scheme);
      } else if (node.kind === 'TypeDecl') {
        env.set(node.name, astTypeToInternal(node.type));
      } else if (node.kind === 'ValStmt') {
        const t = apply(inferExpr(node.value));
        const scheme = generalize(t, envFreeVars());
        env.set(node.name, scheme);
      } else if (node.kind === 'VarStmt') {
        const t = apply(inferExpr(node.value));
        // Var bindings not generalized
        env.set(node.name, t);
      } else if (node.kind === 'ExprStmt') {
        inferExpr(node.expr);
      } else if (node.kind === 'AssignStmt') {
        const targetT = inferExpr(node.target);
        const valueT = inferExpr(node.value);
        const target = node.target;
        if (target.kind === 'FieldExpr') {
          const objT = apply(getInferredType(target.object) ?? targetT);
          if (objT.kind === 'record') {
            const field = objT.fields.find((f) => f.name === target.field);
            if (field == null) throw new TypeCheckError(`Unknown field: ${target.field}`, target);
            if (!field.mut) throw new TypeCheckError(`Cannot assign to immutable field: ${target.field}`, target);
            unify(valueT, field.type, subst);
          }
        } else if (target.kind === 'IdentExpr') {
          const lhs = env.get(target.name);
          if (lhs != null) unify(valueT, lhs, subst);
        }
      }
    }
    // Resolve all inferred types (apply subst) so codegen sees concrete types
    function resolveNode(node: unknown): void {
      if (node == null || typeof node !== 'object') return;
      const n = node as Record<symbol, InternalType | undefined>;
      const t = n[TypedExpr];
      if (t != null) n[TypedExpr] = apply(t);
      if ('kind' in node && node !== null) {
        const n2 = node as { kind: string; [k: string]: unknown };
        if (n2.kind === 'Program' && Array.isArray(n2.body)) n2.body.forEach(resolveNode);
        if (n2.kind === 'ValStmt' || n2.kind === 'VarStmt') { resolveNode(n2.value); }
        if (n2.kind === 'ExprStmt') { resolveNode(n2.expr); }
        if (n2.kind === 'FunDecl') resolveNode(n2.body);
        if (n2.kind === 'BlockExpr') {
          (n2.stmts as unknown[]).forEach(resolveNode);
          resolveNode(n2.result);
        }
        if (n2.kind === 'IfExpr') { resolveNode(n2.cond); resolveNode(n2.then); resolveNode(n2.else); }
        if (n2.kind === 'BinaryExpr') { resolveNode(n2.left); resolveNode(n2.right); }
        if (n2.kind === 'UnaryExpr') { resolveNode(n2.operand); }
        if (n2.kind === 'CallExpr') { resolveNode(n2.callee); (n2.args as unknown[]).forEach(resolveNode); }
        if (n2.kind === 'RecordExpr') (n2.fields as { value: unknown }[]).forEach((f) => resolveNode(f.value));
        if (n2.kind === 'TupleExpr') (n2.elements as unknown[]).forEach(resolveNode);
        if (n2.kind === 'FieldExpr') resolveNode(n2.object);
        if (n2.kind === 'AssignStmt') { resolveNode(n2.target); resolveNode(n2.value); }
        if (n2.kind === 'LambdaExpr') resolveNode(n2.body);
      }
    }
    resolveNode(program);

    const exports = new Map<string, InternalType>();
    for (const node of program.body) {
      if (node.kind === 'FunDecl') {
        const t = env.get(node.name);
        if (t != null) exports.set(node.name, apply(t));
      }
    }
    return { ok: true, exports };
  } catch (e) {
    if (e instanceof UnifyError) {
      errors.push(`${e.message}: ${typeStr(e.left)} vs ${typeStr(e.right)}`);
    } else if (e instanceof TypeCheckError) {
      errors.push(e.message);
    } else {
      errors.push((e as Error).message);
    }
    return { ok: false, errors };
  }
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
