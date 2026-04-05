/**
 * URL import cache (spec 07 §7).
 *
 * Cache layout: ~/.kestrel/cache/<sha256-of-url>/
 *   source.ks      — the fetched source (written atomically via tmp+rename)
 *   source.ks.tmp  — partial download; cleaned up on next lookup
 *   origin.url     — the absolute URL this file was fetched from
 */
import { createHash } from 'node:crypto';
import {
  existsSync,
  mkdirSync,
  readFileSync,
  statSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { tokenize } from './lexer/index.js';
import { parse } from './parser/index.js';
import type { Program } from './ast/nodes.js';
import { distinctSpecifiersInSourceOrder } from './module-specifiers.js';

// ---------------------------------------------------------------------------
// Cache path helpers
// ---------------------------------------------------------------------------

export function sha256Hex(text: string): string {
  return createHash('sha256').update(text).digest('hex');
}

export function defaultCacheRoot(): string {
  return process.env.KESTREL_CACHE ?? join(homedir(), '.kestrel', 'cache');
}

export function urlCacheDir(url: string, cacheRoot: string): string {
  return join(cacheRoot, sha256Hex(url));
}

export function urlCachePath(url: string, cacheRoot: string): string {
  return join(urlCacheDir(url, cacheRoot), 'source.ks');
}

function urlCacheTmpPath(url: string, cacheRoot: string): string {
  return join(urlCacheDir(url, cacheRoot), 'source.ks.tmp');
}

function originUrlFilePath(cacheDir: string): string {
  return join(cacheDir, 'origin.url');
}

// ---------------------------------------------------------------------------
// Cache state queries
// ---------------------------------------------------------------------------

export function isCached(url: string, cacheRoot: string): boolean {
  return existsSync(urlCachePath(url, cacheRoot));
}

const DEFAULT_TTL_SECS = 604_800; // 7 days

export function defaultTtlSecs(): number {
  const env = process.env.KESTREL_CACHE_TTL;
  if (env) {
    const n = Number(env);
    if (Number.isFinite(n) && n > 0) return n;
  }
  return DEFAULT_TTL_SECS;
}

export function isStale(url: string, cacheRoot: string, ttlSecs: number): boolean {
  const p = urlCachePath(url, cacheRoot);
  if (!existsSync(p)) return false;
  const mtimeMs = statSync(p).mtimeMs;
  const ageMs = Date.now() - mtimeMs;
  return ageMs > ttlSecs * 1000;
}

/** Remove a stale .tmp file if it exists without a corresponding source.ks. */
export function cleanStaleTemp(cacheDir: string): void {
  const tmp = join(cacheDir, 'source.ks.tmp');
  const final = join(cacheDir, 'source.ks');
  if (existsSync(tmp) && !existsSync(final)) {
    unlinkSync(tmp);
  }
}

/** Read origin URL from origin.url in the same directory as a cached source file. */
export function readOriginUrl(cachedFilePath: string): string | null {
  const originFile = originUrlFilePath(dirname(cachedFilePath));
  if (!existsSync(originFile)) return null;
  const text = readFileSync(originFile, 'utf-8').trim();
  return text || null;
}

// ---------------------------------------------------------------------------
// URL resolution (RFC 3986 via Node.js URL class)
// ---------------------------------------------------------------------------

export type RelativeUrlResult =
  | { ok: true; url: string }
  | { ok: false; reason: 'cross-origin' | 'invalid' };

/**
 * Resolve a relative specifier against a base URL.
 * Returns `{ ok: false, reason: 'cross-origin' }` if the result would change
 * scheme or host (path traversal escape), and `{ ok: false, reason: 'invalid' }`
 * if the URL cannot be parsed.
 */
export function resolveRelativeUrl(baseUrl: string, relSpec: string): RelativeUrlResult {
  let base: URL;
  try {
    base = new URL(baseUrl);
  } catch {
    return { ok: false, reason: 'invalid' };
  }
  let resolved: URL;
  try {
    resolved = new URL(relSpec, base);
  } catch {
    return { ok: false, reason: 'invalid' };
  }
  if (resolved.protocol !== base.protocol || resolved.host !== base.host) {
    return { ok: false, reason: 'cross-origin' };
  }
  return { ok: true, url: resolved.href };
}

// ---------------------------------------------------------------------------
// Fetch and cache
// ---------------------------------------------------------------------------

export interface FetchOptions {
  allowHttp: boolean;
  refresh: boolean;
  cacheRoot: string;
}

export async function fetchToCache(
  url: string,
  opts: FetchOptions
): Promise<{ ok: true; path: string } | { ok: false; error: string }> {
  const { cacheRoot, allowHttp, refresh } = opts;

  // Protocol check
  if (url.startsWith('http://') && !allowHttp) {
    return { ok: false, error: `http:// imports are not allowed; use https:// or pass --allow-http (${url})` };
  }
  if (!url.startsWith('https://') && !url.startsWith('http://')) {
    return { ok: false, error: `unsupported URL scheme: ${url}` };
  }

  const cacheDir = urlCacheDir(url, cacheRoot);
  const finalPath = join(cacheDir, 'source.ks');
  const tmpPath = join(cacheDir, 'source.ks.tmp');
  const originPath = originUrlFilePath(cacheDir);

  // Clean up stale partial download
  cleanStaleTemp(cacheDir);

  // Cache hit (non-refresh)
  if (!refresh && existsSync(finalPath)) {
    return { ok: true, path: finalPath };
  }

  // Ensure cache directory exists
  mkdirSync(cacheDir, { recursive: true });

  // Write origin.url before fetching (idempotent: always the same value)
  writeFileSync(originPath, url, 'utf-8');

  // Fetch
  let text: string;
  try {
    const response = await fetch(url, {
      redirect: 'follow',
      headers: { 'User-Agent': 'kestrel-compiler/1.0' },
    });

    // Guard against cross-host redirects
    const finalUrlStr = response.url;
    if (finalUrlStr) {
      let finalUrl: URL;
      try {
        finalUrl = new URL(finalUrlStr);
        const orig = new URL(url);
        if (finalUrl.host !== orig.host) {
          return { ok: false, error: `URL ${url} redirected to a different host (${finalUrl.host}); cross-host redirects are not allowed` };
        }
      } catch {
        // URL parse failed — allow through
      }
    }

    if (!response.ok) {
      return { ok: false, error: `HTTP ${response.status} fetching ${url}` };
    }
    text = await response.text();
  } catch (e) {
    return { ok: false, error: `Failed to fetch ${url}: ${e instanceof Error ? e.message : String(e)}` };
  }

  // Atomic write: tmp then rename
  writeFileSync(tmpPath, text, 'utf-8');
  renameSync(tmpPath, finalPath);

  return { ok: true, path: finalPath };
}

// ---------------------------------------------------------------------------
// Pre-fetch BFS
// ---------------------------------------------------------------------------

export interface PrefetchError {
  url: string;
  error: string;
  /** Absolute path of the file that contains this import */
  importingFile: string;
  /** Byte offsets of the import specifier in the source, if known */
  span?: { start: number; end: number };
}

/**
 * BFS over all URL imports reachable from entryPath.
 * Returns errors (compile-error candidates) if any fetches failed.
 * All reachable URLs are written to the cache before returning.
 */
export async function prefetchUrlDependencies(
  entryPath: string,
  opts: FetchOptions
): Promise<PrefetchError[]> {
  const { cacheRoot } = opts;
  const errors: PrefetchError[] = [];

  // Each queue item is either:
  //  - { kind: 'local', filePath } — a local .ks file
  //  - { kind: 'url', url, cachedPath, importingFile } — a URL-fetched file
  type QueueItem =
    | { kind: 'local'; filePath: string }
    | { kind: 'url'; url: string; cachedPath: string; importingFile: string };

  const visited = new Set<string>(); // URLs visited (to avoid re-processing)
  const queue: QueueItem[] = [{ kind: 'local', filePath: entryPath }];

  function parseSource(filePath: string): Program | null {
    try {
      const source = readFileSync(filePath, 'utf-8');
      const tokens = tokenize(source);
      const result = parse(tokens);
      if (!('imports' in result)) return null;
      return result as Program;
    } catch {
      return null;
    }
  }

  while (queue.length > 0) {
    const item = queue.shift()!;
    const filePath = item.kind === 'local' ? item.filePath : item.cachedPath;

    const program = parseSource(filePath);
    if (!program) continue;

    // Determine base URL for URL-fetched items (needed to resolve relative specs)
    const baseUrl: string | null = item.kind === 'url' ? item.url : readOriginUrl(filePath);

    const specs = distinctSpecifiersInSourceOrder(program);

    for (const spec of specs) {
      // Determine if this spec is a URL import
      let absoluteUrl: string | null = null;

      if (spec.startsWith('https://') || spec.startsWith('http://')) {
        absoluteUrl = spec;
      } else if (
        baseUrl &&
        (spec.startsWith('./') || spec.startsWith('../'))
      ) {
        // Relative import inside a URL-fetched module
        const result = resolveRelativeUrl(baseUrl, spec);
        if (!result.ok) {
          errors.push({
            url: spec,
            error:
              result.reason === 'cross-origin'
                ? `relative import '${spec}' in remote module ${baseUrl} would escape the origin; cross-origin path traversal is not allowed`
                : `cannot resolve relative import '${spec}' in remote module ${baseUrl}`,
            importingFile: filePath,
          });
          continue;
        }
        absoluteUrl = result.url;
      }

      if (!absoluteUrl) continue; // not a URL import
      if (visited.has(absoluteUrl)) continue;
      visited.add(absoluteUrl);

      const fetchResult = await fetchToCache(absoluteUrl, opts);
      if (!fetchResult.ok) {
        errors.push({ url: absoluteUrl, error: fetchResult.error, importingFile: filePath });
        continue;
      }

      queue.push({ kind: 'url', url: absoluteUrl, cachedPath: fetchResult.path, importingFile: filePath });
    }
  }

  return errors;
}

// ---------------------------------------------------------------------------
// Status report
// ---------------------------------------------------------------------------

export interface UrlStatusEntry {
  url: string;
  cached: boolean;
  ageMs: number | null;
  stale: boolean;
}

/**
 * Walk the URL dependency graph and collect cache status for each URL.
 * Does NOT fetch anything.
 */
export async function buildStatusEntries(
  entryPath: string,
  cacheRoot: string,
  ttlSecs: number
): Promise<UrlStatusEntry[]> {
  const entries: UrlStatusEntry[] = [];
  const visited = new Set<string>();

  type QueueItem =
    | { kind: 'local'; filePath: string }
    | { kind: 'url'; url: string; cachedPath: string };

  const queue: QueueItem[] = [{ kind: 'local', filePath: entryPath }];

  function parseSource(filePath: string): Program | null {
    try {
      const source = readFileSync(filePath, 'utf-8');
      const tokens = tokenize(source);
      const result = parse(tokens);
      if (!('imports' in result)) return null;
      return result as Program;
    } catch {
      return null;
    }
  }

  while (queue.length > 0) {
    const item = queue.shift()!;
    const filePath = item.kind === 'local' ? item.filePath : item.cachedPath;

    const program = parseSource(filePath);
    if (!program) continue;

    const baseUrl: string | null =
      item.kind === 'url' ? item.url : readOriginUrl(filePath);

    const specs = distinctSpecifiersInSourceOrder(program);

    for (const spec of specs) {
      let absoluteUrl: string | null = null;

      if (spec.startsWith('https://') || spec.startsWith('http://')) {
        absoluteUrl = spec;
      } else if (baseUrl && (spec.startsWith('./') || spec.startsWith('../'))) {
        const result = resolveRelativeUrl(baseUrl, spec);
        if (!result.ok) continue;
        absoluteUrl = result.url;
      }

      if (!absoluteUrl) continue;
      if (visited.has(absoluteUrl)) continue;
      visited.add(absoluteUrl);

      const cached = isCached(absoluteUrl, cacheRoot);
      let ageMs: number | null = null;
      let stale = false;

      if (cached) {
        const p = urlCachePath(absoluteUrl, cacheRoot);
        ageMs = Date.now() - statSync(p).mtimeMs;
        stale = ageMs > ttlSecs * 1000;
      }

      entries.push({ url: absoluteUrl, cached, ageMs, stale });

      if (cached) {
        const cachedPath = urlCachePath(absoluteUrl, cacheRoot);
        queue.push({ kind: 'url', url: absoluteUrl, cachedPath });
      }
    }
  }

  return entries;
}

function formatAge(ageMs: number): string {
  const secs = Math.floor(ageMs / 1000);
  if (secs < 60) return `${secs}s ago`;
  const mins = Math.floor(secs / 60);
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  return `${days} day${days === 1 ? '' : 's'} ago`;
}

export function formatStatusReport(entries: UrlStatusEntry[]): string {
  if (entries.length === 0) {
    return '(no URL dependencies)';
  }
  const lines = entries.map((e) => {
    const status = e.cached ? '\u2713 cached' : '\u2717 not cached';
    const age = e.cached && e.ageMs != null ? `  ${formatAge(e.ageMs)}` : '  \u2014';
    const stale = e.stale ? '  \u26a0 stale' : '';
    return `${e.url.padEnd(60)}  ${status}${age}${stale}`;
  });
  return lines.join('\n');
}
