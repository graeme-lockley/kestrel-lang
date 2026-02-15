/**
 * Typecheck conformance tests (spec 08 §2.2, §3.2).
 * Runs tests/conformance/typecheck/valid/*.ks (must typecheck) and
 * invalid/*.ks (must fail typecheck; optional // EXPECT: substring in first line).
 */
import { describe, it, expect } from 'vitest';
import { readdirSync, readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { tokenize } from '../../src/lexer/index.js';
import { parse } from '../../src/parser/index.js';
import { typecheck } from '../../src/typecheck/index.js';

const thisDir = dirname(fileURLToPath(import.meta.url));
const compilerRoot = join(thisDir, '..', '..');
const repoRoot = join(compilerRoot, '..');
const typecheckDir = join(repoRoot, 'tests', 'conformance', 'typecheck');
const validDir = join(typecheckDir, 'valid');
const invalidDir = join(typecheckDir, 'invalid');

function getConformanceFiles(dir: string): string[] {
  try {
    return readdirSync(dir).filter((f) => f.endsWith('.ks')).sort();
  } catch {
    return [];
  }
}

/** Parse first line for // EXPECT: substring (optional). */
function getExpectedSubstring(source: string): string | null {
  const first = source.split('\n')[0]?.trim() ?? '';
  const match = first.match(/^\/\/\s*EXPECT:\s*(.+)$/);
  return match ? match[1]!.trim() : null;
}

describe('typecheck conformance (valid)', () => {
  const files = getConformanceFiles(validDir);
  if (files.length === 0) {
    it.skip('no valid conformance files', () => {});
    return;
  }
  for (const file of files) {
    it(file, () => {
      const path = join(validDir, file);
      const source = readFileSync(path, 'utf-8');
      const tokens = tokenize(source);
      const ast = parse(tokens);
      const tc = typecheck(ast);
      expect(tc.ok, tc.ok ? '' : (tc as { errors: string[] }).errors.join('; ')).toBe(true);
    });
  }
});

describe('typecheck conformance (invalid)', () => {
  const files = getConformanceFiles(invalidDir);
  if (files.length === 0) {
    it.skip('no invalid conformance files', () => {});
    return;
  }
  for (const file of files) {
    it(file, () => {
      const path = join(invalidDir, file);
      const source = readFileSync(path, 'utf-8');
      const expectedSubstring = getExpectedSubstring(source);
      const tokens = tokenize(source);
      const ast = parse(tokens);
      const tc = typecheck(ast);
      expect(tc.ok).toBe(false);
      if (!tc.ok && expectedSubstring != null) {
        const hasMatch = tc.errors.some((e) => e.includes(expectedSubstring));
        expect(hasMatch, `Expected error to contain "${expectedSubstring}". Got: ${tc.errors.join('; ')}`).toBe(true);
      }
    });
  }
});
