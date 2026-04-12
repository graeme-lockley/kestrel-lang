import { SymbolKind, type DocumentSymbol, type Range } from 'vscode-languageserver/node';

function rangeFromSpan(span: { line: number; column: number; endLine?: number; endColumn?: number }): Range {
  const startLine = Math.max(0, span.line - 1);
  const startChar = Math.max(0, span.column - 1);
  const endLine = Math.max(0, (span.endLine ?? span.line) - 1);
  const endChar = Math.max(startChar + 1, (span.endColumn ?? span.column + 1) - 1);
  return {
    start: { line: startLine, character: startChar },
    end: { line: endLine, character: endChar },
  };
}

function symbolKind(kind: string): SymbolKind {
  switch (kind) {
    case 'FunDecl':
    case 'ExternFunDecl':
      return SymbolKind.Function;
    case 'ValDecl':
    case 'VarDecl':
      return SymbolKind.Variable;
    case 'TypeDecl':
    case 'ExternTypeDecl':
      return SymbolKind.Class;
    case 'ExceptionDecl':
      return SymbolKind.Event;
    default:
      return SymbolKind.Object;
  }
}

export function collectDocumentSymbols(ast: unknown | null): DocumentSymbol[] {
  if (ast == null || typeof ast !== 'object') {
    return [];
  }
  const program = ast as { body?: unknown[] };
  const body = Array.isArray(program.body) ? program.body : [];
  const out: DocumentSymbol[] = [];

  for (const item of body) {
    if (item == null || typeof item !== 'object') {
      continue;
    }
    const decl = item as { kind?: string; name?: string; span?: { line: number; column: number; endLine?: number; endColumn?: number }; body?: unknown };
    if (decl.kind == null || decl.name == null || decl.span == null) {
      continue;
    }

    const range = rangeFromSpan(decl.span);
    const symbol: DocumentSymbol = {
      name: decl.name,
      kind: symbolKind(decl.kind),
      range,
      selectionRange: range,
      children: [],
    };

    if (decl.kind === 'TypeDecl') {
      const typeBody = decl.body as { kind?: string; constructors?: unknown[] } | undefined;
      if (typeBody?.kind === 'ADTBody' && Array.isArray(typeBody.constructors)) {
        for (const ctor of typeBody.constructors) {
          if (ctor == null || typeof ctor !== 'object') {
            continue;
          }
          const c = ctor as { name?: string; span?: { line: number; column: number; endLine?: number; endColumn?: number } };
          if (c.name == null || c.span == null) {
            continue;
          }
          const cr = rangeFromSpan(c.span);
          symbol.children?.push({
            name: c.name,
            kind: SymbolKind.Constructor,
            range: cr,
            selectionRange: cr,
          });
        }
      }
    }

    out.push(symbol);
  }

  return out;
}
