/**
 * Module specifier resolution (spec 07 §4).
 * Maps specifiers to absolute paths for .ks source files.
 */
import { resolve as pathResolve, dirname, join } from 'path';
import { existsSync } from 'fs';
import { urlCachePath, readOriginUrl, resolveRelativeUrl } from './url-cache.js';

/** Map stdlib specifier to relative path segment (e.g. kestrel:string -> kestrel/string.ks). */
function stdlibSpecToPath(spec: string): string | null {
  if (!spec.startsWith('kestrel:')) return null;
  const rest = spec.slice('kestrel:'.length);
  if (!rest) return null;
  // Validate each path segment: alphanum, underscore, hyphen only; no '..' traversal
  const segments = rest.split('/');
  for (const seg of segments) {
    if (!seg || !/^[a-zA-Z0-9_-]+$/.test(seg)) return null;
  }
  return `kestrel/${segments.join('/')}.ks`;
}

export interface ResolveOptions {
  /** Absolute path of the current source file (for resolving relative imports). */
  fromFile: string;
  /** Root directory for the project (used to find stdlib). Default: dirname of compiler. */
  projectRoot?: string;
  /** Path to stdlib directory. Default: projectRoot/stdlib or resolved relative to compiler. */
  stdlibDir?: string;
  /**
   * Root directory for the URL import cache (spec 07 §7).
   * Default: ~/.kestrel/cache/ (via defaultCacheRoot() in url-cache.ts).
   * Only used when resolving https:// or http:// specifiers.
   */
  cacheRoot?: string;
}

/** Resolve a specifier to an absolute path to a .ks file. */
export function resolveSpecifier(spec: string, options: ResolveOptions): { ok: true; path: string } | { ok: false; error: string } {
  // Stdlib: kestrel:string, kestrel:stack, kestrel:data/list, etc.
  const stdlibPath = stdlibSpecToPath(spec);
  if (stdlibPath !== null) {
    const stdlibDir = options.stdlibDir ?? (options.projectRoot ? join(options.projectRoot, 'stdlib') : null);
    if (!stdlibDir) {
      return { ok: false, error: `stdlib path not configured; cannot resolve ${spec}` };
    }
    const abs = pathResolve(stdlibDir, stdlibPath);
    if (!existsSync(abs)) {
      return { ok: false, error: `unknown stdlib module '${spec}'; expected file at ${abs}` };
    }
    return { ok: true, path: abs };
  }

  // URL specifiers: resolve from cache (pre-fetch phase must have populated it)
  if (spec.startsWith('https://') || spec.startsWith('http://')) {
    if (!options.cacheRoot) {
      return { ok: false, error: `URL import '${spec}' requires cacheRoot to be configured` };
    }
    const cached = urlCachePath(spec, options.cacheRoot);
    if (!existsSync(cached)) {
      return { ok: false, error: `URL import '${spec}' is not in the cache; run again or check network access` };
    }
    return { ok: true, path: cached };
  }

  // Relative path imports inside URL-fetched modules
  // fromFile may be a cache path that has a sibling origin.url
  if (spec.startsWith('./') || spec.startsWith('../')) {
    const originUrl = readOriginUrl(options.fromFile);
    if (originUrl) {
      // This import is inside a URL-fetched module — resolve against base URL
      const result = resolveRelativeUrl(originUrl, spec);
      if (!result.ok) {
        if (result.reason === 'cross-origin') {
          return { ok: false, error: `relative import '${spec}' in remote module ${originUrl} would escape the origin; cross-origin path traversal is not allowed` };
        }
        return { ok: false, error: `cannot resolve relative import '${spec}' against base URL ${originUrl}` };
      }
      const resolvedUrl = result.url;
      if (!options.cacheRoot) {
        return { ok: false, error: `URL import '${resolvedUrl}' (resolved from '${spec}') requires cacheRoot to be configured` };
      }
      const cached = urlCachePath(resolvedUrl, options.cacheRoot);
      if (!existsSync(cached)) {
        return { ok: false, error: `URL import '${resolvedUrl}' (resolved from '${spec}') is not in the cache` };
      }
      return { ok: true, path: cached };
    }
  }

  // Path: relative or absolute (local filesystem)
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

