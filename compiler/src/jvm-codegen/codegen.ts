/**
 * JVM codegen: typed AST → .class file(s).
 * Uses same Program + getInferredType as kbc codegen.
 */
import type { Program, Expr, TopLevelStmt, TopLevelDecl } from '../ast/nodes.js';
import type { FunDecl, ValDecl, VarDecl, BlockExpr, LambdaExpr, FunStmt, TypeDecl } from '../ast/nodes.js';
import { getInferredType } from '../typecheck/check.js';
import type { InternalType } from '../types/internal.js';
import { ClassFileBuilder, type MethodBuilder, type StackMapFrameState, paramOnlyFrame } from './classfile.js';
import { JvmOp, ACC_PUBLIC, ACC_STATIC, ACC_PRIVATE, ACC_FINAL } from './opcodes.js';

const RUNTIME = 'kestrel/runtime/KRuntime';
const KUNIT = 'kestrel/runtime/KUnit';
const KRECORD = 'kestrel/runtime/KRecord';
const KMATH = 'kestrel/runtime/KMath';
const LONG = 'java/lang/Long';
const DOUBLE = 'java/lang/Double';
const BOOLEAN = 'java/lang/Boolean';
const STRING_BUILDER = 'java/lang/StringBuilder';
const K_NONE = 'kestrel/runtime/KNone';
const K_SOME = 'kestrel/runtime/KSome';
const K_NIL = 'kestrel/runtime/KNil';
const K_LIST = 'kestrel/runtime/KList';
const K_CONS = 'kestrel/runtime/KCons';
const K_ERR = 'kestrel/runtime/KErr';
const K_OK = 'kestrel/runtime/KOk';
const K_VNULL = 'kestrel/runtime/KVNull';
const K_FUNCTION = 'kestrel/runtime/KFunction';
const K_EXCEPTION = 'kestrel/runtime/KException';

/** Build stack map frame state: objectSlots from env + optional extra (e.g. scrut 55, exn 57); numLocals to cover all; optional stackDepth. */
function frameState(
  env: Map<string, number>,
  nextLocal: number,
  extraObjectSlots?: number[],
  stackDepth?: number
): StackMapFrameState {
  const objectSlots = new Set(env.values());
  if (extraObjectSlots) for (const s of extraObjectSlots) objectSlots.add(s);
  let numLocals = nextLocal;
  for (const s of objectSlots) {
    if (s + 1 > numLocals) numLocals = s + 1;
  }
  const out: StackMapFrameState = { numLocals, objectSlots };
  if (stackDepth !== undefined && stackDepth > 0) out.stackDepth = stackDepth;
  return out;
}

/** Collect free variables of expr (in scope but not in paramNames), first occurrence order. */
function getFreeVars(expr: Expr, paramNames: Set<string>, scope: Map<string, number>): string[] {
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
      case 'TemplateExpr':
        for (const part of e.parts) if (part.type === 'interp') walk(part.expr);
        return;
      case 'ListExpr':
        for (const el of e.elements) walk(el as Expr);
        return;
      case 'LiteralExpr':
      case 'ThrowExpr':
      case 'AwaitExpr':
        return;
      case 'TryExpr':
        walk(e.body);
        for (const c of e.cases) walk(c.body);
        return;
      case 'RecordExpr':
        if (e.spread) walk(e.spread);
        for (const f of e.fields) walk(f.value);
        return;
      case 'TupleExpr':
        for (const el of e.elements) walk(el);
        return;
      default:
        return;
    }
  }
  walk(expr);
  return result;
}

interface LambdaInfo {
  body: Expr;
  params: { name: string }[];
  freeVars: string[];
  capturing: boolean;
  /** For block-local FunStmt: names of other local functions in the same block (mutual recursion). */
  localFunNames?: Set<string>;
  /** Free vars that are `var` (captured by reference via KRecord). */
  freeVarVars?: Set<string>;
}

/** Collect all LambdaExpr (and FunStmt in blocks) from program, assign indices, return infos and id map. */
function collectLambdas(program: Program, globalNames: Set<string>, funNames: Set<string>): { lambdas: LambdaInfo[]; idByNode: Map<Expr | FunStmt, number> } {
  const lambdas: LambdaInfo[] = [];
  const idByNode = new Map<Expr | FunStmt, number>();
  const scope = new Map<string, number>();
  const varScope = new Set<string>();
  for (const name of funNames) scope.set(name, scope.size);
  for (const name of globalNames) scope.set(name, scope.size);
  function addLambda(body: Expr, params: { name: string }[], freeVars: string[], localFunNames?: Set<string>, freeVarVars?: Set<string>): number {
    const id = lambdas.length;
    const capturing = freeVars.length > 0 || (localFunNames?.size ?? 0) > 0;
    lambdas.push({ body, params, freeVars, capturing, localFunNames, freeVarVars });
    return id;
  }
  function walkBlock(block: BlockExpr): void {
    const savedScope = new Map(scope);
    const savedVarScope = new Set(varScope);
    const localFunNames = new Set<string>();
    for (const stmt of block.stmts) {
      if (stmt.kind === 'FunStmt') localFunNames.add(stmt.name);
    }
    for (const stmt of block.stmts) {
      if (stmt.kind === 'ValStmt' || stmt.kind === 'VarStmt') {
        if (stmt.kind === 'VarStmt') varScope.add(stmt.name);
        scope.set(stmt.name, scope.size);
        walk(stmt.value);
      } else if (stmt.kind === 'FunStmt') {
        scope.set(stmt.name, scope.size);
        const paramNames = new Set(stmt.params.map((p) => p.name));
        const fv = getFreeVars(stmt.body, paramNames, scope);
        const fvVars = new Set(fv.filter(name => varScope.has(name)));
        const id = addLambda(stmt.body, stmt.params.map((p) => ({ name: p.name })), fv, localFunNames.size > 1 ? localFunNames : undefined, fvVars.size > 0 ? fvVars : undefined);
        idByNode.set(stmt, id);
        walk(stmt.body);
      } else if (stmt.kind === 'ExprStmt') walk(stmt.expr);
      else if (stmt.kind === 'AssignStmt') {
        if (stmt.target.kind === 'IdentExpr') walk(stmt.target);
        walk(stmt.value);
      }
    }
    walk(block.result);
    scope.clear();
    for (const [k, v] of savedScope) scope.set(k, v);
    varScope.clear();
    for (const v of savedVarScope) varScope.add(v);
  }
  function walk(e: Expr): void {
    switch (e.kind) {
      case 'LambdaExpr': {
        const paramNames = new Set(e.params.map((p) => p.name));
        const fv = getFreeVars(e.body, paramNames, scope);
        const fvVars = new Set(fv.filter(name => varScope.has(name)));
        const id = addLambda(e.body, e.params.map((p) => ({ name: p.name })), fv, undefined, fvVars.size > 0 ? fvVars : undefined);
        idByNode.set(e, id);
        const savedScope = new Map(scope);
        for (const p of e.params) scope.set(p.name, scope.size);
        walk(e.body);
        scope.clear();
        for (const [k, v] of savedScope) scope.set(k, v);
        return;
      }
      case 'BlockExpr':
        walkBlock(e);
        return;
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
      case 'TemplateExpr':
        for (const part of e.parts) if (part.type === 'interp') walk(part.expr);
        return;
      case 'ListExpr':
        for (const el of e.elements) walk(el as Expr);
        return;
      case 'TryExpr':
        walk(e.body);
        for (const c of e.cases) walk(c.body);
        return;
      case 'RecordExpr':
        if (e.spread) walk(e.spread);
        for (const f of e.fields) walk(f.value);
        return;
      case 'TupleExpr':
        for (const el of e.elements) walk(el);
        return;
      default:
        return;
    }
  }
  for (const node of program.body) {
    if (!node) continue;
    if (node.kind === 'FunDecl') {
      const savedScope = new Map(scope);
      for (const p of node.params) scope.set(p.name, scope.size);
      walk(node.body);
      scope.clear();
      for (const [k, v] of savedScope) scope.set(k, v);
    } else if (node.kind === 'ValDecl' || node.kind === 'ValStmt' || node.kind === 'VarDecl' || node.kind === 'VarStmt') {
      const name = (node as ValDecl | { name: string }).name;
      if (node.kind === 'VarDecl' || node.kind === 'VarStmt') varScope.add(name);
      scope.set(name, scope.size);
      const v = node as ValDecl | VarDecl | { name: string; value: Expr };
      walk(v.value);
    } else if (node.kind === 'ExprStmt') {
      walk(node.expr);
    }
  }
  return { lambdas, idByNode };
}

export interface JvmCodegenOptions {
  sourceFile?: string;
  /** Class name (internal form, e.g. "Mandelbrot" or "kestrel/Option"). Default from sourceFile. */
  className?: string;
  /** Imported module class names: spec -> internal class name. */
  importClasses?: Map<string, string>;
  /** Namespace -> class name for namespace imports. */
  namespaceClasses?: Map<string, string>;
  /** Local name -> target class for named imports (direct calls: invokestatic targetClass.name). */
  importedNameToClass?: Map<string, string>;
  /** Local name -> target class for imported val/var (IdentExpr: getstatic targetClass.name). */
  importedValVarToClass?: Map<string, string>;
  /** Local alias -> original exported name (for aliased imports like `import { x as y }`). */
  importedNameToOriginal?: Map<string, string>;
}

export interface JvmCodegenResult {
  /** Main class internal name. */
  className: string;
  /** Bytes of the main class file. */
  classBytes: Uint8Array;
  /** Inner classes (e.g. closures): name -> bytes. */
  innerClasses: Map<string, Uint8Array>;
}

/** Derive class name from source path: "foo/bar.ks" -> "Bar", "kestrel/option.ks" -> "kestrel/Option". */
function classNameFromPath(sourceFile: string): string {
  const normalized = sourceFile.replace(/\\/g, '/');
  const lastSlash = normalized.lastIndexOf('/');
  const base = lastSlash >= 0 ? normalized.slice(lastSlash + 1) : normalized;
  const withoutExt = base.endsWith('.ks') ? base.slice(0, -3) : base;
  const firstUpper = withoutExt.charAt(0).toUpperCase() + withoutExt.slice(1);
  if (lastSlash < 0) return firstUpper;
  const pkg = normalized.slice(0, lastSlash);
  const pkgInternal = pkg.replace(/\//g, '/');
  return pkgInternal + '/' + firstUpper;
}

/** JVM method/field names must be valid identifiers. Mangle Kestrel names that use operators. */
function jvmMangleName(name: string): string {
  if (/^[a-zA-Z_$][a-zA-Z0-9_$]*$/.test(name)) return name;
  const map: Record<string, string> = {
    '<': '$less', '>': '$greater', '=': '$eq', '!': '$bang',
    '+': '$plus', '-': '$minus', '*': '$times', '/': '$div', '%': '$percent',
    '&': '$amp', '|': '$bar', '^': '$up',
  };
  let out = '';
  for (let i = 0; i < name.length; i++) {
    const c = name[i];
    if (map[c]) out += map[c];
    else if (/[a-zA-Z0-9_$]/.test(c)) out += c;
    else out += '$u' + c.charCodeAt(0).toString(16);
  }
  return out || '$';
}

/** Build descriptor for (Object,Object,...) -> Object. */
function descriptor(arity: number): string {
  let params = '';
  for (let i = 0; i < arity; i++) params += 'Ljava/lang/Object;';
  return `(${params})Ljava/lang/Object;`;
}

/** Primitive type name from InternalType. */
function primName(t: InternalType | undefined): string | null {
  if (!t || t.kind !== 'prim') return null;
  return t.name;
}

export function jvmCodegen(program: Program, options: JvmCodegenOptions = {}): JvmCodegenResult {
  const sourceFile = options.sourceFile ?? '<source>';
  const className = options.className ?? classNameFromPath(sourceFile);
  const cf = new ClassFileBuilder(className, 'java/lang/Object');
  const innerClasses = new Map<string, Uint8Array>();

  const adtClassByConstructor = new Map<string, string>();
  for (const node of program.body) {
    if (!node || node.kind !== 'TypeDecl') continue;
    const t = node as TypeDecl;
    if (t.body?.kind !== 'ADTBody') continue;
    const base = className + '$' + t.name;
    for (const c of t.body.constructors) {
      adtClassByConstructor.set(c.name, base + '$' + c.name);
    }
  }

  const funNames = new Set<string>();
  const globalSlots = new Map<string, number>();
  const globalNames = new Set<string>();
  let nextGlobalSlot = 0;
  for (const node of program.body) {
    if (!node) continue;
    if (node.kind === 'FunDecl') funNames.add(node.name);
    if (node.kind === 'ValDecl' || node.kind === 'VarDecl' || node.kind === 'ValStmt' || node.kind === 'VarStmt') {
      const name = node.kind === 'ValStmt' || node.kind === 'VarStmt' ? (node as { name: string }).name : (node as ValDecl).name;
      globalSlots.set(name, nextGlobalSlot++);
      globalNames.add(name);
    }
  }

  cf.addField('$initialized', 'Z', ACC_PRIVATE | ACC_STATIC);
  for (const node of program.body) {
    if (!node) continue;
    if (node.kind === 'ValDecl' || node.kind === 'VarDecl' || node.kind === 'ValStmt' || node.kind === 'VarStmt') {
      const name = node.kind === 'ValStmt' || node.kind === 'VarStmt' ? (node as { name: string }).name : (node as ValDecl).name;
      cf.addField(jvmMangleName(name), 'Ljava/lang/Object;', ACC_PUBLIC | ACC_STATIC);
    }
  }

  const env = new Map<string, number>();
  let nextLocal = 0;
  const varNames = new Set<string>();
  let freeVarToIndex: Map<string, number> | undefined; // set when emitting capturing lambda body
  let localFunNamesInEnv: Set<string> | undefined; // set when emitting block-local lambda (mutual recursion)

  const { lambdas, idByNode } = collectLambdas(program, globalNames, funNames);

  /** Build inner class for lambda (implements KFunction, apply calls outer.$lambdaN). */
  function buildLambdaClass(outerClassName: string, lambdaId: number, arity: number, capturing: boolean): Uint8Array {
    const innerName = outerClassName + '$Lambda' + lambdaId;
    const innerCf = new ClassFileBuilder(innerName, 'java/lang/Object', ACC_PUBLIC | ACC_FINAL);
    innerCf.addInterface(K_FUNCTION);
    if (capturing) {
      innerCf.addField('env', '[Ljava/lang/Object;', ACC_PRIVATE | ACC_FINAL);
      const ctor = innerCf.addMethod('<init>', '([Ljava/lang/Object;)V', ACC_PUBLIC);
      ctor.emit1b(JvmOp.ALOAD, 0);
      ctor.emit1s(JvmOp.INVOKESPECIAL, innerCf.methodref('java/lang/Object', '<init>', '()V'));
      ctor.emit1b(JvmOp.ALOAD, 0);
      ctor.emit1b(JvmOp.ALOAD, 1);
      ctor.emit1s(JvmOp.PUTFIELD, innerCf.fieldref(innerName, 'env', '[Ljava/lang/Object;'));
      ctor.emit1(JvmOp.RETURN);
      ctor.setMaxs(2, 2);
      innerCf.flushLastMethod();
    } else {
      const ctor = innerCf.addMethod('<init>', '()V', ACC_PUBLIC);
      ctor.emit1b(JvmOp.ALOAD, 0);
      ctor.emit1s(JvmOp.INVOKESPECIAL, innerCf.methodref('java/lang/Object', '<init>', '()V'));
      ctor.emit1(JvmOp.RETURN);
      ctor.setMaxs(1, 1);
      innerCf.flushLastMethod();
    }
    const applyMb = innerCf.addMethod('apply', '([Ljava/lang/Object;)Ljava/lang/Object;', ACC_PUBLIC);
    if (capturing) {
      applyMb.emit1b(JvmOp.ALOAD, 0);
      applyMb.emit1s(JvmOp.GETFIELD, innerCf.fieldref(innerName, 'env', '[Ljava/lang/Object;'));
    }
    for (let j = 0; j < arity; j++) {
      applyMb.emit1b(JvmOp.ALOAD, 1);
      applyMb.emit1s(JvmOp.LDC_W, innerCf.constantInt(j));
      applyMb.emit1(JvmOp.AALOAD);
    }
    const lambdaDesc = capturing
      ? `([Ljava/lang/Object;${'Ljava/lang/Object;'.repeat(arity)})Ljava/lang/Object;`
      : descriptor(arity);
    applyMb.emit1s(JvmOp.INVOKESTATIC, innerCf.methodref(outerClassName, '$lambda' + lambdaId, lambdaDesc));
    applyMb.emit1(JvmOp.ARETURN);
    applyMb.setMaxs(8, 3);
    innerCf.flushLastMethod();
    return innerCf.toBytes();
  }

  function emitExpr(expr: Expr, mb: MethodBuilder): void {
    switch (expr.kind) {
      case 'LiteralExpr': {
        switch (expr.literal) {
          case 'int': {
            const n = parseInt(expr.value, 10);
            const idx = cf.constantLong(BigInt(n));
            mb.emit1s(JvmOp.LDC2_W, idx);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(LONG, 'valueOf', '(J)Ljava/lang/Long;'));
            break;
          }
          case 'float': {
            const f = parseFloat(expr.value);
            const idx = cf.constantDouble(f);
            mb.emit1s(JvmOp.LDC2_W, idx);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(DOUBLE, 'valueOf', '(D)Ljava/lang/Double;'));
            break;
          }
          case 'string':
            mb.emit1s(JvmOp.LDC_W, cf.string(expr.value));
            break;
          case 'char': {
            const ch = expr.value.length >= 2 ? expr.value.slice(1, -1) : expr.value;
            const codePoint = ch.startsWith('\\u') ? parseInt(ch.slice(2), 16) : ch.codePointAt(0) ?? 0;
            mb.emit1s(JvmOp.LDC_W, cf.constantInt(codePoint));
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref('java/lang/Integer', 'valueOf', '(I)Ljava/lang/Integer;'));
            break;
          }
          case 'true':
            mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(BOOLEAN, 'TRUE', 'Ljava/lang/Boolean;'));
            break;
          case 'false':
            mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(BOOLEAN, 'FALSE', 'Ljava/lang/Boolean;'));
            break;
          case 'unit':
            mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
            break;
          default:
            mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
        }
        break;
      }
      case 'IdentExpr': {
        if (localFunNamesInEnv?.has(expr.name)) {
          mb.emit1b(JvmOp.ALOAD, 0);
          mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
          mb.emit1s(JvmOp.LDC_W, cf.string(expr.name));
          mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'get', '(Ljava/lang/String;)Ljava/lang/Object;'));
          break;
        }
        if (freeVarToIndex?.has(expr.name)) {
          mb.emit1b(JvmOp.ALOAD, 0);
          mb.emit1s(JvmOp.LDC_W, cf.constantInt(freeVarToIndex.get(expr.name)!));
          mb.emit1(JvmOp.AALOAD);
          if (varNames.has(expr.name)) {
            mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
            mb.emit1s(JvmOp.LDC_W, cf.string('0'));
            mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'get', '(Ljava/lang/String;)Ljava/lang/Object;'));
          }
          break;
        }
        const slot = env.get(expr.name);
        if (slot !== undefined) {
          mb.emit1b(JvmOp.ALOAD, slot);
          if (varNames.has(expr.name)) {
            mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
            mb.emit1s(JvmOp.LDC_W, cf.string('0'));
            mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'get', '(Ljava/lang/String;)Ljava/lang/Object;'));
          }
          break;
        }
        if (globalNames.has(expr.name)) {
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(className, jvmMangleName(expr.name), 'Ljava/lang/Object;'));
          break;
        }
        if (funNames.has(expr.name)) {
          mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(className, jvmMangleName(expr.name), '()Ljava/lang/Object;'));
          break;
        }
        const importedValVarClass = options.importedValVarToClass?.get(expr.name);
        if (importedValVarClass != null) {
          const originalName = options.importedNameToOriginal?.get(expr.name) ?? expr.name;
          mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(importedValVarClass, '$init', '()V'));
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(importedValVarClass, jvmMangleName(originalName), 'Ljava/lang/Object;'));
          break;
        }
        if (expr.name === 'None') {
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(K_NONE, 'INSTANCE', 'Lkestrel/runtime/KNone;'));
          break;
        }
        if (expr.name === 'Nil' || expr.name === '[]') {
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(K_NIL, 'INSTANCE', 'Lkestrel/runtime/KNil;'));
          break;
        }
        if (expr.name === 'Null') {
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(K_VNULL, 'INSTANCE', 'Lkestrel/runtime/KVNull;'));
          break;
        }
        throw new Error(`JVM codegen: unknown variable ${expr.name}`);
      }
      case 'BinaryExpr': {
        if (expr.op === '&' || expr.op === '|') {
          if (expr.op === '&') {
            emitExpr(expr.left, mb);
            const ifeqStart = mb.length();
            mb.emit1s(JvmOp.IFEQ, 0);
            mb.addBranchTarget(mb.length(), frameState(env, nextLocal));
            emitExpr(expr.right, mb);
            const gotoEnd = mb.length();
            mb.emit1s(JvmOp.GOTO, 0);
            const pushFalse = mb.length();
            mb.addBranchTarget(pushFalse, frameState(env, nextLocal));
            mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(BOOLEAN, 'FALSE', 'Ljava/lang/Boolean;'));
            const afterAnd = mb.length();
            mb.addBranchTarget(afterAnd, frameState(env, nextLocal, undefined, 1));
            patchShort(mb, ifeqStart + 1, pushFalse - ifeqStart);
            patchShort(mb, gotoEnd + 1, afterAnd - gotoEnd);
          } else {
            emitExpr(expr.left, mb);
            const ifeqStart = mb.length();
            mb.emit1s(JvmOp.IFEQ, 0);
            mb.addBranchTarget(mb.length(), frameState(env, nextLocal));
            mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(BOOLEAN, 'TRUE', 'Ljava/lang/Boolean;'));
            const gotoSkip = mb.length();
            mb.emit1s(JvmOp.GOTO, 0);
            const rightStart = mb.length();
            mb.addBranchTarget(rightStart, frameState(env, nextLocal));
            emitExpr(expr.right, mb);
            const afterOr = mb.length();
            mb.addBranchTarget(afterOr, frameState(env, nextLocal, undefined, 1));
            patchShort(mb, ifeqStart + 1, rightStart - ifeqStart);
            patchShort(mb, gotoSkip + 1, afterOr - gotoSkip);
          }
          break;
        }
        const leftPrim = primName(getInferredType(expr.left));
        const rightPrim = primName(getInferredType(expr.right));
        const isInt = leftPrim === 'Int' && rightPrim === 'Int';
        const isFloat = leftPrim === 'Float' || rightPrim === 'Float';
        emitExpr(expr.left, mb);
        if (isInt) mb.emit1s(JvmOp.CHECKCAST, cf.classRef(LONG));
        else if (isFloat) mb.emit1s(JvmOp.CHECKCAST, cf.classRef(DOUBLE));
        emitExpr(expr.right, mb);
        if (isInt) mb.emit1s(JvmOp.CHECKCAST, cf.classRef(LONG));
        else if (isFloat) mb.emit1s(JvmOp.CHECKCAST, cf.classRef(DOUBLE));
        if (expr.op === '==') {
          mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'equals', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Boolean;'));
          break;
        }
        if (expr.op === '!=') {
          // `!=` is boolean negation of the same deep equality as `==` (KRuntime.equals).
          mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'equals', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Boolean;'));
          mb.emit1s(JvmOp.CHECKCAST, cf.classRef(BOOLEAN));
          mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(BOOLEAN, 'booleanValue', '()Z'));
          const ifneEqual = mb.length();
          mb.emit1s(JvmOp.IFNE, 0); // values equal -> != is False
          mb.addBranchTarget(mb.length(), frameState(env, nextLocal));
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(BOOLEAN, 'TRUE', 'Ljava/lang/Boolean;'));
          const gotoEnd = mb.length();
          mb.emit1s(JvmOp.GOTO, 0);
          const pushFalse = mb.length();
          mb.addBranchTarget(pushFalse, frameState(env, nextLocal));
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(BOOLEAN, 'FALSE', 'Ljava/lang/Boolean;'));
          const afterNe = mb.length();
          mb.addBranchTarget(afterNe, frameState(env, nextLocal, undefined, 1));
          patchShort(mb, ifneEqual + 1, pushFalse - ifneEqual);
          patchShort(mb, gotoEnd + 1, afterNe - gotoEnd);
          break;
        }
        if (isInt) {
          const cmpOps = new Set(['<', '<=', '>', '>=']);
          if (cmpOps.has(expr.op)) {
            const op = jvmMangleName(expr.op);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(KMATH, op, '(Ljava/lang/Long;Ljava/lang/Long;)Ljava/lang/Boolean;'));
          } else {
            const intOpMap: Record<string, string> = { '+': 'add', '-': 'sub', '*': 'mul', '/': 'div', '%': 'mod', '**': 'pow' };
            const op = intOpMap[expr.op] ?? jvmMangleName(expr.op);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(KMATH, op, '(Ljava/lang/Long;Ljava/lang/Long;)Ljava/lang/Long;'));
          }
        } else if (isFloat) {
          const cmpOps = new Set(['<', '<=', '>', '>=']);
          if (cmpOps.has(expr.op)) {
            const op = jvmMangleName(expr.op) + 'Float';
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(KMATH, op, '(Ljava/lang/Double;Ljava/lang/Double;)Ljava/lang/Boolean;'));
          } else {
            const floatOp = expr.op === '+' ? 'addFloat' : expr.op === '-' ? 'subFloat' : expr.op === '*' ? 'mulFloat' : 'divFloat';
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(KMATH, floatOp, '(Ljava/lang/Double;Ljava/lang/Double;)Ljava/lang/Double;'));
          }
        } else {
          switch (expr.op) {
            case '<': case '<=': case '>': case '>=':
              mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'equals', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Boolean;'));
              mb.emit1(JvmOp.POP);
              mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(BOOLEAN, 'FALSE', 'Ljava/lang/Boolean;'));
              break;
            default:
              throw new Error(`JVM codegen: unsupported binary ${expr.op}`);
          }
        }
        break;
      }
      case 'IfExpr': {
        const ifResultSlot = 53;
        emitExpr(expr.cond, mb);
        mb.emit1s(JvmOp.CHECKCAST, cf.classRef(BOOLEAN));
        mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(BOOLEAN, 'booleanValue', '()Z'));
        const ifBranchState = frameState(env, nextLocal);
        const ifEndState = frameState(env, nextLocal, [ifResultSlot]);
        const ifeqPos = mb.length();
        mb.emit1s(JvmOp.IFEQ, 0);
        mb.addBranchTarget(mb.length(), ifBranchState);
        emitExpr(expr.then, mb);
        mb.emit1b(JvmOp.ASTORE, ifResultSlot);
        const gotoPos = mb.length();
        mb.emit1s(JvmOp.GOTO, 0);
        const elseStart = mb.length();
        mb.addBranchTarget(elseStart, ifBranchState);
        if (expr.else !== undefined) {
          emitExpr(expr.else, mb);
        } else {
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
        }
        mb.emit1b(JvmOp.ASTORE, ifResultSlot);
        const ifEndPos = mb.length();
        mb.addBranchTarget(ifEndPos, ifEndState);
        patchShort(mb, ifeqPos + 1, elseStart - ifeqPos);
        patchShort(mb, gotoPos + 1, ifEndPos - gotoPos);
        mb.emit1b(JvmOp.ALOAD, ifResultSlot);
        break;
      }
      case 'BlockExpr': {
        const outerEnv = new Map(env);
        const outerNextLocal = nextLocal;
        const blockEnv = new Map(env);
        let slot = nextLocal;
        const funStmts = expr.stmts.filter((s): s is FunStmt => s.kind === 'FunStmt');
        const recordSlot = funStmts.length > 1 ? (slot++, slot - 1) : -1;
        if (recordSlot >= 0) {
          mb.emit1s(JvmOp.NEW, cf.classRef(KRECORD));
          mb.emit1(JvmOp.DUP);
          mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(KRECORD, '<init>', '()V'));
          mb.emit1b(JvmOp.ASTORE, recordSlot);
        }
        for (const stmt of expr.stmts) {
          for (const [k, v] of blockEnv) env.set(k, v);
          if (stmt.kind === 'ValStmt') {
            emitExpr(stmt.value, mb);
            blockEnv.set(stmt.name, slot);
            env.set(stmt.name, slot);
            mb.emit1b(JvmOp.ASTORE, slot);
            slot++;
          } else if (stmt.kind === 'VarStmt') {
            mb.emit1s(JvmOp.NEW, cf.classRef(KRECORD));
            mb.emit1(JvmOp.DUP);
            mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(KRECORD, '<init>', '()V'));
            mb.emit1(JvmOp.DUP);
            mb.emit1s(JvmOp.LDC_W, cf.string('0'));
            emitExpr(stmt.value, mb);
            mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'set', '(Ljava/lang/String;Ljava/lang/Object;)V'));
            blockEnv.set(stmt.name, slot);
            env.set(stmt.name, slot);
            varNames.add(stmt.name);
            mb.emit1b(JvmOp.ASTORE, slot);
            slot++;
          } else if (stmt.kind === 'FunStmt') {
            const id = idByNode.get(stmt);
            if (id === undefined) throw new Error('JVM codegen: FunStmt not in idByNode');
            const l = lambdas[id];
            const arity = l.params.length;
            const otherFreeVars = l.localFunNames?.size ? l.freeVars.filter((x) => !l.localFunNames!.has(x)) : l.freeVars;
            if (l.capturing) {
              const hasRecordAt0 = l.localFunNames?.size && recordSlot >= 0;
              const arrLen = hasRecordAt0 ? 1 + otherFreeVars.length : l.freeVars.length;
              mb.emit1b(JvmOp.BIPUSH, arrLen);
              mb.emit1s(JvmOp.ANEWARRAY, cf.classRef('java/lang/Object'));
              if (hasRecordAt0) {
                mb.emit1(JvmOp.DUP);
                mb.emit1b(JvmOp.BIPUSH, 0);
                mb.emit1b(JvmOp.ALOAD, recordSlot);
                mb.emit1(JvmOp.AASTORE);
              }
              const varsToPush = l.localFunNames?.size ? otherFreeVars : l.freeVars;
              for (let i = 0; i < varsToPush.length; i++) {
                mb.emit1(JvmOp.DUP);
                mb.emit1b(JvmOp.BIPUSH, hasRecordAt0 ? 1 + i : i);
                const name = varsToPush[i];
                const s = blockEnv.get(name);
                if (s !== undefined) {
                  mb.emit1b(JvmOp.ALOAD, s);
                } else {
                  const g = env.get(name);
                  if (g !== undefined) {
                    mb.emit1b(JvmOp.ALOAD, g);
                  } else if (globalNames.has(name)) {
                    mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(className, jvmMangleName(name), 'Ljava/lang/Object;'));
                  } else {
                    throw new Error('JVM codegen: free var not in env: ' + name);
                  }
                }
                mb.emit1(JvmOp.AASTORE);
              }
              mb.emit1s(JvmOp.NEW, cf.classRef(className + '$Lambda' + id));
              mb.emit1(JvmOp.DUP_X1);
              mb.emit1(JvmOp.SWAP);
              mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(className + '$Lambda' + id, '<init>', '([Ljava/lang/Object;)V'));
            } else {
              mb.emit1s(JvmOp.NEW, cf.classRef(className + '$Lambda' + id));
              mb.emit1(JvmOp.DUP);
              mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(className + '$Lambda' + id, '<init>', '()V'));
            }
            if (recordSlot >= 0) {
              mb.emit1(JvmOp.DUP);
              mb.emit1b(JvmOp.ASTORE, slot);
              mb.emit1b(JvmOp.ALOAD, recordSlot);
              mb.emit1s(JvmOp.LDC_W, cf.string(stmt.name));
              mb.emit1b(JvmOp.ALOAD, slot);
              mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'set', '(Ljava/lang/String;Ljava/lang/Object;)V'));
            }
            blockEnv.set(stmt.name, slot);
            if (recordSlot < 0) mb.emit1b(JvmOp.ASTORE, slot);
            slot++;
          } else if (stmt.kind === 'AssignStmt') {
            if (stmt.target.kind === 'IdentExpr') {
              const s = blockEnv.get(stmt.target.name);
              if (s !== undefined && varNames.has(stmt.target.name)) {
                mb.emit1b(JvmOp.ALOAD, s);
                mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
                mb.emit1s(JvmOp.LDC_W, cf.string('0'));
                emitExpr(stmt.value, mb);
                mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'set', '(Ljava/lang/String;Ljava/lang/Object;)V'));
                mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
              } else if (freeVarToIndex?.has(stmt.target.name) && varNames.has(stmt.target.name)) {
                mb.emit1b(JvmOp.ALOAD, 0);
                mb.emit1s(JvmOp.LDC_W, cf.constantInt(freeVarToIndex.get(stmt.target.name)!));
                mb.emit1(JvmOp.AALOAD);
                mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
                mb.emit1s(JvmOp.LDC_W, cf.string('0'));
                emitExpr(stmt.value, mb);
                mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'set', '(Ljava/lang/String;Ljava/lang/Object;)V'));
                mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
              } else if (s !== undefined) {
                emitExpr(stmt.value, mb);
                mb.emit1b(JvmOp.ASTORE, s);
                mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
              } else {
                emitExpr(stmt.value, mb);
                mb.emit1(JvmOp.POP);
                mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
              }
            } else if (stmt.target.kind === 'FieldExpr') {
              emitExpr(stmt.value, mb);
              emitExpr(stmt.target.object, mb);
              mb.emit1s(JvmOp.LDC_W, cf.string(stmt.target.field));
              mb.emit1(JvmOp.DUP2_X1);
              mb.emit1(JvmOp.SWAP);
              mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'set', '(Ljava/lang/String;Ljava/lang/Object;)V'));
              mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
            } else {
              emitExpr(stmt.value, mb);
              mb.emit1(JvmOp.POP);
              mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
            }
          } else if (stmt.kind === 'ExprStmt') {
            emitExpr(stmt.expr, mb);
            mb.emit1(JvmOp.POP);
          }
        }
        for (const [k, v] of blockEnv) env.set(k, v);
        nextLocal = slot;
        emitExpr(expr.result, mb);
        env.clear();
        for (const [k, v] of outerEnv) env.set(k, v);
        nextLocal = outerNextLocal;
        break;
      }
      case 'CallExpr': {
        if (expr.callee.kind === 'IdentExpr') {
          const name = expr.callee.name;
          if (name === 'Some' && expr.args.length === 1) {
            mb.emit1s(JvmOp.NEW, cf.classRef(K_SOME));
            mb.emit1(JvmOp.DUP);
            emitExpr(expr.args[0], mb);
            mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(K_SOME, '<init>', '(Ljava/lang/Object;)V'));
            break;
          }
          if (name === 'Cons' && expr.args.length === 2) {
            emitExpr(expr.args[0], mb);
            mb.emit1b(JvmOp.ASTORE, 60);
            emitExpr(expr.args[1], mb);
            mb.emit1b(JvmOp.ASTORE, 61);
            mb.emit1s(JvmOp.NEW, cf.classRef(K_CONS));
            mb.emit1(JvmOp.DUP);
            mb.emit1b(JvmOp.ALOAD, 60);
            mb.emit1b(JvmOp.ALOAD, 61);
            mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(K_CONS, '<init>', '(Ljava/lang/Object;Lkestrel/runtime/KList;)V'));
            break;
          }
          if (name === 'Err' && expr.args.length === 1) {
            mb.emit1s(JvmOp.NEW, cf.classRef(K_ERR));
            mb.emit1(JvmOp.DUP);
            emitExpr(expr.args[0], mb);
            mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(K_ERR, '<init>', '(Ljava/lang/Object;)V'));
            break;
          }
          if (name === 'Ok' && expr.args.length === 1) {
            mb.emit1s(JvmOp.NEW, cf.classRef(K_OK));
            mb.emit1(JvmOp.DUP);
            emitExpr(expr.args[0], mb);
            mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(K_OK, '<init>', '(Ljava/lang/Object;)V'));
            break;
          }
          if (name === 'println' || name === 'print') {
            const runtimeMethod = name === 'println' ? 'println' : 'print';
            for (const arg of expr.args) emitExpr(arg, mb);
            const n = expr.args.length;
            const ARG_BASE = 60;
            for (let i = 0; i < n; i++) mb.emit1b(JvmOp.ASTORE, ARG_BASE + i);
            mb.emit1s(JvmOp.LDC_W, cf.constantInt(n));
            mb.emit1s(JvmOp.ANEWARRAY, cf.classRef('java/lang/Object'));
            for (let i = 0; i < n; i++) {
              mb.emit1(JvmOp.DUP);
              mb.emit1s(JvmOp.LDC_W, cf.constantInt(i));
              mb.emit1b(JvmOp.ALOAD, ARG_BASE + i);
              mb.emit1(JvmOp.AASTORE);
            }
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, runtimeMethod, '([Ljava/lang/Object;)V'));
            mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
            break;
          }
          if (name === 'exit' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'exit', '(Ljava/lang/Object;)V'));
            mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
            break;
          }
          if (name === '__format_one' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'formatOne', '(Ljava/lang/Object;)Ljava/lang/String;'));
            break;
          }
          if (name === 'concat' && expr.args.length === 2) {
            emitExpr(expr.args[0], mb);
            emitExpr(expr.args[1], mb);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'concat', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/String;'));
            break;
          }
          if (name === '__equals' && expr.args.length === 2) {
            emitExpr(expr.args[0], mb);
            emitExpr(expr.args[1], mb);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'equals', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Boolean;'));
            break;
          }
          if (name === '__string_length' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'stringLength', '(Ljava/lang/Object;)Ljava/lang/Long;'));
            break;
          }
          if (name === '__string_slice' && expr.args.length === 3) {
            emitExpr(expr.args[0], mb);
            emitExpr(expr.args[1], mb);
            emitExpr(expr.args[2], mb);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'stringSlice', '(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/String;'));
            break;
          }
          if (name === '__string_index_of' && expr.args.length === 2) {
            emitExpr(expr.args[0], mb);
            emitExpr(expr.args[1], mb);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'stringIndexOf', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Long;'));
            break;
          }
          if (name === '__string_equals' && expr.args.length === 2) {
            emitExpr(expr.args[0], mb);
            emitExpr(expr.args[1], mb);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'stringEquals', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Boolean;'));
            break;
          }
          if (name === '__string_upper' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'stringUpper', '(Ljava/lang/Object;)Ljava/lang/String;'));
            break;
          }
          if (name === '__json_parse' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'jsonParse', '(Ljava/lang/Object;)Lkestrel/runtime/KValue;'));
            break;
          }
          if (name === '__json_stringify' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'jsonStringify', '(Ljava/lang/Object;)Ljava/lang/String;'));
            break;
          }
          if (name === '__read_file_async' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'readFileAsync', '(Ljava/lang/Object;)Ljava/lang/Object;'));
            break;
          }
          if (name === '__list_dir' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'listDir', '(Ljava/lang/Object;)Lkestrel/runtime/KList;'));
            break;
          }
          if (name === '__write_text' && expr.args.length === 2) {
            emitExpr(expr.args[0], mb);
            emitExpr(expr.args[1], mb);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'writeText', '(Ljava/lang/Object;Ljava/lang/Object;)V'));
            mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
            break;
          }
          if (name === '__now_ms' && expr.args.length === 0) {
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'nowMs', '()Ljava/lang/Long;'));
            break;
          }
          if (name === '__get_os' && expr.args.length === 0) {
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'getOs', '()Ljava/lang/String;'));
            break;
          }
          if (name === '__get_args' && expr.args.length === 0) {
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'getArgs', '()Lkestrel/runtime/KList;'));
            break;
          }
          if (name === '__get_cwd' && expr.args.length === 0) {
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'getCwd', '()Ljava/lang/String;'));
            break;
          }
          if (name === '__run_process' && expr.args.length === 2) {
            emitExpr(expr.args[0], mb);
            emitExpr(expr.args[1], mb);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'runProcess', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Long;'));
            break;
          }
          const ns = options.namespaceClasses?.get(name);
          const importedClass = options.importedNameToClass?.get(name);
          if (funNames.has(name) || ns || importedClass) {
            let targetClass = className;
            let methodName = options.importedNameToOriginal?.get(name) ?? name;
            if (ns) targetClass = ns;
            else if (importedClass) targetClass = importedClass;
            if (targetClass !== className) {
              mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(targetClass, '$init', '()V'));
            }
            for (const arg of expr.args) emitExpr(arg, mb);
            const arity = expr.args.length;
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(targetClass, jvmMangleName(methodName), descriptor(arity)));
            break;
          }
        }
        emitExpr(expr.callee, mb);
        const n = expr.args.length;
        const CALLEE_TEMP = 60;
        const ARG_TEMP_BASE = 61;
        mb.emit1b(JvmOp.ASTORE, CALLEE_TEMP);
        for (const arg of expr.args) emitExpr(arg, mb);
        for (let i = 0; i < n; i++) mb.emit1b(JvmOp.ASTORE, ARG_TEMP_BASE + i);
        mb.emit1s(JvmOp.LDC_W, cf.constantInt(n));
        mb.emit1s(JvmOp.ANEWARRAY, cf.classRef('java/lang/Object'));
        for (let i = 0; i < n; i++) {
          mb.emit1(JvmOp.DUP);
          mb.emit1s(JvmOp.LDC_W, cf.constantInt(i));
          mb.emit1b(JvmOp.ALOAD, ARG_TEMP_BASE + i);
          mb.emit1(JvmOp.AASTORE);
        }
        mb.emit1b(JvmOp.ALOAD, CALLEE_TEMP);
        mb.emit1s(JvmOp.CHECKCAST, cf.classRef('kestrel/runtime/KFunction'));
        mb.emit1(JvmOp.SWAP);
        const applyIdx = cf.interfaceMethodref('kestrel/runtime/KFunction', 'apply', '([Ljava/lang/Object;)Ljava/lang/Object;');
        mb.emit1(JvmOp.INVOKEINTERFACE);
        mb.pushShort(applyIdx);
        mb.pushByte(2);
        mb.pushByte(0);
        break;
      }
      case 'TemplateExpr': {
        mb.emit1s(JvmOp.NEW, cf.classRef(STRING_BUILDER));
        mb.emit1(JvmOp.DUP);
        mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(STRING_BUILDER, '<init>', '()V'));
        for (const part of expr.parts) {
          if (part.type === 'literal') {
            mb.emit1s(JvmOp.LDC_W, cf.string(part.value));
            mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(STRING_BUILDER, 'append', '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));
          } else {
            emitExpr(part.expr, mb);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'formatOne', '(Ljava/lang/Object;)Ljava/lang/String;'));
            mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(STRING_BUILDER, 'append', '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));
          }
        }
        mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(STRING_BUILDER, 'toString', '()Ljava/lang/String;'));
        break;
      }
      case 'MatchExpr': {
        emitExpr(expr.scrutinee, mb);
        const scrutSlot = 55;
        const matchResultSlot = 54;
        mb.emit1b(JvmOp.ASTORE, scrutSlot);
        mb.emit1(JvmOp.ACONST_NULL);
        mb.emit1b(JvmOp.ASTORE, matchResultSlot);
        const matchBaseState = frameState(env, nextLocal, [55, matchResultSlot]);
        const endLabels: number[] = [];
        const savedNextLocal = nextLocal;
        env.set('$matchScrut', scrutSlot);
        env.set('$matchResult', matchResultSlot);
        for (let i = 0; i < expr.cases.length; i++) {
          nextLocal = savedNextLocal;
          const c = expr.cases[i]!;
          if (c.pattern.kind === 'ListPattern' && c.pattern.elements.length === 0) {
            mb.emit1b(JvmOp.ALOAD, scrutSlot);
            mb.emit1s(JvmOp.INSTANCEOF, cf.classRef(K_NIL));
            const ifeq = mb.length();
            mb.emit1s(JvmOp.IFEQ, 0);
            mb.addBranchTarget(ifeq + 3, matchBaseState);
            emitExpr(c.body, mb);
            mb.emit1b(JvmOp.ASTORE, matchResultSlot);
            const gotoEnd = mb.length();
            mb.emit1s(JvmOp.GOTO, 0);
            endLabels.push(gotoEnd);
            const afterGoto = gotoEnd + 3;
            patchShort(mb, ifeq + 1, afterGoto - ifeq);
            mb.addBranchTarget(afterGoto, matchBaseState);
            continue;
          }
          if (c.pattern.kind === 'ConstructorPattern') {
            const p = c.pattern;
            if (p.name === 'None') {
              mb.emit1b(JvmOp.ALOAD, scrutSlot);
              mb.emit1s(JvmOp.INSTANCEOF, cf.classRef(K_NONE));
              const ifeq = mb.length();
              mb.emit1s(JvmOp.IFEQ, 0);
              mb.addBranchTarget(ifeq + 3, matchBaseState);
              emitExpr(c.body, mb);
              mb.emit1b(JvmOp.ASTORE, matchResultSlot);
              const gotoEnd = mb.length();
              mb.emit1s(JvmOp.GOTO, 0);
              endLabels.push(gotoEnd);
              const afterGoto = gotoEnd + 3;
              patchShort(mb, ifeq + 1, afterGoto - ifeq);
              mb.addBranchTarget(afterGoto, matchBaseState);
              continue;
            }
            if (p.name === 'Some') {
              mb.emit1b(JvmOp.ALOAD, scrutSlot);
              mb.emit1s(JvmOp.INSTANCEOF, cf.classRef(K_SOME));
              const ifeq = mb.length();
              mb.emit1s(JvmOp.IFEQ, 0);
              mb.addBranchTarget(ifeq + 3, matchBaseState);
              mb.emit1b(JvmOp.ALOAD, scrutSlot);
              mb.emit1s(JvmOp.CHECKCAST, cf.classRef(K_SOME));
              mb.emit1s(JvmOp.GETFIELD, cf.fieldref(K_SOME, 'value', 'Ljava/lang/Object;'));
              const varName = p.fields?.[0] && p.fields[0].pattern?.kind === 'VarPattern' ? (p.fields[0].pattern as { name: string }).name : null;
              if (varName) {
                const slot = nextLocal++;
                env.set(varName, slot);
                mb.emit1b(JvmOp.ASTORE, slot);
              }
              emitExpr(c.body, mb);
              if (varName) env.delete(varName);
              mb.emit1b(JvmOp.ASTORE, matchResultSlot);
              const gotoEnd = mb.length();
              mb.emit1s(JvmOp.GOTO, 0);
              endLabels.push(gotoEnd);
              const afterGoto = gotoEnd + 3;
              patchShort(mb, ifeq + 1, afterGoto - ifeq);
              mb.addBranchTarget(afterGoto, matchBaseState);
              continue;
            }
            if (p.name === 'Nil') {
              mb.emit1b(JvmOp.ALOAD, scrutSlot);
              mb.emit1s(JvmOp.INSTANCEOF, cf.classRef(K_NIL));
              const ifeq = mb.length();
              mb.emit1s(JvmOp.IFEQ, 0);
              mb.addBranchTarget(mb.length(), matchBaseState);
              emitExpr(c.body, mb);
              mb.emit1b(JvmOp.ASTORE, matchResultSlot);
              const gotoEnd = mb.length();
              mb.emit1s(JvmOp.GOTO, 0);
              endLabels.push(gotoEnd);
              const afterGoto = gotoEnd + 3;
              patchShort(mb, ifeq + 1, afterGoto - ifeq);
              mb.addBranchTarget(afterGoto, matchBaseState);
              continue;
            }
            if (p.name === 'Cons') {
              mb.emit1b(JvmOp.ALOAD, scrutSlot);
              mb.emit1s(JvmOp.INSTANCEOF, cf.classRef(K_CONS));
              const ifeq = mb.length();
              mb.emit1s(JvmOp.IFEQ, 0);
              mb.addBranchTarget(mb.length(), matchBaseState);
              const headPat = p.fields?.[0]?.pattern;
              const tailPat = p.fields?.[1]?.pattern;
              if (headPat?.kind === 'VarPattern') {
                mb.emit1b(JvmOp.ALOAD, scrutSlot);
                mb.emit1s(JvmOp.CHECKCAST, cf.classRef(K_CONS));
                mb.emit1s(JvmOp.GETFIELD, cf.fieldref(K_CONS, 'head', 'Ljava/lang/Object;'));
                const slot = nextLocal++;
                env.set(headPat.name, slot);
                mb.emit1b(JvmOp.ASTORE, slot);
              }
              if (tailPat?.kind === 'VarPattern') {
                mb.emit1b(JvmOp.ALOAD, scrutSlot);
                mb.emit1s(JvmOp.CHECKCAST, cf.classRef(K_CONS));
                mb.emit1s(JvmOp.GETFIELD, cf.fieldref(K_CONS, 'tail', 'Lkestrel/runtime/KList;'));
                const slot = nextLocal++;
                env.set(tailPat.name, slot);
                mb.emit1b(JvmOp.ASTORE, slot);
              }
              emitExpr(c.body, mb);
              if (headPat?.kind === 'VarPattern') env.delete(headPat.name);
              if (tailPat?.kind === 'VarPattern') env.delete(tailPat.name);
              mb.emit1b(JvmOp.ASTORE, matchResultSlot);
              const gotoEnd = mb.length();
              mb.emit1s(JvmOp.GOTO, 0);
              endLabels.push(gotoEnd);
              const afterGoto = gotoEnd + 3;
              patchShort(mb, ifeq + 1, afterGoto - ifeq);
              mb.addBranchTarget(afterGoto, matchBaseState);
              continue;
            }
          }
          if (c.pattern.kind === 'ConsPattern') {
            const headPat = c.pattern.head;
            const tailPat = c.pattern.tail;
            mb.emit1b(JvmOp.ALOAD, scrutSlot);
            mb.emit1s(JvmOp.INSTANCEOF, cf.classRef(K_CONS));
            const ifeq = mb.length();
            mb.emit1s(JvmOp.IFEQ, 0);
            mb.addBranchTarget(mb.length(), matchBaseState);
            if (headPat.kind === 'VarPattern') {
              mb.emit1b(JvmOp.ALOAD, scrutSlot);
              mb.emit1s(JvmOp.CHECKCAST, cf.classRef(K_CONS));
              mb.emit1s(JvmOp.GETFIELD, cf.fieldref(K_CONS, 'head', 'Ljava/lang/Object;'));
              const slot = nextLocal++;
              env.set(headPat.name, slot);
              mb.emit1b(JvmOp.ASTORE, slot);
            }
            if (tailPat.kind === 'VarPattern') {
              mb.emit1b(JvmOp.ALOAD, scrutSlot);
              mb.emit1s(JvmOp.CHECKCAST, cf.classRef(K_CONS));
              mb.emit1s(JvmOp.GETFIELD, cf.fieldref(K_CONS, 'tail', 'Lkestrel/runtime/KList;'));
              const slot = nextLocal++;
              env.set(tailPat.name, slot);
              mb.emit1b(JvmOp.ASTORE, slot);
            }
            emitExpr(c.body, mb);
            if (headPat.kind === 'VarPattern') env.delete(headPat.name);
            if (tailPat.kind === 'VarPattern') env.delete(tailPat.name);
            mb.emit1b(JvmOp.ASTORE, matchResultSlot);
            const gotoEnd = mb.length();
            mb.emit1s(JvmOp.GOTO, 0);
            endLabels.push(gotoEnd);
            const afterGoto = gotoEnd + 3;
            patchShort(mb, ifeq + 1, afterGoto - ifeq);
            mb.addBranchTarget(afterGoto, matchBaseState);
            continue;
          }
          if (c.pattern.kind === 'VarPattern') {
            const slot = nextLocal++;
            env.set(c.pattern.name, slot);
            mb.emit1b(JvmOp.ALOAD, scrutSlot);
            mb.emit1b(JvmOp.ASTORE, slot);
            emitExpr(c.body, mb);
            env.delete(c.pattern.name);
            mb.emit1b(JvmOp.ASTORE, matchResultSlot);
            const gotoEnd = mb.length();
            mb.emit1s(JvmOp.GOTO, 0);
            endLabels.push(gotoEnd);
            continue;
          }
          if (c.pattern.kind === 'WildcardPattern') {
            emitExpr(c.body, mb);
            mb.emit1b(JvmOp.ASTORE, matchResultSlot);
            const gotoEnd = mb.length();
            mb.emit1s(JvmOp.GOTO, 0);
            endLabels.push(gotoEnd);
          }
        }
        env.delete('$matchScrut');
        env.delete('$matchResult');
        const endPos = mb.length();
        mb.addBranchTarget(endPos, matchBaseState);
        mb.emit1b(JvmOp.ALOAD, matchResultSlot);
        for (const gotoPos of endLabels) {
          patchShort(mb, gotoPos + 1, endPos - gotoPos);
        }
        break;
      }
      case 'ListExpr': {
        if (expr.elements.length === 0) {
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(K_NIL, 'INSTANCE', 'Lkestrel/runtime/KNil;'));
          break;
        }
        const listTemp = 62;
        const elemTemp = 63;
        mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(K_NIL, 'INSTANCE', 'Lkestrel/runtime/KNil;'));
        mb.emit1b(JvmOp.ASTORE, listTemp);
        for (let i = expr.elements.length - 1; i >= 0; i--) {
          const el = expr.elements[i];
          if (el && typeof el === 'object' && 'spread' in el) {
            emitExpr((el as { expr: Expr }).expr, mb);
          } else {
            emitExpr(el as Expr, mb);
          }
          const elExpr = el && typeof el === 'object' && 'spread' in el ? (el as { expr: Expr }).expr : (el as Expr);
          if (elExpr && (elExpr.kind === 'IfExpr' || elExpr.kind === 'MatchExpr')) {
            mb.emit1b(JvmOp.ALOAD, elExpr.kind === 'IfExpr' ? 53 : 54);
          }
          mb.emit1b(JvmOp.ASTORE, elemTemp);
          mb.emit1s(JvmOp.NEW, cf.classRef(K_CONS));
          mb.emit1(JvmOp.DUP);
          mb.emit1b(JvmOp.ALOAD, elemTemp);
          mb.emit1b(JvmOp.ALOAD, listTemp);
          mb.emit1s(JvmOp.CHECKCAST, cf.classRef(K_LIST));
          mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(K_CONS, '<init>', '(Ljava/lang/Object;Lkestrel/runtime/KList;)V'));
          mb.emit1b(JvmOp.ASTORE, listTemp);
        }
        mb.emit1b(JvmOp.ALOAD, listTemp);
        break;
      }
      case 'ConsExpr': {
        emitExpr(expr.head, mb);
        mb.emit1b(JvmOp.ASTORE, 60);
        emitExpr(expr.tail, mb);
        mb.emit1b(JvmOp.ASTORE, 61);
        mb.emit1s(JvmOp.NEW, cf.classRef(K_CONS));
        mb.emit1(JvmOp.DUP);
        mb.emit1b(JvmOp.ALOAD, 60);
        mb.emit1b(JvmOp.ALOAD, 61);
        mb.emit1s(JvmOp.CHECKCAST, cf.classRef(K_LIST));
        mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(K_CONS, '<init>', '(Ljava/lang/Object;Lkestrel/runtime/KList;)V'));
        break;
      }
      case 'PipeExpr': {
        if (expr.op === '|>') {
          emitExpr(expr.left, mb);
          if (expr.right.kind === 'CallExpr' && expr.right.callee.kind === 'IdentExpr') {
            for (const a of expr.right.args) emitExpr(a, mb);
            const arity = 1 + expr.right.args.length;
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(className, jvmMangleName(expr.right.callee.name), descriptor(arity)));
          } else {
            emitExpr(expr.right, mb);
          }
        } else {
          emitExpr(expr.right, mb);
          emitExpr(expr.left, mb);
        }
        break;
      }
      case 'UnaryExpr': {
        if (expr.op === '-') {
          mb.emit1s(JvmOp.LDC2_W, cf.constantLong(0n));
          mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(LONG, 'valueOf', '(J)Ljava/lang/Long;'));
          emitExpr(expr.operand, mb);
          mb.emit1s(JvmOp.CHECKCAST, cf.classRef(LONG));
          mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(KMATH, 'sub', '(Ljava/lang/Long;Ljava/lang/Long;)Ljava/lang/Long;'));
        } else if (expr.op === '!') {
          emitExpr(expr.operand, mb);
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(BOOLEAN, 'TRUE', 'Ljava/lang/Boolean;'));
          const ifeqPos = mb.length();
          mb.emit1s(JvmOp.IF_ACMPEQ, 0);
          mb.addBranchTarget(mb.length(), frameState(env, nextLocal));
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(BOOLEAN, 'TRUE', 'Ljava/lang/Boolean;'));
          const gotoEnd = mb.length();
          mb.emit1s(JvmOp.GOTO, 0);
          const falseLabel = mb.length();
          mb.addBranchTarget(falseLabel, frameState(env, nextLocal));
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(BOOLEAN, 'FALSE', 'Ljava/lang/Boolean;'));
          const afterNot = mb.length();
          mb.addBranchTarget(afterNot, frameState(env, nextLocal, undefined, 1));
          patchShort(mb, ifeqPos + 1, falseLabel - ifeqPos);
          patchShort(mb, gotoEnd + 1, afterNot - gotoEnd);
        } else {
          emitExpr(expr.operand, mb);
        }
        break;
      }
      case 'LambdaExpr': {
        const id = idByNode.get(expr);
        if (id === undefined) throw new Error('JVM codegen: lambda not in idByNode');
        const l = lambdas[id];
        const arity = l.params.length;
        if (l.capturing) {
          mb.emit1b(JvmOp.BIPUSH, l.freeVars.length);
          mb.emit1s(JvmOp.ANEWARRAY, cf.classRef('java/lang/Object'));
          for (let i = 0; i < l.freeVars.length; i++) {
            mb.emit1(JvmOp.DUP);
            mb.emit1b(JvmOp.BIPUSH, i);
            const name = l.freeVars[i];
            const s = env.get(name);
            if (s !== undefined) {
              mb.emit1b(JvmOp.ALOAD, s);
            } else if (globalNames.has(name)) {
              mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(className, jvmMangleName(name), 'Ljava/lang/Object;'));
            } else {
              throw new Error('JVM codegen: free var not in env/global: ' + name);
            }
            mb.emit1(JvmOp.AASTORE);
          }
          mb.emit1s(JvmOp.NEW, cf.classRef(className + '$Lambda' + id));
          mb.emit1(JvmOp.DUP_X1);
          mb.emit1(JvmOp.SWAP);
          mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(className + '$Lambda' + id, '<init>', '([Ljava/lang/Object;)V'));
        } else {
          mb.emit1s(JvmOp.NEW, cf.classRef(className + '$Lambda' + id));
          mb.emit1(JvmOp.DUP);
          mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(className + '$Lambda' + id, '<init>', '()V'));
        }
        break;
      }
      case 'RecordExpr': {
        if (expr.spread) {
          emitExpr(expr.spread, mb);
          mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
          mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'copy', '()Lkestrel/runtime/KRecord;'));
        } else {
          mb.emit1s(JvmOp.NEW, cf.classRef(KRECORD));
          mb.emit1(JvmOp.DUP);
          mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(KRECORD, '<init>', '()V'));
        }
        for (const f of expr.fields) {
          mb.emit1(JvmOp.DUP);
          mb.emit1s(JvmOp.LDC_W, cf.string(f.name));
          emitExpr(f.value, mb);
          mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'set', '(Ljava/lang/String;Ljava/lang/Object;)V'));
        }
        break;
      }
      case 'FieldExpr': {
        emitExpr(expr.object, mb);
        mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
        mb.emit1s(JvmOp.LDC_W, cf.string(expr.field));
        mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'get', '(Ljava/lang/String;)Ljava/lang/Object;'));
        break;
      }
      case 'TupleExpr': {
        mb.emit1s(JvmOp.NEW, cf.classRef(KRECORD));
        mb.emit1(JvmOp.DUP);
        mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(KRECORD, '<init>', '()V'));
        for (let i = 0; i < expr.elements.length; i++) {
          mb.emit1(JvmOp.DUP);
          mb.emit1s(JvmOp.LDC_W, cf.string(String(i)));
          emitExpr(expr.elements[i], mb);
          mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'set', '(Ljava/lang/String;Ljava/lang/Object;)V'));
        }
        break;
      }
      case 'ThrowExpr': {
        emitExpr(expr.value, mb);
        mb.emit1s(JvmOp.NEW, cf.classRef(K_EXCEPTION));
        mb.emit1(JvmOp.DUP_X1);
        mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(K_EXCEPTION, '<init>', '(Ljava/lang/Object;)V'));
        mb.emit1(JvmOp.ATHROW);
        break;
      }
      case 'TryExpr': {
        const tryStart = mb.length();
        mb.addBranchTarget(tryStart, frameState(env, nextLocal));
        emitExpr(expr.body, mb);
        const tryEnd = mb.length();
        const gotoAfter = mb.length();
        mb.emit1s(JvmOp.GOTO, 0);
        const handlerStart = mb.length();
        mb.addBranchTarget(handlerStart, frameState(env, nextLocal, [57]));
        const EXN_SLOT = 57;
        const PAYLOAD_SLOT = 56;
        mb.emit1b(JvmOp.ASTORE, EXN_SLOT);
        mb.emit1b(JvmOp.ALOAD, EXN_SLOT);
        mb.emit1s(JvmOp.CHECKCAST, cf.classRef(K_EXCEPTION));
        mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(K_EXCEPTION, 'getPayload', '()Ljava/lang/Object;'));
        mb.emit1b(JvmOp.ASTORE, PAYLOAD_SLOT);
        const prevCatchVar = expr.catchVar != null ? env.get(expr.catchVar) : undefined;
        if (expr.catchVar != null) env.set(expr.catchVar, PAYLOAD_SLOT);
        const catchEndLabels: number[] = [];
        for (let i = 0; i < expr.cases.length; i++) {
          const c = expr.cases[i]!;
          if (c.pattern.kind === 'VarPattern') {
            const slot = nextLocal++;
            env.set(c.pattern.name, slot);
            mb.emit1b(JvmOp.ALOAD, PAYLOAD_SLOT);
            mb.emit1b(JvmOp.ASTORE, slot);
            emitExpr(c.body, mb);
            env.delete(c.pattern.name);
            const gotoEnd = mb.length();
            mb.emit1s(JvmOp.GOTO, 0);
            catchEndLabels.push(gotoEnd);
            continue;
          }
          if (c.pattern.kind === 'WildcardPattern') {
            emitExpr(c.body, mb);
            const gotoEnd = mb.length();
            mb.emit1s(JvmOp.GOTO, 0);
            catchEndLabels.push(gotoEnd);
            continue;
          }
          if (c.pattern.kind === 'ConstructorPattern') {
            const p = c.pattern;
            const adtClass = adtClassByConstructor.get(p.name);
            if (adtClass != null) {
              mb.emit1b(JvmOp.ALOAD, PAYLOAD_SLOT);
              mb.emit1s(JvmOp.INSTANCEOF, cf.classRef(adtClass));
              const ifeq = mb.length();
              mb.emit1s(JvmOp.IFEQ, 0);
              mb.addBranchTarget(mb.length(), frameState(env, nextLocal, [57]));
              if (p.fields?.length) {
                mb.emit1b(JvmOp.ALOAD, PAYLOAD_SLOT);
                mb.emit1s(JvmOp.CHECKCAST, cf.classRef(adtClass));
                for (let fi = 0; fi < p.fields.length; fi++) {
                  const f = p.fields[fi]!;
                  const fieldName = f.name ?? String(fi);
                  mb.emit1s(JvmOp.GETFIELD, cf.fieldref(adtClass, fieldName, 'Ljava/lang/Object;'));
                  if (f.pattern?.kind === 'VarPattern') {
                    const slot = nextLocal++;
                    env.set((f.pattern as { name: string }).name, slot);
                    mb.emit1b(JvmOp.ASTORE, slot);
                  }
                }
              }
              emitExpr(c.body, mb);
              if (p.fields?.length) for (const f of p.fields) if (f.pattern?.kind === 'VarPattern') env.delete((f.pattern as { name: string }).name);
              const gotoEnd = mb.length();
              mb.emit1s(JvmOp.GOTO, 0);
              catchEndLabels.push(gotoEnd);
              const afterGoto = gotoEnd + 3;
              patchShort(mb, ifeq + 1, afterGoto - ifeq);
              mb.addBranchTarget(afterGoto, frameState(env, nextLocal, [57]));
              continue;
            }
            if (p.name === 'None') {
              mb.emit1b(JvmOp.ALOAD, PAYLOAD_SLOT);
              mb.emit1s(JvmOp.INSTANCEOF, cf.classRef(K_NONE));
              const ifeq = mb.length();
              mb.emit1s(JvmOp.IFEQ, 0);
              mb.addBranchTarget(mb.length(), frameState(env, nextLocal, [57]));
              emitExpr(c.body, mb);
              const gotoEnd = mb.length();
              mb.emit1s(JvmOp.GOTO, 0);
              catchEndLabels.push(gotoEnd);
              const afterGoto = gotoEnd + 3;
              patchShort(mb, ifeq + 1, afterGoto - ifeq);
              mb.addBranchTarget(afterGoto, frameState(env, nextLocal, [57]));
              continue;
            }
            if (p.name === 'Some') {
              mb.emit1b(JvmOp.ALOAD, PAYLOAD_SLOT);
              mb.emit1s(JvmOp.INSTANCEOF, cf.classRef(K_SOME));
              const ifeq = mb.length();
              mb.emit1s(JvmOp.IFEQ, 0);
              mb.addBranchTarget(mb.length(), frameState(env, nextLocal, [57]));
              mb.emit1b(JvmOp.ALOAD, PAYLOAD_SLOT);
              mb.emit1s(JvmOp.CHECKCAST, cf.classRef(K_SOME));
              mb.emit1s(JvmOp.GETFIELD, cf.fieldref(K_SOME, 'value', 'Ljava/lang/Object;'));
              const varName = p.fields?.[0] && p.fields[0].pattern?.kind === 'VarPattern' ? (p.fields[0].pattern as { name: string }).name : null;
              if (varName) {
                const slot = nextLocal++;
                env.set(varName, slot);
                mb.emit1b(JvmOp.ASTORE, slot);
              }
              emitExpr(c.body, mb);
              if (varName) env.delete(varName);
              const gotoEnd = mb.length();
              mb.emit1s(JvmOp.GOTO, 0);
              catchEndLabels.push(gotoEnd);
              const afterGoto = gotoEnd + 3;
              patchShort(mb, ifeq + 1, afterGoto - ifeq);
              mb.addBranchTarget(afterGoto, frameState(env, nextLocal, [57]));
              continue;
            }
          }
          if (c.pattern.kind === 'LiteralPattern') {
            mb.emit1b(JvmOp.ALOAD, PAYLOAD_SLOT);
            emitExpr({ kind: 'LiteralExpr', literal: c.pattern.literal, value: c.pattern.value, span: undefined } as import('../ast/nodes.js').LiteralExpr, mb);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'equals', '(Ljava/lang/Object;Ljava/lang/Object;)Z'));
            mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref('java/lang/Boolean', 'booleanValue', '()Z'));
            const ifeq = mb.length();
            mb.emit1s(JvmOp.IFEQ, 0);
            mb.addBranchTarget(mb.length(), frameState(env, nextLocal, [57]));
            emitExpr(c.body, mb);
            const gotoEnd = mb.length();
            mb.emit1s(JvmOp.GOTO, 0);
            catchEndLabels.push(gotoEnd);
            const afterGoto = gotoEnd + 3;
            patchShort(mb, ifeq + 1, afterGoto - ifeq);
            mb.addBranchTarget(afterGoto, frameState(env, nextLocal, [57]));
            continue;
          }
        }
        const rethrowPos = mb.length();
        mb.addBranchTarget(rethrowPos, frameState(env, nextLocal, [57]));
        mb.emit1b(JvmOp.ALOAD, EXN_SLOT);
        mb.emit1(JvmOp.ATHROW);
        const afterCatch = mb.length();
        mb.addBranchTarget(afterCatch, frameState(env, nextLocal));
        for (const gotoPos of catchEndLabels) patchShort(mb, gotoPos + 1, afterCatch - gotoPos);
        patchShort(mb, gotoAfter + 1, afterCatch - gotoAfter);
        mb.addException(tryStart, tryEnd, handlerStart, cf.classRef(K_EXCEPTION));
        if (expr.catchVar != null) {
          if (prevCatchVar !== undefined) env.set(expr.catchVar, prevCatchVar);
          else env.delete(expr.catchVar);
        }
        break;
      }
      default:
        throw new Error(`JVM codegen: unsupported expr ${(expr as Expr).kind}`);
    }
  }

  function patchShort(mb: MethodBuilder, at: number, value: number): void {
    const code = mb.getCode();
    if (at >= 0 && at + 2 <= code.length) {
      code[at] = (value >> 8) & 0xff;
      code[at + 1] = value & 0xff;
    }
  }

  // Emit $lambdaN static methods and build inner classes for each lambda
  for (let i = 0; i < lambdas.length; i++) {
    const l = lambdas[i];
    const arity = l.params.length;
    const lambdaEnv = new Map<string, number>();
    let lambdaNext = 0;
    if (l.capturing) {
      lambdaEnv.set('__env', lambdaNext++);
    }
    for (const p of l.params) {
      lambdaEnv.set(p.name, lambdaNext++);
    }
    const prevEnv = env;
    const prevNext = nextLocal;
    const prevFree = freeVarToIndex;
    const prevLocalFuns = localFunNamesInEnv;
    const prevVarNames = new Set(varNames);
    varNames.clear();
    if (l.freeVarVars) for (const v of l.freeVarVars) varNames.add(v);
    env.clear();
    // Never use slot 0 for temporaries: it holds __env (capturing) or first param (arity >= 1).
    nextLocal = Math.max(lambdaNext, 1);
    lambdaEnv.forEach((v, k) => env.set(k, v));
    if (l.capturing) {
      const otherFreeVars = l.localFunNames?.size
        ? l.freeVars.filter((x) => !l.localFunNames!.has(x))
        : l.freeVars;
      freeVarToIndex = new Map();
      for (let j = 0; j < otherFreeVars.length; j++) freeVarToIndex.set(otherFreeVars[j], l.localFunNames?.size ? 1 + j : j);
      localFunNamesInEnv = l.localFunNames?.size ? l.localFunNames : undefined;
    } else {
      freeVarToIndex = undefined;
      localFunNamesInEnv = undefined;
    }
    const desc = l.capturing
      ? `([Ljava/lang/Object;${'Ljava/lang/Object;'.repeat(arity)})Ljava/lang/Object;`
      : descriptor(arity);
    const mb = cf.addMethod('$lambda' + i, desc, ACC_PUBLIC | ACC_STATIC);
    emitExpr(l.body, mb);
    mb.emit1(JvmOp.ARETURN);
    mb.setMaxs(32, nextLocal);
    cf.flushLastMethod();
    env.clear();
    prevEnv.forEach((v, k) => env.set(k, v));
    nextLocal = prevNext;
    freeVarToIndex = prevFree;
    localFunNamesInEnv = prevLocalFuns;
    varNames.clear();
    for (const v of prevVarNames) varNames.add(v);
    innerClasses.set(className + '$Lambda' + i, buildLambdaClass(className, i, arity, l.capturing));
  }

  for (const node of program.body) {
    if (!node || node.kind !== 'FunDecl') continue;
    const fun = node as FunDecl;
    const arity = fun.params.length;
    const mb = cf.addMethod(jvmMangleName(fun.name), descriptor(arity), ACC_PUBLIC | ACC_STATIC);
    const paramEnv = new Map<string, number>();
    fun.params.forEach((p, i) => paramEnv.set(p.name, i));
    for (const [k, v] of paramEnv) env.set(k, v);
    nextLocal = arity;
    emitExpr(fun.body, mb);
    mb.setMaxs(32, Math.max(Math.max(arity, nextLocal) + 8, 70));
    mb.emit1(JvmOp.ARETURN);
    cf.flushLastMethod();
    for (const k of paramEnv.keys()) env.delete(k);
  }

  nextLocal = 0;
  env.clear();
  const initMb = cf.addMethod('$init', '()V', ACC_PUBLIC | ACC_STATIC);
  initMb.emit1s(JvmOp.GETSTATIC, cf.fieldref(className, '$initialized', 'Z'));
  const initGuardPos = initMb.length();
  initMb.emit1s(JvmOp.IFNE, 0);
  initMb.addBranchTarget(initMb.length(), frameState(env, nextLocal));
  initMb.emit1(JvmOp.ICONST_1);
  initMb.emit1s(JvmOp.PUTSTATIC, cf.fieldref(className, '$initialized', 'Z'));
  for (const node of program.body) {
    if (!node) continue;
    if (node.kind === 'ValDecl' || node.kind === 'ValStmt') {
      const v = node as ValDecl | { name: string; value: Expr };
      emitExpr(v.value, initMb);
      initMb.emit1s(JvmOp.PUTSTATIC, cf.fieldref(className, jvmMangleName(v.name), 'Ljava/lang/Object;'));
    } else if (node.kind === 'VarDecl' || node.kind === 'VarStmt') {
      const v = node as VarDecl | { name: string; value: Expr };
      initMb.emit1s(JvmOp.NEW, cf.classRef(KRECORD));
      initMb.emit1(JvmOp.DUP);
      initMb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(KRECORD, '<init>', '()V'));
      initMb.emit1(JvmOp.DUP);
      initMb.emit1s(JvmOp.LDC_W, cf.string('0'));
      emitExpr(v.value, initMb);
      initMb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'set', '(Ljava/lang/String;Ljava/lang/Object;)V'));
      initMb.emit1s(JvmOp.PUTSTATIC, cf.fieldref(className, jvmMangleName(v.name), 'Ljava/lang/Object;'));
    } else if (node.kind === 'ExprStmt') {
      emitExpr(node.expr, initMb);
      initMb.emit1(JvmOp.POP);
    }
  }
  const initEndPos = initMb.length();
  initMb.addBranchTarget(initEndPos, frameState(env, nextLocal));
  initMb.emit1(JvmOp.RETURN);
  patchShort(initMb, initGuardPos + 1, initEndPos - initGuardPos);
  initMb.setMaxs(32, 70);
  cf.flushLastMethod();

  const mainMb = cf.addMethod('main', '([Ljava/lang/String;)V', ACC_PUBLIC | ACC_STATIC);
  mainMb.emit1s(JvmOp.ALOAD, 0);
  mainMb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'setMainArgs', '([Ljava/lang/String;)V'));
  mainMb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(className, '$init', '()V'));
  mainMb.emit1(JvmOp.RETURN);
  mainMb.setMaxs(2, 1);
  cf.flushLastMethod();

  return {
    className,
    classBytes: cf.toBytes(),
    innerClasses,
  };
}

