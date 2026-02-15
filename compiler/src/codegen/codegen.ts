/**
 * Code generation: typed AST → constant pool + code + function table (spec 04).
 * Covers: module initializer, top-level val/var, fun decls, literals, locals, calls.
 */
import type { Program, Expr, TopLevelStmt } from '../ast/nodes.js';
import type { FunDecl } from '../ast/nodes.js';
import type { ConstantEntry } from '../bytecode/constants.js';
import { ConstTag } from '../bytecode/constants.js';
import { getInferredType } from '../typecheck/check.js';
import {
  codeStart,
  codeSlice,
  codeOffset,
  patchI32,
  emitLoadConst,
  emitStoreLocal,
  emitRet,
  emitLoadLocal,
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

export interface CodegenResult {
  stringTable: string[];
  constantPool: ConstantEntry[];
  code: Uint8Array;
  functionTable: FunctionEntry[];
  importSpecifierIndices: number[];
  shapes: ShapeEntry[];
  adts: AdtEntry[];
}

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

/** Emit code for expr; leaves value on stack. funNameToId for CallExpr, shapes for RecordExpr, adts for List/ADT. */
function emitExpr(
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
    case 'IdentExpr': {
      const slot = env.get(expr.name);
      if (slot === undefined) throw new Error(`Codegen: unknown variable ${expr.name}`);
      emitLoadLocal(slot);
      break;
    }
    case 'BinaryExpr': {
      if (expr.op === '&') {
        // a & b: eval a; if false push false; else eval b, discard a and leave b (temp locals 254,255)
        emitExpr(expr.left, env, funNameToId, shapes, adts);
        const andSkipPos = codeOffset();
        emitJumpIfFalse(0); // patch: jump to push false
        emitExpr(expr.right, env, funNameToId, shapes, adts);
        emitStoreLocal(126); // right -> temp
        emitStoreLocal(127); // pop left
        emitLoadLocal(126);  // result = right
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
      emitExpr(expr.else, env, funNameToId, shapes, adts);
      const afterElse = codeOffset();
      patchI32(jumpIfFalsePos + 1, elseStart - (jumpIfFalsePos + 5));
      patchI32(jumpOverElsePos + 1, afterElse - (jumpOverElsePos + 5));
      break;
    }
    case 'BlockExpr': {
      const blockEnv = new Map(env);
      for (const stmt of expr.stmts) {
        if (stmt.kind === 'ValStmt') {
          emitExpr(stmt.value, blockEnv, funNameToId, shapes);
          const slot = blockEnv.size;
          blockEnv.set(stmt.name, slot);
          emitStoreLocal(slot);
        } else if (stmt.kind === 'VarStmt') {
          emitExpr(stmt.value, blockEnv, funNameToId, shapes);
          const slot = blockEnv.size;
          blockEnv.set(stmt.name, slot);
          emitStoreLocal(slot);
        } else if (stmt.kind === 'ExprStmt') {
          emitExpr(stmt.expr, blockEnv, funNameToId, shapes);
          // Expression result is left on stack, will be discarded
        }
      }
      emitExpr(expr.result, blockEnv, funNameToId, shapes);
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

        // Check for user-defined function
        if (funNameToId != null) {
          const fnId = funNameToId.get(expr.callee.name);
          if (fnId !== undefined) {
            for (const arg of expr.args) emitExpr(arg, env, funNameToId, shapes, adts);
            emitCall(fnId, expr.args.length);
            break;
          }
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

      // Store scrutinee in a local so we can access it in each case
      const scrutineeSlot = env.size;
      env.set('$scrutinee', scrutineeSlot); // Reserve the slot
      emitStoreLocal(scrutineeSlot);

      // Determine if this is an ADT match (Nil/Cons patterns) or wildcard match
      const hasAdtPatterns = expr.cases.some(
        c => c.pattern.kind === 'ConstructorPattern' ||
            c.pattern.kind === 'ConsPattern' ||
            c.pattern.kind === 'ListPattern'
      );

      if (hasAdtPatterns) {
        // Use MATCH instruction for ADT dispatch
        // MATCH pops an ADT value and jumps based on constructor tag
        emitLoadLocal(scrutineeSlot);

        // Build jump table - we need placeholders for each constructor
        // For List: constructor 0 = Nil, constructor 1 = Cons
        const matchPos = codeOffset();
        const jumpTableSize = 2; // Nil and Cons
        const placeholders: number[] = new Array(jumpTableSize).fill(0);
        emitMatch(placeholders);

        // Track case positions for patching
        const casePositions: number[] = [];
        const endJumps: number[] = [];

        // Emit each case
        for (const matchCase of expr.cases) {
          const caseStart = codeOffset();

          if (matchCase.pattern.kind === 'ListPattern' && matchCase.pattern.elements.length === 0) {
            // Empty list pattern [] matches Nil (constructor 0)
            casePositions[0] = caseStart - matchPos;
            emitExpr(matchCase.body, env, funNameToId, shapes, adts);
          } else if (matchCase.pattern.kind === 'ConstructorPattern' && matchCase.pattern.name === 'Nil') {
            // Nil case (constructor 0)
            casePositions[0] = caseStart - matchPos;
            emitExpr(matchCase.body, env, funNameToId, shapes, adts);
          } else if (matchCase.pattern.kind === 'ConstructorPattern' && matchCase.pattern.name === 'False') {
            // False case (constructor 0)
            casePositions[0] = caseStart - matchPos;
            emitExpr(matchCase.body, env, funNameToId, shapes, adts);
          } else if (matchCase.pattern.kind === 'ConstructorPattern' && matchCase.pattern.name === 'True') {
            // True case (constructor 1)
            casePositions[1] = caseStart - matchPos;
            emitExpr(matchCase.body, env, funNameToId, shapes, adts);
          } else if (matchCase.pattern.kind === 'ConsPattern') {
            // Cons case (constructor 1)
            casePositions[1] = caseStart - matchPos;

            // Bind head (extract from field 0)
            if (matchCase.pattern.head.kind === 'VarPattern') {
              const headSlot = env.size;
              env.set(matchCase.pattern.head.name, headSlot);
              emitLoadLocal(scrutineeSlot);
              emitGetField(0);
              emitStoreLocal(headSlot);
            }

            // Bind tail (extract from field 1)
            if (matchCase.pattern.tail.kind === 'VarPattern') {
              const tailSlot = env.size;
              env.set(matchCase.pattern.tail.name, tailSlot);
              emitLoadLocal(scrutineeSlot);
              emitGetField(1);
              emitStoreLocal(tailSlot);
            }

            emitExpr(matchCase.body, env, funNameToId, shapes, adts);

            // Clean up bindings
            if (matchCase.pattern.head.kind === 'VarPattern') {
              env.delete(matchCase.pattern.head.name);
            }
            if (matchCase.pattern.tail.kind === 'VarPattern') {
              env.delete(matchCase.pattern.tail.name);
            }
          } else if (matchCase.pattern.kind === 'WildcardPattern') {
            // Wildcard can handle any constructor - use it as fallback
            // For now, assume it's the Nil case if not already covered
            if (casePositions[0] === undefined) {
              casePositions[0] = caseStart - matchPos;
            }
            emitExpr(matchCase.body, env, funNameToId, shapes, adts);
          }

          // Jump to end after executing this case
          const jumpPos = codeOffset();
          emitJump(0);
          endJumps.push(jumpPos);
        }

        // Patch end jumps first to get end position
        const endPos = codeOffset();
        for (const jumpPos of endJumps) {
          // Offset is relative to position after the JUMP instruction (jumpPos + 5)
          patchI32(jumpPos + 1, endPos - (jumpPos + 5));
        }

        // Patch jump table - use end position as default for uncovered cases
        const matchJumpTablePos = matchPos + 1 + 4; // opcode + table size
        const defaultOffset = endPos - matchPos;
        for (let i = 0; i < jumpTableSize; i++) {
          const offset = casePositions[i] !== undefined ? casePositions[i] : defaultOffset;
          patchI32(matchJumpTablePos + i * 4, offset);
        }

        env.delete('$scrutinee'); // Clean up temporary
      } else {
        // Simple var/wildcard pattern - just bind and execute
        const firstCase = expr.cases[0];
        if (firstCase && firstCase.pattern.kind === 'VarPattern') {
          const slot = env.size;
          env.set(firstCase.pattern.name, slot);
          emitLoadLocal(scrutineeSlot);
          emitStoreLocal(slot);
          emitExpr(firstCase.body, env, funNameToId, shapes, adts);
          env.delete(firstCase.pattern.name);
        } else {
          // Wildcard or empty - just evaluate first case body
          emitExpr(firstCase?.body || { kind: 'LitExpr', value: { kind: 'unit' } }, env, funNameToId, shapes, adts);
        }
        env.delete('$scrutinee'); // Clean up temporary
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
    default:
      // Fallback: push unit
      emitLoadConst(addConstant({ tag: ConstTag.Unit }));
  }
}

/** Generate bytecode for program. */
export function codegen(program: Program): CodegenResult {
  stringTable.length = 0;
  constantPool.length = 0;
  codeStart();
  const shapes: ShapeEntry[] = [];

  // Initialize ADT table with built-in List ADT (always at index 0)
  const adts: AdtEntry[] = [{
    nameIndex: stringIndex('List'),
    constructors: [
      { nameIndex: stringIndex('Nil'), payloadTypeIndex: 0xFFFFFFFF },
      { nameIndex: stringIndex('Cons'), payloadTypeIndex: 0xFFFFFFFF }, // Simplified: payload type not used yet
    ],
  }];

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
  const funNameToId = new Map<string, number>();
  // Function IDs start from 1 (IDs 0xFFFFFF00, 0xFFFFFF01 are print/println primitives)
  // But function table entries start from index 0
  for (let i = 0; i < funDecls.length; i++) {
    funNameToId.set(funDecls[i]!.name, i);
    stringIndex(funDecls[i]!.name); // ensure name is in string table
  }

  const stmts = program.body.filter((n): n is TopLevelStmt =>
    n.kind === 'ValStmt' || n.kind === 'VarStmt' || n.kind === 'AssignStmt' || n.kind === 'ExprStmt'
  );
  const env = new Map<string, number>();

  for (const stmt of stmts) {
    if (stmt.kind === 'ValStmt' || stmt.kind === 'VarStmt') {
      emitExpr(stmt.value, env, funNameToId, shapes, adts);
      const slot = env.size;
      env.set(stmt.name, slot);
      emitStoreLocal(slot);
    } else if (stmt.kind === 'ExprStmt') {
      emitExpr(stmt.expr, env, funNameToId, shapes, adts);
      // Expression result is left on stack and will be discarded
    } else {
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
          if (slot === undefined) throw new Error(`Codegen: assign to unknown ${stmt.target.name}`);
          emitStoreLocal(slot);
        } else {
          emitStoreLocal(0);
        }
      }
    }
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
  };
}
