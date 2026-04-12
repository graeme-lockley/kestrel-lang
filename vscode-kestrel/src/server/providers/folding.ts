import type { FoldingRange } from 'vscode-languageserver/node';

function hasSpan(node: unknown): node is { span: { line: number; endLine?: number } } {
  if (node == null || typeof node !== 'object') {
    return false;
  }
  const span = (node as { span?: { line?: unknown; endLine?: unknown } }).span;
  return span != null && typeof span.line === 'number';
}

function pushRangeFromSpan(out: FoldingRange[], span: { line: number; endLine?: number }): void {
  const startLine = span.line - 1;
  const endLine = (span.endLine ?? span.line) - 1;
  if (endLine > startLine) {
    out.push({ startLine, endLine });
  }
}

function walk(node: unknown, out: FoldingRange[]): void {
  if (node == null || typeof node !== 'object') {
    return;
  }

  const kind = (node as { kind?: string }).kind;
  if (kind === 'BlockExpr' || kind === 'TypeDecl' || kind === 'IfExpr' || kind === 'WhileExpr' || kind === 'MatchExpr' || kind === 'TryExpr') {
    if (hasSpan(node)) {
      pushRangeFromSpan(out, node.span);
    }
  }

  for (const [key, value] of Object.entries(node as Record<string, unknown>)) {
    if (key === 'span') {
      continue;
    }
    if (Array.isArray(value)) {
      for (const item of value) {
        walk(item, out);
      }
      continue;
    }
    walk(value, out);
  }
}

function commentFoldingRanges(source: string): FoldingRange[] {
  const out: FoldingRange[] = [];
  const re = /\/\*[\s\S]*?\*\//g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(source)) != null) {
    const text = m[0];
    const startOffset = m.index;
    const endOffset = m.index + text.length;
    const beforeStart = source.slice(0, startOffset);
    const beforeEnd = source.slice(0, endOffset);
    const startLine = (beforeStart.match(/\n/g)?.length ?? 0);
    const endLine = (beforeEnd.match(/\n/g)?.length ?? 0);
    if (endLine > startLine) {
      out.push({ startLine, endLine });
    }
  }
  return out;
}

export function collectFoldingRanges(ast: unknown | null, source: string): FoldingRange[] {
  const out: FoldingRange[] = [];
  walk(ast, out);
  out.push(...commentFoldingRanges(source));
  return out;
}
