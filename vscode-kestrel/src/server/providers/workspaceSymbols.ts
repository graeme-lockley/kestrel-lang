import { SymbolKind, type SymbolInformation } from 'vscode-languageserver/node';

import type { WorkspaceDecl, WorkspaceIndex } from '../compiler-bridge';

function kindFromDecl(decl: WorkspaceDecl): SymbolKind {
  switch (decl.kind) {
    case 'fun':
      return SymbolKind.Function;
    case 'type':
      return SymbolKind.Class;
    case 'exception':
      return SymbolKind.Event;
    case 'val':
    case 'var':
      return SymbolKind.Variable;
    default:
      return SymbolKind.Object;
  }
}

export function collectWorkspaceSymbols(workspaceIndex: WorkspaceIndex, query: string): SymbolInformation[] {
  const q = query.trim().toLowerCase();
  const out: SymbolInformation[] = [];

  for (const decl of workspaceIndex.decls) {
    if (q.length > 0 && !decl.name.toLowerCase().includes(q)) {
      continue;
    }

    out.push({
      name: decl.name,
      kind: kindFromDecl(decl),
      location: {
        uri: decl.uri,
        range: {
          start: { line: Math.max(0, decl.line - 1), character: Math.max(0, decl.column - 1) },
          end: { line: Math.max(0, decl.endLine - 1), character: Math.max(0, decl.endColumn - 1) },
        },
      },
    });
  }

  return out;
}
