/**
 * Code generation: typed AST → constant pool + code + function table (spec 04).
 * Covers: module initializer, top-level val/var, fun decls, literals, locals, calls.
 */
import type { Program, Expr, TopLevelStmt } from '../ast/nodes.js';
import type { FunDecl, FunStmt, ValDecl, VarDecl, ExceptionDecl } from '../ast/nodes.js';
import type { ConstantEntry } from '../bytecode/constants.js';
import { ConstTag } from '../bytecode/constants.js';

/** If expr is a literal, return the constant entry for it; else null (export val/var must be constant). */
function literalToConstant(expr: Expr, stringIndex: (s: string) => number): ConstantEntry | null {
  if (expr.kind !== 'LiteralExpr') return null;
  switch (expr.literal) {
    case 'int':
      return { tag: ConstTag.Int, value: parseInt(expr.value, 10) };
    case 'float':
      return { tag: ConstTag.Float, value: parseFloat(expr.value) };
    case 'string':
      return { tag: ConstTag.String, stringIndex: stringIndex(expr.value) };
    case 'char': {
      const ch = expr.value.length >= 2 ? expr.value.slice(1, -1) : expr.value;
      const codePoint = ch.startsWith('\\u') ? parseInt(ch.slice(2), 16) : ch.codePointAt(0) ?? 0;
      return { tag: ConstTag.Char, value: codePoint };
    }
    case 'true':
      return { tag: ConstTag.True };
    case 'false':
      return { tag: ConstTag.False };
    case 'unit':
      return { tag: ConstTag.Unit };
    default:
      return { tag: ConstTag.Unit };
  }
}
import { getInferredType } from '../typecheck/check.js';
import type { ImportedFunctionEntry } from '../bytecode/write.js';
import {
  codeStart,
  codeSlice,
  codeOffset,
  patchI32,
  emitLoadConst,
  emitStoreLocal,
  emitRet,
  emitLoadLocal,
  emitLoadGlobal,
  emitStoreGlobal,
  emitCall,
  emitAllocRecord,
  emitGetField,
  emitSetField,
  emitSpread,
  emitAdd,
  emitSub,
  emitMul,
  emitDiv,
  emitMod,
  emitPow,
  emitEq,
  emitNe,
  emitLt,
  emitLe,
  emitGt,
  emitGe,
  emitJump,
  emitJumpIfFalse,
  emitConstruct,
  emitMatch,
  emitThrow,
  emitTry,
  emitEndTry,
  emitAwait,
  emitCallIndirect,
  emitLoadFn,
  emitMakeClosure,
  codeSave,
  codeRestore,
} from '../bytecode/instructions.js';

export interface FunctionEntry {
  nameIndex: number;
  arity: number;
  codeOffset: number;
}

/** Shape for record literals: field names as string table indices (order = layout). */
export interface ShapeEntry {
  nameIndices: number[];
}


/** Constructor entry for ADT table (spec 03 §10). */
export interface ConstructorEntry {
  nameIndex: number;
  payloadTypeIndex: number; // 0xFFFFFFFF if no payload
}

/** ADT entry for ADT table (spec 03 §10). */
export interface AdtEntry {
  nameIndex: number;
  constructors: ConstructorEntry[];
}

/** Built-in ADT indices (List=0, Option=1, Result=2, Value=3). */
export const ADT_LIST = 0;
export const ADT_OPTION = 1;
export const ADT_RESULT = 2;
export const ADT_VALUE = 3;

/** Constructor lookup: name -> (adtId, ctorIndex, arity). Built after adts array is populated. */
let constructorLookup: Map<string, { adtId: number; ctor: number; arity: number }> | null = null;

/** Resolve constructor to (adtId, ctorIndex, arity). First checks user-defined ADTs, then built-ins. */
function getConstructor(
  name: string,
  argCount: number,
  adts?: AdtEntry[]
): { adtId: number; ctor: number; arity: number } | null {
  // Check user-defined ADTs first (user-defined types take precedence over built-ins with same constructor names)
  if (constructorLookup) {
    const result = constructorLookup.get(name);
    if (result && result.arity === argCount) {
      return result;
    }
  }
  
  // Check built-in constructors
  switch (name) {
    case 'None':
      return argCount === 0 ? { adtId: ADT_OPTION, ctor: 0, arity: 0 } : null;
    case 'Some':
      return argCount === 1 ? { adtId: ADT_OPTION, ctor: 1, arity: 1 } : null;
    case 'Err':
      return argCount === 1 ? { adtId: ADT_RESULT, ctor: 0, arity: 1 } : null;
    case 'Ok':
      return argCount === 1 ? { adtId: ADT_RESULT, ctor: 1, arity: 1 } : null;
    case 'Null':
      return argCount === 0 ? { adtId: ADT_VALUE, ctor: 0, arity: 0 } : null;
    case 'Bool':
      return argCount === 1 ? { adtId: ADT_VALUE, ctor: 1, arity: 1 } : null;
    case 'Int':
      return argCount === 1 ? { adtId: ADT_VALUE, ctor: 2, arity: 1 } : null;
    case 'Float':
      return argCount === 1 ? { adtId: ADT_VALUE, ctor: 3, arity: 1 } : null;
    case 'String':
      return argCount === 1 ? { adtId: ADT_VALUE, ctor: 4, arity: 1 } : null;
    case 'Array':
      return argCount === 1 ? { adtId: ADT_VALUE, ctor: 5, arity: 1 } : null;
    case 'Object':
      return argCount === 1 ? { adtId: ADT_VALUE, ctor: 6, arity: 1 } : null;
  }
  
  return null;
}

/** Match config: constructor name -> (tag index, field count for payload). */
interface MatchConfig {
  size: number;
  ctorToTag: Record<string, number>;
  ctorArity: Record<string, number>;
}

function getMatchConfig(scrutineeType: { kind: string; name?: string } | undefined, adts?: AdtEntry[], userAdtConfigs?: Map<string, MatchConfig>): MatchConfig | null {
  if (scrutineeType?.kind !== 'app' && scrutineeType?.kind !== 'prim') return null;
  const name = scrutineeType.name;
  if (name === 'List') {
    return { size: 2, ctorToTag: { Nil: 0, Cons: 1 }, ctorArity: { Nil: 0, Cons: 2 } };
  }
  if (name === 'Option') {
    return { size: 2, ctorToTag: { None: 0, Some: 1 }, ctorArity: { None: 0, Some: 1 } };
  }
  if (name === 'Result') {
    return { size: 2, ctorToTag: { Err: 0, Ok: 1 }, ctorArity: { Err: 1, Ok: 1 } };
  }
  if (name === 'Value') {
    return {
      size: 7,
      ctorToTag: { Null: 0, Bool: 1, Int: 2, Float: 3, String: 4, Array: 5, Object: 6 },
      ctorArity: { Null: 0, Bool: 1, Int: 1, Float: 1, String: 1, Array: 1, Object: 1 },
    };
  }
  if (name === 'Bool') {
    return { size: 2, ctorToTag: { False: 0, True: 1 }, ctorArity: { False: 0, True: 0 } };
  }
  
  // Check user-defined ADTs using pre-built config map
  if (userAdtConfigs && name) {
    return userAdtConfigs.get(name) ?? null;
  }
  
  return null;
}

export interface CodegenResult {
  stringTable: string[];
  constantPool: ConstantEntry[];
  code: Uint8Array;
  functionTable: FunctionEntry[];
  importSpecifierIndices: number[];
  /** For cross-package CALL; built by compile-file and emitted in section 2 §6.6. */
  importedFunctionTable?: ImportedFunctionEntry[];
  shapes: ShapeEntry[];
  adts: AdtEntry[];
  /** Number of module global slots (init's locals); 0 if none. Used for export var. */
  nGlobals?: number;
  /** For each export var, the function table index of its setter (1-arity). Used for .kti and importer. */
  varSetterIndices?: Map<string, number>;
}

/** Context for codegen: string table, constant pool, and helpers. */
function makeCodegenContext() {
  const stringTable: string[] = [];
  const constantPool: ConstantEntry[] = [];
  /** Map from constant key to pool index for deduplication. */
  const constantKeyToIndex = new Map<string, number>();

  function stringIndex(s: string): number {
    const i = stringTable.indexOf(s);
    if (i >= 0) return i;
    stringTable.push(s);
    return stringTable.length - 1;
  }

  /** Key for constant deduplication (tag + payload). */
  function constantKey(c: ConstantEntry): string {
    switch (c.tag) {
      case ConstTag.Int:
      case ConstTag.Float:
      case ConstTag.Char:
        return `${c.tag}:${c.value}`;
      case ConstTag.String:
        return `${c.tag}:${c.stringIndex}`;
      case ConstTag.False:
      case ConstTag.True:
      case ConstTag.Unit:
        return String(c.tag);
      default:
        return String((c as ConstantEntry).tag);
    }
  }

  function addConstant(c: ConstantEntry): number {
    const key = constantKey(c);
    const existing = constantKeyToIndex.get(key);
    if (existing !== undefined) return existing;
    const i = constantPool.length;
    constantPool.push(c);
    constantKeyToIndex.set(key, i);
    return i;
  }
  return { stringTable, constantPool, stringIndex, addConstant };
}

export interface LambdaEntry {
  arity: number;
  code: Uint8Array;
}

/** Returns true if expr contains a reference to name (excluding params/bound in nested lambdas). */
function bodyReferencesName(expr: Expr, name: string, bound: Set<string>): boolean {
  switch (expr.kind) {
    case 'IdentExpr':
      return expr.name === name && !bound.has(name);
    case 'LambdaExpr': {
      const inner = new Set(bound);
      for (const p of expr.params) inner.add(p.name);
      return bodyReferencesName(expr.body, name, inner);
    }
    case 'BlockExpr': {
      const blockBound = new Set(bound);
      for (const stmt of expr.stmts) {
        if (stmt.kind === 'ValStmt' || stmt.kind === 'VarStmt') {
          blockBound.add(stmt.name);
          if (bodyReferencesName(stmt.value, name, blockBound)) return true;
        } else if (stmt.kind === 'FunStmt') {
          blockBound.add(stmt.name);
          const inner = new Set(blockBound);
          for (const p of stmt.params) inner.add(p.name);
          if (bodyReferencesName(stmt.body, name, inner)) return true;
        } else if (stmt.kind === 'ExprStmt' && bodyReferencesName(stmt.expr, name, blockBound)) return true;
        else if (stmt.kind === 'AssignStmt') {
          if (stmt.target.kind === 'IdentExpr' && bodyReferencesName(stmt.target, name, blockBound)) return true;
          if (bodyReferencesName(stmt.value, name, blockBound)) return true;
        }
      }
      return bodyReferencesName(expr.result, name, blockBound);
    }
    case 'CallExpr':
      if (bodyReferencesName(expr.callee, name, bound)) return true;
      for (const a of expr.args) if (bodyReferencesName(a, name, bound)) return true;
      return false;
    case 'BinaryExpr':
      return bodyReferencesName(expr.left, name, bound) || bodyReferencesName(expr.right, name, bound);
    case 'UnaryExpr':
      return bodyReferencesName(expr.operand, name, bound);
    case 'IfExpr':
      return bodyReferencesName(expr.cond, name, bound) || bodyReferencesName(expr.then, name, bound) || (expr.else != null && bodyReferencesName(expr.else, name, bound));
    case 'MatchExpr':
      if (bodyReferencesName(expr.scrutinee, name, bound)) return true;
      for (const c of expr.cases) if (bodyReferencesName(c.body, name, bound)) return true;
      return false;
    case 'TryExpr':
      if (bodyReferencesName(expr.body, name, bound)) return true;
      for (const c of expr.cases) if (bodyReferencesName(c.body, name, bound)) return true;
      return false;
    case 'PipeExpr':
      return bodyReferencesName(expr.left, name, bound) || bodyReferencesName(expr.right, name, bound);
    case 'ConsExpr':
      return bodyReferencesName(expr.head, name, bound) || bodyReferencesName(expr.tail, name, bound);
    case 'FieldExpr':
      return bodyReferencesName(expr.object, name, bound);
    case 'ThrowExpr':
      return bodyReferencesName(expr.value, name, bound);
    case 'AwaitExpr':
      return bodyReferencesName(expr.value, name, bound);
    case 'TupleExpr':
      return expr.elements.some((e) => bodyReferencesName(e, name, bound));
    case 'ListExpr':
      return expr.elements.some((el) => typeof el === 'object' && 'expr' in el ? bodyReferencesName((el as { expr: Expr }).expr, name, bound) : bodyReferencesName(el as Expr, name, bound));
    case 'RecordExpr':
      return (expr.spread != null && bodyReferencesName(expr.spread, name, bound)) || expr.fields.some((f) => bodyReferencesName(f.value, name, bound));
    case 'TemplateExpr':
      return expr.parts.some((p) => p.type === 'interp' && bodyReferencesName(p.expr, name, bound));
    default:
      return false;
  }
}

/** Single-field shape for ref cells (var by-reference). */
function getRefShapeId(shapes: ShapeEntry[], stringIndex: (s: string) => number): number {
  const refField = stringIndex('0');
  let id = shapes.findIndex((s) => s.nameIndices.length === 1 && s.nameIndices[0] === refField);
  if (id < 0) {
    id = shapes.length;
    shapes.push({ nameIndices: [refField] });
  }
  return id;
}

/** Collect free variables of expr (in scope but not in paramNames), ordered by first occurrence. */
function getFreeVars(
  expr: Expr,
  paramNames: Set<string>,
  scope: Map<string, number>
): string[] {
  const result: string[] = [];
  const seen = new Set<string>();
  const bound = new Set(paramNames);

  function walk(e: Expr): void {
    switch (e.kind) {
      case 'IdentExpr':
        if (scope.has(e.name) && !bound.has(e.name) && !seen.has(e.name)) {
          seen.add(e.name);
          result.push(e.name);
        }
        return;
      case 'LambdaExpr':
        for (const p of e.params) bound.add(p.name);
        walk(e.body);
        for (const p of e.params) bound.delete(p.name);
        return;
      case 'BlockExpr': {
        for (const stmt of e.stmts) {
          if (stmt.kind === 'ValStmt' || stmt.kind === 'VarStmt') {
            bound.add(stmt.name);
            walk(stmt.value);
          } else if (stmt.kind === 'FunStmt') {
            bound.add(stmt.name);
            for (const p of stmt.params) bound.add(p.name);
            walk(stmt.body);
            for (const p of stmt.params) bound.delete(p.name);
          } else if (stmt.kind === 'ExprStmt') walk(stmt.expr);
          else if (stmt.kind === 'AssignStmt') {
            if (stmt.target.kind === 'IdentExpr') walk(stmt.target);
            walk(stmt.value);
          }
        }
        walk(e.result);
        return;
      }
      case 'CallExpr':
        walk(e.callee);
        for (const a of e.args) walk(a);
        return;
      case 'BinaryExpr':
        walk(e.left);
        walk(e.right);
        return;
      case 'UnaryExpr':
        walk(e.operand);
        return;
      case 'IfExpr':
        walk(e.cond);
        walk(e.then);
        if (e.else !== undefined) walk(e.else);
        return;
      case 'MatchExpr':
        walk(e.scrutinee);
        for (const c of e.cases) walk(c.body);
        return;
      case 'TryExpr':
        walk(e.body);
        for (const c of e.cases) walk(c.body);
        return;
      case 'PipeExpr':
        walk(e.left);
        walk(e.right);
        return;
      case 'ConsExpr':
        walk(e.head);
        walk(e.tail);
        return;
      case 'FieldExpr':
        walk(e.object);
        return;
      case 'ThrowExpr':
        walk(e.value);
        return;
      case 'AwaitExpr':
        walk(e.value);
        return;
      case 'TupleExpr':
        for (const el of e.elements) walk(el);
        return;
      case 'ListExpr':
        for (const el of e.elements) {
          if (typeof el === 'object' && 'spread' in el) walk((el as { expr: Expr }).expr);
          else walk(el as Expr);
        }
        return;
      case 'RecordExpr':
        if (e.spread) walk(e.spread);
        for (const f of e.fields) walk(f.value);
        return;
      case 'TemplateExpr':
        for (const p of e.parts) if (p.type === 'interp') walk(p.expr);
        return;
      default:
        return;
    }
  }
  walk(expr);
  return result;
}

/** Emit code for expr; leaves value on stack. funNameToId for CallExpr, shapes for RecordExpr, adts for List/ADT. */
function makeEmitExpr(
  stringIndex: (s: string) => number,
  addConstant: (c: ConstantEntry) => number,
  lambdaEntries: LambdaEntry[],
  funDeclCountRef: { value: number },
): { emitExpr: (
  expr: Expr,
  env: Map<string, number>,
  funNameToId?: Map<string, number>,
  shapes?: ShapeEntry[],
  adts?: AdtEntry[],
  captures?: Map<string, { index: number; isVar: boolean }>,
  varNames?: Set<string>,
  userAdtConfigs?: Map<string, MatchConfig>
) => void; moduleGlobals: Map<string, number> } {
  const moduleGlobals = new Map<string, number>();
  return { moduleGlobals, emitExpr: function emitExpr(
  expr: Expr,
  env: Map<string, number>,
  funNameToId?: Map<string, number>,
  shapes?: ShapeEntry[],
  adts?: AdtEntry[],
  captures?: Map<string, { index: number; isVar: boolean }>,
  varNames?: Set<string>,
  userAdtConfigs?: Map<string, MatchConfig>
): void {
  switch (expr.kind) {
    case 'LiteralExpr': {
      switch (expr.literal) {
        case 'int': {
          const n = parseInt(expr.value, 10);
          const idx = addConstant({ tag: ConstTag.Int, value: n });
          emitLoadConst(idx);
          break;
        }
        case 'float': {
          const f = parseFloat(expr.value);
          const idx = addConstant({ tag: ConstTag.Float, value: f });
          emitLoadConst(idx);
          break;
        }
        case 'string': {
          const idx = addConstant({ tag: ConstTag.String, stringIndex: stringIndex(expr.value) });
          emitLoadConst(idx);
          break;
        }
        case 'char':
          // value is e.g. 'a' or \uXXXX
          const ch = expr.value.length >= 2 ? expr.value.slice(1, -1) : expr.value;
          const codePoint = ch.startsWith('\\u') ? parseInt(ch.slice(2), 16) : ch.codePointAt(0) ?? 0;
          emitLoadConst(addConstant({ tag: ConstTag.Char, value: codePoint }));
          break;
        case 'true':
          emitLoadConst(addConstant({ tag: ConstTag.True }));
          break;
        case 'false':
          emitLoadConst(addConstant({ tag: ConstTag.False }));
          break;
        case 'unit':
          emitLoadConst(addConstant({ tag: ConstTag.Unit }));
          break;
        default:
          emitLoadConst(addConstant({ tag: ConstTag.Unit }));
      }
      break;
    }
    case 'TemplateExpr': {
      const emptyIdx = addConstant({ tag: ConstTag.String, stringIndex: stringIndex('') });
      emitLoadConst(emptyIdx);
      for (const part of expr.parts) {
        if (part.type === 'literal') {
          const idx = addConstant({ tag: ConstTag.String, stringIndex: stringIndex(part.value) });
          emitLoadConst(idx);
        } else {
          emitExpr(part.expr, env, funNameToId, shapes, adts, captures, varNames);
          emitCall(0xffffff03, 1); // format value -> string
        }
        emitCall(0xffffff04, 2); // concat(top-1, top) -> result
      }
      break;
    }
    case 'IdentExpr': {
      const cap = captures?.get(expr.name);
      if (cap !== undefined) {
        emitLoadLocal(0);
        emitGetField(cap.index);
        if (cap.isVar) emitGetField(0);
        break;
      }
      const slot = env.get(expr.name);
      if (slot !== undefined) {
        emitLoadLocal(slot);
        if (varNames?.has(expr.name)) emitGetField(0);
        break;
      }
      // 0-ary constructors: None, Null, and user-defined nullary constructors
      if (adts != null) {
        const ctor = getConstructor(expr.name, 0, adts);
        if (ctor != null) {
          emitConstruct(ctor.adtId, ctor.ctor, ctor.arity);
          break;
        }
      }
      const globalSlot = moduleGlobals.get(expr.name);
      if (globalSlot !== undefined) {
        emitLoadGlobal(globalSlot);
        break;
      }
      // Imported value (export val/var) is a 0-arity function; call it to get the value
      const fnId = funNameToId?.get(expr.name);
      if (fnId !== undefined) {
        emitCall(fnId, 0);
        break;
      }
      throw new Error(`Codegen: unknown variable ${expr.name}`);
    }
    case 'BinaryExpr': {
      if (expr.op === '&') {
        // a & b: eval a; JUMP_IF_FALSE pops a – if false, push False; else eval b (result)
        emitExpr(expr.left, env, funNameToId, shapes, adts, captures, varNames);
        const andSkipPos = codeOffset();
        emitJumpIfFalse(0);
        emitExpr(expr.right, env, funNameToId, shapes, adts, captures, varNames);
        const andJumpOverFalse = codeOffset();
        emitJump(0);
        const andPushFalsePos = codeOffset();
        emitLoadConst(addConstant({ tag: ConstTag.False }));
        const andEnd = codeOffset();
        patchI32(andSkipPos + 1, andPushFalsePos - (andSkipPos + 5));
        patchI32(andJumpOverFalse + 1, andEnd - (andJumpOverFalse + 5));
        break;
      }
      if (expr.op === '|') {
        // a | b: eval a; if true push true and skip b; else eval b
        emitExpr(expr.left, env, funNameToId, shapes, adts, captures, varNames);
        const orEvalRightPos = codeOffset();
        emitJumpIfFalse(0); // patch: when false, go eval right
        emitLoadConst(addConstant({ tag: ConstTag.True }));
        const orJumpToEnd = codeOffset();
        emitJump(0); // patch: skip right
        const orRightStart = codeOffset();
        emitExpr(expr.right, env, funNameToId, shapes, adts, captures, varNames);
        const orEnd = codeOffset();
        patchI32(orEvalRightPos + 1, orRightStart - (orEvalRightPos + 5));
        patchI32(orJumpToEnd + 1, orEnd - (orJumpToEnd + 5));
        break;
      }
emitExpr(expr.left, env, funNameToId, shapes, adts, captures, varNames);
        emitExpr(expr.right, env, funNameToId, shapes, adts, captures, varNames);
      switch (expr.op) {
        case '+': emitAdd(); break;
        case '-': emitSub(); break;
        case '*': emitMul(); break;
        case '/': emitDiv(); break;
        case '%': emitMod(); break;
        case '**': emitPow(); break;
        case '==': emitEq(); break;
        case '!=': emitNe(); break;
        case '<': emitLt(); break;
        case '<=': emitLe(); break;
        case '>': emitGt(); break;
        case '>=': emitGe(); break;
        default:
          throw new Error(`Codegen: unsupported binary op ${expr.op}`);
      }
      break;
    }
    case 'UnaryExpr': {
      if (expr.op === '-') {
        // Unary minus: 0 - operand
        emitLoadConst(addConstant({ tag: ConstTag.Int, value: 0 }));
        emitExpr(expr.operand, env, funNameToId, shapes, adts, captures, varNames);
        emitSub();
      } else if (expr.op === '+') {
        // Unary plus: just emit operand
        emitExpr(expr.operand, env, funNameToId, shapes, adts, captures, varNames);
      } else if (expr.op === '!') {
        // Logical not: constant-fold !True -> False, !False -> True; else (x == False)
        const op = expr.operand;
        if (op.kind === 'LiteralExpr' && (op.literal === 'true' || op.literal === 'false')) {
          emitLoadConst(addConstant({ tag: op.literal === 'true' ? ConstTag.False : ConstTag.True }));
        } else {
          emitExpr(expr.operand, env, funNameToId, shapes, adts, captures, varNames);
          emitLoadConst(addConstant({ tag: ConstTag.False }));
          emitEq();
        }
      } else {
        throw new Error(`Codegen: unsupported unary op ${expr.op}`);
      }
      break;
    }
    case 'IfExpr': {
      emitExpr(expr.cond, env, funNameToId, shapes, adts, captures, varNames);
      const jumpIfFalsePos = codeOffset();
      emitJumpIfFalse(0); // patch later
      emitExpr(expr.then, env, funNameToId, shapes, adts, captures, varNames);
      const jumpOverElsePos = codeOffset();
      emitJump(0); // patch later
      const elseStart = codeOffset();
      if (expr.else !== undefined) {
        emitExpr(expr.else, env, funNameToId, shapes, adts, captures, varNames);
      } else {
        emitLoadConst(addConstant({ tag: ConstTag.Unit }));
      }
      const afterElse = codeOffset();
      patchI32(jumpIfFalsePos + 1, elseStart - (jumpIfFalsePos + 5));
      patchI32(jumpOverElsePos + 1, afterElse - (jumpOverElsePos + 5));
      break;
    }
    case 'BlockExpr': {
      const blockEnv = new Map(env);
      const blockVarNames = new Set<string>(expr.stmts.filter((s): s is { kind: 'VarStmt'; name: string; value: Expr } => s.kind === 'VarStmt').map((s) => s.name));
      const nextVarNames = new Set(varNames ?? []);
      for (const n of blockVarNames) nextVarNames.add(n);
      const hasExprStmt = expr.stmts.some((s) => s.kind === 'ExprStmt');
      const hasAssignStmt = expr.stmts.some((s) => s.kind === 'AssignStmt');
      const needsDiscard = hasExprStmt || hasAssignStmt;
      // When inside a closure, reserve slots 0 and 1 for env and first param so block locals don't overwrite them
      const blockLocalStart = captures != null ? Math.max(blockEnv.size, 2) : blockEnv.size;
      if (needsDiscard) {
        blockEnv.set('$discard', blockLocalStart);
        // Pad so next VarStmt/ValStmt gets blockLocalStart + 1 (so $discard and first var don't collide)
        for (let i = blockEnv.size; i < blockLocalStart + 1; i++) blockEnv.set(`\x00_${i}`, i);
      }
      // Bind all block-level fun names so any later statement (including ExprStmt/result) can reference them
      const funStmts = expr.stmts.filter((s): s is FunStmt => s.kind === 'FunStmt');
      // When there are block-level funs, never use slot 1: the enclosing closure may have param at 1 (e.g. sg);
      // storing the closure in slot 1 would overwrite it and cause wrong env/ptr → bus error.
      let nextSlot = funStmts.length > 0 ? Math.max(blockEnv.size, 2) : blockEnv.size;
      for (const s of funStmts) {
        blockEnv.set(s.name, nextSlot);
        nextSlot++;
      }
/** Use the block's own sharedRecordTemp so the record slot is in block scope and doesn't collide with caller (second block in same scope was reading a caller slot when using fixed high slot). */
      const sharedRecordTemp = nextSlot;
      const closureTemp = nextSlot + 1;
      const unitTemp = nextSlot + 2; // for mutual recursion: pop SET_FIELD Unit without overwriting record
      // Reserve these slots so Phase 1 (ValStmt/VarStmt) doesn't use them
      blockEnv.set('\x00_record', sharedRecordTemp);
      blockEnv.set('\x00_closure', closureTemp);
      blockEnv.set('\x00_unit', unitTemp);

      // Phase 1: iterate stmts in source order, emitting val/var/expr/assign as they appear.
      // FunStmt closures (Phase 2) are emitted lazily: the moment the first ExprStmt or
      // AssignStmt is reached that follows at least one FunStmt in source order, Phase 2 runs
      // inline so FunStmt closures are ready before any stmt that might reference them.
      // If no such stmt exists (FunStmts only precede the result expr), Phase 2 runs after the loop.
      const mutualFunNames: string[] = [];
      let seenFunStmtInSource = false;
      let phase2Emitted = false;

      const emitPhase2 = () => {
        if (phase2Emitted) return;
        phase2Emitted = true;
      if (funStmts.length >= 2 && shapes) {
        // Mutual recursion: one shared record, same shape for all closures
        const funNames = funStmts.map((s) => s.name);
        mutualFunNames.push(...funNames);
        const otherFreeSet = new Set<string>();
        for (const s of funStmts) {
          const paramNames = new Set(s.params.map((p) => p.name));
          const fv = getFreeVars(s.body, paramNames, blockEnv);
          for (const n of fv) if (!funNames.includes(n)) otherFreeSet.add(n);
        }
        const otherFree = Array.from(otherFreeSet);
        const shapeNames = [...funNames, ...otherFree];
        const nameIndices = shapeNames.map((s) => stringIndex(s));
        let shapeId = shapes.findIndex(
          (s) =>
            s.nameIndices.length === nameIndices.length &&
            s.nameIndices.every((n, i) => n === nameIndices[i])
        );
        if (shapeId < 0) {
          shapeId = shapes.length;
          shapes.push({ nameIndices });
        }
        const captureMap = new Map<string, { index: number; isVar: boolean }>();
        shapeNames.forEach((name, i) => captureMap.set(name, { index: i, isVar: nextVarNames?.has(name) ?? false }));

        // Compile all N bodies (same captureMap; each gets __env at 0, params at 1,2,...)
        const mutualLambdaIndices: number[] = [];
        for (const stmt of funStmts) {
          const liftedEnv = new Map<string, number>();
          liftedEnv.set('__env', 0);
          for (let i = 0; i < stmt.params.length; i++) liftedEnv.set(stmt.params[i]!.name, i + 1);
          const saved = codeSave();
          codeStart();
          emitExpr(stmt.body, liftedEnv, funNameToId, shapes, adts, captureMap, undefined);
          emitRet();
          const lambdaCode = codeSlice();
          codeRestore(saved);
          const lambdaIndex = funDeclCountRef.value + lambdaEntries.length;
          lambdaEntries.push({ arity: stmt.params.length + 1, code: lambdaCode });
          mutualLambdaIndices.push(lambdaIndex);
        }

        // Allocate shared record: fun slots = Unit, other = load from blockEnv
        for (const name of shapeNames) {
          if (funNames.includes(name)) {
            emitLoadConst(addConstant({ tag: ConstTag.Unit }));
          } else {
            const localSlot = blockEnv.get(name);
            if (localSlot !== undefined) {
              emitLoadLocal(localSlot);
            } else {
              const globalSlot = moduleGlobals.get(name);
              if (globalSlot !== undefined) {
                emitLoadGlobal(globalSlot);
              } else {
                const fnId = funNameToId?.get(name);
                if (fnId !== undefined) {
                  emitLoadFn(fnId);
                }
              }
            }
          }
        }
        emitAllocRecord(shapeId);
        emitStoreLocal(sharedRecordTemp);

        // For each fun: make closure, patch record field, store in block slot
        for (let i = 0; i < funStmts.length; i++) {
          const stmt = funStmts[i]!;
          const lambdaIndex = mutualLambdaIndices[i]!;
          const slot = blockEnv.get(stmt.name)!;
          emitLoadLocal(sharedRecordTemp);
          emitMakeClosure(lambdaIndex);
          emitStoreLocal(closureTemp);
          emitLoadLocal(sharedRecordTemp);
          emitLoadLocal(closureTemp);
          emitSetField(i);
          emitStoreLocal(unitTemp); // pop Unit result of SET_FIELD (do not overwrite record)
          emitLoadLocal(closureTemp);
          emitStoreLocal(slot);
        }
        // Reload closures from record into slots
        for (let i = 0; i < funStmts.length; i++) {
          const slot = blockEnv.get(funStmts[i]!.name)!;
          emitLoadLocal(sharedRecordTemp);
          emitGetField(i);
          emitStoreLocal(slot);
        }
      } else {
        // Single fun or no fun: process each FunStmt with current behavior
        for (const stmt of expr.stmts) {
          if (stmt.kind !== 'FunStmt') continue;
          const paramNames = new Set(stmt.params.map((p) => p.name));
          let freeVars = getFreeVars(stmt.body, paramNames, blockEnv);
          const hasSelf = bodyReferencesName(stmt.body, stmt.name, new Set(paramNames));
          if (hasSelf) {
            freeVars = [stmt.name, ...freeVars.filter((n) => n !== stmt.name)];
          }
          const slot = blockEnv.get(stmt.name)!;
          if (freeVars.length === 0) {
            const saved = codeSave();
            codeStart();
            const lambdaEnv = new Map<string, number>();
            for (let i = 0; i < stmt.params.length; i++) lambdaEnv.set(stmt.params[i]!.name, i);
            emitExpr(stmt.body, lambdaEnv, funNameToId, shapes, adts, captures, nextVarNames);
            emitRet();
            const lambdaCode = codeSlice();
            codeRestore(saved);
            const lambdaIndex = funDeclCountRef.value + lambdaEntries.length;
            lambdaEntries.push({ arity: stmt.params.length, code: lambdaCode });
            emitLoadFn(lambdaIndex);
            emitStoreLocal(slot);
          } else {
            if (!shapes) break;
            const nameIndices = freeVars.map((s) => stringIndex(s));
            let shapeId = shapes.findIndex(
              (s) =>
                s.nameIndices.length === nameIndices.length &&
                s.nameIndices.every((n, i) => n === nameIndices[i])
            );
            if (shapeId < 0) {
              shapeId = shapes.length;
              shapes.push({ nameIndices });
            }
            const singleCaptureMap = new Map<string, { index: number; isVar: boolean }>();
            freeVars.forEach((name, i) => singleCaptureMap.set(name, { index: i, isVar: nextVarNames?.has(name) ?? false }));
            const liftedEnv = new Map<string, number>();
            liftedEnv.set('__env', 0);
            for (let i = 0; i < stmt.params.length; i++) liftedEnv.set(stmt.params[i]!.name, i + 1);
            const saved = codeSave();
            codeStart();
            emitExpr(stmt.body, liftedEnv, funNameToId, shapes, adts, singleCaptureMap, undefined);
            emitRet();
            const lambdaCode = codeSlice();
            codeRestore(saved);
            const lambdaIndex = funDeclCountRef.value + lambdaEntries.length;
            lambdaEntries.push({ arity: stmt.params.length + 1, code: lambdaCode });
            for (const name of freeVars) {
              if (name === stmt.name) {
                emitLoadConst(addConstant({ tag: ConstTag.Unit }));
              } else {
                const localSlot = blockEnv.get(name);
                if (localSlot !== undefined) {
                  emitLoadLocal(localSlot);
                } else {
                  const globalSlot = moduleGlobals.get(name);
                  if (globalSlot !== undefined) {
                    emitLoadGlobal(globalSlot);
                  } else {
                    const fnId = funNameToId?.get(name);
                    if (fnId !== undefined) {
                      emitLoadFn(fnId);
                    }
                  }
                }
              }
            }
            emitAllocRecord(shapeId);
            if (hasSelf) {
              const envTemp = slot + 1;
              const closureTempSingle = slot + 2;
              emitStoreLocal(envTemp);
              emitLoadLocal(envTemp);
              emitMakeClosure(lambdaIndex);
              emitStoreLocal(closureTempSingle);
              emitLoadLocal(envTemp);      // record at sp-2 for SET_FIELD
              emitLoadLocal(closureTempSingle); // closure at sp-1 (value to store in record)
              emitSetField(0);
              emitStoreLocal(envTemp);          // pop Unit result of SET_FIELD (envTemp no longer needed)
              emitLoadLocal(closureTempSingle);
            } else {
              emitMakeClosure(lambdaIndex);
            }
            emitStoreLocal(slot);
          }
        }
      }
      };

      for (const stmt of expr.stmts) {
        if (stmt.kind === 'ValStmt') {
          emitExpr(stmt.value, blockEnv, funNameToId, shapes, adts, captures, nextVarNames);
          const slot = blockEnv.size;
          blockEnv.set(stmt.name, slot);
          emitStoreLocal(slot);
        } else if (stmt.kind === 'VarStmt') {
          if (!shapes) break;
          const refShapeId = getRefShapeId(shapes, stringIndex);
          const slot = blockEnv.size;
          blockEnv.set(stmt.name, slot);
          emitExpr(stmt.value, blockEnv, funNameToId, shapes, adts, captures, nextVarNames);
          emitAllocRecord(refShapeId);
          emitStoreLocal(slot);
        } else if (stmt.kind === 'ExprStmt') {
          if (seenFunStmtInSource) emitPhase2();
          emitExpr(stmt.expr, blockEnv, funNameToId, shapes, adts, captures, nextVarNames);
          const discardSlot = blockEnv.get('$discard');
          if (discardSlot !== undefined) emitStoreLocal(discardSlot);
        } else if (stmt.kind === 'AssignStmt') {
          if (seenFunStmtInSource) emitPhase2();
          const target = stmt.target;
          if (target.kind === 'FieldExpr') {
            const objType = getInferredType(target.object);
            let fieldSlot = -1;
            if (objType?.kind === 'record') {
              fieldSlot = objType.fields.findIndex((f) => f.name === target.field);
            }
            if (fieldSlot >= 0) {
              emitExpr(target.object, blockEnv, funNameToId, shapes, adts, captures, nextVarNames);
              emitExpr(stmt.value, blockEnv, funNameToId, shapes, adts, captures, nextVarNames);
              emitSetField(fieldSlot);
            }
          } else if (target.kind === 'IdentExpr') {
            const cap = captures?.get(target.name);
            if (cap?.isVar) {
              emitLoadLocal(0);
              emitGetField(cap.index);
              emitExpr(stmt.value, blockEnv, funNameToId, shapes, adts, captures, nextVarNames);
              emitSetField(0);
              const discardSlotCap = blockEnv.get('$discard');
              if (discardSlotCap !== undefined) emitStoreLocal(discardSlotCap);
            } else {
              const localSlot = blockEnv.get(target.name);
              if (localSlot !== undefined && nextVarNames.has(target.name)) {
                emitLoadLocal(localSlot);
                emitExpr(stmt.value, blockEnv, funNameToId, shapes, adts, captures, nextVarNames);
                emitSetField(0);
                const discardSlot = blockEnv.get('$discard');
                if (discardSlot !== undefined) emitStoreLocal(discardSlot);
              } else {
                emitExpr(stmt.value, blockEnv, funNameToId, shapes, adts, captures, nextVarNames);
                if (localSlot !== undefined) {
                  emitStoreLocal(localSlot);
                } else {
                  const gSlot = moduleGlobals.get(target.name);
                  if (gSlot !== undefined) {
                    emitStoreGlobal(gSlot);
                  }
                }
              }
            }
          }
        } else if (stmt.kind === 'FunStmt') {
          seenFunStmtInSource = true;
        }
      }
      emitPhase2();
      {
        const result = expr.result;
        if (
          mutualFunNames.length > 0 &&
          result.kind === 'CallExpr' &&
          result.callee.kind === 'IdentExpr' &&
          mutualFunNames.includes(result.callee.name)
        ) {
          const fieldIndex = mutualFunNames.indexOf(result.callee.name);
          emitLoadLocal(sharedRecordTemp);
          emitGetField(fieldIndex);
          for (const arg of result.args) emitExpr(arg, blockEnv, funNameToId, shapes, adts, captures, nextVarNames);
          emitCallIndirect(result.args.length);
        } else {
          emitExpr(expr.result, blockEnv, funNameToId, shapes, adts, captures, nextVarNames);
        }
      }
      break;
    }
    case 'TupleExpr': {
      if (!shapes || expr.elements.length === 0) break;
      const nameIndices = expr.elements.map((_, i) => stringIndex(String(i)));
      let shapeId = shapes.findIndex((s) => s.nameIndices.length === nameIndices.length && s.nameIndices.every((n, i) => n === nameIndices[i]));
      if (shapeId < 0) {
        shapeId = shapes.length;
        shapes.push({ nameIndices: [...nameIndices] });
      }
      for (const e of expr.elements) emitExpr(e, env, funNameToId, shapes, adts, captures, varNames);
      emitAllocRecord(shapeId);
      break;
    }
    case 'RecordExpr': {
      if (!shapes) break;
      if (expr.spread == null) {
        // Non-spread record: { x = e, y = f }
        const nameIndices = expr.fields.map((f) => stringIndex(f.name));
        let shapeId = shapes.findIndex((s) => s.nameIndices.length === nameIndices.length && s.nameIndices.every((n, i) => n === nameIndices[i]));
        if (shapeId < 0) {
          shapeId = shapes.length;
          shapes.push({ nameIndices: [...nameIndices] });
        }
        for (const f of expr.fields) emitExpr(f.value, env, funNameToId, shapes, adts, captures, varNames);
        emitAllocRecord(shapeId);
        break;
      }
      // Record spread: { ...base, ...fields }
      const baseType = getInferredType(expr.spread);
      const extendedType = getInferredType(expr);
      if (baseType?.kind !== 'record' || extendedType?.kind !== 'record') break;
      const baseFields = baseType.fields;
      const extendedFields = extendedType.fields;
      const baseCount = baseFields.length;
      const extendedCount = extendedFields.length;
      const exprFieldsByName = new Map(expr.fields.map((f) => [f.name, f]));

      // Extended shape (for both SPREAD and override path)
      const extendedNameIndices = extendedFields.map((f) => stringIndex(f.name));
      let extendedShapeId = shapes.findIndex(
        (s) => s.nameIndices.length === extendedNameIndices.length && s.nameIndices.every((n, i) => n === extendedNameIndices[i])
      );
      if (extendedShapeId < 0) {
        extendedShapeId = shapes.length;
        shapes.push({ nameIndices: [...extendedNameIndices] });
      }

      if (extendedCount > baseCount) {
        // SPREAD path: VM pops record first (top), then n_extra values (04 §1.8). So push additional values first, then record.
        for (let i = baseCount; i < extendedCount; i++) {
          const name = extendedFields[i]!.name;
          const fieldExpr = exprFieldsByName.get(name);
          if (fieldExpr) emitExpr(fieldExpr.value, env, funNameToId, shapes, adts, captures, varNames);
        }
        emitExpr(expr.spread, env, funNameToId, shapes, adts, captures, varNames);
        emitSpread(extendedShapeId);
      } else {
        // Override-only: build record manually (base shape + overrides). Temp slot for base record.
        const tempSlot = env.size;
        env.set('$spreadBase', tempSlot);
        emitExpr(expr.spread, env, funNameToId, shapes, adts, captures, varNames);
        emitStoreLocal(tempSlot);
        for (let i = 0; i < extendedCount; i++) {
          const name = extendedFields[i]!.name;
          const fieldExpr = exprFieldsByName.get(name);
          if (fieldExpr) {
            emitExpr(fieldExpr.value, env, funNameToId, shapes, adts, captures, varNames);
          } else {
            const baseSlot = baseFields.findIndex((f) => f.name === name);
            if (baseSlot >= 0) {
              emitLoadLocal(tempSlot);
              emitGetField(baseSlot);
            }
          }
        }
        emitAllocRecord(extendedShapeId);
      }
      break;
    }
    case 'FieldExpr': {
      const objType = getInferredType(expr.object);
      let slot = -1;
      if (objType?.kind === 'tuple') {
        const i = parseInt(expr.field, 10);
        if (i >= 0 && i < objType.elements.length) slot = i;
      } else if (objType?.kind === 'record') {
        slot = objType.fields.findIndex((f) => f.name === expr.field);
      } else if (expr.object.kind === 'RecordExpr') {
        slot = expr.object.fields.findIndex((f) => f.name === expr.field);
      } else if (expr.object.kind === 'TupleExpr') {
        const i = parseInt(expr.field, 10);
        if (i >= 0 && i < expr.object.elements.length) slot = i;
      }
      if (slot >= 0) {
        emitExpr(expr.object, env, funNameToId, shapes, adts, captures, varNames);
        emitGetField(slot);
        break;
      }
      emitLoadConst(addConstant({ tag: ConstTag.Unit }));
      break;
    }
    case 'CallExpr': {
      if (expr.callee.kind === 'IdentExpr') {
        // Check for builtin primitives: print (no newline), println (newline)
        if (expr.callee.name === 'print') {
          for (const arg of expr.args) emitExpr(arg, env, funNameToId, shapes, adts, captures, varNames);
          emitCall(0xFFFFFF00, expr.args.length);
          break;
        }
        if (expr.callee.name === 'println') {
          for (const arg of expr.args) emitExpr(arg, env, funNameToId, shapes, adts, captures, varNames);
          emitCall(0xFFFFFF01, expr.args.length);
          break;
        }
        if (expr.callee.name === 'exit' && expr.args.length === 1) {
          emitExpr(expr.args[0]!, env, funNameToId, shapes, adts, captures, varNames);
          emitCall(0xFFFFFF02, 1);
          break;
        }
        if (expr.callee.name === '__json_parse' && expr.args.length === 1) {
          emitExpr(expr.args[0]!, env, funNameToId, shapes, adts, captures, varNames);
          emitCall(0xFFFFFF05, 1);
          break;
        }
        if (expr.callee.name === '__json_stringify' && expr.args.length === 1) {
          emitExpr(expr.args[0]!, env, funNameToId, shapes, adts, captures, varNames);
          emitCall(0xFFFFFF06, 1);
          break;
        }
        if (expr.callee.name === '__read_file_async' && expr.args.length === 1) {
          emitExpr(expr.args[0]!, env, funNameToId, shapes, adts, captures, varNames);
          emitCall(0xFFFFFF07, 1);
          break;
        }
        if (expr.callee.name === '__now_ms' && expr.args.length === 0) {
          emitCall(0xFFFFFF08, 0);
          break;
        }
        if (expr.callee.name === '__string_length' && expr.args.length === 1) {
          emitExpr(expr.args[0]!, env, funNameToId, shapes, adts, captures, varNames);
          emitCall(0xFFFFFF09, 1);
          break;
        }
        if (expr.callee.name === '__string_slice' && expr.args.length === 3) {
          for (const arg of expr.args) emitExpr(arg, env, funNameToId, shapes, adts, captures, varNames);
          emitCall(0xFFFFFF0A, 3);
          break;
        }
        if (expr.callee.name === '__string_index_of' && expr.args.length === 2) {
          emitExpr(expr.args[0]!, env, funNameToId, shapes, adts, captures, varNames);
          emitExpr(expr.args[1]!, env, funNameToId, shapes, adts, captures, varNames);
          emitCall(0xFFFFFF0B, 2);
          break;
        }
        if (expr.callee.name === '__string_equals' && expr.args.length === 2) {
          emitExpr(expr.args[0]!, env, funNameToId, shapes, adts, captures, varNames);
          emitExpr(expr.args[1]!, env, funNameToId, shapes, adts, captures, varNames);
          emitCall(0xFFFFFF0C, 2);
          break;
        }
        if (expr.callee.name === '__string_upper' && expr.args.length === 1) {
          emitExpr(expr.args[0]!, env, funNameToId, shapes, adts, captures, varNames);
          emitCall(0xFFFFFF0D, 1);
          break;
        }
        if (expr.callee.name === '__format_one' && expr.args.length === 1) {
          emitExpr(expr.args[0]!, env, funNameToId, shapes, adts, captures, varNames);
          emitCall(0xFFFFFF03, 1);
          break;
        }
        if (expr.callee.name === '__print_one' && expr.args.length === 1) {
          emitExpr(expr.args[0]!, env, funNameToId, shapes, adts, captures, varNames);
          emitCall(0xFFFFFF00, 1);
          break;
        }
        if (expr.callee.name === '__equals' && expr.args.length === 2) {
          for (const arg of expr.args) emitExpr(arg, env, funNameToId, shapes, adts, captures, varNames);
          emitCall(0xFFFFFF0E, 2);
          break;
        }
        if (expr.callee.name === '__get_process' && expr.args.length === 0) {
          emitCall(0xFFFFFF0F, 0);
          break;
        }
        if (expr.callee.name === '__get_os' && expr.args.length === 0) {
          emitCall(0xFFFFFF13, 0);
          break;
        }
        if (expr.callee.name === '__get_args' && expr.args.length === 0) {
          emitCall(0xFFFFFF14, 0);
          break;
        }
        if (expr.callee.name === '__get_cwd' && expr.args.length === 0) {
          emitCall(0xFFFFFF15, 0);
          break;
        }
        if (expr.callee.name === '__list_dir' && expr.args.length === 1) {
          emitExpr(expr.args[0]!, env, funNameToId, shapes, adts, captures, varNames);
          emitCall(0xFFFFFF10, 1);
          break;
        }
        if (expr.callee.name === '__write_text' && expr.args.length === 2) {
          for (const arg of expr.args) emitExpr(arg, env, funNameToId, shapes, adts, captures, varNames);
          emitCall(0xFFFFFF11, 2);
          break;
        }
        if (expr.callee.name === '__run_process' && expr.args.length === 2) {
          for (const arg of expr.args) emitExpr(arg, env, funNameToId, shapes, adts, captures, varNames);
          emitCall(0xFFFFFF12, 2);
          break;
        }

        // Built-in ADT constructors: Some(x), Ok(x), Err(e), Null(), Bool(x), Int(x), etc.
        // Also handles user-defined ADT constructors
        if (adts != null) {
          const ctor = getConstructor(expr.callee.name, expr.args.length, adts);
          if (ctor != null) {
            for (const arg of expr.args) emitExpr(arg, env, funNameToId, shapes, adts, captures, varNames);
            emitConstruct(ctor.adtId, ctor.ctor, ctor.arity);
            break;
          }
        }

        // Check for user-defined function
        if (funNameToId != null) {
          const fnId = funNameToId.get(expr.callee.name);
          if (fnId !== undefined) {
            for (const arg of expr.args) emitExpr(arg, env, funNameToId, shapes, adts, captures, varNames);
            emitCall(fnId, expr.args.length);
            break;
          }
        }

        // Callee is a capture (e.g. self-reference in recursive nested fun); always a closure, not a var
        const capCallee = captures?.get(expr.callee.name);
        if (capCallee !== undefined) {
          emitLoadLocal(0);
          emitGetField(capCallee.index);
          for (const arg of expr.args) emitExpr(arg, env, funNameToId, shapes, adts, captures, varNames);
          emitCallIndirect(expr.args.length);
          break;
        }

        // Local variable holding a function value (closure / lambda)
        const localSlot = env.get(expr.callee.name);
        if (localSlot !== undefined) {
          emitLoadLocal(localSlot);
          for (const arg of expr.args) emitExpr(arg, env, funNameToId, shapes, adts, captures, varNames);
          emitCallIndirect(expr.args.length);
          break;
        }
      }
      // Callee is an expression (e.g. makeAdd(2) — call that returns a closure; chained call)
      emitExpr(expr.callee, env, funNameToId, shapes, adts, captures, varNames);
      for (const arg of expr.args) emitExpr(arg, env, funNameToId, shapes, adts, captures, varNames);
      emitCallIndirect(expr.args.length);
      break;
    }
    case 'ListExpr': {
      // List literal [a, b, c] compiles to Cons(a, Cons(b, Cons(c, Nil)))
      if (!adts) break;
      const listAdtId = 0; // List is always ADT 0
      const nilCtor = 0;   // Nil constructor
      const consCtor = 1;  // Cons constructor

      // Build from right to left: start with Nil
      emitConstruct(listAdtId, nilCtor, 0);

      // Add elements in reverse order: [a,b,c] => Cons(a, Cons(b, Cons(c, Nil)))
      for (let i = expr.elements.length - 1; i >= 0; i--) {
        const elem = expr.elements[i]!;
        if (typeof elem === 'object' && 'spread' in elem) {
          // Spread not supported yet in list literals
          continue;
        }
        // Stack has tail, need to push head then CONSTRUCT
        // CONSTRUCT pops args left-to-right, so push: head, tail
        emitExpr(elem as Expr, env, funNameToId, shapes, adts, captures, varNames); // Push head
        // Now stack: tail, head - need to swap
        const temp1 = env.size;
        const temp2 = env.size + 1;
        emitStoreLocal(temp1); // Store head to temp1
        emitStoreLocal(temp2); // Store tail to temp2
        emitLoadLocal(temp1);  // Load head
        emitLoadLocal(temp2);  // Load tail
        emitConstruct(listAdtId, consCtor, 2); // Cons(head, tail)
      }
      break;
    }
    case 'ConsExpr': {
      // head :: tail compiles to Cons(head, tail)
      if (!adts) break;
      const listAdtId = 0;
      const consCtor = 1;
      emitExpr(expr.head, env, funNameToId, shapes, adts, captures, varNames);
      emitExpr(expr.tail, env, funNameToId, shapes, adts, captures, varNames);
      emitConstruct(listAdtId, consCtor, 2);
      break;
    }
    case 'MatchExpr': {
      // match (scrutinee) { Pat1 => e1; Pat2 => e2; ... }
      emitExpr(expr.scrutinee, env, funNameToId, shapes, adts, captures, varNames);

      const scrutineeSlot = env.size;
      env.set('$scrutinee', scrutineeSlot);
      emitStoreLocal(scrutineeSlot);

      const scrutineeType = getInferredType(expr.scrutinee);
      const hasAdtPatterns = expr.cases.some(
        c => c.pattern.kind === 'ConstructorPattern' ||
            c.pattern.kind === 'ConsPattern' ||
            c.pattern.kind === 'ListPattern'
      );

      let config = getMatchConfig(scrutineeType ?? undefined, adts, userAdtConfigs);
      if (hasAdtPatterns && !config && expr.cases.some(c => c.pattern.kind === 'ListPattern' || c.pattern.kind === 'ConsPattern' || (c.pattern.kind === 'ConstructorPattern' && c.pattern.name === 'Nil'))) {
        config = getMatchConfig({ kind: 'app', name: 'List' }, adts, userAdtConfigs);
      }

      if (hasAdtPatterns && config) {
        emitLoadLocal(scrutineeSlot);
        const matchPos = codeOffset();
        const jumpTableSize = config.size;
        const placeholders: number[] = new Array(jumpTableSize).fill(0);
        emitMatch(placeholders);

        const casePositions: number[] = [];
        const endJumps: number[] = [];

        for (const matchCase of expr.cases) {
          const caseStart = codeOffset();
          let tag: number | undefined;

          if (matchCase.pattern.kind === 'ListPattern' && matchCase.pattern.elements.length === 0) {
            tag = config.ctorToTag['Nil'];
          } else if (matchCase.pattern.kind === 'ConstructorPattern') {
            tag = config.ctorToTag[matchCase.pattern.name];
          } else if (matchCase.pattern.kind === 'ConsPattern') {
            tag = config.ctorToTag['Cons'];
          }

          if (tag !== undefined) {
            casePositions[tag] = caseStart - matchPos;

            // Bind payload fields for ConsPattern (head, tail) or ConstructorPattern (Some(x), Ok(v), etc.)
            const ctorName = Object.keys(config.ctorToTag).find(k => config.ctorToTag[k] === tag);
            const arity = ctorName != null ? (config.ctorArity[ctorName] ?? 0) : 0;
            if (matchCase.pattern.kind === 'ConsPattern' && arity === 2) {
              if (matchCase.pattern.head.kind === 'VarPattern') {
                const headSlot = env.size;
                env.set(matchCase.pattern.head.name, headSlot);
                emitLoadLocal(scrutineeSlot);
                emitGetField(0);
                emitStoreLocal(headSlot);
              }
              if (matchCase.pattern.tail.kind === 'VarPattern') {
                const tailSlot = env.size;
                env.set(matchCase.pattern.tail.name, tailSlot);
                emitLoadLocal(scrutineeSlot);
                emitGetField(1);
                emitStoreLocal(tailSlot);
              }
            } else if (matchCase.pattern.kind === 'ConstructorPattern' && matchCase.pattern.fields?.length) {
              const fieldCount = config.ctorArity[matchCase.pattern.name] ?? 0;
              for (let f = 0; f < fieldCount && f < matchCase.pattern.fields.length; f++) {
                const field = matchCase.pattern.fields[f];
                const pat = field?.pattern ?? (matchCase.pattern as { fields?: { pattern?: { kind: string; name?: string } }[] }).fields?.[f]?.pattern;
                if (pat?.kind === 'VarPattern' && pat.name != null) {
                  const slot = env.size;
                  env.set(pat.name, slot);
                  emitLoadLocal(scrutineeSlot);
                  emitGetField(f);
                  emitStoreLocal(slot);
                }
              }
            }

            emitExpr(matchCase.body, env, funNameToId, shapes, adts, captures, varNames);

            if (matchCase.pattern.kind === 'ConsPattern') {
              if (matchCase.pattern.head.kind === 'VarPattern') env.delete(matchCase.pattern.head.name);
              if (matchCase.pattern.tail.kind === 'VarPattern') env.delete(matchCase.pattern.tail.name);
            } else if (matchCase.pattern.kind === 'ConstructorPattern' && matchCase.pattern.fields?.length) {
              const fieldCount = config.ctorArity[matchCase.pattern.name] ?? 0;
              for (let f = 0; f < fieldCount && f < matchCase.pattern.fields.length; f++) {
                const pat = matchCase.pattern.fields[f]?.pattern;
                if (pat?.kind === 'VarPattern' && pat.name != null) env.delete(pat.name);
              }
            }
          } else if (matchCase.pattern.kind === 'WildcardPattern') {
            const firstUncovered = [...Array(jumpTableSize).keys()].find(i => casePositions[i] === undefined);
            if (firstUncovered !== undefined) casePositions[firstUncovered] = caseStart - matchPos;
            emitExpr(matchCase.body, env, funNameToId, shapes, adts, captures, varNames);
          }

          const jumpPos = codeOffset();
          emitJump(0);
          endJumps.push(jumpPos);
        }

        const endPos = codeOffset();
        for (const jumpPos of endJumps) {
          patchI32(jumpPos + 1, endPos - (jumpPos + 5));
        }
        const matchJumpTablePos = matchPos + 1 + 4;
        const defaultOffset = endPos - matchPos;
        for (let i = 0; i < jumpTableSize; i++) {
          patchI32(matchJumpTablePos + i * 4, casePositions[i] !== undefined ? casePositions[i]! : defaultOffset);
        }
        env.delete('$scrutinee');
      } else {
        const firstCase = expr.cases[0];
        if (firstCase && firstCase.pattern.kind === 'VarPattern') {
          const slot = env.size;
          env.set(firstCase.pattern.name, slot);
          emitLoadLocal(scrutineeSlot);
          emitStoreLocal(slot);
          emitExpr(firstCase.body, env, funNameToId, shapes, adts, captures, varNames);
          env.delete(firstCase.pattern.name);
        } else if (firstCase && firstCase.pattern.kind === 'TuplePattern') {
          const scrutineeType = getInferredType(expr.scrutinee);
          if (scrutineeType?.kind === 'tuple' && scrutineeType.elements.length === firstCase.pattern.elements.length) {
            for (let i = 0; i < firstCase.pattern.elements.length; i++) {
              const elemPat = firstCase.pattern.elements[i]!;
              if (elemPat.kind === 'VarPattern') {
                const slot = env.size;
                env.set(elemPat.name, slot);
                emitLoadLocal(scrutineeSlot);
                emitGetField(i);
                emitStoreLocal(slot);
              }
            }
            emitExpr(firstCase.body, env, funNameToId, shapes, adts, captures, varNames);
            for (const elemPat of firstCase.pattern.elements) {
              if (elemPat.kind === 'VarPattern') env.delete(elemPat.name);
            }
          } else {
            emitExpr(firstCase?.body || { kind: 'LiteralExpr', literal: 'unit', value: { kind: 'unit' } }, env, funNameToId, shapes, adts, captures, varNames);
          }
        } else {
          emitExpr(firstCase?.body || { kind: 'LiteralExpr', literal: 'unit', value: { kind: 'unit' } }, env, funNameToId, shapes, adts, captures, varNames);
        }
        env.delete('$scrutinee');
      }
      break;
    }
    case 'ThrowExpr': {
      // Evaluate exception value and throw
      emitExpr(expr.value, env, funNameToId, shapes, adts, captures, varNames);
      emitThrow();
      // Push unit (unreachable but keeps stack consistent)
      emitLoadConst(addConstant({ tag: ConstTag.Unit }));
      break;
    }
    case 'TryExpr': {
      // try { block } catch (e) { cases }
      // Emit: TRY handler_offset, block, END_TRY, JUMP end, handler: cases, end:
      const tryPos = codeOffset();
      emitTry(0); // Placeholder offset, will be patched

      // Emit try block
      emitExpr(expr.body, env, funNameToId, shapes, adts, captures, varNames);
      emitEndTry();

      // Jump over catch handler
      const jumpPos = codeOffset();
      emitJump(0); // Placeholder, will be patched

      // Handler starts here
      const handlerPos = codeOffset();
      // Patch TRY instruction with handler offset (relative to TRY start)
      patchI32(tryPos + 1, handlerPos - tryPos);

      // Exception value is on stack; store in slot for case matching; optionally bind to catch variable
      const excSlot = env.size;
      if (expr.catchVar != null) {
        env.set(expr.catchVar, excSlot);
      }
      emitStoreLocal(excSlot);

      // Emit catch cases (similar to match)
      const firstCase = expr.cases[0];
      if (firstCase) {
        if (firstCase.pattern.kind === 'VarPattern') {
          const slot = env.size;
          env.set(firstCase.pattern.name, slot);
          emitLoadLocal(excSlot); // Load exception
          emitStoreLocal(slot);
          emitExpr(firstCase.body, env, funNameToId, shapes, adts, captures, varNames);
          env.delete(firstCase.pattern.name);
        } else {
          emitExpr(firstCase.body, env, funNameToId, shapes, adts, captures, varNames);
        }
      } else {
        emitLoadConst(addConstant({ tag: ConstTag.Unit }));
      }

      if (expr.catchVar != null) {
        env.delete(expr.catchVar);
      }

      // End: patch jump
      const endPos = codeOffset();
      patchI32(jumpPos + 1, endPos - jumpPos);
      break;
    }
    case 'AwaitExpr': {
      // Evaluate task expression and await it
      emitExpr(expr.value, env, funNameToId, shapes, adts, captures, varNames);
      emitAwait();
      // AWAIT leaves the result on stack
      break;
    }
    case 'PipeExpr': {
      if (expr.op === '|>') {
        const call: Expr = { kind: 'CallExpr', callee: expr.right, args: [expr.left] };
        emitExpr(call, env, funNameToId, shapes, adts, captures, varNames);
      } else {
        const call: Expr = { kind: 'CallExpr', callee: expr.left, args: [expr.right] };
        emitExpr(call, env, funNameToId, shapes, adts, captures, varNames);
      }
      break;
    }
    case 'LambdaExpr': {
      const paramNames = new Set(expr.params.map((p) => p.name));
      const freeVars = getFreeVars(expr.body, paramNames, env);
      if (freeVars.length === 0) {
        const saved = codeSave();
        codeStart();
        const lambdaEnv = new Map<string, number>();
        for (let i = 0; i < expr.params.length; i++) lambdaEnv.set(expr.params[i]!.name, i);
        emitExpr(expr.body, lambdaEnv, funNameToId, shapes, adts, captures, varNames);
        emitRet();
        const lambdaCode = codeSlice();
        codeRestore(saved);
        const lambdaIndex = funDeclCountRef.value + lambdaEntries.length;
        lambdaEntries.push({ arity: expr.params.length, code: lambdaCode });
        emitLoadFn(lambdaIndex);
        break;
      }
      if (!shapes) break;
      const nameIndices = freeVars.map((s) => stringIndex(s));
      let shapeId = shapes.findIndex(
        (s) =>
          s.nameIndices.length === nameIndices.length &&
          s.nameIndices.every((n, i) => n === nameIndices[i])
      );
      if (shapeId < 0) {
        shapeId = shapes.length;
        shapes.push({ nameIndices });
      }
      const captureMap = new Map<string, { index: number; isVar: boolean }>();
      freeVars.forEach((name, i) => captureMap.set(name, { index: i, isVar: varNames?.has(name) ?? false }));
      const liftedEnv = new Map<string, number>();
      liftedEnv.set('__env', 0);
      for (let i = 0; i < expr.params.length; i++) liftedEnv.set(expr.params[i]!.name, i + 1);
      const saved = codeSave();
      codeStart();
      emitExpr(expr.body, liftedEnv, funNameToId, shapes, adts, captureMap, undefined);
      emitRet();
      const lambdaCode = codeSlice();
      codeRestore(saved);
      const lambdaIndex = funDeclCountRef.value + lambdaEntries.length;
      lambdaEntries.push({ arity: expr.params.length + 1, code: lambdaCode });
      for (const name of freeVars) {
        const slot = env.get(name);
        if (slot !== undefined) {
          emitLoadLocal(slot);
        } else {
          const globalSlot = moduleGlobals.get(name);
          if (globalSlot !== undefined) {
            emitLoadGlobal(globalSlot);
          } else {
            const fnId = funNameToId?.get(name);
            if (fnId !== undefined) {
              emitLoadFn(fnId);
            }
          }
        }
      }
      emitAllocRecord(shapeId);
      emitMakeClosure(lambdaIndex);
      break;
    }
    default:
      // Fallback: push unit
      emitLoadConst(addConstant({ tag: ConstTag.Unit }));
  }
} };
}

export interface CodegenOptions {
  /** Map of imported function names to their indices in the (possibly merged) function table. */
  importedFuncIds?: Map<string, number>;
  /** Map of imported var names to the imported function table index of their setter (1-arity). */
  importedVarSetterIds?: Map<string, number>;
}

/** Generate bytecode for program. */
export function codegen(program: Program, options?: CodegenOptions): CodegenResult {
  const ctx = makeCodegenContext();
  const { stringTable, constantPool, stringIndex, addConstant } = ctx;
  const lambdaEntries: LambdaEntry[] = [];
  const funDeclCountRef = { value: 0 };
  const { emitExpr, moduleGlobals } = makeEmitExpr(ctx.stringIndex, ctx.addConstant, lambdaEntries, funDeclCountRef);

  codeStart();
  const shapes: ShapeEntry[] = [];
  const userAdtConfigs = new Map<string, MatchConfig>();

  // Initialize ADT table: List(0), Option(1), Result(2), Value(3) per spec 02
  const adts: AdtEntry[] = [
    {
      nameIndex: stringIndex('List'),
      constructors: [
        { nameIndex: stringIndex('Nil'), payloadTypeIndex: 0xFFFFFFFF },
        { nameIndex: stringIndex('Cons'), payloadTypeIndex: 0xFFFFFFFF },
      ],
    },
    {
      nameIndex: stringIndex('Option'),
      constructors: [
        { nameIndex: stringIndex('None'), payloadTypeIndex: 0xFFFFFFFF },
        { nameIndex: stringIndex('Some'), payloadTypeIndex: 0xFFFFFFFF },
      ],
    },
    {
      nameIndex: stringIndex('Result'),
      constructors: [
        { nameIndex: stringIndex('Err'), payloadTypeIndex: 0xFFFFFFFF },
        { nameIndex: stringIndex('Ok'), payloadTypeIndex: 0xFFFFFFFF },
      ],
    },
    {
      nameIndex: stringIndex('Value'),
      constructors: [
        { nameIndex: stringIndex('Null'), payloadTypeIndex: 0xFFFFFFFF },
        { nameIndex: stringIndex('Bool'), payloadTypeIndex: 0xFFFFFFFF },
        { nameIndex: stringIndex('Int'), payloadTypeIndex: 0xFFFFFFFF },
        { nameIndex: stringIndex('Float'), payloadTypeIndex: 0xFFFFFFFF },
        { nameIndex: stringIndex('String'), payloadTypeIndex: 0xFFFFFFFF },
        { nameIndex: stringIndex('Array'), payloadTypeIndex: 0xFFFFFFFF },
        { nameIndex: stringIndex('Object'), payloadTypeIndex: 0xFFFFFFFF },
      ],
    },
  ];

  // Add user-defined ADTs from the program
  const typeDecls = program.body.filter((n): n is typeof n & { kind: 'TypeDecl'; body: { kind: 'ADTBody' } } => 
    n != null && n.kind === 'TypeDecl' && n.body.kind === 'ADTBody'
  );
  const userCtorArityMap = new Map<string, number>();
  for (const td of typeDecls) {
    adts.push({
      nameIndex: stringIndex(td.name),
      constructors: td.body.constructors.map(c => {
        userCtorArityMap.set(c.name, c.params.length);
        return {
          nameIndex: stringIndex(c.name),
          payloadTypeIndex: c.params.length === 0 ? 0xFFFFFFFF : 0,
        };
      }),
    });
  }

  // Add exception declarations as single-constructor ADTs (so VM can throw by name, e.g. DivideByZero, ArithmeticOverflow)
  const exceptionDecls = program.body.filter((n): n is ExceptionDecl => n != null && n.kind === 'ExceptionDecl');
  for (const ed of exceptionDecls) {
    const arity = ed.fields?.length ?? 0;
    userCtorArityMap.set(ed.name, arity);
    adts.push({
      nameIndex: stringIndex(ed.name),
      constructors: [{
        nameIndex: stringIndex(ed.name),
        payloadTypeIndex: arity === 0 ? 0xFFFFFFFF : 0,
      }],
    });
  }

  // Build constructor lookup map for user-defined ADTs
  constructorLookup = new Map();
  for (let adtId = 4; adtId < adts.length; adtId++) {
    const adt = adts[adtId]!;
    const adtName = stringTable[adt.nameIndex]!;
    const ctorToTag: Record<string, number> = {};
    const ctorArity: Record<string, number> = {};
    for (let ctor = 0; ctor < adt.constructors.length; ctor++) {
      const ctorDef = adt.constructors[ctor]!;
      const ctorName = stringTable[ctorDef.nameIndex]!;
      const arity = userCtorArityMap.get(ctorName) ?? (ctorDef.payloadTypeIndex === 0xFFFFFFFF ? 0 : 1);
      constructorLookup.set(ctorName, { adtId, ctor, arity });
      ctorToTag[ctorName] = ctor;
      ctorArity[ctorName] = arity;
    }
    userAdtConfigs.set(adtName, { size: adt.constructors.length, ctorToTag, ctorArity });
  }

  const seenSpecs = new Set<string>();
  const importSpecifierIndices: number[] = [];
  for (const imp of program.imports) {
    const spec = imp.spec;
    if (!seenSpecs.has(spec)) {
      seenSpecs.add(spec);
      importSpecifierIndices.push(stringIndex(spec));
    }
  }

  const funDecls = program.body.filter((n): n is FunDecl => n != null && n.kind === 'FunDecl');
  const valOrVarDecls = program.body.filter(
    (n): n is ValDecl | VarDecl => n != null && (n.kind === 'ValDecl' || n.kind === 'VarDecl')
  );
  const funNameToId = new Map<string, number>();
  // Add imported function IDs first (for cross-module calls)
  if (options?.importedFuncIds) {
    for (const [name, id] of options.importedFuncIds) funNameToId.set(name, id);
  }
  // Function IDs: 0xFFFFFF00/01 = print/println; 0..n-1 = our functions (then lambdas, then getters for val/var)
  funDeclCountRef.value = funDecls.length;
  for (let i = 0; i < funDecls.length; i++) {
    funNameToId.set(funDecls[i]!.name, i);
    stringIndex(funDecls[i]!.name); // ensure name is in string table
  }
  for (const d of valOrVarDecls) {
    stringIndex(d.name);
  }

  const stmts = program.body.filter((n): n is TopLevelStmt =>
    n != null && (n.kind === 'ValStmt' || n.kind === 'VarStmt' || n.kind === 'AssignStmt' || n.kind === 'ExprStmt')
  );
  const env = new Map<string, number>();

  for (const node of program.body) {
    if (!node) continue;
    if (node.kind === 'ValStmt' || node.kind === 'VarStmt') {
      const stmt = node;
      emitExpr(stmt.value, env, funNameToId, shapes, adts, undefined, undefined, userAdtConfigs);
      const slot = env.size;
      env.set(stmt.name, slot);
      moduleGlobals.set(stmt.name, slot);
      emitStoreLocal(slot);
    } else if (node.kind === 'ValDecl') {
      emitExpr(node.value, env, funNameToId, shapes, adts);
      const valSlot = env.size;
      env.set(node.name, valSlot);
      moduleGlobals.set(node.name, valSlot);
      emitStoreLocal(valSlot);
    } else if (node.kind === 'VarDecl') {
      // Exported var: init stores to module global slot so assignment works; getter uses LOAD_GLOBAL
      const decl = node;
      emitExpr(decl.value, env, funNameToId, shapes, adts);
      const slot = env.size;
      env.set(decl.name, slot);
      moduleGlobals.set(decl.name, slot);
      emitStoreLocal(slot);
    } else if (node.kind === 'ExprStmt') {
      const stmt = node;
      emitExpr(stmt.expr, env, funNameToId, shapes, adts);
      // Expression result is left on stack and will be discarded
    } else if (node.kind === 'AssignStmt') {
      const stmt = node;
      const target = stmt.target;
      if (target.kind === 'FieldExpr') {
        const objType = getInferredType(target.object);
        let slot = -1;
        if (objType?.kind === 'record') {
          slot = objType.fields.findIndex((f) => f.name === target.field);
        } else if (target.object.kind === 'RecordExpr') {
          slot = target.object.fields.findIndex((f) => f.name === target.field);
        }
        if (slot >= 0) {
          emitExpr(target.object, env, funNameToId, shapes, adts);
          emitExpr(stmt.value, env, funNameToId, shapes, adts, undefined, undefined, userAdtConfigs);
          emitSetField(slot);
        } else {
          emitExpr(stmt.value, env, funNameToId, shapes, adts, undefined, undefined, userAdtConfigs);
          emitStoreLocal(0);
        }
      } else {
        emitExpr(stmt.value, env, funNameToId, shapes, adts, undefined, undefined, userAdtConfigs);
        if (stmt.target.kind === 'IdentExpr') {
          const slot = env.get(stmt.target.name);
          if (slot !== undefined) {
            emitStoreLocal(slot);
          } else {
            const setterId = options?.importedVarSetterIds?.get(stmt.target.name);
            if (setterId !== undefined) emitCall(setterId, 1);
            else throw new Error(`Codegen: assign to unknown ${stmt.target.name}`);
          }
        } else {
          emitStoreLocal(0);
        }
      }
    }
    // Skip FunDecl, TypeDecl, ExceptionDecl, ExportDecl (handled elsewhere)
  }

  emitRet();
  const initCode = codeSlice();
  const codeChunks: Uint8Array[] = [initCode];
  let codeOffsetSoFar = initCode.length;
  const functionTable: FunctionEntry[] = [];

  for (const decl of funDecls) {
    codeStart();
    const arity = decl.params.length;
    const fnEnv = new Map<string, number>();
    for (let i = 0; i < arity; i++) fnEnv.set(decl.params[i]!.name, i);
    emitExpr(decl.body, fnEnv, funNameToId, shapes, adts, undefined, undefined, userAdtConfigs);
    emitRet();
    const fnCode = codeSlice();
    functionTable.push({
      nameIndex: stringIndex(decl.name),
      arity,
      codeOffset: codeOffsetSoFar,
    });
    codeChunks.push(fnCode);
    codeOffsetSoFar += fnCode.length;
  }

  // Lambda functions (compiled inline during emitExpr; add them to function table after FunDecls)
  for (const lambda of lambdaEntries) {
    functionTable.push({
      nameIndex: stringIndex('<lambda>'),
      arity: lambda.arity,
      codeOffset: codeOffsetSoFar,
    });
    codeChunks.push(lambda.code);
    codeOffsetSoFar += lambda.code.length;
  }

  // Init code may use temp slots (e.g. block-level FunStmt self-patch uses slot+1, slot+2).
  // Ensure enough globals so STORE_LOCAL(slot+1) and STORE_LOCAL(slot+2) succeed when slot is 0.
  const nGlobals = Math.max(env.size, 3);

  const varSetterIndices = new Map<string, number>();

  // Export val/var as 0-arity getters: LOAD_GLOBAL slot + RET
  for (const decl of valOrVarDecls) {
    if (decl.kind === 'ValDecl') {
      const slot = env.get(decl.name);
      if (slot === undefined) throw new Error(`Codegen: export val slot missing: ${decl.name}`);
      codeStart();
      emitLoadGlobal(slot);
      emitRet();
    } else {
      const slot = env.get(decl.name);
      if (slot === undefined) throw new Error(`Codegen: export var slot missing: ${decl.name}`);
      codeStart();
      emitLoadGlobal(slot);
      emitRet();
    }
    const fnCode = codeSlice();
    functionTable.push({
      nameIndex: stringIndex(decl.name),
      arity: 0,
      codeOffset: codeOffsetSoFar,
    });
    funNameToId.set(decl.name, functionTable.length - 1);
    codeChunks.push(fnCode);
    codeOffsetSoFar += fnCode.length;
  }

  // Export var setters: 1-arity, body LOAD_LOCAL 0 → STORE_GLOBAL slot → RET
  for (const decl of valOrVarDecls) {
    if (decl.kind !== 'VarDecl') continue;
    const slot = env.get(decl.name);
    if (slot === undefined) throw new Error(`Codegen: export var slot missing: ${decl.name}`);
    codeStart();
    emitLoadLocal(0);
    emitStoreGlobal(slot);
    emitRet();
    const setterCode = codeSlice();
    functionTable.push({
      nameIndex: stringIndex(decl.name + '$set'),
      arity: 1,
      codeOffset: codeOffsetSoFar,
    });
    varSetterIndices.set(decl.name, functionTable.length - 1);
    codeChunks.push(setterCode);
    codeOffsetSoFar += setterCode.length;
  }

  const totalCodeLen = codeChunks.reduce((s, c) => s + c.length, 0);
  const code = new Uint8Array(totalCodeLen);
  let off = 0;
  for (const chunk of codeChunks) {
    code.set(chunk, off);
    off += chunk.length;
  }

  return {
    stringTable: [...stringTable],
    constantPool: [...constantPool],
    code,
    functionTable,
    importSpecifierIndices,
    shapes,
    adts,
    nGlobals: nGlobals > 0 ? nGlobals : undefined,
    varSetterIndices: varSetterIndices.size > 0 ? varSetterIndices : undefined,
  };
}
