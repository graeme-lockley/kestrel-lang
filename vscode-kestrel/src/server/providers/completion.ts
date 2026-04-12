import { CompletionItemKind, type CompletionItem } from 'vscode-languageserver/node';

const KEYWORDS = [
  'as', 'fun', 'type', 'val', 'var', 'mut', 'if', 'else', 'while', 'break', 'continue', 'match', 'try', 'catch', 'throw',
  'async', 'await', 'export', 'import', 'from', 'exception', 'is', 'opaque', 'extern', 'True', 'False',
];

function pushUnique(out: CompletionItem[], seen: Set<string>, item: CompletionItem): void {
  if (seen.has(item.label)) {
    return;
  }
  seen.add(item.label);
  out.push(item);
}

export function collectCompletions(ast: unknown | null): CompletionItem[] {
  const out: CompletionItem[] = [];
  const seen = new Set<string>();

  for (const kw of KEYWORDS) {
    pushUnique(out, seen, { label: kw, kind: CompletionItemKind.Keyword });
  }

  if (ast == null || typeof ast !== 'object') {
    return out;
  }

  const program = ast as { imports?: unknown[]; body?: unknown[] };

  for (const imp of program.imports ?? []) {
    if (imp == null || typeof imp !== 'object') continue;
    const n = imp as { kind?: string; specs?: Array<{ local?: string }> };
    if (n.kind === 'NamedImport') {
      for (const spec of n.specs ?? []) {
        if (spec.local != null) {
          pushUnique(out, seen, { label: spec.local, kind: CompletionItemKind.Variable });
        }
      }
    }
  }

  for (const node of program.body ?? []) {
    if (node == null || typeof node !== 'object') continue;
    const d = node as {
      kind?: string;
      name?: string;
      params?: Array<{ name?: string }>;
      body?: { kind?: string; constructors?: Array<{ name?: string }> };
    };

    if (d.name != null) {
      let kind: CompletionItemKind = CompletionItemKind.Variable;
      if (d.kind === 'FunDecl' || d.kind === 'ExternFunDecl') {
        kind = CompletionItemKind.Function;
      } else if (d.kind === 'TypeDecl' || d.kind === 'ExternTypeDecl') {
        kind = CompletionItemKind.Class;
      } else if (d.kind === 'ExceptionDecl') {
        kind = CompletionItemKind.Event;
      }
      pushUnique(out, seen, { label: d.name, kind });
    }

    if (d.kind === 'FunDecl') {
      for (const param of d.params ?? []) {
        if (param.name != null) {
          pushUnique(out, seen, { label: param.name, kind: CompletionItemKind.Variable });
        }
      }
    }

    if (d.kind === 'TypeDecl' && d.body?.kind === 'ADTBody') {
      for (const ctor of d.body.constructors ?? []) {
        if (ctor.name != null) {
          pushUnique(out, seen, { label: ctor.name, kind: CompletionItemKind.Constructor });
        }
      }
    }
  }

  return out;
}
