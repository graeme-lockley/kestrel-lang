/**
 * JVM codegen: typed AST → .class file(s).
 * Uses same Program + getInferredType pipeline as the main compiler.
 */
import type { Program, Expr, TopLevelStmt, TopLevelDecl, TuplePattern } from '../ast/nodes.js';
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
const K_TASK = 'kestrel/runtime/KTask';

/** Parser `char` token value is the decoded scalar (no quotes); astral scalars may span two UTF-16 units in JS. */
function charLiteralCodePoint(value: string): number {
  return value.codePointAt(0) ?? 0;
}

/** Direct self tail-call lowering (GOTO method head). */
interface JvmSelfTailTarget {
  name: string;
  arity: number;
  loopHead: number;
  argBase?: number;
}
interface JvmMutualTailTarget {
  memberStateByName: Map<string, number>;
  arity: number;
  loopHead: number;
  stateLocal: number;
  argBase: number;
}
type JvmEmitTailContext = { self: JvmSelfTailTarget; mutual?: JvmMutualTailTarget; inTail: boolean };

function subJvmTail(parent: JvmEmitTailContext | undefined, childIsTail: boolean): JvmEmitTailContext | undefined {
  if (parent?.self == null) return undefined;
  return { self: parent.self, mutual: parent.mutual, inTail: childIsTail && parent.inTail };
}
const K_OK = 'kestrel/runtime/KOk';
const K_ADT = 'kestrel/runtime/KAdt';
const K_FUNCTION = 'kestrel/runtime/KFunction';
const K_FUNCTION_REF = 'kestrel/runtime/KFunctionRef';
const K_EXCEPTION = 'kestrel/runtime/KException';

function jvmAsRecord(t: InternalType | undefined): (InternalType & { kind: 'record' }) | null {
  if (t == null) return null;
  if (t.kind === 'record') return t as InternalType & { kind: 'record' };
  if (t.kind === 'union') {
    return jvmAsRecord(t.left) ?? jvmAsRecord(t.right);
  }
  return null;
}

function jvmPrimDisc(name: string): number {
  switch (name) {
    case 'Int':
      return 0;
    case 'Bool':
      return 1;
    case 'Unit':
      return 2;
    case 'Char':
    case 'Rune':
      return 3;
    case 'String':
      return 4;
    case 'Float':
      return 5;
    default:
      return -1;
  }
}

/** Built-in constructor tag info for JVM `is` (mirrors vm codegen ADT indices). */
function jvmBuiltinCtorInfo(name: string, arity: number): { arity: number } | null {
  switch (name) {
    case 'None':
    case 'Nil':
      return arity === 0 ? { arity: 0 } : null;
    case 'Some':
    case 'Ok':
    case 'Err':
      return arity === 1 ? { arity: 1 } : null;
    case 'Cons':
      return arity === 2 ? { arity: 2 } : null;
    default:
      return null;
  }
}

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

/**
 * True if an if-arm ends by falling through with one value on the JVM stack (needs astore / goto glue).
 * False for arms that always transfer out via break/continue/never without pushing a value.
 */
function thenArmPushesValue(thenExpr: Expr): boolean {
  if (thenExpr.kind === 'NeverExpr') return false;
  if (thenExpr.kind === 'BlockExpr') {
    const b = thenExpr as BlockExpr;
    if (b.stmts.length === 0) return thenArmPushesValue(b.result);
    const last = b.stmts[b.stmts.length - 1]!;
    if (last.kind === 'BreakStmt' || last.kind === 'ContinueStmt') return false;
  }
  return true;
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
      case 'IsExpr':
        walk(e.expr);
        return;
      case 'WhileExpr':
        walk(e.cond);
        walk(e.body);
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
        return;
      case 'ThrowExpr':
        walk(e.value);
        return;
      case 'AwaitExpr':
        walk(e.value);
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
  async: boolean;
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
  function addLambda(body: Expr, async: boolean, params: { name: string }[], freeVars: string[], localFunNames?: Set<string>, freeVarVars?: Set<string>): number {
    const id = lambdas.length;
    const capturing = freeVars.length > 0 || (localFunNames?.size ?? 0) > 0;
    lambdas.push({ body, async, params, freeVars, capturing, localFunNames, freeVarVars });
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
          // Pass localFunNames for mutual recursion (>1 funs) OR self-recursion (fun references itself)
          const isSelfRecursive = fv.includes(stmt.name);
          const useLFN = (localFunNames.size > 1 || isSelfRecursive) ? localFunNames : undefined;
          const id = addLambda(stmt.body, stmt.async ?? false, stmt.params.map((p) => ({ name: p.name })), fv, useLFN, fvVars.size > 0 ? fvVars : undefined);
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
        const id = addLambda(e.body, e.async, e.params.map((p) => ({ name: p.name })), fv, undefined, fvVars.size > 0 ? fvVars : undefined);
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
      case 'IsExpr':
        walk(e.expr);
        return;
      case 'WhileExpr':
        walk(e.cond);
        walk(e.body);
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
  /** Namespace -> (function name -> arity) for namespace function value access. */
  namespaceFunArities?: Map<string, Map<string, number>>;
  /** Namespace -> set of async function names for direct call descriptors. */
  namespaceAsyncFunNames?: Map<string, Set<string>>;
  /** Namespace -> (constructor name -> full inner class name) for namespace ADT constructor access. */
  namespaceAdtConstructors?: Map<string, Map<string, string>>;
  /** Namespace -> set of var field names (for KRecord-based read/write). */
  namespaceVarFields?: Map<string, Set<string>>;
  /** Local import name -> inner class name for imported nullary ADT constructors and exceptions. */
  importedAdtClasses?: Map<string, string>;
  /** Local name -> target class for named imports (direct calls: invokestatic targetClass.name). */
  importedNameToClass?: Map<string, string>;
  /** Local name -> target class for imported val/var (IdentExpr: getstatic targetClass.name). */
  importedValVarToClass?: Map<string, string>;
  /** Local import names that refer specifically to exported vars. */
  importedVarNames?: Set<string>;
  /** Local name -> arity for imported function declarations (IdentExpr: build KFunctionRef). */
  importedFunArities?: Map<string, number>;
  /** Local imported names that refer to async functions. */
  importedAsyncFunNames?: Set<string>;
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

function descriptorWithReturn(arity: number, returnDescriptor: string): string {
  let params = '';
  for (let i = 0; i < arity; i++) params += 'Ljava/lang/Object;';
  return `(${params})${returnDescriptor}`;
}

/** Build descriptor for (Object,Object,...) -> Object. */
function descriptor(arity: number): string {
  return descriptorWithReturn(arity, 'Ljava/lang/Object;');
}

function taskDescriptor(arity: number): string {
  return descriptorWithReturn(arity, 'Lkestrel/runtime/KTask;');
}

function asyncPayloadMethodName(name: string): string {
  return `$async$${jvmMangleName(name)}`;
}

function asyncLambdaPayloadMethodName(lambdaId: number): string {
  return `$async$lambda${lambdaId}`;
}

/** Primitive type name from InternalType. */
function primName(t: InternalType | undefined): string | null {
  if (!t || t.kind !== 'prim') return null;
  return t.name;
}

/**
 * Build inner class bytes for a user-defined ADT constructor.
 * Nullary: generates a singleton INSTANCE field and private constructor.
 * Parameterized (arity>0): generates public fields "0","1",... and a constructor + payload().
 * All classes extend KAdt and implement tag().
 */
function buildAdtClass(adtClassName: string, arity: number, tag: number): Uint8Array {
  const innerCf = new ClassFileBuilder(adtClassName, K_ADT, ACC_PUBLIC | ACC_FINAL);

  if (arity === 0) {
    // public static final CtorClass INSTANCE;
    innerCf.addField('INSTANCE', 'L' + adtClassName + ';', ACC_PUBLIC | ACC_STATIC | ACC_FINAL);

    // <clinit>: INSTANCE = new CtorClass();
    const clinit = innerCf.addMethod('<clinit>', '()V', ACC_STATIC);
    clinit.emit1s(JvmOp.NEW, innerCf.classRef(adtClassName));
    clinit.emit1(JvmOp.DUP);
    clinit.emit1s(JvmOp.INVOKESPECIAL, innerCf.methodref(adtClassName, '<init>', '()V'));
    clinit.emit1s(JvmOp.PUTSTATIC, innerCf.fieldref(adtClassName, 'INSTANCE', 'L' + adtClassName + ';'));
    clinit.emit1(JvmOp.RETURN);
    clinit.setMaxs(2, 0);
    innerCf.flushLastMethod();

    // private <init>()
    const ctor = innerCf.addMethod('<init>', '()V', ACC_PUBLIC);
    ctor.emit1b(JvmOp.ALOAD, 0);
    ctor.emit1s(JvmOp.INVOKESPECIAL, innerCf.methodref(K_ADT, '<init>', '()V'));
    ctor.emit1(JvmOp.RETURN);
    ctor.setMaxs(1, 1);
    innerCf.flushLastMethod();
  } else {
    // public Object __field_0; ... public Object __field_{arity-1};
    for (let i = 0; i < arity; i++) {
      innerCf.addField(`__field_${i}`, 'Ljava/lang/Object;', ACC_PUBLIC);
    }

    // public <init>(Object f0, ..., Object f{arity-1})
    const ctorDesc = '(' + 'Ljava/lang/Object;'.repeat(arity) + ')V';
    const ctor = innerCf.addMethod('<init>', ctorDesc, ACC_PUBLIC);
    ctor.emit1b(JvmOp.ALOAD, 0);
    ctor.emit1s(JvmOp.INVOKESPECIAL, innerCf.methodref(K_ADT, '<init>', '()V'));
    for (let i = 0; i < arity; i++) {
      ctor.emit1b(JvmOp.ALOAD, 0);
      ctor.emit1b(JvmOp.ALOAD, i + 1);
      ctor.emit1s(JvmOp.PUTFIELD, innerCf.fieldref(adtClassName, `__field_${i}`, 'Ljava/lang/Object;'));
    }
    ctor.emit1(JvmOp.RETURN);
    ctor.setMaxs(2, arity + 1);
    innerCf.flushLastMethod();

    // public Object[] payload()
    const payloadMb = innerCf.addMethod('payload', '()[Ljava/lang/Object;', ACC_PUBLIC);
    payloadMb.emit1b(JvmOp.BIPUSH, arity);
    payloadMb.emit1s(JvmOp.ANEWARRAY, innerCf.classRef('java/lang/Object'));
    for (let i = 0; i < arity; i++) {
      payloadMb.emit1(JvmOp.DUP);
      payloadMb.emit1b(JvmOp.BIPUSH, i);
      payloadMb.emit1b(JvmOp.ALOAD, 0);
      payloadMb.emit1s(JvmOp.GETFIELD, innerCf.fieldref(adtClassName, `__field_${i}`, 'Ljava/lang/Object;'));
      payloadMb.emit1(JvmOp.AASTORE);
    }
    payloadMb.emit1(JvmOp.ARETURN);
    payloadMb.setMaxs(4, 1);
    innerCf.flushLastMethod();
  }

  // public int tag()
  const tagMb = innerCf.addMethod('tag', '()I', ACC_PUBLIC);
  const iconst = [JvmOp.ICONST_0, JvmOp.ICONST_1, JvmOp.ICONST_2, JvmOp.ICONST_3, JvmOp.ICONST_4, JvmOp.ICONST_5];
  if (tag >= 0 && tag <= 5) {
    tagMb.emit1(iconst[tag]!);
  } else {
    tagMb.emit1b(JvmOp.BIPUSH, tag);
  }
  tagMb.emit1(JvmOp.IRETURN);
  tagMb.setMaxs(1, 1);
  innerCf.flushLastMethod();

  return innerCf.toBytes();
}

export function jvmCodegen(program: Program, options: JvmCodegenOptions = {}): JvmCodegenResult {
  const sourceFile = options.sourceFile ?? '<source>';
  const className = options.className ?? classNameFromPath(sourceFile);
  const cf = new ClassFileBuilder(className, 'java/lang/Object');
  const innerClasses = new Map<string, Uint8Array>();
  interface JvmMutualGroupInfo {
    helperMethod: string;
    arity: number;
    memberNames: string[];
    memberStateByName: Map<string, number>;
  }

  const adtClassByConstructor = new Map<string, string>();
  const adtConstructorArity = new Map<string, number>();
  for (const node of program.body) {
    if (!node || node.kind !== 'TypeDecl') continue;
    const t = node as TypeDecl;
    if (t.body?.kind !== 'ADTBody') continue;
    const base = className + '$' + t.name;
    for (let ci = 0; ci < t.body.constructors.length; ci++) {
      const c = t.body.constructors[ci]!;
      const adtClass = base + '$' + c.name;
      adtClassByConstructor.set(c.name, adtClass);
      const arity = c.params?.length ?? 0;
      adtConstructorArity.set(c.name, arity);
      innerClasses.set(adtClass, buildAdtClass(adtClass, arity, ci));
    }
  }

    // Also generate inner classes + register exception declarations as nullary ADT constructors
    for (const node of program.body) {
      if (!node || node.kind !== 'ExceptionDecl') continue;
      const excClass = className + '$' + (node as { name: string }).name;
      adtClassByConstructor.set((node as { name: string }).name, excClass);
      adtConstructorArity.set((node as { name: string }).name, 0);
      innerClasses.set(excClass, buildAdtClass(excClass, 0, 0));
    }

    // Seed adtClassByConstructor from imported ADT/exception names (for catch patterns + IdentExpr)
    if (options.importedAdtClasses) {
      for (const [localName, innerClass] of options.importedAdtClasses) {
        adtClassByConstructor.set(localName, innerClass);
        adtConstructorArity.set(localName, 0);
      }
    }
  const funNames = new Set<string>();
  const funArities = new Map<string, number>();
  const asyncFunNames = new Set<string>();
  const topLevelFunDecls: FunDecl[] = [];
  const globalSlots = new Map<string, number>();
  const globalNames = new Set<string>();
  const globalVarNames = new Set<string>();
  let nextGlobalSlot = 0;
  for (const node of program.body) {
    if (!node) continue;
    if (node.kind === 'FunDecl') {
      const fun = node as FunDecl;
      funNames.add(fun.name);
      funArities.set(fun.name, fun.params.length);
      if (fun.async) asyncFunNames.add(fun.name);
      topLevelFunDecls.push(fun);
    }
    if (node.kind === 'ValDecl' || node.kind === 'VarDecl' || node.kind === 'ValStmt' || node.kind === 'VarStmt') {
      const name = node.kind === 'ValStmt' || node.kind === 'VarStmt' ? (node as { name: string }).name : (node as ValDecl).name;
      globalSlots.set(name, nextGlobalSlot++);
      globalNames.add(name);
      if (node.kind === 'VarDecl' || node.kind === 'VarStmt') globalVarNames.add(name);
    }
  }

  const funByName = new Map<string, FunDecl>();
  for (const fun of topLevelFunDecls) funByName.set(fun.name, fun);

  function collectCalledTopLevelFns(fun: FunDecl): Set<string> {
    const out = new Set<string>();
    const visitUnknown = (v: unknown): void => {
      if (v == null) return;
      if (Array.isArray(v)) {
        for (const item of v) visitUnknown(item);
        return;
      }
      if (typeof v !== 'object') return;
      const obj = v as Record<string, unknown>;
      if (obj.kind === 'CallExpr') {
        const callee = obj.callee as { kind?: unknown; name?: unknown } | undefined;
        if (callee?.kind === 'IdentExpr' && typeof callee.name === 'string' && funByName.has(callee.name)) {
          out.add(callee.name);
        }
      }
      for (const child of Object.values(obj)) visitUnknown(child);
    };
    visitUnknown(fun.body);
    return out;
  }

  const edgeMap = new Map<string, Set<string>>();
  for (const fun of topLevelFunDecls) edgeMap.set(fun.name, collectCalledTopLevelFns(fun));

  const indexByName = new Map<string, number>();
  const lowByName = new Map<string, number>();
  const onStack = new Set<string>();
  const stack: string[] = [];
  let nextSccIndex = 0;
  const sccs: string[][] = [];
  const strongConnect = (name: string): void => {
    indexByName.set(name, nextSccIndex);
    lowByName.set(name, nextSccIndex);
    nextSccIndex++;
    stack.push(name);
    onStack.add(name);

    for (const to of edgeMap.get(name) ?? []) {
      if (!indexByName.has(to)) {
        strongConnect(to);
        lowByName.set(name, Math.min(lowByName.get(name)!, lowByName.get(to)!));
      } else if (onStack.has(to)) {
        lowByName.set(name, Math.min(lowByName.get(name)!, indexByName.get(to)!));
      }
    }

    if (lowByName.get(name) === indexByName.get(name)) {
      const scc: string[] = [];
      while (stack.length > 0) {
        const w = stack.pop()!;
        onStack.delete(w);
        scc.push(w);
        if (w === name) break;
      }
      sccs.push(scc);
    }
  };
  for (const fun of topLevelFunDecls) {
    if (!indexByName.has(fun.name)) strongConnect(fun.name);
  }

  const mutualGroupByFun = new Map<string, JvmMutualGroupInfo>();
  for (const scc of sccs) {
    if (scc.length < 2) continue;
    const arity = funByName.get(scc[0]!)?.params.length;
    if (arity == null) continue;
    if (!scc.every((name) => funByName.get(name)?.params.length === arity)) continue;
    if (scc.some((name) => funByName.get(name)?.async)) continue;
    const orderedMembers = topLevelFunDecls.map((f) => f.name).filter((n) => scc.includes(n));
    const memberStateByName = new Map<string, number>();
    for (let i = 0; i < orderedMembers.length; i++) memberStateByName.set(orderedMembers[i]!, i);
    const group: JvmMutualGroupInfo = {
      helperMethod: `$mtc$arity_${arity}_${orderedMembers[0]}`,
      arity,
      memberNames: orderedMembers,
      memberStateByName,
    };
    for (const name of orderedMembers) mutualGroupByFun.set(name, group);
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

  function emitFunctionRef(mb: MethodBuilder, ownerClass: string, methodName: string, arity: number): void {
    mb.emit1s(JvmOp.LDC_W, cf.classRef(ownerClass));
    mb.emit1s(JvmOp.LDC_W, cf.string(methodName));
    mb.emit1s(JvmOp.LDC_W, cf.constantInt(arity));
    mb.emit1s(
      JvmOp.INVOKESTATIC,
      cf.methodref(K_FUNCTION_REF, 'of', '(Ljava/lang/Class;Ljava/lang/String;I)L' + K_FUNCTION_REF + ';')
    );
  }

  function emitArgsObjectArray(mb: MethodBuilder, argSlots: number[]): void {
    mb.emit1s(JvmOp.LDC_W, cf.constantInt(argSlots.length));
    mb.emit1s(JvmOp.ANEWARRAY, cf.classRef('java/lang/Object'));
    for (let i = 0; i < argSlots.length; i++) {
      mb.emit1(JvmOp.DUP);
      mb.emit1s(JvmOp.LDC_W, cf.constantInt(i));
      mb.emit1b(JvmOp.ALOAD, argSlots[i]!);
      mb.emit1(JvmOp.AASTORE);
    }
  }

  function isImportedAsyncFunction(name: string): boolean {
    return options.importedAsyncFunNames?.has(name) ?? false;
  }

  function isNamespaceAsyncFunction(namespaceName: string, functionName: string): boolean {
    return options.namespaceAsyncFunNames?.get(namespaceName)?.has(functionName) ?? false;
  }

  function methodDescriptorForDirectCall(name: string, arity: number, namespaceName?: string): string {
    if (namespaceName != null) return isNamespaceAsyncFunction(namespaceName, name) ? taskDescriptor(arity) : descriptor(arity);
    return asyncFunNames.has(name) || isImportedAsyncFunction(name) ? taskDescriptor(arity) : descriptor(arity);
  }

  /** Nearest enclosing `while` for `break`/`continue` (JVM emitExpr closure). */
  const loopBreakStack: { breakJumps: number[]; loopHead: number }[] = [];

  function buildAsyncLambdaPayloadClass(outerClassName: string, lambdaId: number, arity: number, capturing: boolean): Uint8Array {
    const innerName = outerClassName + '$Lambda' + lambdaId + '$Payload';
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
    const payloadDesc = capturing
      ? `([Ljava/lang/Object;${'Ljava/lang/Object;'.repeat(arity)})Ljava/lang/Object;`
      : descriptor(arity);
    applyMb.emit1s(JvmOp.INVOKESTATIC, innerCf.methodref(outerClassName, asyncLambdaPayloadMethodName(lambdaId), payloadDesc));
    applyMb.emit1(JvmOp.ARETURN);
    applyMb.setMaxs(8, 3);
    innerCf.flushLastMethod();
    return innerCf.toBytes();
  }

  /** Build inner class for lambda (implements KFunction, apply either evaluates synchronously or submits async payload). */
  function buildLambdaClass(outerClassName: string, lambdaId: number, arity: number, capturing: boolean, async: boolean): Uint8Array {
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
    if (async) {
      const payloadClassName = innerName + '$Payload';
      applyMb.emit1s(JvmOp.NEW, innerCf.classRef(payloadClassName));
      applyMb.emit1(JvmOp.DUP);
      if (capturing) {
        applyMb.emit1b(JvmOp.ALOAD, 0);
        applyMb.emit1s(JvmOp.GETFIELD, innerCf.fieldref(innerName, 'env', '[Ljava/lang/Object;'));
        applyMb.emit1s(JvmOp.INVOKESPECIAL, innerCf.methodref(payloadClassName, '<init>', '([Ljava/lang/Object;)V'));
      } else {
        applyMb.emit1s(JvmOp.INVOKESPECIAL, innerCf.methodref(payloadClassName, '<init>', '()V'));
      }
      applyMb.emit1b(JvmOp.ALOAD, 1);
      applyMb.emit1s(
        JvmOp.INVOKESTATIC,
        innerCf.methodref(RUNTIME, 'submitAsync', '(Lkestrel/runtime/KFunction;[Ljava/lang/Object;)Lkestrel/runtime/KTask;')
      );
      applyMb.emit1(JvmOp.ARETURN);
      applyMb.setMaxs(8, 3);
      innerCf.flushLastMethod();
      return innerCf.toBytes();
    }
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

  function emitIntConst(mb: MethodBuilder, n: number): void {
    if (n >= -1 && n <= 5) {
      const ops = [JvmOp.ICONST_M1, JvmOp.ICONST_0, JvmOp.ICONST_1, JvmOp.ICONST_2, JvmOp.ICONST_3, JvmOp.ICONST_4, JvmOp.ICONST_5];
      mb.emit1(ops[n + 1]!);
      return;
    }
    if (n >= -128 && n <= 127) {
      mb.emit1b(JvmOp.BIPUSH, n);
      return;
    }
    if (n >= -32768 && n <= 32767) {
      mb.emit1s(JvmOp.SIPUSH, n);
      return;
    }
    mb.emit1s(JvmOp.LDC_W, cf.constantInt(n));
  }

  function emitLongObjectConst(mb: MethodBuilder, n: number): void {
    mb.emit1s(JvmOp.LDC2_W, cf.constantLong(BigInt(n)));
    mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(LONG, 'valueOf', '(J)Ljava/lang/Long;'));
  }

  function emitExpr(expr: Expr, mb: MethodBuilder, tailCtx?: JvmEmitTailContext, stackDepth: number = 0): boolean {
    const tcN = subJvmTail(tailCtx, false);
    const tcT = subJvmTail(tailCtx, true);
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
            const codePoint = charLiteralCodePoint(expr.value);
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
        return false;
      }
      case 'IdentExpr': {
        if (localFunNamesInEnv?.has(expr.name)) {
          if (freeVarToIndex) {
            // Capturing lambda: slot 0 is Object[] env, and env[0] holds the local-fun record.
            mb.emit1b(JvmOp.ALOAD, 0);
            mb.emit1s(JvmOp.CHECKCAST, cf.classRef('[Ljava/lang/Object;'));
            mb.emit1b(JvmOp.BIPUSH, 0);
            mb.emit1(JvmOp.AALOAD);
          } else {
            // Non-capturing lambda/fun-stmt path: slot 0 is already the record.
            mb.emit1b(JvmOp.ALOAD, 0);
          }
          mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
          mb.emit1s(JvmOp.LDC_W, cf.string(expr.name));
          mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'get', '(Ljava/lang/String;)Ljava/lang/Object;'));
          return false;
        }
        if (freeVarToIndex?.has(expr.name)) {
          mb.emit1b(JvmOp.ALOAD, 0);
          mb.emit1s(JvmOp.CHECKCAST, cf.classRef('[Ljava/lang/Object;'));
          mb.emit1s(JvmOp.LDC_W, cf.constantInt(freeVarToIndex.get(expr.name)!));
          mb.emit1(JvmOp.AALOAD);
          if (varNames.has(expr.name)) {
            mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
            mb.emit1s(JvmOp.LDC_W, cf.string('0'));
            mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'get', '(Ljava/lang/String;)Ljava/lang/Object;'));
          }
          return false;
        }
        const slot = env.get(expr.name);
        if (slot !== undefined) {
          mb.emit1b(JvmOp.ALOAD, slot);
          if (varNames.has(expr.name)) {
            mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
            mb.emit1s(JvmOp.LDC_W, cf.string('0'));
            mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'get', '(Ljava/lang/String;)Ljava/lang/Object;'));
          }
          return false;
        }
        if (globalNames.has(expr.name)) {
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(className, jvmMangleName(expr.name), 'Ljava/lang/Object;'));
          if (globalVarNames.has(expr.name)) {
            mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
            mb.emit1s(JvmOp.LDC_W, cf.string('0'));
            mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'get', '(Ljava/lang/String;)Ljava/lang/Object;'));
          }
          return false;
        }
        if (funNames.has(expr.name)) {
          const arity = funArities.get(expr.name);
          if (arity === undefined) throw new Error(`JVM codegen: missing arity for function ${expr.name}`);
          emitFunctionRef(mb, className, jvmMangleName(expr.name), arity);
          return false;
        }
        const importedValVarClass = options.importedValVarToClass?.get(expr.name);
        if (importedValVarClass != null) {
          const originalName = options.importedNameToOriginal?.get(expr.name) ?? expr.name;
          mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(importedValVarClass, '$init', '()V'));
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(importedValVarClass, jvmMangleName(originalName), 'Ljava/lang/Object;'));
          if (options.importedVarNames?.has(expr.name)) {
            mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
            mb.emit1s(JvmOp.LDC_W, cf.string('0'));
            mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'get', '(Ljava/lang/String;)Ljava/lang/Object;'));
          }
          return false;
        }
        const importedFunClass = options.importedNameToClass?.get(expr.name);
        const importedFunArity = options.importedFunArities?.get(expr.name);
        if (importedFunClass != null && importedFunArity !== undefined) {
          const originalName = options.importedNameToOriginal?.get(expr.name) ?? expr.name;
          mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(importedFunClass, '$init', '()V'));
          emitFunctionRef(mb, importedFunClass, jvmMangleName(originalName), importedFunArity);
          return false;
        }
        if (expr.name === 'None') {
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(K_NONE, 'INSTANCE', 'Lkestrel/runtime/KNone;'));
          return false;
        }
        if (expr.name === 'Nil' || expr.name === '[]') {
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(K_NIL, 'INSTANCE', 'Lkestrel/runtime/KNil;'));
          return false;
        }
        // User-defined nullary ADT constructor (e.g. Red, Eof, CTrue)
        const nullaryAdtClass = adtClassByConstructor.get(expr.name);
        if (nullaryAdtClass != null && (adtConstructorArity.get(expr.name) ?? 0) === 0) {
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(nullaryAdtClass, 'INSTANCE', 'L' + nullaryAdtClass + ';'));
          return false;
        }
        throw new Error(`JVM codegen: unknown variable ${expr.name}`);
      }
      case 'BinaryExpr': {
        if (expr.op === '&' || expr.op === '|') {
          // Left/right are boxed Boolean (e.g. from ==); IFEQ expects int — unbox first.
          const unboxBool = (): void => {
            mb.emit1s(JvmOp.CHECKCAST, cf.classRef(BOOLEAN));
            mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(BOOLEAN, 'booleanValue', '()Z'));
          };
          if (expr.op === '&') {
            emitExpr(expr.left, mb, tcN, stackDepth);
            unboxBool();
            const ifeqStart = mb.length();
            mb.emit1s(JvmOp.IFEQ, 0);
            mb.addBranchTarget(mb.length(), frameState(env, nextLocal, undefined, stackDepth));
            emitExpr(expr.right, mb, tcN, stackDepth);
            const gotoEnd = mb.length();
            mb.emit1s(JvmOp.GOTO, 0);
            const pushFalse = mb.length();
            mb.addBranchTarget(pushFalse, frameState(env, nextLocal, undefined, stackDepth));
            mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(BOOLEAN, 'FALSE', 'Ljava/lang/Boolean;'));
            const afterAnd = mb.length();
            mb.addBranchTarget(afterAnd, frameState(env, nextLocal, undefined, stackDepth + 1));
            patchShort(mb, ifeqStart + 1, pushFalse - ifeqStart);
            patchShort(mb, gotoEnd + 1, afterAnd - gotoEnd);
          } else {
            emitExpr(expr.left, mb, tcN, stackDepth);
            unboxBool();
            const ifeqStart = mb.length();
            mb.emit1s(JvmOp.IFEQ, 0);
            mb.addBranchTarget(mb.length(), frameState(env, nextLocal, undefined, stackDepth));
            mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(BOOLEAN, 'TRUE', 'Ljava/lang/Boolean;'));
            const gotoSkip = mb.length();
            mb.emit1s(JvmOp.GOTO, 0);
            const rightStart = mb.length();
            mb.addBranchTarget(rightStart, frameState(env, nextLocal, undefined, stackDepth));
            emitExpr(expr.right, mb, tcN, stackDepth);
            const afterOr = mb.length();
            mb.addBranchTarget(afterOr, frameState(env, nextLocal, undefined, stackDepth + 1));
            patchShort(mb, ifeqStart + 1, rightStart - ifeqStart);
            patchShort(mb, gotoSkip + 1, afterOr - gotoSkip);
          }
          break;
        }
        const leftPrim = primName(getInferredType(expr.left));
        const rightPrim = primName(getInferredType(expr.right));
        const isInt = leftPrim === 'Int' && rightPrim === 'Int';
        const isChar =
          (leftPrim === 'Char' || leftPrim === 'Rune') && (rightPrim === 'Char' || rightPrim === 'Rune');
        const isFloat = leftPrim === 'Float' || rightPrim === 'Float';
        emitExpr(expr.left, mb, tcN, stackDepth);
        if (isInt) mb.emit1s(JvmOp.CHECKCAST, cf.classRef(LONG));
        else if (isFloat) mb.emit1s(JvmOp.CHECKCAST, cf.classRef(DOUBLE));
        else if (isChar) mb.emit1s(JvmOp.CHECKCAST, cf.classRef('java/lang/Integer'));
        emitExpr(expr.right, mb, tcN, stackDepth + 1);
        if (isInt) mb.emit1s(JvmOp.CHECKCAST, cf.classRef(LONG));
        else if (isFloat) mb.emit1s(JvmOp.CHECKCAST, cf.classRef(DOUBLE));
        else if (isChar) mb.emit1s(JvmOp.CHECKCAST, cf.classRef('java/lang/Integer'));
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
          mb.addBranchTarget(mb.length(), frameState(env, nextLocal, undefined, stackDepth));
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(BOOLEAN, 'TRUE', 'Ljava/lang/Boolean;'));
          const gotoEnd = mb.length();
          mb.emit1s(JvmOp.GOTO, 0);
          const pushFalse = mb.length();
          mb.addBranchTarget(pushFalse, frameState(env, nextLocal, undefined, stackDepth));
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(BOOLEAN, 'FALSE', 'Ljava/lang/Boolean;'));
          const afterNe = mb.length();
          mb.addBranchTarget(afterNe, frameState(env, nextLocal, undefined, stackDepth + 1));
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
        } else if (isChar) {
          const cmpOps = new Set(['<', '<=', '>', '>=']);
          if (cmpOps.has(expr.op)) {
            const charMethod =
              expr.op === '<'
                ? 'charLess'
                : expr.op === '<='
                  ? 'charLessEq'
                  : expr.op === '>'
                    ? 'charGreater'
                    : 'charGreaterEq';
            mb.emit1s(
              JvmOp.INVOKESTATIC,
              cf.methodref(KMATH, charMethod, '(Ljava/lang/Integer;Ljava/lang/Integer;)Ljava/lang/Boolean;')
            );
          } else {
            throw new Error(`JVM codegen: unsupported binary ${expr.op} on Char`);
          }
        } else if (isFloat) {
          const cmpOps = new Set(['<', '<=', '>', '>=']);
          if (cmpOps.has(expr.op)) {
            const op = jvmMangleName(expr.op) + 'Float';
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(KMATH, op, '(Ljava/lang/Double;Ljava/lang/Double;)Ljava/lang/Boolean;'));
          } else {
            const floatOp =
              expr.op === '+' ? 'addFloat' :
              expr.op === '-' ? 'subFloat' :
              expr.op === '*' ? 'mulFloat' :
              expr.op === '**' ? 'powFloat' :
              'divFloat';
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
        return false;
      }
      case 'IfExpr': {
        emitExpr(expr.cond, mb, tcN, stackDepth);
        mb.emit1s(JvmOp.CHECKCAST, cf.classRef(BOOLEAN));
        mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(BOOLEAN, 'booleanValue', '()Z'));
        const ifBranchState = frameState(env, nextLocal, undefined, stackDepth);
        const ifeqPos = mb.length();
        mb.emit1s(JvmOp.IFEQ, 0);
        mb.addBranchTarget(mb.length(), ifBranchState);

        if (tailCtx?.inTail === true) {
          const thenXfer = emitExpr(expr.then, mb, tcT, stackDepth);
          if (!thenXfer) mb.emit1(JvmOp.ARETURN);
          const elseStart = mb.length();
          mb.addBranchTarget(elseStart, ifBranchState);
          patchShort(mb, ifeqPos + 1, elseStart - ifeqPos);
          if (expr.else !== undefined) {
            const elseXfer = emitExpr(expr.else, mb, tcT, stackDepth);
            if (!elseXfer) mb.emit1(JvmOp.ARETURN);
          } else {
            mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
            mb.emit1(JvmOp.ARETURN);
          }
          return true;
        }

        const ifResultSlot = 53;
        const ifEndState = frameState(env, nextLocal, [ifResultSlot], stackDepth);
        emitExpr(expr.then, mb, tcN, stackDepth);
        let thenSkipToEndPos: number | undefined;
        if (thenArmPushesValue(expr.then)) {
          mb.emit1b(JvmOp.ASTORE, ifResultSlot);
          thenSkipToEndPos = mb.length();
          mb.emit1s(JvmOp.GOTO, 0);
        }
        const elseStart = mb.length();
        mb.addBranchTarget(elseStart, ifBranchState);
        if (expr.else !== undefined) {
          emitExpr(expr.else, mb, tcN, stackDepth);
        } else {
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
        }
        mb.emit1b(JvmOp.ASTORE, ifResultSlot);
        const ifEndPos = mb.length();
        mb.addBranchTarget(ifEndPos, ifEndState);
        patchShort(mb, ifeqPos + 1, elseStart - ifeqPos);
        if (thenSkipToEndPos !== undefined) {
          patchShort(mb, thenSkipToEndPos + 1, ifEndPos - thenSkipToEndPos);
        }
        mb.emit1b(JvmOp.ALOAD, ifResultSlot);
        return false;
      }
      case 'WhileExpr': {
        const loopState = frameState(env, nextLocal, undefined, stackDepth);
        const loopHead = mb.length();
        mb.addBranchTarget(loopHead, loopState);
        emitExpr(expr.cond, mb, tcN, stackDepth);
        mb.emit1s(JvmOp.CHECKCAST, cf.classRef(BOOLEAN));
        mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(BOOLEAN, 'booleanValue', '()Z'));
        const ifeqPos = mb.length();
        mb.emit1s(JvmOp.IFEQ, 0);
        mb.addBranchTarget(mb.length(), loopState);
        const layer = { breakJumps: [] as number[], loopHead };
        loopBreakStack.push(layer);
        emitExpr(expr.body, mb, tcN, stackDepth);
        loopBreakStack.pop();
        mb.emit1(JvmOp.POP);
        const gotoPos = mb.length();
        mb.emit1s(JvmOp.GOTO, 0);
        const exitPos = mb.length();
        mb.addBranchTarget(exitPos, loopState);
        patchShort(mb, ifeqPos + 1, exitPos - ifeqPos);
        patchShort(mb, gotoPos + 1, loopHead - gotoPos);
        for (const j of layer.breakJumps) {
          patchShort(mb, j + 1, exitPos - j);
        }
        mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
        return false;
      }
      case 'BlockExpr': {
        const outerEnv = new Map(env);
        const outerNextLocal = nextLocal;
        const blockEnv = new Map(env);
        let slot = nextLocal;
        const funStmts = expr.stmts.filter((s): s is FunStmt => s.kind === 'FunStmt');
          // Allocate a KRecord for mutual recursion (>1 funs) or any self-recursive single fun
          const anyNeedRecord = funStmts.length > 1 || (funStmts.length === 1 && (() => {
            const id = idByNode.get(funStmts[0]!);
            return id !== undefined && (lambdas[id]?.localFunNames?.size ?? 0) > 0;
          })());
          const recordSlot = anyNeedRecord ? (slot++, slot - 1) : -1;
        if (recordSlot >= 0) {
          mb.emit1s(JvmOp.NEW, cf.classRef(KRECORD));
          mb.emit1(JvmOp.DUP);
          mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(KRECORD, '<init>', '()V'));
          mb.emit1b(JvmOp.ASTORE, recordSlot);
        }
        for (const stmt of expr.stmts) {
          for (const [k, v] of blockEnv) env.set(k, v);
          if (stmt.kind === 'ValStmt') {
            emitExpr(stmt.value, mb, tcN, stackDepth);
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
            emitExpr(stmt.value, mb, tcN, stackDepth);
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
                  } else if (freeVarToIndex?.has(name)) {
                    // name is captured from outer lambda's env array (fun inside lambda)
                    mb.emit1b(JvmOp.ALOAD, env.get('__env')!);
                    mb.emit1s(JvmOp.CHECKCAST, cf.classRef('[Ljava/lang/Object;'));
                    mb.emit1s(JvmOp.LDC_W, cf.constantInt(freeVarToIndex.get(name)!));
                    mb.emit1(JvmOp.AALOAD);
                  } else if (globalNames.has(name)) {
                    mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(className, jvmMangleName(name), 'Ljava/lang/Object;'));
                  } else if (funNames.has(name)) {
                    const arity = funArities.get(name);
                    if (arity === undefined) throw new Error(`JVM codegen: missing arity for function ${name}`);
                    mb.emit1s(JvmOp.LDC_W, cf.classRef(className));
                    mb.emit1s(JvmOp.LDC_W, cf.string(jvmMangleName(name)));
                    mb.emit1s(JvmOp.LDC_W, cf.constantInt(arity));
                    mb.emit1s(
                      JvmOp.INVOKESTATIC,
                      cf.methodref(K_FUNCTION_REF, 'of', '(Ljava/lang/Class;Ljava/lang/String;I)L' + K_FUNCTION_REF + ';')
                    );
                  } else if (
                    options.importedNameToClass?.get(name) != null &&
                    options.importedFunArities?.get(name) !== undefined
                  ) {
                    const importedFunClass = options.importedNameToClass.get(name)!;
                    const importedFunArity = options.importedFunArities.get(name)!;
                    const originalName = options.importedNameToOriginal?.get(name) ?? name;
                    mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(importedFunClass, '$init', '()V'));
                    mb.emit1s(JvmOp.LDC_W, cf.classRef(importedFunClass));
                    mb.emit1s(JvmOp.LDC_W, cf.string(jvmMangleName(originalName)));
                    mb.emit1s(JvmOp.LDC_W, cf.constantInt(importedFunArity));
                    mb.emit1s(
                      JvmOp.INVOKESTATIC,
                      cf.methodref(K_FUNCTION_REF, 'of', '(Ljava/lang/Class;Ljava/lang/String;I)L' + K_FUNCTION_REF + ';')
                    );
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
              // Statement context: do not leak the original lambda value on the operand stack.
              mb.emit1(JvmOp.POP);
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
                emitExpr(stmt.value, mb, tcN, stackDepth);
                mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'set', '(Ljava/lang/String;Ljava/lang/Object;)V'));
                mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
                mb.emit1(JvmOp.POP);
              } else if (freeVarToIndex?.has(stmt.target.name) && varNames.has(stmt.target.name)) {
                mb.emit1b(JvmOp.ALOAD, 0);
                mb.emit1s(JvmOp.CHECKCAST, cf.classRef('[Ljava/lang/Object;'));
                mb.emit1s(JvmOp.LDC_W, cf.constantInt(freeVarToIndex.get(stmt.target.name)!));
                mb.emit1(JvmOp.AALOAD);
                mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
                mb.emit1s(JvmOp.LDC_W, cf.string('0'));
                emitExpr(stmt.value, mb, tcN, stackDepth);
                mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'set', '(Ljava/lang/String;Ljava/lang/Object;)V'));
                mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
                mb.emit1(JvmOp.POP);
              } else if (s !== undefined) {
                emitExpr(stmt.value, mb, tcN, stackDepth);
                mb.emit1b(JvmOp.ASTORE, s);
                mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
                mb.emit1(JvmOp.POP);
              } else if (globalVarNames.has(stmt.target.name)) {
                mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(className, jvmMangleName(stmt.target.name), 'Ljava/lang/Object;'));
                mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
                mb.emit1s(JvmOp.LDC_W, cf.string('0'));
                emitExpr(stmt.value, mb, tcN, stackDepth);
                mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'set', '(Ljava/lang/String;Ljava/lang/Object;)V'));
                mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
                mb.emit1(JvmOp.POP);
              } else if (options.importedValVarToClass?.get(stmt.target.name) != null) {
                const importedVarClass = options.importedValVarToClass.get(stmt.target.name)!;
                const originalName = options.importedNameToOriginal?.get(stmt.target.name) ?? stmt.target.name;
                mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(importedVarClass, '$init', '()V'));
                mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(importedVarClass, jvmMangleName(originalName), 'Ljava/lang/Object;'));
                mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
                mb.emit1s(JvmOp.LDC_W, cf.string('0'));
                emitExpr(stmt.value, mb, tcN, stackDepth);
                mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'set', '(Ljava/lang/String;Ljava/lang/Object;)V'));
                mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
                mb.emit1(JvmOp.POP);
              } else {
                emitExpr(stmt.value, mb, tcN, stackDepth);
                mb.emit1(JvmOp.POP);
                mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
                mb.emit1(JvmOp.POP);
              }
            } else if (stmt.target.kind === 'FieldExpr') {
              // Check if it's a namespace var assignment (e.g. Helper.counter := 42)
              if (
                stmt.target.object.kind === 'IdentExpr' &&
                options.namespaceClasses?.get(stmt.target.object.name) != null &&
                options.namespaceVarFields?.get(stmt.target.object.name)?.has(stmt.target.field)
              ) {
                const nsClass = options.namespaceClasses!.get(stmt.target.object.name)!;
                if (nsClass !== className) {
                  mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(nsClass, '$init', '()V'));
                }
                mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(nsClass, jvmMangleName(stmt.target.field), 'Ljava/lang/Object;'));
                mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
                mb.emit1s(JvmOp.LDC_W, cf.string('0'));
                emitExpr(stmt.value, mb, tcN, stackDepth);
                mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'set', '(Ljava/lang/String;Ljava/lang/Object;)V'));
                mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
                mb.emit1(JvmOp.POP);
              } else {
              emitExpr(stmt.target.object, mb, tcN, stackDepth);
              mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
              mb.emit1s(JvmOp.LDC_W, cf.string(stmt.target.field));
              emitExpr(stmt.value, mb, tcN, stackDepth + 2);
              mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'set', '(Ljava/lang/String;Ljava/lang/Object;)V'));
              mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
              mb.emit1(JvmOp.POP);
              }
            } else {
              emitExpr(stmt.value, mb, tcN, stackDepth);
              mb.emit1(JvmOp.POP);
              mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
              mb.emit1(JvmOp.POP);
            }
          } else if (stmt.kind === 'BreakStmt') {
            const top = loopBreakStack[loopBreakStack.length - 1];
            if (!top) throw new Error('JVM codegen: `break` outside loop');
            const gotoPos = mb.length();
            mb.emit1s(JvmOp.GOTO, 0);
            top.breakJumps.push(gotoPos);
          } else if (stmt.kind === 'ContinueStmt') {
            const top = loopBreakStack[loopBreakStack.length - 1];
            if (!top) throw new Error('JVM codegen: `continue` outside loop');
            const gotoPos = mb.length();
            mb.emit1s(JvmOp.GOTO, 0);
            patchShort(mb, gotoPos + 1, top.loopHead - gotoPos);
          } else if (stmt.kind === 'ExprStmt') {
            emitExpr(stmt.expr, mb, tcN, stackDepth);
            mb.emit1(JvmOp.POP);
          }
          // Nested emitExpr uses `nextLocal` for new locals; sync after each stmt so bindings do not
          // reuse slots still holding outer values (e.g. val _ inside if vs var current in printPrimes).
          nextLocal = slot;
        }
        for (const [k, v] of blockEnv) env.set(k, v);
        nextLocal = slot;
        const lastStmt = expr.stmts[expr.stmts.length - 1];
        const endsWithLoopExit =
          lastStmt !== undefined &&
          (lastStmt.kind === 'BreakStmt' || lastStmt.kind === 'ContinueStmt');
        const blockTail = endsWithLoopExit ? false : emitExpr(expr.result, mb, tcT, stackDepth);
        env.clear();
        for (const [k, v] of outerEnv) env.set(k, v);
        nextLocal = outerNextLocal;
        return blockTail;
      }
      case 'CallExpr': {
        if (expr.callee.kind === 'IdentExpr') {
          const name = expr.callee.name;
          if (name === 'Some' && expr.args.length === 1) {
            mb.emit1s(JvmOp.NEW, cf.classRef(K_SOME));
            mb.emit1(JvmOp.DUP);
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(K_SOME, '<init>', '(Ljava/lang/Object;)V'));
            return false;
          }
          if (name === 'Cons' && expr.args.length === 2) {
            const consHeadSlot = nextLocal++;
            const consTailSlot = nextLocal++;
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1b(JvmOp.ASTORE, consHeadSlot);
            emitExpr(expr.args[1], mb, tcN, stackDepth);
            mb.emit1b(JvmOp.ASTORE, consTailSlot);
            mb.emit1s(JvmOp.NEW, cf.classRef(K_CONS));
            mb.emit1(JvmOp.DUP);
            mb.emit1b(JvmOp.ALOAD, consHeadSlot);
            mb.emit1b(JvmOp.ALOAD, consTailSlot);
            mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(K_CONS, '<init>', '(Ljava/lang/Object;Lkestrel/runtime/KList;)V'));
            return false;
          }
          if (name === 'Err' && expr.args.length === 1) {
            mb.emit1s(JvmOp.NEW, cf.classRef(K_ERR));
            mb.emit1(JvmOp.DUP);
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(K_ERR, '<init>', '(Ljava/lang/Object;)V'));
            return false;
          }
          if (name === 'Ok' && expr.args.length === 1) {
            mb.emit1s(JvmOp.NEW, cf.classRef(K_OK));
            mb.emit1(JvmOp.DUP);
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(K_OK, '<init>', '(Ljava/lang/Object;)V'));
            return false;
          }
          // User-defined parameterized ADT constructor (e.g. Leaf(x), MkPoint(3,4), Num(42))
          {
            const adtCtorClass = adtClassByConstructor.get(name);
            if (adtCtorClass != null && (adtConstructorArity.get(name) ?? -1) === expr.args.length) {
              mb.emit1s(JvmOp.NEW, cf.classRef(adtCtorClass));
              mb.emit1(JvmOp.DUP);
              for (let ai = 0; ai < expr.args.length; ai++) emitExpr(expr.args[ai]!, mb, tcN, stackDepth + ai);
              const ctorDesc = '(' + 'Ljava/lang/Object;'.repeat(expr.args.length) + ')V';
              mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(adtCtorClass, '<init>', ctorDesc));
              return false;
            }
          }
          if (name === 'println' || name === 'print') {
            const runtimeMethod = name === 'println' ? 'println' : 'print';
            for (let ai = 0; ai < expr.args.length; ai++) emitExpr(expr.args[ai]!, mb, tcN, stackDepth + ai);
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
            return false;
          }
          if (name === 'exit' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'exit', '(Ljava/lang/Object;)V'));
            mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
            return false;
          }
          if (name === '__format_one' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'formatOne', '(Ljava/lang/Object;)Ljava/lang/String;'));
            return false;
          }
          if (name === '__print_one' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'printOne', '(Ljava/lang/Object;)V'));
            mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(KUNIT, 'INSTANCE', 'Lkestrel/runtime/KUnit;'));
            return false;
          }
          if (name === '__capture_trace' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'captureTrace', '(Ljava/lang/Object;)Ljava/lang/Object;'));
            return false;
          }
          if (name === 'concat' && expr.args.length === 2) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            emitExpr(expr.args[1], mb, tcN, stackDepth + 1);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'concat', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/String;'));
            return false;
          }
          if (name === '__string_length' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'stringLength', '(Ljava/lang/Object;)Ljava/lang/Long;'));
            return false;
          }
          if (name === '__string_slice' && expr.args.length === 3) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            emitExpr(expr.args[1], mb, tcN, stackDepth + 1);
            emitExpr(expr.args[2], mb, tcN, stackDepth + 2);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'stringSlice', '(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/String;'));
            return false;
          }
          if (name === '__string_index_of' && expr.args.length === 2) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            emitExpr(expr.args[1], mb, tcN, stackDepth + 1);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'stringIndexOf', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Long;'));
            return false;
          }
          if (name === '__string_equals' && expr.args.length === 2) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            emitExpr(expr.args[1], mb, tcN, stackDepth + 1);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'stringEquals', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Boolean;'));
            return false;
          }
          if (name === '__string_concat' && expr.args.length === 2) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            emitExpr(expr.args[1], mb, tcN, stackDepth + 1);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'concat', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/String;'));
            return false;
          }
          if (name === '__string_upper' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'stringUpper', '(Ljava/lang/Object;)Ljava/lang/String;'));
            return false;
          }
          if (name === '__string_lower' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'stringLower', '(Ljava/lang/Object;)Ljava/lang/String;'));
            return false;
          }
          if (name === '__string_trim' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'stringTrim', '(Ljava/lang/Object;)Ljava/lang/String;'));
            return false;
          }
          if (name === '__string_code_point_at' && expr.args.length === 2) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            emitExpr(expr.args[1], mb, tcN, stackDepth + 1);
            mb.emit1s(
              JvmOp.INVOKESTATIC,
              cf.methodref(RUNTIME, 'stringCodePointAt', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Long;')
            );
            return false;
          }
          if (name === '__char_code_point' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'charCodePoint', '(Ljava/lang/Object;)Ljava/lang/Long;'));
            return false;
          }
          if (name === '__string_char_at' && expr.args.length === 2) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            emitExpr(expr.args[1], mb, tcN, stackDepth + 1);
            mb.emit1s(
              JvmOp.INVOKESTATIC,
              cf.methodref(RUNTIME, 'stringCharAt', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Integer;')
            );
            return false;
          }
          if (name === '__char_to_string' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'charToString', '(Ljava/lang/Object;)Ljava/lang/String;'));
            return false;
          }
          if (name === '__int_to_float' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'intToFloat', '(Ljava/lang/Object;)Ljava/lang/Double;'));
            return false;
          }
          if (name === '__float_to_int' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'floatToInt', '(Ljava/lang/Object;)Ljava/lang/Long;'));
            return false;
          }
          if (name === '__float_floor' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'floatFloor', '(Ljava/lang/Object;)Ljava/lang/Long;'));
            return false;
          }
          if (name === '__float_ceil' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'floatCeil', '(Ljava/lang/Object;)Ljava/lang/Long;'));
            return false;
          }
          if (name === '__float_round' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'floatRound', '(Ljava/lang/Object;)Ljava/lang/Long;'));
            return false;
          }
          if (name === '__float_sqrt' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'floatSqrt', '(Ljava/lang/Object;)Ljava/lang/Double;'));
            return false;
          }
          if (name === '__float_is_nan' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'floatIsNan', '(Ljava/lang/Object;)Ljava/lang/Boolean;'));
            return false;
          }
          if (name === '__float_is_infinite' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'floatIsInfinite', '(Ljava/lang/Object;)Ljava/lang/Boolean;'));
            return false;
          }
          if (name === '__float_abs' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'floatAbs', '(Ljava/lang/Object;)Ljava/lang/Double;'));
            return false;
          }
          if (name === '__char_from_code' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'charFromCode', '(Ljava/lang/Object;)Ljava/lang/Integer;'));
            return false;
          }
          if (name === '__read_file_async' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'readFileAsync', '(Ljava/lang/Object;)Lkestrel/runtime/KTask;'));
            return false;
          }
          if (name === '__list_dir' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'listDirAsync', '(Ljava/lang/Object;)Lkestrel/runtime/KTask;'));
            return false;
          }
          if (name === '__write_text' && expr.args.length === 2) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            emitExpr(expr.args[1], mb, tcN, stackDepth + 1);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'writeTextAsync', '(Ljava/lang/Object;Ljava/lang/Object;)Lkestrel/runtime/KTask;'));
            return false;
          }
          if (name === '__now_ms' && expr.args.length === 0) {
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'nowMs', '()Ljava/lang/Long;'));
            return false;
          }
          if (name === '__get_os' && expr.args.length === 0) {
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'getOs', '()Ljava/lang/String;'));
            return false;
          }
          if (name === '__get_args' && expr.args.length === 0) {
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'getArgs', '()Lkestrel/runtime/KList;'));
            return false;
          }
          if (name === '__get_cwd' && expr.args.length === 0) {
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'getCwd', '()Ljava/lang/String;'));
            return false;
          }
          if (name === '__run_process' && expr.args.length === 2) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            emitExpr(expr.args[1], mb, tcN, stackDepth + 1);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'runProcessAsync', '(Ljava/lang/Object;Ljava/lang/Object;)Lkestrel/runtime/KTask;'));
            return false;
          }
          if (name === '__task_map' && expr.args.length === 2) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            emitExpr(expr.args[1], mb, tcN, stackDepth + 1);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(K_TASK, 'taskMap', '(Ljava/lang/Object;Ljava/lang/Object;)Lkestrel/runtime/KTask;'));
            return false;
          }
          if (name === '__task_all' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(K_TASK, 'taskAll', '(Ljava/lang/Object;)Lkestrel/runtime/KTask;'));
            return false;
          }
          if (name === '__task_race' && expr.args.length === 1) {
            emitExpr(expr.args[0], mb, tcN, stackDepth);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(K_TASK, 'taskRace', '(Ljava/lang/Object;)Lkestrel/runtime/KTask;'));
            return false;
          }
          const ns = options.namespaceClasses?.get(name);
          const importedClass = options.importedNameToClass?.get(name);
          if (funNames.has(name) || ns || importedClass) {
            let targetClass = className;
            let methodName = options.importedNameToOriginal?.get(name) ?? name;
            let isAsyncTarget = asyncFunNames.has(name);
            if (ns) targetClass = ns;
            else if (importedClass) {
              targetClass = importedClass;
              isAsyncTarget = isImportedAsyncFunction(name);
            }
            if (targetClass !== className) {
              mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(targetClass, '$init', '()V'));
            }
            const arity = expr.args.length;
            const st = tailCtx?.inTail === true ? tailCtx.self : undefined;
            // Self tail only: Java bytecode cannot GOTO another method, so mutual tail stays INVOKESTATIC.
            if (
              !isAsyncTarget &&
              st != null &&
              name === st.name &&
              targetClass === className &&
              expr.args.length === st.arity &&
              funArities.get(name) === st.arity
            ) {
              for (let ai = 0; ai < expr.args.length; ai++) emitExpr(expr.args[ai]!, mb, tcN, stackDepth + ai);
              const selfArgBase = st.argBase ?? 0;
              for (let i = st.arity - 1; i >= 0; i--) mb.emit1b(JvmOp.ASTORE, selfArgBase + i);
              const gpos = mb.length();
              mb.emit1s(JvmOp.GOTO, 0);
              patchShort(mb, gpos + 1, st.loopHead - gpos);
              return true;
            }
            const mt = tailCtx?.inTail === true ? tailCtx.mutual : undefined;
            const mtState = mt?.memberStateByName.get(name);
            if (
              !isAsyncTarget &&
              mt != null &&
              mtState !== undefined &&
              targetClass === className &&
              expr.args.length === mt.arity
            ) {
              for (let ai = 0; ai < expr.args.length; ai++) emitExpr(expr.args[ai]!, mb, tcN, stackDepth + ai);
              for (let i = mt.arity - 1; i >= 0; i--) mb.emit1b(JvmOp.ASTORE, mt.argBase + i);
              emitLongObjectConst(mb, mtState);
              mb.emit1b(JvmOp.ASTORE, mt.stateLocal);
              const gpos = mb.length();
              mb.emit1s(JvmOp.GOTO, 0);
              patchShort(mb, gpos + 1, mt.loopHead - gpos);
              return true;
            }
            for (let ai = 0; ai < expr.args.length; ai++) emitExpr(expr.args[ai]!, mb, tcN, stackDepth + ai);
            mb.emit1s(
              JvmOp.INVOKESTATIC,
              cf.methodref(targetClass, jvmMangleName(methodName), methodDescriptorForDirectCall(name, arity))
            );
            return false;
          }
        }
        // `import * as Str from "..."` → calls parse as CallExpr(FieldExpr(Ident Str, length), args).
        if (expr.callee.kind === 'FieldExpr') {
          const fe = expr.callee;
          if (fe.object.kind === 'IdentExpr') {
            const nsClass = options.namespaceClasses?.get(fe.object.name);
            if (nsClass != null) {
              // Check if the field is a namespace ADT constructor (parameterized, e.g. Lib.PubNum(42))
              const nsAdtCtors = options.namespaceAdtConstructors?.get(fe.object.name);
              const ctorClass = nsAdtCtors?.get(fe.field);
              if (ctorClass != null) {
                if (nsClass !== className) {
                  mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(nsClass, '$init', '()V'));
                }
                mb.emit1s(JvmOp.NEW, cf.classRef(ctorClass));
                mb.emit1(JvmOp.DUP);
                for (let ai = 0; ai < expr.args.length; ai++) emitExpr(expr.args[ai]!, mb, tcN, stackDepth + ai);
                const ctorDesc = '(' + 'Ljava/lang/Object;'.repeat(expr.args.length) + ')V';
                mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(ctorClass, '<init>', ctorDesc));
                return false;
              }
              if (nsClass !== className) {
                mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(nsClass, '$init', '()V'));
              }
              const arity = expr.args.length;
              for (let ai = 0; ai < arity; ai++) emitExpr(expr.args[ai]!, mb, tcN, stackDepth + ai);
              mb.emit1s(
                JvmOp.INVOKESTATIC,
                cf.methodref(nsClass, jvmMangleName(fe.field), methodDescriptorForDirectCall(fe.field, arity, fe.object.name))
              );
              return false;
            }
          }
        }
        emitExpr(expr.callee, mb, tcN, stackDepth);
        const n = expr.args.length;
        const CALLEE_TEMP = 60;
        const ARG_TEMP_BASE = 61;
        mb.emit1b(JvmOp.ASTORE, CALLEE_TEMP);
        for (let ai = 0; ai < expr.args.length; ai++) emitExpr(expr.args[ai]!, mb, tcN, stackDepth + 1 + ai);
        // Pop stack right-to-left so temp slots preserve original left-to-right arg order.
        for (let i = n - 1; i >= 0; i--) mb.emit1b(JvmOp.ASTORE, ARG_TEMP_BASE + i);
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
        return false;
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
            emitExpr(part.expr, mb, tcN);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'formatOne', '(Ljava/lang/Object;)Ljava/lang/String;'));
            mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(STRING_BUILDER, 'append', '(Ljava/lang/String;)Ljava/lang/StringBuilder;'));
          }
        }
        mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(STRING_BUILDER, 'toString', '()Ljava/lang/String;'));
        return false;
      }
      case 'MatchExpr': {
        emitExpr(expr.scrutinee, mb, tcN);
        const scrutSlot = 55;
        const matchResultSlot = 54;
        mb.emit1b(JvmOp.ASTORE, scrutSlot);
        mb.emit1(JvmOp.ACONST_NULL);
        mb.emit1b(JvmOp.ASTORE, matchResultSlot);
        const matchBaseState = frameState(env, nextLocal, [55, matchResultSlot], stackDepth);
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
            const xfer = emitExpr(c.body, mb, tcT, stackDepth);
            if (!xfer) {
              mb.emit1b(JvmOp.ASTORE, matchResultSlot);
              const gotoEnd = mb.length();
              mb.emit1s(JvmOp.GOTO, 0);
              endLabels.push(gotoEnd);
            }
            const afterGoto = mb.length();
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
              const xferNone = emitExpr(c.body, mb, tcT, stackDepth);
              if (!xferNone) {
                mb.emit1b(JvmOp.ASTORE, matchResultSlot);
                const gotoEnd = mb.length();
                mb.emit1s(JvmOp.GOTO, 0);
                endLabels.push(gotoEnd);
              }
              const afterGoto = mb.length();
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
              } else {
                // Some(_) / wildcard: discard payload so stack is empty before body (fixes VerifyError).
                mb.emit1(JvmOp.POP);
              }
              const xferSome = emitExpr(c.body, mb, tcT, stackDepth);
              if (varName) env.delete(varName);
              if (!xferSome) {
                mb.emit1b(JvmOp.ASTORE, matchResultSlot);
                const gotoEnd = mb.length();
                mb.emit1s(JvmOp.GOTO, 0);
                endLabels.push(gotoEnd);
              }
              const afterGoto = mb.length();
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
              const xferNil = emitExpr(c.body, mb, tcT, stackDepth);
              if (!xferNil) {
                mb.emit1b(JvmOp.ASTORE, matchResultSlot);
                const gotoEnd = mb.length();
                mb.emit1s(JvmOp.GOTO, 0);
                endLabels.push(gotoEnd);
              }
              const afterGoto = mb.length();
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
              const xferCons = emitExpr(c.body, mb, tcT, stackDepth);
              if (headPat?.kind === 'VarPattern') env.delete(headPat.name);
              if (tailPat?.kind === 'VarPattern') env.delete(tailPat.name);
              if (!xferCons) {
                mb.emit1b(JvmOp.ASTORE, matchResultSlot);
                const gotoEnd = mb.length();
                mb.emit1s(JvmOp.GOTO, 0);
                endLabels.push(gotoEnd);
              }
              const afterGoto = mb.length();
              patchShort(mb, ifeq + 1, afterGoto - ifeq);
              mb.addBranchTarget(afterGoto, matchBaseState);
              continue;
            }
            if (p.name === 'Ok' || p.name === 'Err') {
              const ctorClass = p.name === 'Ok' ? K_OK : K_ERR;
              mb.emit1b(JvmOp.ALOAD, scrutSlot);
              mb.emit1s(JvmOp.INSTANCEOF, cf.classRef(ctorClass));
              const ifeq = mb.length();
              mb.emit1s(JvmOp.IFEQ, 0);
              mb.addBranchTarget(ifeq + 3, matchBaseState);
              const vpat = p.fields?.[0]?.pattern;
              if (vpat?.kind === 'VarPattern') {
                mb.emit1b(JvmOp.ALOAD, scrutSlot);
                mb.emit1s(JvmOp.CHECKCAST, cf.classRef(ctorClass));
                mb.emit1s(JvmOp.GETFIELD, cf.fieldref(ctorClass, 'value', 'Ljava/lang/Object;'));
                const slot = nextLocal++;
                env.set(vpat.name, slot);
                mb.emit1b(JvmOp.ASTORE, slot);
              }
              const xferRes = emitExpr(c.body, mb, tcT, stackDepth);
              if (vpat?.kind === 'VarPattern') env.delete(vpat.name);
              if (!xferRes) {
                mb.emit1b(JvmOp.ASTORE, matchResultSlot);
                const gotoEnd = mb.length();
                mb.emit1s(JvmOp.GOTO, 0);
                endLabels.push(gotoEnd);
              }
              const afterGoto = mb.length();
              patchShort(mb, ifeq + 1, afterGoto - ifeq);
              mb.addBranchTarget(afterGoto, matchBaseState);
              continue;
            }
            if (p.name === 'True' || p.name === 'False') {
              mb.emit1b(JvmOp.ALOAD, scrutSlot);
              mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(BOOLEAN, p.name === 'True' ? 'TRUE' : 'FALSE', 'Ljava/lang/Boolean;'));
              mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'equals', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Boolean;'));
              mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(BOOLEAN, 'booleanValue', '()Z'));
              const ifeq = mb.length();
              mb.emit1s(JvmOp.IFEQ, 0);
              mb.addBranchTarget(ifeq + 3, matchBaseState);
              const xferBool = emitExpr(c.body, mb, tcT, stackDepth);
              if (!xferBool) {
                mb.emit1b(JvmOp.ASTORE, matchResultSlot);
                const gotoEnd = mb.length();
                mb.emit1s(JvmOp.GOTO, 0);
                endLabels.push(gotoEnd);
              }
              const afterGoto = mb.length();
              patchShort(mb, ifeq + 1, afterGoto - ifeq);
              mb.addBranchTarget(afterGoto, matchBaseState);
              continue;
            }

            // User-defined ADT constructor patterns (including opaque ADTs)
            const adtClass = adtClassByConstructor.get(p.name);
            if (adtClass != null) {
              mb.emit1b(JvmOp.ALOAD, scrutSlot);
              mb.emit1s(JvmOp.INSTANCEOF, cf.classRef(adtClass));
              const ifeq = mb.length();
              mb.emit1s(JvmOp.IFEQ, 0);
              mb.addBranchTarget(ifeq + 3, matchBaseState);

              const prevFieldBindings: Array<{ name: string; prev: number | undefined }> = [];
              if (p.fields?.length) {
                for (let fi = 0; fi < p.fields.length; fi++) {
                  const f = p.fields[fi]!;
                  const fieldName = f.name ?? String(fi);
                  mb.emit1b(JvmOp.ALOAD, scrutSlot);
                  mb.emit1s(JvmOp.CHECKCAST, cf.classRef(adtClass));
                  mb.emit1s(JvmOp.GETFIELD, cf.fieldref(adtClass, fieldName, 'Ljava/lang/Object;'));
                  if (f.pattern?.kind === 'VarPattern') {
                    const bindName = (f.pattern as { name: string }).name;
                    const slot = nextLocal++;
                    prevFieldBindings.push({ name: bindName, prev: env.get(bindName) });
                    env.set(bindName, slot);
                    mb.emit1b(JvmOp.ASTORE, slot);
                  } else {
                    // Wildcard / non-binding field pattern: discard extracted field value.
                    mb.emit1(JvmOp.POP);
                  }
                }
              }

              const xferAdt = emitExpr(c.body, mb, tcT, stackDepth);
              for (let bi = prevFieldBindings.length - 1; bi >= 0; bi--) {
                const b = prevFieldBindings[bi]!;
                if (b.prev !== undefined) env.set(b.name, b.prev);
                else env.delete(b.name);
              }
              if (!xferAdt) {
                mb.emit1b(JvmOp.ASTORE, matchResultSlot);
                const gotoEnd = mb.length();
                mb.emit1s(JvmOp.GOTO, 0);
                endLabels.push(gotoEnd);
              }
              const afterGoto = mb.length();
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
            const xferConsPat = emitExpr(c.body, mb, tcT, stackDepth);
            if (headPat.kind === 'VarPattern') env.delete(headPat.name);
            if (tailPat.kind === 'VarPattern') env.delete(tailPat.name);
            if (!xferConsPat) {
              mb.emit1b(JvmOp.ASTORE, matchResultSlot);
              const gotoEnd = mb.length();
              mb.emit1s(JvmOp.GOTO, 0);
              endLabels.push(gotoEnd);
            }
            const afterGoto = mb.length();
            patchShort(mb, ifeq + 1, afterGoto - ifeq);
            mb.addBranchTarget(afterGoto, matchBaseState);
            continue;
          }
          if (c.pattern.kind === 'LiteralPattern') {
            if (c.pattern.literal === 'float' && Number.isNaN(Number.parseFloat(c.pattern.value))) {
              mb.emit1b(JvmOp.ALOAD, scrutSlot);
              mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'floatIsNan', '(Ljava/lang/Object;)Ljava/lang/Boolean;'));
              mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(BOOLEAN, 'booleanValue', '()Z'));
              const ifeq = mb.length();
              mb.emit1s(JvmOp.IFEQ, 0);
              mb.addBranchTarget(ifeq + 3, matchBaseState);
              const xferLitNan = emitExpr(c.body, mb, tcT, stackDepth);
              if (!xferLitNan) {
                mb.emit1b(JvmOp.ASTORE, matchResultSlot);
                const gotoEnd = mb.length();
                mb.emit1s(JvmOp.GOTO, 0);
                endLabels.push(gotoEnd);
              }
              const afterGoto = mb.length();
              patchShort(mb, ifeq + 1, afterGoto - ifeq);
              mb.addBranchTarget(afterGoto, matchBaseState);
              continue;
            }

            mb.emit1b(JvmOp.ALOAD, scrutSlot);
            emitExpr({ kind: 'LiteralExpr', literal: c.pattern.literal, value: c.pattern.value, span: undefined } as import('../ast/nodes.js').LiteralExpr, mb, tcN);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'equals', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Boolean;'));
            mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(BOOLEAN, 'booleanValue', '()Z'));
            const ifeq = mb.length();
            mb.emit1s(JvmOp.IFEQ, 0);
            mb.addBranchTarget(ifeq + 3, matchBaseState);
            const xferLit = emitExpr(c.body, mb, tcT, stackDepth);
            if (!xferLit) {
              mb.emit1b(JvmOp.ASTORE, matchResultSlot);
              const gotoEnd = mb.length();
              mb.emit1s(JvmOp.GOTO, 0);
              endLabels.push(gotoEnd);
            }
            const afterGoto = mb.length();
            patchShort(mb, ifeq + 1, afterGoto - ifeq);
            mb.addBranchTarget(afterGoto, matchBaseState);
            continue;
          }
          if (c.pattern.kind === 'TuplePattern') {
            const missLabels: number[] = [];
            const scrutT = getInferredType(expr.scrutinee);

            function deleteTupleBindings(pat: TuplePattern): void {
              for (const e of pat.elements) {
                if (e.kind === 'VarPattern') env.delete(e.name);
                else if (e.kind === 'TuplePattern') deleteTupleBindings(e);
              }
            }

            function emitTupleSlots(scrutSlot: number, pattern: TuplePattern, tupleType: InternalType | undefined): void {
              const elemsT = tupleType?.kind === 'tuple' ? tupleType.elements : undefined;
              for (let i = 0; i < pattern.elements.length; i++) {
                const elem = pattern.elements[i]!;
                const elemT = elemsT?.[i];
                if (elem.kind === 'VarPattern') {
                  mb.emit1b(JvmOp.ALOAD, scrutSlot);
                  mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
                  mb.emit1s(JvmOp.LDC_W, cf.string(String(i)));
                  mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'get', '(Ljava/lang/String;)Ljava/lang/Object;'));
                  const slot = nextLocal++;
                  env.set(elem.name, slot);
                  mb.emit1b(JvmOp.ASTORE, slot);
                } else if (elem.kind === 'WildcardPattern') {
                  const toss = nextLocal++;
                  mb.emit1b(JvmOp.ALOAD, scrutSlot);
                  mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
                  mb.emit1s(JvmOp.LDC_W, cf.string(String(i)));
                  mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'get', '(Ljava/lang/String;)Ljava/lang/Object;'));
                  mb.emit1b(JvmOp.ASTORE, toss);
                } else if (elem.kind === 'LiteralPattern') {
                  const tmp = nextLocal++;
                  mb.emit1b(JvmOp.ALOAD, scrutSlot);
                  mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
                  mb.emit1s(JvmOp.LDC_W, cf.string(String(i)));
                  mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'get', '(Ljava/lang/String;)Ljava/lang/Object;'));
                  mb.emit1b(JvmOp.ASTORE, tmp);
                  const lit = elem;
                  if (lit.literal === 'float' && Number.isNaN(Number.parseFloat(lit.value))) {
                    mb.emit1b(JvmOp.ALOAD, tmp);
                    mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'floatIsNan', '(Ljava/lang/Object;)Ljava/lang/Boolean;'));
                    mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(BOOLEAN, 'booleanValue', '()Z'));
                  } else {
                    mb.emit1b(JvmOp.ALOAD, tmp);
                    emitExpr(
                      { kind: 'LiteralExpr', literal: lit.literal, value: lit.value, span: undefined } as import('../ast/nodes.js').LiteralExpr,
                      mb,
                      tcN,
                    );
                    mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'equals', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Boolean;'));
                    mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(BOOLEAN, 'booleanValue', '()Z'));
                  }
                  const ifeq = mb.length();
                  mb.emit1s(JvmOp.IFEQ, 0);
                  missLabels.push(ifeq);
                } else if (elem.kind === 'TuplePattern') {
                  const innerSlot = nextLocal++;
                  mb.emit1b(JvmOp.ALOAD, scrutSlot);
                  mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
                  mb.emit1s(JvmOp.LDC_W, cf.string(String(i)));
                  mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'get', '(Ljava/lang/String;)Ljava/lang/Object;'));
                  mb.emit1b(JvmOp.ASTORE, innerSlot);
                  mb.emit1b(JvmOp.ALOAD, innerSlot);
                  mb.emit1s(JvmOp.INSTANCEOF, cf.classRef(KRECORD));
                  const ifeq = mb.length();
                  mb.emit1s(JvmOp.IFEQ, 0);
                  missLabels.push(ifeq);
                  emitTupleSlots(innerSlot, elem, elemT?.kind === 'tuple' ? elemT : undefined);
                }
              }
            }

            mb.emit1b(JvmOp.ALOAD, scrutSlot);
            mb.emit1s(JvmOp.INSTANCEOF, cf.classRef(KRECORD));
            const ifNotTuple = mb.length();
            mb.emit1s(JvmOp.IFEQ, 0);
            missLabels.push(ifNotTuple);

            emitTupleSlots(scrutSlot, c.pattern, scrutT?.kind === 'tuple' ? scrutT : undefined);

            const xferTuple = emitExpr(c.body, mb, tcT, stackDepth);
            deleteTupleBindings(c.pattern);

            if (!xferTuple) {
              mb.emit1b(JvmOp.ASTORE, matchResultSlot);
              const gotoEnd = mb.length();
              mb.emit1s(JvmOp.GOTO, 0);
              endLabels.push(gotoEnd);
            }
            const nextCaseStart = mb.length();
            for (const miss of missLabels) {
              patchShort(mb, miss + 1, nextCaseStart - miss);
            }
            mb.addBranchTarget(nextCaseStart, matchBaseState);
            continue;
          }
          if (c.pattern.kind === 'VarPattern') {
            const slot = nextLocal++;
            env.set(c.pattern.name, slot);
            mb.emit1b(JvmOp.ALOAD, scrutSlot);
            mb.emit1b(JvmOp.ASTORE, slot);
            const xferVar = emitExpr(c.body, mb, tcT, stackDepth);
            env.delete(c.pattern.name);
            if (!xferVar) {
              mb.emit1b(JvmOp.ASTORE, matchResultSlot);
              const gotoEnd = mb.length();
              mb.emit1s(JvmOp.GOTO, 0);
              endLabels.push(gotoEnd);
            }
            continue;
          }
          if (c.pattern.kind === 'WildcardPattern') {
            const xferWild = emitExpr(c.body, mb, tcT, stackDepth);
            if (!xferWild) {
              mb.emit1b(JvmOp.ASTORE, matchResultSlot);
              const gotoEnd = mb.length();
              mb.emit1s(JvmOp.GOTO, 0);
              endLabels.push(gotoEnd);
            }
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
        return false;
      }
      case 'ListExpr': {
        if (expr.elements.length === 0) {
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(K_NIL, 'INSTANCE', 'Lkestrel/runtime/KNil;'));
          return false;
        }
        const listTemp = nextLocal++;
        const elemTemp = nextLocal++;
        mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(K_NIL, 'INSTANCE', 'Lkestrel/runtime/KNil;'));
        mb.emit1b(JvmOp.ASTORE, listTemp);
        for (let i = expr.elements.length - 1; i >= 0; i--) {
          const el = expr.elements[i];
          if (el && typeof el === 'object' && 'spread' in el) {
            emitExpr((el as { expr: Expr }).expr, mb, tcN);
          } else {
            emitExpr(el as Expr, mb, tcN);
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
        return false;
      }
      case 'ConsExpr': {
        const consHeadSlot = nextLocal++;
        const consTailSlot = nextLocal++;
        emitExpr(expr.head, mb, tcN);
        mb.emit1b(JvmOp.ASTORE, consHeadSlot);
        emitExpr(expr.tail, mb, tcN);
        mb.emit1b(JvmOp.ASTORE, consTailSlot);
        mb.emit1s(JvmOp.NEW, cf.classRef(K_CONS));
        mb.emit1(JvmOp.DUP);
        mb.emit1b(JvmOp.ALOAD, consHeadSlot);
        mb.emit1b(JvmOp.ALOAD, consTailSlot);
        mb.emit1s(JvmOp.CHECKCAST, cf.classRef(K_LIST));
        mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(K_CONS, '<init>', '(Ljava/lang/Object;Lkestrel/runtime/KList;)V'));
        return false;
      }
      case 'PipeExpr': {
        if (expr.op === '|>') {
          const call: Expr =
            expr.right.kind === 'CallExpr'
              ? { kind: 'CallExpr', callee: expr.right.callee, args: [expr.left, ...expr.right.args], span: expr.span }
              : { kind: 'CallExpr', callee: expr.right, args: [expr.left], span: expr.span };
          return emitExpr(call, mb, tailCtx, stackDepth);
        }
        const call: Expr =
          expr.left.kind === 'CallExpr'
            ? { kind: 'CallExpr', callee: expr.left.callee, args: [...expr.left.args, expr.right], span: expr.span }
            : { kind: 'CallExpr', callee: expr.left, args: [expr.right], span: expr.span };
        return emitExpr(call, mb, tailCtx, stackDepth);
      }
      case 'UnaryExpr': {
        if (expr.op === '-') {
          mb.emit1s(JvmOp.LDC2_W, cf.constantLong(0n));
          mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(LONG, 'valueOf', '(J)Ljava/lang/Long;'));
          emitExpr(expr.operand, mb, tcN, stackDepth + 1);
          mb.emit1s(JvmOp.CHECKCAST, cf.classRef(LONG));
          mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(KMATH, 'sub', '(Ljava/lang/Long;Ljava/lang/Long;)Ljava/lang/Long;'));
        } else if (expr.op === '!') {
          emitExpr(expr.operand, mb, tcN, stackDepth);
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(BOOLEAN, 'TRUE', 'Ljava/lang/Boolean;'));
          const ifeqPos = mb.length();
          mb.emit1s(JvmOp.IF_ACMPEQ, 0);
          mb.addBranchTarget(mb.length(), frameState(env, nextLocal, undefined, stackDepth));
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(BOOLEAN, 'TRUE', 'Ljava/lang/Boolean;'));
          const gotoEnd = mb.length();
          mb.emit1s(JvmOp.GOTO, 0);
          const falseLabel = mb.length();
          mb.addBranchTarget(falseLabel, frameState(env, nextLocal, undefined, stackDepth));
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(BOOLEAN, 'FALSE', 'Ljava/lang/Boolean;'));
          const afterNot = mb.length();
          mb.addBranchTarget(afterNot, frameState(env, nextLocal, undefined, stackDepth + 1));
          patchShort(mb, ifeqPos + 1, falseLabel - ifeqPos);
          patchShort(mb, gotoEnd + 1, afterNot - gotoEnd);
        } else {
          emitExpr(expr.operand, mb, tcN, stackDepth);
        }
        return false;
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
            } else if (freeVarToIndex?.has(name)) {
              // name is captured from outer lambda's env array (lambda inside lambda)
              mb.emit1b(JvmOp.ALOAD, env.get('__env')!);
              mb.emit1s(JvmOp.CHECKCAST, cf.classRef('[Ljava/lang/Object;'));
              mb.emit1s(JvmOp.LDC_W, cf.constantInt(freeVarToIndex.get(name)!));
              mb.emit1(JvmOp.AALOAD);
            } else if (globalNames.has(name)) {
              mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(className, jvmMangleName(name), 'Ljava/lang/Object;'));
            } else if (funNames.has(name)) {
              const arity = funArities.get(name);
              if (arity === undefined) throw new Error(`JVM codegen: missing arity for function ${name}`);
              emitFunctionRef(mb, className, jvmMangleName(name), arity);
            } else if (
              options.importedNameToClass?.get(name) != null &&
              options.importedFunArities?.get(name) !== undefined
            ) {
              const importedFunClass = options.importedNameToClass.get(name)!;
              const importedFunArity = options.importedFunArities.get(name)!;
              const originalName = options.importedNameToOriginal?.get(name) ?? name;
              mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(importedFunClass, '$init', '()V'));
              emitFunctionRef(mb, importedFunClass, jvmMangleName(originalName), importedFunArity);
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
        return false;
      }
      case 'RecordExpr': {
        if (expr.spread) {
          emitExpr(expr.spread, mb, tcN);
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
          emitExpr(f.value, mb, tcN);
          mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'set', '(Ljava/lang/String;Ljava/lang/Object;)V'));
        }
        return false;
      }
      case 'FieldExpr': {
        if (expr.object.kind === 'IdentExpr') {
          const nsClass = options.namespaceClasses?.get(expr.object.name);
          if (nsClass != null) {
            const nsFunArity = options.namespaceFunArities?.get(expr.object.name)?.get(expr.field);
            if (nsFunArity !== undefined) {
              if (nsClass !== className) {
                mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(nsClass, '$init', '()V'));
              }
              mb.emit1s(JvmOp.LDC_W, cf.classRef(nsClass));
              mb.emit1s(JvmOp.LDC_W, cf.string(jvmMangleName(expr.field)));
              mb.emit1s(JvmOp.LDC_W, cf.constantInt(nsFunArity));
              mb.emit1s(
                JvmOp.INVOKESTATIC,
                cf.methodref(
                  K_FUNCTION_REF,
                  'of',
                  '(Ljava/lang/Class;Ljava/lang/String;I)L' + K_FUNCTION_REF + ';'
                )
              );
              return false;
            }
            // Check if this is a namespace nullary ADT constructor (e.g. Lib.PubEof)
            const nsAdtCtors = options.namespaceAdtConstructors?.get(expr.object.name);
            const ctorClass = nsAdtCtors?.get(expr.field);
            if (ctorClass != null) {
              if (nsClass !== className) {
                mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(nsClass, '$init', '()V'));
              }
              mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(ctorClass, 'INSTANCE', 'L' + ctorClass + ';'));
              return false;
            }
            if (nsClass !== className) {
              mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(nsClass, '$init', '()V'));
            }
            mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(nsClass, jvmMangleName(expr.field), 'Ljava/lang/Object;'));
            // If the field is a var, unwrap the KRecord to get the actual value
            if (options.namespaceVarFields?.get(expr.object.name)?.has(expr.field)) {
              mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
              mb.emit1s(JvmOp.LDC_W, cf.string('0'));
              mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'get', '(Ljava/lang/String;)Ljava/lang/Object;'));
            }
            return false;
          }
        }
        emitExpr(expr.object, mb, tcN);
        mb.emit1s(JvmOp.CHECKCAST, cf.classRef(KRECORD));
        mb.emit1s(JvmOp.LDC_W, cf.string(expr.field));
        mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'get', '(Ljava/lang/String;)Ljava/lang/Object;'));
        return false;
      }
      case 'TupleExpr': {
        mb.emit1s(JvmOp.NEW, cf.classRef(KRECORD));
        mb.emit1(JvmOp.DUP);
        mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(KRECORD, '<init>', '()V'));
        for (let i = 0; i < expr.elements.length; i++) {
          mb.emit1(JvmOp.DUP);
          mb.emit1s(JvmOp.LDC_W, cf.string(String(i)));
          emitExpr(expr.elements[i], mb, tcN);
          mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(KRECORD, 'set', '(Ljava/lang/String;Ljava/lang/Object;)V'));
        }
        return false;
      }
      case 'ThrowExpr': {
        emitExpr(expr.value, mb, tcN);
        mb.emit1s(JvmOp.NEW, cf.classRef(K_EXCEPTION));
        mb.emit1(JvmOp.DUP_X1);
        mb.emit1(JvmOp.SWAP);
        mb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref(K_EXCEPTION, '<init>', '(Ljava/lang/Object;)V'));
        mb.emit1(JvmOp.ATHROW);
        return true;
      }
      case 'TryExpr': {
        const kExceptionClassIdx = cf.classRef(K_EXCEPTION);
        const throwableClassIdx = cf.classRef('java/lang/Throwable');
        const ambientDepth = stackDepth;
        const ambientSlots: number[] = [];
        const ambientNames: string[] = [];
        if (ambientDepth > 0) {
          for (let i = ambientDepth - 1; i >= 0; i--) {
            const slot = nextLocal++;
            ambientSlots[i] = slot;
            const ambientName = `$tryAmbient${i}`;
            ambientNames[i] = ambientName;
            env.set(ambientName, slot);
            mb.emit1b(JvmOp.ASTORE, slot);
          }
        }
        const innerStackDepth = 0;
        const tryResultSlot = nextLocal++;
        const tryStart = mb.length();
        mb.addBranchTarget(tryStart, frameState(env, nextLocal, undefined, innerStackDepth));
        const tryBodyXfer = emitExpr(expr.body, mb, tcT, innerStackDepth);
        const tryEnd = mb.length();
        let gotoAfter: number | undefined;
        if (!tryBodyXfer) {
          mb.emit1b(JvmOp.ASTORE, tryResultSlot);
          gotoAfter = mb.length();
          mb.emit1s(JvmOp.GOTO, 0);
        }
        const handlerStart = mb.length();
        const handlerFrame = frameState(env, nextLocal, undefined, 1);
        handlerFrame.stackItemCpIdx = throwableClassIdx;
        mb.addBranchTarget(handlerStart, handlerFrame);
        const EXN_SLOT = 57;
        const PAYLOAD_SLOT = 56;
        const arithOverflowClass = adtClassByConstructor.get('ArithmeticOverflow');
        const divideByZeroClass = adtClassByConstructor.get('DivideByZero');
        mb.emit1b(JvmOp.ASTORE, EXN_SLOT);
        mb.emit1b(JvmOp.ALOAD, EXN_SLOT);
        mb.emit1s(JvmOp.CHECKCAST, cf.classRef('java/lang/Throwable'));
        if (arithOverflowClass != null) mb.emit1s(JvmOp.LDC_W, cf.string(arithOverflowClass));
        else mb.emit1(JvmOp.ACONST_NULL);
        if (divideByZeroClass != null) mb.emit1s(JvmOp.LDC_W, cf.string(divideByZeroClass));
        else mb.emit1(JvmOp.ACONST_NULL);
        mb.emit1s(
          JvmOp.INVOKESTATIC,
          cf.methodref(RUNTIME, 'normalizeCaught', '(Ljava/lang/Throwable;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/Object;')
        );
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
            const xferTryVar = emitExpr(c.body, mb, tcT, innerStackDepth);
            env.delete(c.pattern.name);
            if (!xferTryVar) {
              mb.emit1b(JvmOp.ASTORE, tryResultSlot);
              const gotoEnd = mb.length();
              mb.emit1s(JvmOp.GOTO, 0);
              catchEndLabels.push(gotoEnd);
            }
            continue;
          }
          if (c.pattern.kind === 'WildcardPattern') {
            const xferTryWild = emitExpr(c.body, mb, tcT, innerStackDepth);
            if (!xferTryWild) {
              mb.emit1b(JvmOp.ASTORE, tryResultSlot);
              const gotoEnd = mb.length();
              mb.emit1s(JvmOp.GOTO, 0);
              catchEndLabels.push(gotoEnd);
            }
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
              mb.addBranchTarget(mb.length(), frameState(env, nextLocal, [57, 56]));
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
                  } else {
                    // Wildcard / non-binding field pattern: discard extracted field value.
                    mb.emit1(JvmOp.POP);
                  }
                }
              }
              const xferTryAdt = emitExpr(c.body, mb, tcT, innerStackDepth);
              if (p.fields?.length) for (const f of p.fields) if (f.pattern?.kind === 'VarPattern') env.delete((f.pattern as { name: string }).name);
              if (!xferTryAdt) {
                mb.emit1b(JvmOp.ASTORE, tryResultSlot);
                const gotoEnd = mb.length();
                mb.emit1s(JvmOp.GOTO, 0);
                catchEndLabels.push(gotoEnd);
              }
              const afterGoto = mb.length();
              patchShort(mb, ifeq + 1, afterGoto - ifeq);
              mb.addBranchTarget(afterGoto, frameState(env, nextLocal, [57, 56]));
              continue;
            }
            if (p.name === 'None') {
              mb.emit1b(JvmOp.ALOAD, PAYLOAD_SLOT);
              mb.emit1s(JvmOp.INSTANCEOF, cf.classRef(K_NONE));
              const ifeq = mb.length();
              mb.emit1s(JvmOp.IFEQ, 0);
              mb.addBranchTarget(mb.length(), frameState(env, nextLocal, [57, 56]));
              const xferTryNone = emitExpr(c.body, mb, tcT, innerStackDepth);
              if (!xferTryNone) {
                mb.emit1b(JvmOp.ASTORE, tryResultSlot);
                const gotoEnd = mb.length();
                mb.emit1s(JvmOp.GOTO, 0);
                catchEndLabels.push(gotoEnd);
              }
              const afterGoto = mb.length();
              patchShort(mb, ifeq + 1, afterGoto - ifeq);
              mb.addBranchTarget(afterGoto, frameState(env, nextLocal, [57, 56]));
              continue;
            }
            if (p.name === 'Some') {
              mb.emit1b(JvmOp.ALOAD, PAYLOAD_SLOT);
              mb.emit1s(JvmOp.INSTANCEOF, cf.classRef(K_SOME));
              const ifeq = mb.length();
              mb.emit1s(JvmOp.IFEQ, 0);
              mb.addBranchTarget(mb.length(), frameState(env, nextLocal, [57, 56]));
              mb.emit1b(JvmOp.ALOAD, PAYLOAD_SLOT);
              mb.emit1s(JvmOp.CHECKCAST, cf.classRef(K_SOME));
              mb.emit1s(JvmOp.GETFIELD, cf.fieldref(K_SOME, 'value', 'Ljava/lang/Object;'));
              const varName = p.fields?.[0] && p.fields[0].pattern?.kind === 'VarPattern' ? (p.fields[0].pattern as { name: string }).name : null;
              if (varName) {
                const slot = nextLocal++;
                env.set(varName, slot);
                mb.emit1b(JvmOp.ASTORE, slot);
              } else {
                mb.emit1(JvmOp.POP);
              }
              const xferTrySome = emitExpr(c.body, mb, tcT, innerStackDepth);
              if (varName) env.delete(varName);
              if (!xferTrySome) {
                mb.emit1b(JvmOp.ASTORE, tryResultSlot);
                const gotoEnd = mb.length();
                mb.emit1s(JvmOp.GOTO, 0);
                catchEndLabels.push(gotoEnd);
              }
              const afterGoto = mb.length();
              patchShort(mb, ifeq + 1, afterGoto - ifeq);
              mb.addBranchTarget(afterGoto, frameState(env, nextLocal, [57, 56]));
              continue;
            }
          }
          if (c.pattern.kind === 'LiteralPattern') {
            mb.emit1b(JvmOp.ALOAD, PAYLOAD_SLOT);
            emitExpr({ kind: 'LiteralExpr', literal: c.pattern.literal, value: c.pattern.value, span: undefined } as import('../ast/nodes.js').LiteralExpr, mb, tcN);
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'equals', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Boolean;'));
            mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref('java/lang/Boolean', 'booleanValue', '()Z'));
            const ifeq = mb.length();
            mb.emit1s(JvmOp.IFEQ, 0);
            mb.addBranchTarget(mb.length(), frameState(env, nextLocal, [57, 56]));
            const xferTryLit = emitExpr(c.body, mb, tcT, innerStackDepth);
            if (!xferTryLit) {
              mb.emit1b(JvmOp.ASTORE, tryResultSlot);
              const gotoEnd = mb.length();
              mb.emit1s(JvmOp.GOTO, 0);
              catchEndLabels.push(gotoEnd);
            }
            const afterGoto = mb.length();
            patchShort(mb, ifeq + 1, afterGoto - ifeq);
            mb.addBranchTarget(afterGoto, frameState(env, nextLocal, [57, 56]));
            continue;
          }
        }
        const rethrowPos = mb.length();
        mb.addBranchTarget(rethrowPos, frameState(env, nextLocal, [57, 56]));
        mb.emit1b(JvmOp.ALOAD, EXN_SLOT);
        mb.emit1s(JvmOp.CHECKCAST, cf.classRef('java/lang/Throwable'));
        mb.emit1(JvmOp.ATHROW);
        const afterCatch = mb.length();
        mb.addBranchTarget(afterCatch, frameState(env, nextLocal, [tryResultSlot], innerStackDepth));
        for (const gotoPos of catchEndLabels) patchShort(mb, gotoPos + 1, afterCatch - gotoPos);
        if (gotoAfter !== undefined) patchShort(mb, gotoAfter + 1, afterCatch - gotoAfter);
        mb.addException(tryStart, tryEnd, handlerStart, throwableClassIdx);
        if (expr.catchVar != null) {
          if (prevCatchVar !== undefined) env.set(expr.catchVar, prevCatchVar);
          else env.delete(expr.catchVar);
        }
        if (ambientDepth > 0) {
          const restoredResultSlot = nextLocal++;
          mb.emit1b(JvmOp.ALOAD, tryResultSlot);
          mb.emit1b(JvmOp.ASTORE, restoredResultSlot);
          for (let i = 0; i < ambientSlots.length; i++) mb.emit1b(JvmOp.ALOAD, ambientSlots[i]!);
          mb.emit1b(JvmOp.ALOAD, restoredResultSlot);
          for (const name of ambientNames) env.delete(name);
        } else {
          mb.emit1b(JvmOp.ALOAD, tryResultSlot);
        }
        return false;
      }
      case 'IsExpr': {
        const tested = expr.testedType;
        const subjT = getInferredType(expr.expr);
        const boxBoolFromInt = (): void => {
          mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(BOOLEAN, 'valueOf', '(Z)Ljava/lang/Boolean;'));
        };
        if (tested.kind === 'PrimType') {
          const d = jvmPrimDisc(tested.name);
          if (d < 0) throw new Error(`JVM codegen: is ${tested.name} not supported`);
          emitExpr(expr.expr, mb, tcN);
          mb.emit1s(JvmOp.LDC_W, cf.constantInt(d));
          mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'isValueKind', '(Ljava/lang/Object;I)Z'));
          boxBoolFromInt();
          return false;
        }
        if (tested.kind === 'RecordType') {
          const subRec = jvmAsRecord(subjT);
          if (subRec == null) throw new Error('JVM codegen: record is needs record scrutinee');
          for (const f of tested.fields) {
            if (subRec.fields.every((x) => x.name !== f.name)) {
              throw new Error(`JVM codegen: record is missing field ${f.name}`);
            }
          }
          const tmpSlot = nextLocal++;
          emitExpr(expr.expr, mb, tcN);
          mb.emit1b(JvmOp.ASTORE, tmpSlot);
          mb.emit1b(JvmOp.ALOAD, tmpSlot);
          mb.emit1s(JvmOp.LDC_W, cf.constantInt(6));
          mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'isValueKind', '(Ljava/lang/Object;I)Z'));
          const falseJumps: number[] = [];
          falseJumps.push(mb.length());
          mb.emit1s(JvmOp.IFEQ, 0);
          for (const f of tested.fields) {
            if (f.type.kind !== 'PrimType') {
              throw new Error('JVM codegen: record is only supports primitive field types here');
            }
            const fd = jvmPrimDisc(f.type.name);
            if (fd < 0) throw new Error(`JVM codegen: is field ${f.type.name}`);
            mb.emit1b(JvmOp.ALOAD, tmpSlot);
            mb.emit1s(JvmOp.LDC_W, cf.string(f.name));
            mb.emit1s(JvmOp.LDC_W, cf.constantInt(fd));
            mb.emit1s(
              JvmOp.INVOKESTATIC,
              cf.methodref(RUNTIME, 'recordFieldIsKind', '(Ljava/lang/Object;Ljava/lang/String;I)Z')
            );
            falseJumps.push(mb.length());
            mb.emit1s(JvmOp.IFEQ, 0);
          }
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(BOOLEAN, 'TRUE', 'Ljava/lang/Boolean;'));
          const gotoEnd = mb.length();
          mb.emit1s(JvmOp.GOTO, 0);
          const falseLab = mb.length();
          mb.addBranchTarget(falseLab, frameState(env, nextLocal, undefined, stackDepth));
          mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(BOOLEAN, 'FALSE', 'Ljava/lang/Boolean;'));
          const endLab = mb.length();
          mb.addBranchTarget(endLab, frameState(env, nextLocal, undefined, stackDepth + 1));
          patchShort(mb, gotoEnd + 1, endLab - gotoEnd);
          for (const j of falseJumps) {
            patchShort(mb, j + 1, falseLab - j);
          }
          return false;
        }
        if (tested.kind === 'IdentType') {
          if (jvmBuiltinCtorInfo(tested.name, 0) != null) {
            emitExpr(expr.expr, mb, tcN);
            if (tested.name === 'None') {
              mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(K_NONE, 'INSTANCE', 'Lkestrel/runtime/KNone;'));
            } else if (tested.name === 'Nil') {
              mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(K_NIL, 'INSTANCE', 'Lkestrel/runtime/KNil;'));
            } else {
              throw new Error(`JVM codegen: is ${tested.name}`);
            }
            mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'equals', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Boolean;'));
            return false;
          }
          const subjApp = subjT?.kind === 'app' ? subjT : null;
          if (subjApp != null && subjApp.name === tested.name) {
            mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(BOOLEAN, 'TRUE', 'Ljava/lang/Boolean;'));
            return false;
          }
          const adtCtorClass = adtClassByConstructor.get(tested.name);
          if (adtCtorClass != null) {
            emitExpr(expr.expr, mb, tcN);
            mb.emit1s(JvmOp.INSTANCEOF, cf.classRef(adtCtorClass));
            boxBoolFromInt();
            return false;
          }
          emitExpr(expr.expr, mb, tcN);
          mb.emit1s(JvmOp.LDC_W, cf.string(tested.name));
          mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'isAdtNamedCtor', '(Ljava/lang/Object;Ljava/lang/String;)Z'));
          boxBoolFromInt();
          return false;
        }
        if (tested.kind === 'AppType') {
          const b = jvmBuiltinCtorInfo(tested.name, tested.args.length);
          if (b != null) {
            if (b.arity === 0) {
              emitExpr(expr.expr, mb, tcN);
              if (tested.name === 'None') {
                mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(K_NONE, 'INSTANCE', 'Lkestrel/runtime/KNone;'));
              } else if (tested.name === 'Nil') {
                mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(K_NIL, 'INSTANCE', 'Lkestrel/runtime/KNil;'));
              } else {
                throw new Error(`JVM codegen: is ${tested.name}`);
              }
              mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'equals', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Boolean;'));
              return false;
            }
            emitExpr(expr.expr, mb, tcN);
            if (tested.name === 'Some') {
              mb.emit1s(JvmOp.INSTANCEOF, cf.classRef(K_SOME));
            } else if (tested.name === 'Ok') {
              mb.emit1s(JvmOp.INSTANCEOF, cf.classRef(K_OK));
            } else if (tested.name === 'Err') {
              mb.emit1s(JvmOp.INSTANCEOF, cf.classRef(K_ERR));
            } else if (tested.name === 'Cons') {
              mb.emit1s(JvmOp.INSTANCEOF, cf.classRef(K_CONS));
            } else {
              throw new Error(`JVM codegen: is ${tested.name}`);
            }
            boxBoolFromInt();
            return false;
          }
          if (subjT?.kind === 'app' && subjT.name === tested.name) {
            mb.emit1s(JvmOp.GETSTATIC, cf.fieldref(BOOLEAN, 'TRUE', 'Ljava/lang/Boolean;'));
            return false;
          }
          const adtCtorClass = adtClassByConstructor.get(tested.name);
          if (adtCtorClass != null) {
            emitExpr(expr.expr, mb, tcN);
            mb.emit1s(JvmOp.INSTANCEOF, cf.classRef(adtCtorClass));
            boxBoolFromInt();
            return false;
          }
          throw new Error(`JVM codegen: is ${tested.name}<...> not supported`);
        }
        throw new Error('JVM codegen: is — unsupported tested type');
      }
      case 'NeverExpr':
        // Unreachable tail after `break`/`continue` in the same block.
        return false;
      case 'AwaitExpr':
        emitExpr(expr.value, mb, tcN);
        mb.emit1s(JvmOp.CHECKCAST, cf.classRef(K_TASK));
        mb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(K_TASK, 'get', '()Ljava/lang/Object;'));
        return false;
      default:
        throw new Error(`JVM codegen: unsupported expr ${(expr as Expr).kind}`);
    }
    return false;
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
    const methodName = l.async ? asyncLambdaPayloadMethodName(i) : '$lambda' + i;
    const methodFlags = ACC_PUBLIC | ACC_STATIC;
    const mb = cf.addMethod(methodName, desc, methodFlags);
    const lambdaXfer = emitExpr(l.body, mb, undefined);
    if (!lambdaXfer) mb.emit1(JvmOp.ARETURN);
    // Match top-level fun decls: emitExpr uses fixed high slots (e.g. ConsExpr 60–61); nextLocal alone is too small.
    mb.setMaxs(32, Math.max(Math.max(lambdaNext, nextLocal) + 8, 70));
    cf.flushLastMethod();
    env.clear();
    prevEnv.forEach((v, k) => env.set(k, v));
    nextLocal = prevNext;
    freeVarToIndex = prevFree;
    localFunNamesInEnv = prevLocalFuns;
    varNames.clear();
    for (const v of prevVarNames) varNames.add(v);
    innerClasses.set(className + '$Lambda' + i, buildLambdaClass(className, i, arity, l.capturing, l.async));
    if (l.async) {
      innerClasses.set(className + '$Lambda' + i + '$Payload', buildAsyncLambdaPayloadClass(className, i, arity, l.capturing));
    }
  }

  const emittedMutualHelpers = new Set<string>();
  for (const fun of topLevelFunDecls) {
    const group = mutualGroupByFun.get(fun.name);
    if (group == null) continue;
    if (emittedMutualHelpers.has(group.helperMethod)) continue;
    emittedMutualHelpers.add(group.helperMethod);

    const helperDesc = '(Ljava/lang/Object;' + 'Ljava/lang/Object;'.repeat(group.arity) + ')Ljava/lang/Object;';
    const helperMb = cf.addMethod(group.helperMethod, helperDesc, ACC_PRIVATE | ACC_STATIC);
    const helperArgEnv = new Map<string, number>();
    helperArgEnv.set('$state', 0);
    for (let i = 0; i < group.arity; i++) helperArgEnv.set(`$arg${i}`, i + 1);
    const dispatchHead = helperMb.length();
    helperMb.addBranchTarget(dispatchHead, frameState(helperArgEnv, group.arity + 1));

    const stateChecks: number[] = [];
    for (let i = 0; i < group.memberNames.length; i++) {
      helperMb.emit1b(JvmOp.ALOAD, 0);
      emitLongObjectConst(helperMb, i);
      helperMb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'equals', '(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Boolean;'));
      helperMb.emit1s(JvmOp.INVOKEVIRTUAL, cf.methodref(BOOLEAN, 'booleanValue', '()Z'));
      const check = helperMb.length();
      helperMb.emit1s(JvmOp.IFNE, 0);
      stateChecks.push(check);
    }

    helperMb.emit1s(JvmOp.NEW, cf.classRef('java/lang/IllegalStateException'));
    helperMb.emit1(JvmOp.DUP);
    helperMb.emit1s(JvmOp.LDC_W, cf.string('Invalid mutual tail-call dispatch state'));
    helperMb.emit1s(JvmOp.INVOKESPECIAL, cf.methodref('java/lang/IllegalStateException', '<init>', '(Ljava/lang/String;)V'));
    helperMb.emit1(JvmOp.ATHROW);

    for (let i = 0; i < group.memberNames.length; i++) {
      const caseStart = helperMb.length();
      patchShort(helperMb, stateChecks[i]! + 1, caseStart - stateChecks[i]!);
      const name = group.memberNames[i]!;
      const member = funByName.get(name);
      if (!member) continue;
      const paramEnv = new Map<string, number>();
      paramEnv.set('__state', 0);
      member.params.forEach((p, pi) => paramEnv.set(p.name, pi + 1));
      helperMb.addBranchTarget(caseStart, frameState(paramEnv, group.arity + 1));
      env.clear();
      for (const [k, v] of paramEnv) env.set(k, v);
      for (let pi = 0; pi < group.arity; pi++) env.set(`__param$${pi}`, pi + 1);
      nextLocal = group.arity + 1;
      const helperTailCtx: JvmEmitTailContext = {
        self: { name: member.name, arity: group.arity, loopHead: dispatchHead, argBase: 1 },
        mutual: {
          memberStateByName: group.memberStateByName,
          arity: group.arity,
          loopHead: dispatchHead,
          stateLocal: 0,
          argBase: 1,
        },
        inTail: true,
      };
      const bodyXfer = emitExpr(member.body, helperMb, helperTailCtx);
      if (!bodyXfer) {
        helperMb.emit1(JvmOp.ARETURN);
      }
    }
    helperMb.setMaxs(32, Math.max(Math.max(group.arity + 1, nextLocal) + 8, 70));
    cf.flushLastMethod();
    env.clear();
    nextLocal = 0;
  }

  for (const fun of topLevelFunDecls) {
    if (!fun.async) continue;
    const arity = fun.params.length;
    const payloadMb = cf.addMethod(asyncPayloadMethodName(fun.name), descriptor(arity), ACC_PRIVATE | ACC_STATIC);
    const paramEnv = new Map<string, number>();
    const fixedParamKeys: string[] = [];
    fun.params.forEach((p, i) => paramEnv.set(p.name, i));
    for (const [k, v] of paramEnv) env.set(k, v);
    for (let i = 0; i < arity; i++) {
      const fixedKey = `__param$${i}`;
      fixedParamKeys.push(fixedKey);
      env.set(fixedKey, i);
    }
    nextLocal = arity;
    const payloadXfer = emitExpr(fun.body, payloadMb, undefined);
    payloadMb.setMaxs(32, Math.max(Math.max(arity, nextLocal) + 8, 70));
    if (!payloadXfer) payloadMb.emit1(JvmOp.ARETURN);
    cf.flushLastMethod();
    for (const k of paramEnv.keys()) env.delete(k);
    for (const k of fixedParamKeys) env.delete(k);
    nextLocal = 0;
  }

  for (const fun of topLevelFunDecls) {
    const arity = fun.params.length;
    const group = mutualGroupByFun.get(fun.name);
    const mb = cf.addMethod(jvmMangleName(fun.name), fun.async ? taskDescriptor(arity) : descriptor(arity), ACC_PUBLIC | ACC_STATIC);
    if (fun.async) {
      emitFunctionRef(mb, className, asyncPayloadMethodName(fun.name), arity);
      emitArgsObjectArray(mb, Array.from({ length: arity }, (_, i) => i));
      mb.emit1s(
        JvmOp.INVOKESTATIC,
        cf.methodref(RUNTIME, 'submitAsync', '(Lkestrel/runtime/KFunction;[Ljava/lang/Object;)Lkestrel/runtime/KTask;')
      );
      mb.emit1(JvmOp.ARETURN);
      mb.setMaxs(32, Math.max(arity + 4, 8));
      cf.flushLastMethod();
      continue;
    }
    if (group != null) {
      const state = group.memberStateByName.get(fun.name);
      if (state == null) throw new Error(`JVM codegen: missing mutual state for ${fun.name}`);
      emitLongObjectConst(mb, state);
      for (let i = 0; i < arity; i++) mb.emit1b(JvmOp.ALOAD, i);
      const helperDesc = '(Ljava/lang/Object;' + 'Ljava/lang/Object;'.repeat(arity) + ')Ljava/lang/Object;';
      mb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(className, group.helperMethod, helperDesc));
      mb.emit1(JvmOp.ARETURN);
      mb.setMaxs(32, Math.max(Math.max(arity, nextLocal) + 8, 70));
      cf.flushLastMethod();
      continue;
    }

    const paramEnv = new Map<string, number>();
    const fixedParamKeys: string[] = [];
    fun.params.forEach((p, i) => paramEnv.set(p.name, i));
    for (const [k, v] of paramEnv) env.set(k, v);
    for (let i = 0; i < arity; i++) {
      const fixedKey = `__param$${i}`;
      fixedParamKeys.push(fixedKey);
      env.set(fixedKey, i);
    }
    nextLocal = arity;
    const funLoopHead = mb.length();
    mb.addBranchTarget(funLoopHead, frameState(env, nextLocal));
    const funSelfTail: JvmEmitTailContext = {
      self: { name: fun.name, arity, loopHead: funLoopHead, argBase: 0 },
      inTail: true,
    };
    const funXfer = emitExpr(fun.body, mb, funSelfTail);
    mb.setMaxs(32, Math.max(Math.max(arity, nextLocal) + 8, 70));
    if (!funXfer) {
      mb.emit1(JvmOp.ARETURN);
    }
    cf.flushLastMethod();
    for (const k of paramEnv.keys()) env.delete(k);
    for (const k of fixedParamKeys) env.delete(k);
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
  emitFunctionRef(mainMb, className, '$init', 0);
  mainMb.emit1s(JvmOp.INVOKESTATIC, cf.methodref(RUNTIME, 'runMain', '([Ljava/lang/String;Lkestrel/runtime/KFunction;)V'));
  mainMb.emit1(JvmOp.RETURN);
  mainMb.setMaxs(6, 1);
  cf.flushLastMethod();

  return {
    className,
    classBytes: cf.toBytes(),
    innerClasses,
  };
}

