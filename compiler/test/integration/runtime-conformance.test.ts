/**
 * Runtime conformance (spec 08 §2.4–2.5, §3.2).
 * Compiles each valid/*.ks to JVM classes via dist/cli.js, runs them on the JVM, compares stdout
 * to golden lines from // comments (see helpers/runtime-stdout-goldens.ts).
 */
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { readdirSync, readFileSync, mkdtempSync, rmSync } from 'fs';
import { join, dirname, resolve } from 'path';
import { fileURLToPath } from 'url';
import { tmpdir } from 'os';
import { execSync } from 'child_process';
import { extractExpectedStdoutLines } from './helpers/runtime-stdout-goldens.js';

const thisDir = dirname(fileURLToPath(import.meta.url));
const compilerRoot = join(thisDir, '..', '..');
const repoRoot = join(compilerRoot, '..');
const runtimeValidDir = join(repoRoot, 'tests', 'conformance', 'runtime', 'valid');
const cliJs = join(compilerRoot, 'dist', 'cli.js');
const runtimeJar = join(repoRoot, 'runtime', 'jvm', 'kestrel-runtime.jar');

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

function mainClassFor(ksAbsolute: string): string {
  const normalized = resolve(ksAbsolute).replace(/\\/g, '/');
  const rel = normalized.startsWith('/') ? normalized.slice(1) : normalized;
  const withoutExt = rel.endsWith('.ks') ? rel.slice(0, -3) : rel;
  const parts = withoutExt.split('/').map((part) => part.replace(/[^a-zA-Z0-9_]/g, '_'));
  const last = parts[parts.length - 1] ?? '';
  const main = last.charAt(0).toUpperCase() + last.slice(1);
  if (parts.length === 1) return main;
  return parts.slice(0, -1).join('.') + '.' + main;
}

let testJvmClassDir: string | undefined;

beforeAll(() => {
  testJvmClassDir = mkdtempSync(join(tmpdir(), 'kestrel-runtime-jvm-'));
  execSync('./build.sh', {
    cwd: join(repoRoot, 'runtime', 'jvm'),
    stdio: 'pipe',
  });
});

afterAll(() => {
  if (testJvmClassDir == null) return;
  try {
    rmSync(testJvmClassDir, { recursive: true, force: true });
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
      const classDir = testJvmClassDir;
      const mainClass = mainClassFor(ksPath);
      try {
        execSync(`node "${cliJs}" "${ksPath}" --target jvm -o "${classDir}"`, {
          cwd: repoRoot,
          encoding: 'utf-8',
          stdio: ['pipe', 'pipe', 'pipe'],
        });
      } catch (e) {
        throw new Error(`Compile failed for ${file}: ${String(e)}`);
      }

      let stdout = '';
      let stderr = '';
      try {
        const out = execSync(`java -cp "${runtimeJar}:${classDir}" "${mainClass}"`, {
          cwd: repoRoot,
          encoding: 'utf-8',
          stdio: ['pipe', 'pipe', 'pipe'],
        });
        stdout = typeof out === 'string' ? out : out.toString();
      } catch (e: unknown) {
        const err = e as { stdout?: string; stderr?: string; status?: number };
        stdout = err.stdout?.toString() ?? '';
        stderr = err.stderr?.toString() ?? '';
        throw new Error(`JVM exit ${err.status} for ${file}. stderr: ${stderr}`);
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
