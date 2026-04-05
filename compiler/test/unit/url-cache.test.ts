/**
 * Unit tests for url-cache helpers (S04-01).
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { sha256Hex, resolveRelativeUrl, isCached, isStale, urlCachePath, urlCacheDir } from '../../src/url-cache.js';
import { mkdtempSync, mkdirSync, writeFileSync, utimesSync, rmSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

describe('sha256Hex', () => {
  it('returns 64-char lowercase hex', () => {
    const h = sha256Hex('https://example.com/lib.ks');
    expect(h).toHaveLength(64);
    expect(h).toMatch(/^[0-9a-f]+$/);
  });

  it('is deterministic', () => {
    expect(sha256Hex('https://a.com/x.ks')).toBe(sha256Hex('https://a.com/x.ks'));
  });

  it('differs for different inputs', () => {
    expect(sha256Hex('https://a.com/x.ks')).not.toBe(sha256Hex('https://b.com/x.ks'));
  });
});

describe('resolveRelativeUrl', () => {
  it('resolves ./dir/mary.ks against base URL', () => {
    const result = resolveRelativeUrl('https://example.com/fred.ks', './dir/mary.ks');
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.url).toBe('https://example.com/dir/mary.ks');
  });

  it('resolves ../util.ks against base URL', () => {
    const result = resolveRelativeUrl('https://example.com/path/fred.ks', '../util.ks');
    expect(result.ok).toBe(true);
    if (result.ok) expect(result.url).toBe('https://example.com/util.ks');
  });

  it('returns cross-origin for protocol-relative spec //evil.com/path.ks', () => {
    const result = resolveRelativeUrl('https://example.com/fred.ks', '//evil.com/path.ks');
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe('cross-origin');
  });

  it('returns cross-origin for absolute URL to different host inside relative context', () => {
    // Although this won't start with ./ or ../, the guard catches it
    const result = resolveRelativeUrl('https://example.com/fred.ks', 'https://evil.com/steal.ks');
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe('cross-origin');
  });

  it('returns invalid for a malformed base URL', () => {
    const result = resolveRelativeUrl('not-a-url', './path.ks');
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.reason).toBe('invalid');
  });

  it('same host same path is ok', () => {
    const result = resolveRelativeUrl('https://a.com/x/y.ks', './z.ks');
    expect(result.ok).toBe(true);
  });
});

describe('isCached / isStale', () => {
  let tmpDir: string;
  let cacheRoot: string;

  beforeEach(() => {
    tmpDir = mkdtempSync(join(tmpdir(), 'kestrel-url-cache-unit-'));
    cacheRoot = join(tmpDir, 'cache');
    mkdirSync(cacheRoot, { recursive: true });
  });

  afterEach(() => {
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it('isCached returns false when source.ks absent', () => {
    expect(isCached('https://example.com/lib.ks', cacheRoot)).toBe(false);
  });

  it('isCached returns true after writing source.ks', () => {
    const url = 'https://example.com/lib.ks';
    const dir = urlCacheDir(url, cacheRoot);
    mkdirSync(dir, { recursive: true });
    writeFileSync(urlCachePath(url, cacheRoot), 'content');
    expect(isCached(url, cacheRoot)).toBe(true);
  });

  it('isStale returns false for fresh file', () => {
    const url = 'https://example.com/lib.ks';
    const dir = urlCacheDir(url, cacheRoot);
    mkdirSync(dir, { recursive: true });
    writeFileSync(urlCachePath(url, cacheRoot), 'content');
    expect(isStale(url, cacheRoot, 3600)).toBe(false);
  });

  it('isStale returns true for file older than TTL', () => {
    const url = 'https://example.com/lib.ks';
    const dir = urlCacheDir(url, cacheRoot);
    mkdirSync(dir, { recursive: true });
    const p = urlCachePath(url, cacheRoot);
    writeFileSync(p, 'content');
    // Backdate mtime by 2 hours
    const old = new Date(Date.now() - 2 * 3600 * 1000);
    utimesSync(p, old, old);
    expect(isStale(url, cacheRoot, 3600)).toBe(true);
  });
});
