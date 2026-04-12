import {
  SemanticTokensBuilder,
  type SemanticTokens,
} from 'vscode-languageserver/node';

import { tokenizeSource } from '../compiler-bridge';

export const semanticTokenLegend = {
  tokenTypes: ['keyword', 'type', 'enumMember', 'function', 'variable', 'string', 'number', 'operator'],
  tokenModifiers: [] as string[],
};

function tokenTypeIndex(name: string): number {
  const index = semanticTokenLegend.tokenTypes.indexOf(name);
  return index >= 0 ? index : semanticTokenLegend.tokenTypes.indexOf('variable');
}

function classify(token: { kind?: string; value?: string }, prev: { kind?: string; value?: string } | null): string | null {
  if (token.kind == null) return null;

  if (token.kind === 'keyword') return 'keyword';
  if (token.kind === 'string' || token.kind === 'char') return 'string';
  if (token.kind === 'int' || token.kind === 'float') return 'number';
  if (token.kind === 'op') return 'operator';
  if (token.kind !== 'ident') return null;

  const value = token.value ?? '';
  if (prev?.kind === 'keyword' && prev.value === 'fun') return 'function';
  if (/^[A-Z]/.test(value)) return 'type';
  return 'variable';
}

export async function collectSemanticTokens(source: string): Promise<SemanticTokens> {
  const tokens = await tokenizeSource(source);
  const builder = new SemanticTokensBuilder();

  let prev: { kind?: string; value?: string } | null = null;
  for (const token of tokens) {
    const kind = classify(token as { kind?: string; value?: string }, prev);
    prev = token as { kind?: string; value?: string };
    if (kind == null) {
      continue;
    }

    const t = token as { span?: { line: number; column: number; start: number; end: number }; value?: string };
    if (t.span == null) {
      continue;
    }
    const length = Math.max(1, t.span.end - t.span.start);
    builder.push(t.span.line - 1, t.span.column - 1, length, tokenTypeIndex(kind), 0);
  }

  return builder.build();
}
