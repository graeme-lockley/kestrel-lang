import type { InlayHint } from 'vscode-languageserver/node';

import { inferredTypeText } from '../compiler-bridge';

function hintPosition(span: { line: number; column: number }, name: string): { line: number; character: number } {
  return { line: Math.max(0, span.line - 1), character: Math.max(0, span.column - 1 + name.length) };
}

export async function collectInlayHints(ast: unknown | null): Promise<InlayHint[]> {
  if (ast == null || typeof ast !== 'object') {
    return [];
  }

  const out: InlayHint[] = [];
  const program = ast as { body?: unknown[] };

  for (const node of program.body ?? []) {
    if (node == null || typeof node !== 'object') {
      continue;
    }

    const d = node as {
      kind?: string;
      name?: string;
      span?: { line: number; column: number };
      type?: unknown;
      value?: unknown;
      params?: Array<{ name?: string; type?: unknown; span?: { line: number; column: number } }>;
    };

    if ((d.kind === 'ValDecl' || d.kind === 'VarDecl') && d.type == null && d.name != null && d.span != null && d.value != null) {
      const text = await inferredTypeText(d.value);
      if (text != null) {
        out.push({
          position: hintPosition(d.span, d.name),
          label: `: ${text}`,
        });
      }
    }

    if (d.kind === 'FunDecl') {
      for (const p of d.params ?? []) {
        if (p.name == null || p.type != null || p.span == null) {
          continue;
        }
        const text = await inferredTypeText(p);
        if (text != null) {
          out.push({
            position: hintPosition(p.span, p.name),
            label: `: ${text}`,
          });
        }
      }
    }
  }

  return out;
}
