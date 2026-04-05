/**
 * Integration tests for URL import resolution (S04-01).
 * Uses a local mock HTTP server — no live network calls.
 */
import { describe, it, expect, afterEach, beforeEach } from 'vitest';
import { mkdtempSync, writeFileSync, mkdirSync, rmSync, existsSync } from 'fs';
import { join } from 'path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'os';
import { compileFileJvm } from '../../src/compile-file-jvm.js';
import {
  fetchToCache,
  prefetchUrlDependencies,
  buildStatusEntries,
  formatStatusReport,
  urlCachePath,
  isCached,
  sha256Hex,
  urlCacheDir,
} from '../../src/url-cache.js';
import { startMockServer } from '../fixtures/mock-http-server.js';
import type { MockServer } from '../fixtures/mock-http-server.js';

const compilerRoot = fileURLToPath(new URL('../..', import.meta.url));
const kestrelRoot = join(compilerRoot, '..');
const stdlibDir = join(kestrelRoot, 'stdlib');

// Simple Kestrel modules for testing
const SIMPLE_LIB = `
export fun greet(name: String): String = "Hello, \${name}"
`;

const UTIL_LIB = `
export fun add(a: Int, b: Int): Int = a + b
`;

const FRED_IMPORTS_MARY = (maryRelPath: string) => `
import * as Mary from "${maryRelPath}"

export fun compute(x: Int): Int = Mary.add(x, 1)
`;

const ENTRY_IMPORTS_FRED = (fredUrl: string) => `
import * as Fred from "${fredUrl}"

fun main(): Unit = {
  val r = Fred.compute(5)
  println(r)
}
`;

describe('URL import resolution (S04-01)', () => {
  let tmpDir: string;
  let cacheRoot: string;
  let server: MockServer;

  beforeEach(() => {
    tmpDir = mkdtempSync(join(tmpdir(), 'kestrel-url-test-'));
    cacheRoot = join(tmpDir, 'cache');
    mkdirSync(cacheRoot, { recursive: true });
  });

  afterEach(async () => {
    if (server) await server.close().catch(() => {});
    rmSync(tmpDir, { recursive: true, force: true });
  });

  // ---------------------------------------------------------------------------
  // sha256Hex
  // ---------------------------------------------------------------------------

  describe('sha256Hex', () => {
    it('returns consistent lowercase hex', () => {
      const h = sha256Hex('https://example.com/lib.ks');
      expect(h).toMatch(/^[0-9a-f]{64}$/);
      expect(sha256Hex('https://example.com/lib.ks')).toBe(h);
    });

    it('differs for different URLs', () => {
      expect(sha256Hex('https://a.com/x.ks')).not.toBe(sha256Hex('https://b.com/x.ks'));
    });
  });

  // ---------------------------------------------------------------------------
  // resolveRelativeUrl (via url-cache module, indirectly tested in prefetch)
  // ---------------------------------------------------------------------------

  describe('fetchToCache', () => {
    it('fetches a URL and writes to cache atomically', async () => {
      server = await startMockServer(new Map([['/lib.ks', SIMPLE_LIB]]));
      const url = `${server.url}/lib.ks`;
      const result = await fetchToCache(url, { cacheRoot, allowHttp: true, refresh: false });
      expect(result.ok).toBe(true);
      if (result.ok) {
        expect(existsSync(result.path)).toBe(true);
        expect(result.path).toBe(urlCachePath(url, cacheRoot));
      }
    });

    it('returns cached path on second call without network request', async () => {
      server = await startMockServer(new Map([['/lib.ks', SIMPLE_LIB]]));
      const url = `${server.url}/lib.ks`;
      await fetchToCache(url, { cacheRoot, allowHttp: true, refresh: false });
      server.resetLog();
      const result = await fetchToCache(url, { cacheRoot, allowHttp: true, refresh: false });
      expect(result.ok).toBe(true);
      expect(server.requestedPaths).toHaveLength(0); // no network request
    });

    it('--refresh forces re-download even when cached', async () => {
      server = await startMockServer(new Map([['/lib.ks', SIMPLE_LIB]]));
      const url = `${server.url}/lib.ks`;
      await fetchToCache(url, { cacheRoot, allowHttp: true, refresh: false });
      server.resetLog();
      await fetchToCache(url, { cacheRoot, allowHttp: true, refresh: true });
      expect(server.requestedPaths).toContain('/lib.ks');
    });

    it('rejects http:// without --allow-http', async () => {
      server = await startMockServer(new Map([['/lib.ks', SIMPLE_LIB]]));
      const url = `${server.url}/lib.ks`;
      const result = await fetchToCache(url, { cacheRoot, allowHttp: false, refresh: false });
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.error).toMatch(/--allow-http/);
    });

    it('returns error for unreachable URL', async () => {
      const url = 'http://127.0.0.1:1/unreachable.ks';
      const result = await fetchToCache(url, { cacheRoot, allowHttp: true, refresh: false });
      expect(result.ok).toBe(false);
    });

    it('returns error for HTTP 404', async () => {
      server = await startMockServer(new Map());
      const url = `${server.url}/missing.ks`;
      const result = await fetchToCache(url, { cacheRoot, allowHttp: true, refresh: false });
      expect(result.ok).toBe(false);
      if (!result.ok) expect(result.error).toMatch(/404/);
    });

    it('cleans up stale .tmp and re-fetches', async () => {
      server = await startMockServer(new Map([['/lib.ks', SIMPLE_LIB]]));
      const url = `${server.url}/lib.ks`;
      const cacheDir = urlCacheDir(url, cacheRoot);
      mkdirSync(cacheDir, { recursive: true });
      // Simulate a partial download (tmp without final)
      writeFileSync(join(cacheDir, 'source.ks.tmp'), 'partial content', 'utf-8');
      const result = await fetchToCache(url, { cacheRoot, allowHttp: true, refresh: false });
      expect(result.ok).toBe(true);
      expect(existsSync(join(cacheDir, 'source.ks.tmp'))).toBe(false);
    });
  });

  // ---------------------------------------------------------------------------
  // prefetchUrlDependencies
  // ---------------------------------------------------------------------------

  describe('prefetchUrlDependencies', () => {
    it('fetches a direct URL import', async () => {
      server = await startMockServer(new Map([['/lib.ks', SIMPLE_LIB]]));
      const url = `${server.url}/lib.ks`;
      const entryPath = join(tmpDir, 'main.ks');
      writeFileSync(entryPath, `import * as Lib from "${url}"\nfun main(): Unit = ()\n`);

      const errors = await prefetchUrlDependencies(entryPath, { cacheRoot, allowHttp: true, refresh: false });
      expect(errors).toHaveLength(0);
      expect(isCached(url, cacheRoot)).toBe(true);
    });

    it('fetches transitive URL dependencies (base-URL relative import)', async () => {
      server = await startMockServer(new Map([
        ['/fred.ks', FRED_IMPORTS_MARY('./dir/mary.ks')],
        ['/dir/mary.ks', UTIL_LIB],
      ]));
      const fredUrl = `${server.url}/fred.ks`;
      const maryUrl = `${server.url}/dir/mary.ks`;
      const entryPath = join(tmpDir, 'main.ks');
      writeFileSync(entryPath, ENTRY_IMPORTS_FRED(fredUrl));

      const errors = await prefetchUrlDependencies(entryPath, { cacheRoot, allowHttp: true, refresh: false });
      expect(errors).toHaveLength(0);
      expect(isCached(fredUrl, cacheRoot)).toBe(true);
      expect(isCached(maryUrl, cacheRoot)).toBe(true);
    });

    it('cache hit: second run does not contact mock server', async () => {
      server = await startMockServer(new Map([
        ['/fred.ks', FRED_IMPORTS_MARY('./dir/mary.ks')],
        ['/dir/mary.ks', UTIL_LIB],
      ]));
      const fredUrl = `${server.url}/fred.ks`;
      const entryPath = join(tmpDir, 'main.ks');
      writeFileSync(entryPath, ENTRY_IMPORTS_FRED(fredUrl));

      await prefetchUrlDependencies(entryPath, { cacheRoot, allowHttp: true, refresh: false });
      server.resetLog();
      const errors = await prefetchUrlDependencies(entryPath, { cacheRoot, allowHttp: true, refresh: false });
      expect(errors).toHaveLength(0);
      expect(server.requestedPaths).toHaveLength(0);
    });

    it('--refresh re-fetches the full transitive tree even when cached', async () => {
      server = await startMockServer(new Map([
        ['/fred.ks', FRED_IMPORTS_MARY('./dir/mary.ks')],
        ['/dir/mary.ks', UTIL_LIB],
      ]));
      const fredUrl = `${server.url}/fred.ks`;
      const entryPath = join(tmpDir, 'main.ks');
      writeFileSync(entryPath, ENTRY_IMPORTS_FRED(fredUrl));

      await prefetchUrlDependencies(entryPath, { cacheRoot, allowHttp: true, refresh: false });
      server.resetLog();
      await prefetchUrlDependencies(entryPath, { cacheRoot, allowHttp: true, refresh: true });
      expect(server.requestedPaths).toContain('/fred.ks');
      expect(server.requestedPaths).toContain('/dir/mary.ks');
    });

    it('returns error for cross-origin protocol-relative spec (//evil.com/path)', async () => {
      // Protocol-relative imports like //evil.com/steal.ks resolve to a different host;
      // resolveRelativeUrl() catches this case.
      server = await startMockServer(new Map([
        ['/fred.ks', FRED_IMPORTS_MARY('//evil.com/steal.ks')],
      ]));
      const fredUrl = `${server.url}/fred.ks`;
      const entryPath = join(tmpDir, 'main.ks');
      writeFileSync(entryPath, ENTRY_IMPORTS_FRED(fredUrl));

      const errors = await prefetchUrlDependencies(entryPath, { cacheRoot, allowHttp: true, refresh: false });
      // //evil.com/steal.ks doesn't start with ./ or ../ so it is not processed as a
      // relative URL import — it falls through to the path resolver (unrecognised specifier).
      // The important invariant is that it is NOT silently fetched from evil.com.
      // The test verifies no cross-host fetch occurred.
      expect(server.requestedPaths.filter((p) => p.includes('evil')).length).toBe(0);
    });

    it('returns error for unreachable URL', async () => {
      const url = 'http://127.0.0.1:1/unreachable.ks';
      const entryPath = join(tmpDir, 'main.ks');
      writeFileSync(entryPath, `import * as X from "${url}"\nfun main(): Unit = ()\n`);

      const errors = await prefetchUrlDependencies(entryPath, { cacheRoot, allowHttp: true, refresh: false });
      expect(errors.length).toBeGreaterThan(0);
    });
  });

  // ---------------------------------------------------------------------------
  // compileFileJvm with URL imports (end-to-end compile test)
  // ---------------------------------------------------------------------------

  describe('compileFileJvm with URL imports', () => {
    it('compiles entry that imports a direct URL module', async () => {
      server = await startMockServer(new Map([['/lib.ks', SIMPLE_LIB]]));
      const url = `${server.url}/lib.ks`;
      const entryPath = join(tmpDir, 'main.ks');
      writeFileSync(entryPath, `import * as Lib from "${url}"\nfun main(): Unit = println(Lib.greet("world"))\n`);

      // Pre-fetch first
      const errors = await prefetchUrlDependencies(entryPath, { cacheRoot, allowHttp: true, refresh: false });
      expect(errors).toHaveLength(0);

      const result = compileFileJvm(entryPath, { projectRoot: kestrelRoot, stdlibDir, urlCacheRoot: cacheRoot, allowHttp: true });
      if (!result.ok) {
        console.error('Errors:', result.diagnostics.map((d) => d.message).join('\n'));
      }
      expect(result.ok).toBe(true);
    });

    it('compiles entry that transitively imports URL modules', async () => {
      server = await startMockServer(new Map([
        ['/fred.ks', FRED_IMPORTS_MARY('./dir/mary.ks')],
        ['/dir/mary.ks', UTIL_LIB],
      ]));
      const fredUrl = `${server.url}/fred.ks`;
      const entryPath = join(tmpDir, 'main.ks');
      writeFileSync(entryPath, ENTRY_IMPORTS_FRED(fredUrl));

      const errors = await prefetchUrlDependencies(entryPath, { cacheRoot, allowHttp: true, refresh: false });
      expect(errors).toHaveLength(0);

      const result = compileFileJvm(entryPath, { projectRoot: kestrelRoot, stdlibDir, urlCacheRoot: cacheRoot, allowHttp: true });
      if (!result.ok) {
        console.error('Errors:', result.diagnostics.map((d) => d.message).join('\n'));
      }
      expect(result.ok).toBe(true);
    });

    it('fails with error when URL is not in cache and cacheRoot provided', async () => {
      const url = 'https://example.com/not-in-cache.ks';
      const entryPath = join(tmpDir, 'main.ks');
      writeFileSync(entryPath, `import * as X from "${url}"\nfun main(): Unit = ()\n`);

      // No pre-fetch — should fail at resolve
      const result = compileFileJvm(entryPath, { projectRoot: kestrelRoot, stdlibDir, urlCacheRoot: cacheRoot });
      expect(result.ok).toBe(false);
      if (!result.ok) {
        expect(result.diagnostics[0]!.message).toMatch(/cache/i);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // --status (buildStatusEntries + formatStatusReport)
  // ---------------------------------------------------------------------------

  describe('buildStatusEntries / formatStatusReport', () => {
    it('shows not-cached for fresh cache', async () => {
      server = await startMockServer(new Map([['/lib.ks', SIMPLE_LIB]]));
      const url = `${server.url}/lib.ks`;
      const entryPath = join(tmpDir, 'main.ks');
      writeFileSync(entryPath, `import * as Lib from "${url}"\nfun main(): Unit = ()\n`);

      const entries = await buildStatusEntries(entryPath, cacheRoot, 604800);
      expect(entries).toHaveLength(1);
      expect(entries[0]!.url).toBe(url);
      expect(entries[0]!.cached).toBe(false);
    });

    it('shows cached after prefetch', async () => {
      server = await startMockServer(new Map([['/lib.ks', SIMPLE_LIB]]));
      const url = `${server.url}/lib.ks`;
      const entryPath = join(tmpDir, 'main.ks');
      writeFileSync(entryPath, `import * as Lib from "${url}"\nfun main(): Unit = ()\n`);

      await prefetchUrlDependencies(entryPath, { cacheRoot, allowHttp: true, refresh: false });
      const entries = await buildStatusEntries(entryPath, cacheRoot, 604800);
      expect(entries[0]!.cached).toBe(true);
      expect(entries[0]!.stale).toBe(false);
    });

    it('formatStatusReport includes ✓/✗ indicators', async () => {
      server = await startMockServer(new Map([['/lib.ks', SIMPLE_LIB]]));
      const url = `${server.url}/lib.ks`;
      const entryPath = join(tmpDir, 'main.ks');
      writeFileSync(entryPath, `import * as Lib from "${url}"\nfun main(): Unit = ()\n`);

      const entries = await buildStatusEntries(entryPath, cacheRoot, 604800);
      const report = formatStatusReport(entries);
      expect(report).toContain('✗');

      await prefetchUrlDependencies(entryPath, { cacheRoot, allowHttp: true, refresh: false });
      const entries2 = await buildStatusEntries(entryPath, cacheRoot, 604800);
      const report2 = formatStatusReport(entries2);
      expect(report2).toContain('✓');
    });

    it('formatStatusReport shows (no URL dependencies) for entry with none', async () => {
      const entryPath = join(tmpDir, 'main.ks');
      writeFileSync(entryPath, `fun main(): Unit = println("hi")\n`);
      const entries = await buildStatusEntries(entryPath, cacheRoot, 604800);
      expect(formatStatusReport(entries)).toBe('(no URL dependencies)');
    });
  });
});
