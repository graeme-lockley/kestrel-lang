/**
 * Module specifier resolution (spec 07 §4).
 * Maps specifiers to absolute paths for .ks source files.
 */
import { resolve as pathResolve, dirname, join } from 'path';
import { existsSync } from 'fs';

/** Stdlib module names from spec 02 / 07. */
const STDLIB_NAMES = [
  'kestrel:string', 'kestrel:char', 'kestrel:stack', 'kestrel:http', 'kestrel:json', 'kestrel:fs',
  'kestrel:option', 'kestrel:result', 'kestrel:list', 'kestrel:value', 'kestrel:test',
  'kestrel:process', 'kestrel:console',
] as const;

/** Map stdlib specifier to path segment (e.g. kestrel:string -> kestrel/string.ks). */
function stdlibSpecToPath(spec: string): string | null {
  if (!STDLIB_NAMES.includes(spec as (typeof STDLIB_NAMES)[number])) return null;
  const [, mod] = spec.split(':');
  return `kestrel/${mod}.ks`;
}

export interface ResolveOptions {
  /** Absolute path of the current source file (for resolving relative imports). */
  fromFile: string;
  /** Root directory for the project (used to find stdlib). Default: dirname of compiler. */
  projectRoot?: string;
  /** Path to stdlib directory. Default: projectRoot/stdlib or resolved relative to compiler. */
  stdlibDir?: string;
}

/** Resolve a specifier to an absolute path to a .ks file. */
export function resolveSpecifier(spec: string, options: ResolveOptions): { ok: true; path: string } | { ok: false; error: string } {
  // Stdlib: kestrel:string, kestrel:stack, etc.
  const stdlibPath = stdlibSpecToPath(spec);
  if (stdlibPath) {
    const stdlibDir = options.stdlibDir ?? (options.projectRoot ? join(options.projectRoot, 'stdlib') : null);
    if (!stdlibDir) {
      return { ok: false, error: `stdlib path not configured; cannot resolve ${spec}` };
    }
    const abs = pathResolve(stdlibDir, stdlibPath);
    if (!existsSync(abs)) {
      return { ok: false, error: `stdlib module not found: ${spec} (expected ${abs})` };
    }
    return { ok: true, path: abs };
  }

  // URL specifiers: not implemented
  if (spec.startsWith('http://') || spec.startsWith('https://')) {
    return { ok: false, error: `URL imports not yet supported: ${spec}` };
  }

  // Path: relative or absolute
  const fromDir = dirname(options.fromFile);
  let resolved: string;
  if (spec.startsWith('/')) {
    resolved = spec.endsWith('.ks') ? spec : `${spec}.ks`;
  } else {
    const joined = join(fromDir, spec);
    resolved = spec.endsWith('.ks') ? joined : `${joined}.ks`;
  }
  const absPath = pathResolve(resolved);
  if (!existsSync(absPath)) {
    return { ok: false, error: `Module not found: ${spec} (resolved to ${absPath})` };
  }
  return { ok: true, path: absPath };
}
