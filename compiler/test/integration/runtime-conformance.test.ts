/**
 * Runtime conformance (spec 08 §2.4–2.5, §3.2).
 * Compiles each valid/*.ks to .kbc via dist/cli.js, runs vm/zig-out/bin/kestrel, compares stdout
 * to golden lines from // comments (see helpers/runtime-stdout-goldens.ts).
 */
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { readdirSync, readFileSync, mkdtempSync, mkdirSync, rmSync } from 'fs';
import { join, dirname, basename, resolve } from 'path';
import { fileURLToPath } from 'url';
import { tmpdir } from 'os';
import { execSync } from 'child_process';
import { extractExpectedStdoutLines } from './helpers/runtime-stdout-goldens.js';

const thisDir = dirname(fileURLToPath(import.meta.url));
const compilerRoot = join(thisDir, '..', '..');
const repoRoot = join(compilerRoot, '..');
const runtimeValidDir = join(repoRoot, 'tests', 'conformance', 'runtime', 'valid');
const cliJs = join(compilerRoot, 'dist', 'cli.js');
const vmExe = join(repoRoot, 'vm', 'zig-out', 'bin', 'kestrel');

function listKs(dir: string): string[] {
  try {
    return readdirSync(dir).filter((f) => f.endsWith('.ks')).sort();
  } catch {
    return [];
  }
}

function normalizeStdout(s: string): string {
  return s.replace(/\r\n/g, '\n').replace(/\n$/, '');
}

/** Same layout as `scripts/kestrel` `kbc_path_for`: multi-module .kbc must live under KESTREL_CACHE + abs source dir. */
function kbcCacheOutputPath(ksAbsolute: string, cacheRoot: string): string {
  const absDir = dirname(ksAbsolute);
  const base = basename(ksAbsolute, '.ks');
  const out = join(cacheRoot, absDir, `${base}.kbc`);
  mkdirSync(dirname(out), { recursive: true });
  return out;
}

let testKbcCache: string | undefined;

beforeAll(() => {
  testKbcCache = mkdtempSync(join(tmpdir(), 'kestrel-runtime-kbc-'));
  process.env.KESTREL_CACHE = testKbcCache;
  execSync('zig build -Doptimize=ReleaseSafe', {
    cwd: join(repoRoot, 'vm'),
    stdio: 'pipe',
  });
});

afterAll(() => {
  if (testKbcCache == null) return;
  try {
    rmSync(testKbcCache, { recursive: true, force: true });
  } catch {
    /* temp cleanup best-effort */
  }
});

describe('runtime conformance (valid)', () => {
  const files = listKs(runtimeValidDir);
  if (files.length === 0) {
    it.skip('no runtime valid conformance files', () => {});
    return;
  }
  for (const file of files) {
    it(file, () => {
      const ksPath = resolve(runtimeValidDir, file);
      const source = readFileSync(ksPath, 'utf-8');
      const expectedLines = extractExpectedStdoutLines(source);
      const kbcPath = kbcCacheOutputPath(ksPath, testKbcCache);
      try {
        execSync(`node "${cliJs}" "${ksPath}" -o "${kbcPath}"`, {
          cwd: repoRoot,
          encoding: 'utf-8',
          stdio: ['pipe', 'pipe', 'pipe'],
          env: { ...process.env, KESTREL_CACHE: testKbcCache },
        });
      } catch (e) {
        throw new Error(`Compile failed for ${file}: ${String(e)}`);
      }

      let stdout = '';
      let stderr = '';
      try {
        const out = execSync(`"${vmExe}" "${kbcPath}"`, {
          cwd: repoRoot,
          encoding: 'utf-8',
          stdio: ['pipe', 'pipe', 'pipe'],
        });
        stdout = typeof out === 'string' ? out : out.toString();
      } catch (e: unknown) {
        const err = e as { stdout?: string; stderr?: string; status?: number };
        stdout = err.stdout?.toString() ?? '';
        stderr = err.stderr?.toString() ?? '';
        throw new Error(`VM exit ${err.status} for ${file}. stderr: ${stderr}`);
      }

      expect(stderr.trim(), `stderr should be empty for ${file}`).toBe('');

      const gotLines = normalizeStdout(stdout)
        .split('\n')
        .filter((l) => l.length > 0);
      expect(
        gotLines,
        `stdout line count mismatch for ${file}; expected ${expectedLines.length} non-empty lines`
      ).toEqual(expectedLines);
    });
  }
});
