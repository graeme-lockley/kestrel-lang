/**
 * Code generation: typed AST → constant pool + code + function table (spec 04).
 * Covers: module initializer, top-level val/var, fun decls, literals, locals, calls.
 */
import type { Program, Expr, TopLevelStmt } from '../ast/nodes.js';
import type { FunDecl, ValDecl, VarDecl } from '../ast/nodes.js';
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

/** Resolve built-in constructor to (adtId, ctorIndex, arity). 0-ary: None, Null. */
function getBuiltinConstructor(
  name: string,
  argCount: number
): { adtId: number; ctor: number; arity: number } | null {
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
    default:
      return null;
  }
}

/** Match config: constructor name -> (tag index, field count for payload). */
interface MatchConfig {
  size: number;
  ctorToTag: Record<string, number>;
  ctorArity: Record<string, number>;
}

function getMatchConfig(scrutineeType: { kind: string; name?: string } | undefined): MatchConfig | null {
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
  function stringIndex(s: string): number {
    const i = stringTable.indexOf(s);
    if (i >= 0) return i;
    stringTable.push(s);
    return stringTable.length - 1;
  }
  function addConstant(c: ConstantEntry): number {
    const i = constantPool.length;
    constantPool.push(c);
    return i;
  }
  return { stringTable, constantPool, stringIndex, addConstant };
}

export interface LambdaEntry {
  arity: number;
  code: Uint8Array;
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
  adts?: AdtEntry[]
) => void; moduleGlobals: Map<string, number> } {
  const moduleGlobals = new Map<string, number>();
  return { moduleGlobals, emitExpr: function emitExpr(
  expr: Expr,
  env: Map<string, number>,
  funNameToId?: Map<string, number>,
  shapes?: ShapeEntry[],
  adts?: AdtEntry[]
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
          emitExpr(part.expr, env, funNameToId, shapes, adts);
          emitCall(0xffffff03, 1); // format value -> string
        }
        emitCall(0xffffff04, 2); // concat(top-1, top) -> result
      }
      break;
    }
    case 'IdentExpr': {
      // 0-ary built-in constructors: None, Null
      if (adts != null) {
        const builtin = getBuiltinConstructor(expr.name, 0);
        if (builtin != null) {
          emitConstruct(builtin.adtId, builtin.ctor, builtin.arity);
          break;
        }
      }
      const slot = env.get(expr.name);
      if (slot !== undefined) {
        emitLoadLocal(slot);
        break;
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
        emitExpr(expr.left, env, funNameToId, shapes, adts);
        const andSkipPos = codeOffset();
        emitJumpIfFalse(0);
        emitExpr(expr.right, env, funNameToId, shapes, adts);
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
        emitExpr(expr.left, env, funNameToId, shapes, adts);
        const orEvalRightPos = codeOffset();
        emitJumpIfFalse(0); // patch: when false, go eval right
        emitLoadConst(addConstant({ tag: ConstTag.True }));
        const orJumpToEnd = codeOffset();
        emitJump(0); // patch: skip right
        const orRightStart = codeOffset();
        emitExpr(expr.right, env, funNameToId, shapes, adts);
        const orEnd = codeOffset();
        patchI32(orEvalRightPos + 1, orRightStart - (orEvalRightPos + 5));
        patchI32(orJumpToEnd + 1, orEnd - (orJumpToEnd + 5));
        break;
      }
      emitExpr(expr.left, env, funNameToId, shapes, adts);
      emitExpr(expr.right, env, funNameToId, shapes, adts);
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
        emitExpr(expr.operand, env, funNameToId, shapes, adts);
        emitSub();
      } else if (expr.op === '+') {
        // Unary plus: just emit operand
        emitExpr(expr.operand, env, funNameToId, shapes, adts);
      } else if (expr.op === '!') {
        // Logical not: constant-fold !True -> False, !False -> True; else (x == False)
        const op = expr.operand;
        if (op.kind === 'LiteralExpr' && (op.literal === 'true' || op.literal === 'false')) {
          emitLoadConst(addConstant({ tag: op.literal === 'true' ? ConstTag.False : ConstTag.True }));
        } else {
          emitExpr(expr.operand, env, funNameToId, shapes, adts);
          emitLoadConst(addConstant({ tag: ConstTag.False }));
          emitEq();
        }
      } else {
        throw new Error(`Codegen: unsupported unary op ${expr.op}`);
      }
      break;
    }
    case 'IfExpr': {
      emitExpr(expr.cond, env, funNameToId, shapes, adts);
      const jumpIfFalsePos = codeOffset();
      emitJumpIfFalse(0); // patch later
      emitExpr(expr.then, env, funNameToId, shapes, adts);
      const jumpOverElsePos = codeOffset();
      emitJump(0); // patch later
      const elseStart = codeOffset();
      if (expr.else !== undefined) {
        emitExpr(expr.else, env, funNameToId, shapes, adts);
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
      for (const stmt of expr.stmts) {
        if (stmt.kind === 'ValStmt') {
          emitExpr(stmt.value, blockEnv, funNameToId, shapes, adts);
          const slot = blockEnv.size;
          blockEnv.set(stmt.name, slot);
          emitStoreLocal(slot);
        } else if (stmt.kind === 'VarStmt') {
          emitExpr(stmt.value, blockEnv, funNameToId, shapes, adts);
          const slot = blockEnv.size;
          blockEnv.set(stmt.name, slot);
          emitStoreLocal(slot);
        } else if (stmt.kind === 'ExprStmt') {
          emitExpr(stmt.expr, blockEnv, funNameToId, shapes, adts);
        } else if (stmt.kind === 'AssignStmt') {
          const target = stmt.target;
          if (target.kind === 'FieldExpr') {
            const objType = getInferredType(target.object);
            let fieldSlot = -1;
            if (objType?.kind === 'record') {
              fieldSlot = objType.fields.findIndex((f) => f.name === target.field);
            }
            if (fieldSlot >= 0) {
              emitExpr(target.object, blockEnv, funNameToId, shapes, adts);
              emitExpr(stmt.value, blockEnv, funNameToId, shapes, adts);
              emitSetField(fieldSlot);
            }
          } else if (target.kind === 'IdentExpr') {
            emitExpr(stmt.value, blockEnv, funNameToId, shapes, adts);
            const localSlot = blockEnv.get(target.name);
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
      emitExpr(expr.result, blockEnv, funNameToId, shapes, adts);
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
      for (const e of expr.elements) emitExpr(e, env, funNameToId, shapes, adts);
      emitAllocRecord(shapeId);
      break;
    }
    case 'RecordExpr': {
      if (expr.spread != null || !shapes) break;
      const nameIndices = expr.fields.map((f) => stringIndex(f.name));
      let shapeId = shapes.findIndex((s) => s.nameIndices.length === nameIndices.length && s.nameIndices.every((n, i) => n === nameIndices[i]));
      if (shapeId < 0) {
        shapeId = shapes.length;
        shapes.push({ nameIndices: [...nameIndices] });
      }
      for (const f of expr.fields) emitExpr(f.value, env, funNameToId, shapes, adts);
      emitAllocRecord(shapeId);
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
        emitExpr(expr.object, env, funNameToId, shapes, adts);
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
          for (const arg of expr.args) emitExpr(arg, env, funNameToId, shapes, adts);
          emitCall(0xFFFFFF00, expr.args.length);
          break;
        }
        if (expr.callee.name === 'println') {
          for (const arg of expr.args) emitExpr(arg, env, funNameToId, shapes, adts);
          emitCall(0xFFFFFF01, expr.args.length);
          break;
        }
        if (expr.callee.name === 'exit' && expr.args.length === 1) {
          emitExpr(expr.args[0]!, env, funNameToId, shapes, adts);
          emitCall(0xFFFFFF02, 1);
          break;
        }
        if (expr.callee.name === '__json_parse' && expr.args.length === 1) {
          emitExpr(expr.args[0]!, env, funNameToId, shapes, adts);
          emitCall(0xFFFFFF05, 1);
          break;
        }
        if (expr.callee.name === '__json_stringify' && expr.args.length === 1) {
          emitExpr(expr.args[0]!, env, funNameToId, shapes, adts);
          emitCall(0xFFFFFF06, 1);
          break;
        }
        if (expr.callee.name === '__read_file_async' && expr.args.length === 1) {
          emitExpr(expr.args[0]!, env, funNameToId, shapes, adts);
          emitCall(0xFFFFFF07, 1);
          break;
        }
        if (expr.callee.name === '__now_ms' && expr.args.length === 0) {
          emitCall(0xFFFFFF08, 0);
          break;
        }
        if (expr.callee.name === '__string_length' && expr.args.length === 1) {
          emitExpr(expr.args[0]!, env, funNameToId, shapes, adts);
          emitCall(0xFFFFFF09, 1);
          break;
        }
        if (expr.callee.name === '__string_slice' && expr.args.length === 3) {
          for (const arg of expr.args) emitExpr(arg, env, funNameToId, shapes, adts);
          emitCall(0xFFFFFF0A, 3);
          break;
        }
        if (expr.callee.name === '__string_index_of' && expr.args.length === 2) {
          emitExpr(expr.args[0]!, env, funNameToId, shapes, adts);
          emitExpr(expr.args[1]!, env, funNameToId, shapes, adts);
          emitCall(0xFFFFFF0B, 2);
          break;
        }
        if (expr.callee.name === '__string_equals' && expr.args.length === 2) {
          emitExpr(expr.args[0]!, env, funNameToId, shapes, adts);
          emitExpr(expr.args[1]!, env, funNameToId, shapes, adts);
          emitCall(0xFFFFFF0C, 2);
          break;
        }
        if (expr.callee.name === '__string_upper' && expr.args.length === 1) {
          emitExpr(expr.args[0]!, env, funNameToId, shapes, adts);
          emitCall(0xFFFFFF0D, 1);
          break;
        }
        if (expr.callee.name === '__format_one' && expr.args.length === 1) {
          emitExpr(expr.args[0]!, env, funNameToId, shapes, adts);
          emitCall(0xFFFFFF03, 1);
          break;
        }
        if (expr.callee.name === '__print_one' && expr.args.length === 1) {
          emitExpr(expr.args[0]!, env, funNameToId, shapes, adts);
          emitCall(0xFFFFFF00, 1);
          break;
        }
        if (expr.callee.name === '__equals' && expr.args.length === 2) {
          for (const arg of expr.args) emitExpr(arg, env, funNameToId, shapes, adts);
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
          emitExpr(expr.args[0]!, env, funNameToId, shapes, adts);
          emitCall(0xFFFFFF10, 1);
          break;
        }
        if (expr.callee.name === '__write_text' && expr.args.length === 2) {
          for (const arg of expr.args) emitExpr(arg, env, funNameToId, shapes, adts);
          emitCall(0xFFFFFF11, 2);
          break;
        }
        if (expr.callee.name === '__run_process' && expr.args.length === 2) {
          for (const arg of expr.args) emitExpr(arg, env, funNameToId, shapes, adts);
          emitCall(0xFFFFFF12, 2);
          break;
        }

        // Built-in ADT constructors: Some(x), Ok(x), Err(e), Null(), Bool(x), Int(x), etc.
        if (adts != null) {
          const builtin = getBuiltinConstructor(expr.callee.name, expr.args.length);
          if (builtin != null) {
            for (const arg of expr.args) emitExpr(arg, env, funNameToId, shapes, adts);
            emitConstruct(builtin.adtId, builtin.ctor, builtin.arity);
            break;
          }
        }

        // Check for user-defined function
        if (funNameToId != null) {
          const fnId = funNameToId.get(expr.callee.name);
          if (fnId !== undefined) {
            for (const arg of expr.args) emitExpr(arg, env, funNameToId, shapes, adts);
            emitCall(fnId, expr.args.length);
            break;
          }
        }

        // Local variable holding a function value (closure / lambda)
        const localSlot = env.get(expr.callee.name);
        if (localSlot !== undefined) {
          emitLoadLocal(localSlot);
          for (const arg of expr.args) emitExpr(arg, env, funNameToId, shapes, adts);
          emitCallIndirect(expr.args.length);
          break;
        }
      }
      emitLoadConst(addConstant({ tag: ConstTag.Unit }));
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
        emitExpr(elem as Expr, env, funNameToId, shapes, adts); // Push head
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
      emitExpr(expr.head, env, funNameToId, shapes, adts);
      emitExpr(expr.tail, env, funNameToId, shapes, adts);
      emitConstruct(listAdtId, consCtor, 2);
      break;
    }
    case 'MatchExpr': {
      // match (scrutinee) { Pat1 => e1; Pat2 => e2; ... }
      emitExpr(expr.scrutinee, env, funNameToId, shapes, adts);

      const scrutineeSlot = env.size;
      env.set('$scrutinee', scrutineeSlot);
      emitStoreLocal(scrutineeSlot);

      const scrutineeType = getInferredType(expr.scrutinee);
      const hasAdtPatterns = expr.cases.some(
        c => c.pattern.kind === 'ConstructorPattern' ||
            c.pattern.kind === 'ConsPattern' ||
            c.pattern.kind === 'ListPattern'
      );

      let config = getMatchConfig(scrutineeType ?? undefined);
      if (hasAdtPatterns && !config && expr.cases.some(c => c.pattern.kind === 'ListPattern' || c.pattern.kind === 'ConsPattern' || (c.pattern.kind === 'ConstructorPattern' && c.pattern.name === 'Nil'))) {
        config = getMatchConfig({ kind: 'app', name: 'List' });
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

            emitExpr(matchCase.body, env, funNameToId, shapes, adts);

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
            emitExpr(matchCase.body, env, funNameToId, shapes, adts);
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
          emitExpr(firstCase.body, env, funNameToId, shapes, adts);
          env.delete(firstCase.pattern.name);
        } else {
          emitExpr(firstCase?.body || { kind: 'LitExpr', value: { kind: 'unit' } }, env, funNameToId, shapes, adts);
        }
        env.delete('$scrutinee');
      }
      break;
    }
    case 'ThrowExpr': {
      // Evaluate exception value and throw
      emitExpr(expr.value, env, funNameToId, shapes, adts);
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
      emitExpr(expr.body, env, funNameToId, shapes, adts);
      emitEndTry();

      // Jump over catch handler
      const jumpPos = codeOffset();
      emitJump(0); // Placeholder, will be patched

      // Handler starts here
      const handlerPos = codeOffset();
      // Patch TRY instruction with handler offset (relative to TRY start)
      patchI32(tryPos + 1, handlerPos - tryPos);

      // Exception value is on stack, bind to catch variable
      const excSlot = env.size;
      env.set(expr.catchVar, excSlot);
      emitStoreLocal(excSlot);

      // Emit catch cases (similar to match)
      const firstCase = expr.cases[0];
      if (firstCase) {
        if (firstCase.pattern.kind === 'VarPattern') {
          const slot = env.size;
          env.set(firstCase.pattern.name, slot);
          emitLoadLocal(excSlot); // Load exception
          emitStoreLocal(slot);
          emitExpr(firstCase.body, env, funNameToId, shapes, adts);
          env.delete(firstCase.pattern.name);
        } else {
          emitExpr(firstCase.body, env, funNameToId, shapes, adts);
        }
      } else {
        emitLoadConst(addConstant({ tag: ConstTag.Unit }));
      }

      env.delete(expr.catchVar);

      // End: patch jump
      const endPos = codeOffset();
      patchI32(jumpPos + 1, endPos - jumpPos);
      break;
    }
    case 'AwaitExpr': {
      // Evaluate task expression and await it
      emitExpr(expr.value, env, funNameToId, shapes, adts);
      emitAwait();
      // AWAIT leaves the result on stack
      break;
    }
    case 'PipeExpr': {
      if (expr.op === '|>') {
        const call: Expr = { kind: 'CallExpr', callee: expr.right, args: [expr.left] };
        emitExpr(call, env, funNameToId, shapes, adts);
      } else {
        const call: Expr = { kind: 'CallExpr', callee: expr.left, args: [expr.right] };
        emitExpr(call, env, funNameToId, shapes, adts);
      }
      break;
    }
    case 'LambdaExpr': {
      const saved = codeSave();
      codeStart();
      const lambdaEnv = new Map<string, number>();
      for (let i = 0; i < expr.params.length; i++) lambdaEnv.set(expr.params[i]!.name, i);
      emitExpr(expr.body, lambdaEnv, funNameToId, shapes, adts);
      emitRet();
      const lambdaCode = codeSlice();
      codeRestore(saved);
      const lambdaIndex = funDeclCountRef.value + lambdaEntries.length;
      lambdaEntries.push({ arity: expr.params.length, code: lambdaCode });
      emitLoadFn(lambdaIndex);
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

  const seenSpecs = new Set<string>();
  const importSpecifierIndices: number[] = [];
  for (const imp of program.imports) {
    const spec = imp.spec;
    if (!seenSpecs.has(spec)) {
      seenSpecs.add(spec);
      importSpecifierIndices.push(stringIndex(spec));
    }
  }

  const funDecls = program.body.filter((n): n is FunDecl => n.kind === 'FunDecl');
  const valOrVarDecls = program.body.filter(
    (n): n is ValDecl | VarDecl => n.kind === 'ValDecl' || n.kind === 'VarDecl'
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
    n.kind === 'ValStmt' || n.kind === 'VarStmt' || n.kind === 'AssignStmt' || n.kind === 'ExprStmt'
  );
  const env = new Map<string, number>();

  for (const node of program.body) {
    if (node.kind === 'ValStmt' || node.kind === 'VarStmt') {
      const stmt = node;
      emitExpr(stmt.value, env, funNameToId, shapes, adts);
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
          emitExpr(stmt.value, env, funNameToId, shapes, adts);
          emitSetField(slot);
        } else {
          emitExpr(stmt.value, env, funNameToId, shapes, adts);
          emitStoreLocal(0);
        }
      } else {
        emitExpr(stmt.value, env, funNameToId, shapes, adts);
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
    emitExpr(decl.body, fnEnv, funNameToId, shapes, adts);
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

  const nGlobals = env.size;

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
