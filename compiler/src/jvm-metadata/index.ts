/**
 * JVM class metadata reader.
 *
 * Uses `javap` to enumerate public methods from a Java class at compile time.
 * This is a compile-time-only feature: no classes are instantiated or executed.
 */
import { execSync } from 'child_process';

export interface JavaMethod {
  /** '<init>' for constructors, else the simple method name (e.g. 'size', 'get') */
  jvmMethodName: string;
  isConstructor: boolean;
  isStatic: boolean;
  /** Erased Java source-level param types, e.g. ['java.lang.Object', 'int'] */
  javaParamTypes: string[];
  /** Erased Java source-level return type, e.g. 'java.lang.Object', 'void' */
  javaReturnType: string;
}

export interface ClassMetadata {
  /** Fully-qualified class name, e.g. 'java.util.HashMap' */
  className: string;
  /** Simple (unqualified) class name, e.g. 'HashMap' */
  simpleClassName: string;
  methods: JavaMethod[];
}

/**
 * Read public method metadata from a Java class using `javap`.
 *
 * @param className Fully-qualified Java class name, e.g. 'java.util.HashMap'
 * @param jarPaths  Optional list of jar file paths to include on the classpath
 */
export function readClassMetadata(className: string, jarPaths?: string[]): ClassMetadata {
  const args: string[] = ['-public', '-s'];
  if (jarPaths && jarPaths.length > 0) {
    args.push('-cp', jarPaths.join(':'));
  }
  args.push(className);

  let output: string;
  try {
    output = execSync(`javap ${args.map((a) => JSON.stringify(a)).join(' ')}`, {
      encoding: 'utf-8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    throw new Error(`Failed to read class metadata for '${className}': ${msg}`);
  }

  return parseJavapOutput(className, output);
}

// ---------------------------------------------------------------------------
// javap output parser
// ---------------------------------------------------------------------------

function parseJavapOutput(className: string, output: string): ClassMetadata {
  const simpleClassName = className.split('.').pop()!;
  const lines = output.split('\n');
  const methods: JavaMethod[] = [];

  // We walk through looking for "descriptor: (...)" lines; the previous
  // non-blank, non-header line is the method source signature.
  let prevSourceLine: string | null = null;

  for (const raw of lines) {
    const line = raw.trimEnd();
    const trimmed = line.trim();

    if (!trimmed || trimmed.startsWith('Compiled from') || trimmed.startsWith('public class') ||
        trimmed.startsWith('public abstract class') || trimmed.startsWith('public interface') ||
        trimmed.startsWith('public final class') || trimmed === '{' || trimmed === '}') {
      // Skip structural lines; but still reset prevSourceLine on blank lines
      if (!trimmed) prevSourceLine = null;
      continue;
    }

    if (trimmed.startsWith('descriptor:')) {
      if (prevSourceLine !== null && prevSourceLine.includes('(')) {
        const desc = trimmed.slice('descriptor:'.length).trim();
        const method = buildMethod(prevSourceLine, desc, className, simpleClassName);
        if (method !== null) {
          methods.push(method);
        }
      }
      prevSourceLine = null;
      continue;
    }

    // Candidate source-signature line: must look like a method/constructor
    // (contains '(' and ends with ';')
    if (trimmed.endsWith(';') && trimmed.includes('(')) {
      prevSourceLine = trimmed;
    } else {
      prevSourceLine = null;
    }
  }

  // Disambiguate overloaded method names: first occurrence keeps its name,
  // subsequent occurrences get _2, _3, ... suffixes.
  disambiguateOverloads(methods);

  return { className, simpleClassName, methods };
}

function buildMethod(
  sourceLine: string,
  descriptor: string,
  className: string,
  simpleClassName: string
): JavaMethod | null {
  // Strip trailing ';'
  const src = sourceLine.replace(/;$/, '').trim();

  // Split at first '(' to get signature head and params
  const parenIdx = src.indexOf('(');
  if (parenIdx < 0) return null;

  const head = src.slice(0, parenIdx).trim();

  // Remove generic type-parameter tokens like '<K, V>' from the head
  // Use multi-pass stripping in case of nested < > (e.g. Map<K, ? extends V>)
  let stripped = head;
  for (let pass = 0; pass < 4; pass++) {
    stripped = stripped.replace(/<[^<>]*>/g, '');
  }
  stripped = stripped.trim();

  const words = stripped.split(/\s+/).filter(Boolean);
  if (words.length === 0) return null;

  // Filter out access/modifier keywords; what remains: [returnType,] methodName
  const modifiers = new Set(['public', 'protected', 'private', 'static', 'final', 'abstract',
    'native', 'synchronized', 'default', 'strictfp', 'transient', 'volatile']);
  const cleaned = words.filter((w) => !modifiers.has(w));
  if (cleaned.length === 0) return null;

  const rawMethodName = cleaned[cleaned.length - 1];

  // Skip static initializers and other non-bindable synthetic members
  if (rawMethodName === '{}' || rawMethodName === 'static' || rawMethodName === '{') return null;

  // Detect constructor: the "method name" IS the fully qualified class name or the simple name
  const isConstructor = rawMethodName === className || rawMethodName === simpleClassName;
  const isStatic = /\bstatic\b/.test(head);

  // Parse the descriptor
  const closeParen = descriptor.lastIndexOf(')');
  if (!descriptor.startsWith('(') || closeParen < 0) return null;
  const paramDescRaw = descriptor.slice(1, closeParen);
  const returnDescRaw = descriptor.slice(closeParen + 1);

  const paramBinTypes = parseDescriptorParams(paramDescRaw);
  const returnBinType = returnDescRaw;

  const javaParamTypes = paramBinTypes.map(binaryTypeToJavaSource);
  const javaReturnType = binaryTypeToJavaSource(returnBinType);

  return {
    jvmMethodName: isConstructor ? '<init>' : rawMethodName,
    isConstructor,
    isStatic,
    javaParamTypes,
    javaReturnType,
  };
}

// ---------------------------------------------------------------------------
// Descriptor parsing helpers
// ---------------------------------------------------------------------------

/** Parse a JVM binary descriptor param section (between '(' and ')') into a list of binary type tokens. */
function parseDescriptorParams(paramSec: string): string[] {
  const result: string[] = [];
  let i = 0;
  while (i < paramSec.length) {
    const c = paramSec[i];
    if (c === '[') {
      // Array — consume all leading '[' then the element type
      let j = i;
      while (paramSec[j] === '[') j++;
      if (paramSec[j] === 'L') {
        const semi = paramSec.indexOf(';', j);
        if (semi < 0) break;
        result.push(paramSec.slice(i, semi + 1));
        i = semi + 1;
      } else {
        result.push(paramSec.slice(i, j + 1));
        i = j + 1;
      }
    } else if (c === 'L') {
      const semi = paramSec.indexOf(';', i);
      if (semi < 0) break;
      result.push(paramSec.slice(i, semi + 1));
      i = semi + 1;
    } else {
      // Primitive
      result.push(c);
      i++;
    }
  }
  return result;
}

/** Convert a single JVM binary type token to a Java source-level type name. */
function binaryTypeToJavaSource(t: string): string {
  switch (t) {
    case 'Z': return 'boolean';
    case 'B': return 'byte';
    case 'C': return 'char';
    case 'S': return 'short';
    case 'I': return 'int';
    case 'J': return 'long';
    case 'F': return 'float';
    case 'D': return 'double';
    case 'V': return 'void';
    default:
      if (t.startsWith('[')) {
        return binaryTypeToJavaSource(t.slice(1)) + '[]';
      }
      if (t.startsWith('L') && t.endsWith(';')) {
        return t.slice(1, -1).replace(/\//g, '.');
      }
      return t;
  }
}

// ---------------------------------------------------------------------------
// Overload disambiguation
// ---------------------------------------------------------------------------

function disambiguateOverloads(methods: JavaMethod[]): void {
  const nameCount = new Map<string, number>();
  for (const m of methods) {
    const count = (nameCount.get(m.jvmMethodName) ?? 0) + 1;
    nameCount.set(m.jvmMethodName, count);
  }

  // For each name that appears more than once, assign suffixes in order of appearance
  const nameIdx = new Map<string, number>();
  for (const m of methods) {
    if ((nameCount.get(m.jvmMethodName) ?? 1) > 1) {
      const idx = (nameIdx.get(m.jvmMethodName) ?? 0) + 1;
      nameIdx.set(m.jvmMethodName, idx);
      if (idx > 1) {
        // Mutate the jvmMethodName to add suffix so callers can use it directly
        // We store the disambiguated name in a separate field added below.
      }
    }
  }

  // Re-do: assign kestrelName for each method
  const occurrences = new Map<string, number>();
  for (const m of methods) {
    const idx = (occurrences.get(m.jvmMethodName) ?? 0) + 1;
    occurrences.set(m.jvmMethodName, idx);
    (m as JavaMethod & { kestrelName?: string }).kestrelName = buildKestrelName(m, idx > 1 ? idx : undefined);
  }
}

/** Build the Kestrel function name for an auto-generated extern stub. */
function buildKestrelName(m: JavaMethod, overloadIndex?: number): string {
  let base: string;
  if (m.isConstructor) {
    // Constructor: 'new' + simpleClassName
    // We don't have simpleClassName here; it will be set by the caller
    base = '__ctor__';
  } else {
    base = m.jvmMethodName;
  }
  return overloadIndex !== undefined && overloadIndex > 1 ? `${base}_${overloadIndex}` : base;
}

// ---------------------------------------------------------------------------
// Kestrel stub generation
// ---------------------------------------------------------------------------

/** Map a Java source-level type name to the most appropriate Kestrel AST type string. */
export function javaTypeToKestrelType(javaType: string): string {
  // Array types have no Kestrel equivalent — map to Any
  if (javaType.endsWith('[]')) return 'Any';
  switch (javaType) {
    case 'void': return 'Unit';
    case 'int':
    case 'long':
    case 'short':
    case 'byte':
    case 'char': return 'Int';
    case 'float':
    case 'double': return 'Float';
    case 'boolean': return 'Bool';
    case 'java.lang.String': return 'String';
    default: return 'Any';
  }
}

export interface StubMethod {
  /** The Kestrel function name to use in the extern fun declaration */
  kestrelName: string;
  /** True if this stub represents a constructor */
  isConstructor: boolean;
  /** The receiver type name (alias), undefined for static methods and constructors */
  receiverType: string | undefined;
  /** Kestrel parameter list, as (name: Type) strings (receiver excluded) */
  kestrelParams: Array<{ name: string; type: string }>;
  /** Kestrel return type string */
  kestrelReturnType: string;
  /** The jvm("...") descriptor string, e.g. 'java.util.HashMap#get(java.lang.Object)' */
  jvmDescriptor: string;
}

/**
 * Generate stub declarations for all public methods of a class.
 *
 * @param meta     Class metadata from readClassMetadata()
 * @param alias    The Kestrel alias name for the generated extern type (e.g. 'HashMap')
 * @param overrides  Map from Kestrel method name → explicit param/return strings (from override block)
 */
export function generateStubs(
  meta: ClassMetadata,
  alias: string,
  overrides: Map<string, { params: Array<{ name: string; type: string }>; returnType: string }>
): StubMethod[] {
  const stubs: StubMethod[] = [];

  // Track occurrences by Kestrel base name (constructors use newAlias, others use method name)
  const occurrences = new Map<string, number>();

  // Sort constructors by param count ascending so the no-arg constructor (if any) gets the
  // base name `new${alias}`; preserve original order for non-constructors.
  const sortedMethods = [...meta.methods].sort((a, b) => {
    if (a.isConstructor && b.isConstructor) return a.javaParamTypes.length - b.javaParamTypes.length;
    return 0;
  });

  for (const m of sortedMethods) {
    const baseKestrelName = m.isConstructor ? `new${alias}` : m.jvmMethodName;

    const idx = (occurrences.get(baseKestrelName) ?? 0) + 1;
    occurrences.set(baseKestrelName, idx);

    const kestrelName = idx > 1 ? `${baseKestrelName}_${idx}` : baseKestrelName;

    // Build jvm("...") descriptor string, with ':ReturnType' suffix for primitive-returning methods
    const paramDescStr = m.javaParamTypes.join(',');
    const primitiveReturnTypes = new Set(['boolean', 'byte', 'char', 'short', 'int', 'long', 'float', 'double']);
    const retSuffix = (!m.isConstructor && primitiveReturnTypes.has(m.javaReturnType)) ? `:${m.javaReturnType}` : '';
    const jvmDescriptor = `${meta.className}#${m.jvmMethodName}(${paramDescStr})${retSuffix}`;

    // Check for an override for this kestrelName
    const override = overrides.get(kestrelName) ?? overrides.get(m.jvmMethodName);

    let params: Array<{ name: string; type: string }>;
    let kestrelReturnType: string;

    if (override) {
      params = override.params;
      kestrelReturnType = override.returnType;
    } else {
      // Auto-generate: receiver type for instance methods, no receiver for static/constructor
      params = m.javaParamTypes.map((t, i) => ({
        name: `p${i}`,
        type: javaTypeToKestrelType(t),
      }));
      kestrelReturnType = m.isConstructor ? alias : javaTypeToKestrelType(m.javaReturnType);
    }

    const receiverType = (!m.isStatic && !m.isConstructor) ? alias : undefined;

    stubs.push({ kestrelName, isConstructor: m.isConstructor, receiverType, kestrelParams: params, kestrelReturnType, jvmDescriptor });
  }

  return stubs;
}

/**
 * Render stub methods and the extern type declaration to a Kestrel source string
 * suitable for the .extern.ks sidecar file.
 */
export function renderExternKs(meta: ClassMetadata, alias: string, stubs: StubMethod[]): string {
  const lines: string[] = [
    `// Auto-generated by Kestrel compiler from ${meta.className}`,
    `// Do not edit — this file is regenerated on each compile.`,
    '',
    `extern type ${alias} = jvm("${meta.className}")`,
    '',
  ];

  for (const s of stubs) {
    const paramList: string[] = [];
    if (s.receiverType !== undefined) {
      paramList.push(`instance: ${s.receiverType}`);
    }
    for (const p of s.kestrelParams) {
      paramList.push(`${p.name}: ${p.type}`);
    }
    const paramsStr = paramList.join(', ');
    lines.push(`extern fun ${s.kestrelName}(${paramsStr}): ${s.kestrelReturnType} = jvm("${s.jvmDescriptor}")`);
  }

  lines.push('');
  return lines.join('\n');
}
