import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import * as oniguruma from 'vscode-oniguruma';
import { Registry } from 'vscode-textmate';
import { describe, expect, it } from 'vitest';

const here = __dirname;
const root = join(here, '..', '..');
const grammarPath = join(root, 'syntaxes', 'kestrel.tmLanguage.json');

let wasmLoaded = false;
async function loadRegistry(): Promise<Registry> {
  if (!wasmLoaded) {
    const onigWasmPath = join(root, 'node_modules', 'vscode-oniguruma', 'release', 'onig.wasm');
    const wasmBin = readFileSync(onigWasmPath);
    const wasmBuffer = wasmBin.buffer.slice(wasmBin.byteOffset, wasmBin.byteOffset + wasmBin.byteLength);
    await oniguruma.loadWASM(wasmBuffer);
    wasmLoaded = true;
  }

  return new Registry({
    onigLib: Promise.resolve({
      createOnigScanner: (patterns: string[]) => new oniguruma.OnigScanner(patterns),
      createOnigString: (s: string) => new oniguruma.OnigString(s)
    }),
    loadGrammar: async (scopeName: string) => {
      if (scopeName !== 'source.kestrel') {
        return null;
      }
      const raw = readFileSync(grammarPath, 'utf8');
      return JSON.parse(raw);
    }
  });
}

async function tokenize(line: string) {
  const registry = await loadRegistry();
  const grammar = await registry.loadGrammar('source.kestrel');
  if (!grammar) {
    throw new Error('Failed to load grammar');
  }
  return grammar.tokenizeLine(line, null).tokens;
}

describe('kestrel TextMate grammar', () => {
  it('scopes keywords as keyword.control.kestrel', async () => {
    const tokens = await tokenize('fun add(a: Int): Int = 1');
    const keyword = tokens.find((t) => t.scopes.includes('keyword.control.kestrel'));
    expect(keyword).toBeDefined();
  });

  it('scopes True/False as constant.language.boolean.kestrel', async () => {
    const tokens = await tokenize('val x = True');
    const bool = tokens.find((t) => t.scopes.includes('constant.language.boolean.kestrel'));
    expect(bool).toBeDefined();
  });

  it('scopes PascalCase names as entity.name.type.kestrel', async () => {
    const tokens = await tokenize('val x: Option<Int> = None');
    const typeToken = tokens.find((t) => t.scopes.includes('entity.name.type.kestrel'));
    expect(typeToken).toBeDefined();
  });

  it('scopes string literals as string.quoted.double.kestrel', async () => {
    const tokens = await tokenize('val s = "hello"');
    const str = tokens.find((t) => t.scopes.includes('string.quoted.double.kestrel'));
    expect(str).toBeDefined();
  });
});
