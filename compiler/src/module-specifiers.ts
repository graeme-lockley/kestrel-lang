/**
 * Distinct module specifiers for resolution and bytecode import table (07 §2.1, §6).
 * Includes specifiers from import declarations and from `export * from` / `export { … } from`.
 */
import type { Program } from './ast/nodes.js';
import type { Span } from './lexer/types.js';

export function distinctSpecifiersInSourceOrder(program: Program): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const imp of program.imports) {
    if (!seen.has(imp.spec)) {
      seen.add(imp.spec);
      out.push(imp.spec);
    }
  }
  for (const node of program.body) {
    if (!node || node.kind !== 'ExportDecl') continue;
    const inner = node.inner;
    if (inner.kind === 'ExportStar' || inner.kind === 'ExportNamed') {
      const spec = inner.spec;
      if (!seen.has(spec)) {
        seen.add(spec);
        out.push(spec);
      }
    }
  }
  return out;
}

/** Span for a specifier on an import or re-export (for diagnostics). */
export function spanForSpecifier(program: Program, spec: string): Span | undefined {
  for (const imp of program.imports) {
    if (imp.spec === spec) return imp.span;
  }
  for (const node of program.body) {
    if (!node || node.kind !== 'ExportDecl') continue;
    const inner = node.inner;
    if ((inner.kind === 'ExportStar' || inner.kind === 'ExportNamed') && inner.spec === spec) {
      return inner.span ?? node.span;
    }
  }
  return undefined;
}
