/**
 * Parse conformance (spec 08 §2.1, §3.2).
 * valid/*.ks must tokenize and parse to a Program; invalid/*.ks must yield { ok: false }.
 */
import { describe, it, expect } from 'vitest';
import { readdirSync, readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import { tokenize } from '../../src/lexer/index.js';
import { parse, type ParseResult } from '../../src/parser/index.js';
import type { Program } from '../../src/parser/index.js';

const thisDir = dirname(fileURLToPath(import.meta.url));
const compilerRoot = join(thisDir, '..', '..');
const repoRoot = join(compilerRoot, '..');
const parseRoot = join(repoRoot, 'tests', 'conformance', 'parse');
const validDir = join(parseRoot, 'valid');
const invalidDir = join(parseRoot, 'invalid');

function getConformanceFiles(dir: string): string[] {
  try {
    return readdirSync(dir).filter((f) => f.endsWith('.ks')).sort();
  } catch {
    return [];
  }
}

function isParseProgram(r: ParseResult): r is Program {
  return !('ok' in r && r.ok === false);
}

function getExpectedSubstring(source: string): string | null {
  const first = source.split('\n')[0]?.trim() ?? '';
  const match = first.match(/^\/\/\s*EXPECT:\s*(.+)$/);
  return match ? match[1]!.trim() : null;
}

describe('parse conformance (valid)', () => {
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
      const result = parse(tokens);
      expect(isParseProgram(result), JSON.stringify(result)).toBe(true);
    });
  }
});

describe('parse conformance (invalid)', () => {
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
      const result = parse(tokens);
      expect(isParseProgram(result)).toBe(false);
      if (!isParseProgram(result)) {
        expect(result.errors.length).toBeGreaterThan(0);
        if (expectedSubstring != null) {
          const joined = result.errors.map((e) => e.message).join('; ');
          expect(
            result.errors.some((e) => e.message.includes(expectedSubstring)),
            `Expected an error containing "${expectedSubstring}". Got: ${joined}`
          ).toBe(true);
        }
      }
    });
  }
});
