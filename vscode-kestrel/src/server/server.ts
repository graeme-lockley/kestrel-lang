import {
  createConnection,
  ProposedFeatures,
  TextDocuments,
  TextDocumentSyncKind,
  type InitializeParams,
} from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';

import { compileSource } from './compiler-bridge';
import { DebouncedScheduler } from './debounce';
import { toLspDiagnostics } from './diagnostics';
import { DocumentManager } from './document-manager';
import { collectCompletions } from './providers/completion';
import { findDefinition } from './providers/definition';
import { collectFoldingRanges } from './providers/folding';
import { buildHover } from './providers/hover';
import { collectInlayHints } from './providers/inlayHints';
import { collectSemanticTokens, semanticTokenLegend } from './providers/semanticTokens';
import { collectDocumentSymbols } from './providers/symbols';

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);
const documentManager = new DocumentManager();
const debouncers = new Map<string, DebouncedScheduler>();

const DEFAULT_DEBOUNCE_MS = 250;

function scheduleDiagnostics(doc: TextDocument): void {
  const uri = doc.uri;
  let scheduler = debouncers.get(uri);
  if (scheduler == null) {
    scheduler = new DebouncedScheduler(DEFAULT_DEBOUNCE_MS);
    debouncers.set(uri, scheduler);
  }

  scheduler.cancel();
  scheduler = new DebouncedScheduler(DEFAULT_DEBOUNCE_MS);
  debouncers.set(uri, scheduler);

  scheduler.schedule(async () => {
    const source = doc.getText();
    const result = await compileSource(source, uri);
    documentManager.update(uri, source, result.ast, result.diagnostics);
    connection.sendDiagnostics({ uri, diagnostics: toLspDiagnostics(uri, result.diagnostics) });
  });
}

connection.onInitialize((_params: InitializeParams) => {
  return {
    capabilities: {
      textDocumentSync: TextDocumentSyncKind.Incremental,
      hoverProvider: true,
      documentSymbolProvider: true,
      foldingRangeProvider: true,
      definitionProvider: true,
      completionProvider: {
        triggerCharacters: ['.'],
      },
      semanticTokensProvider: {
        full: true,
        legend: semanticTokenLegend,
      },
      inlayHintProvider: true,
    },
  };
});

connection.onDefinition((params) => {
  const doc = documentManager.get(params.textDocument.uri);
  if (doc == null) {
    return null;
  }
  return findDefinition(doc.ast, doc.source, params.textDocument.uri, params.position);
});

connection.onCompletion((params) => {
  const doc = documentManager.get(params.textDocument.uri);
  if (doc == null) {
    return [];
  }
  return collectCompletions(doc.ast);
});

connection.languages.semanticTokens.on(async (params) => {
  const doc = documentManager.get(params.textDocument.uri);
  if (doc == null) {
    return { data: [] };
  }
  return collectSemanticTokens(doc.source);
});

connection.languages.inlayHint.on(async (params) => {
  const doc = documentManager.get(params.textDocument.uri);
  if (doc == null) {
    return [];
  }
  return collectInlayHints(doc.ast);
});

connection.onHover(async (params) => {
  const doc = documentManager.get(params.textDocument.uri);
  if (doc == null) {
    return null;
  }
  return buildHover(doc.source, doc.ast, params.position);
});

connection.onDocumentSymbol((params) => {
  const doc = documentManager.get(params.textDocument.uri);
  if (doc == null) {
    return [];
  }
  return collectDocumentSymbols(doc.ast);
});

connection.onFoldingRanges((params) => {
  const doc = documentManager.get(params.textDocument.uri);
  if (doc == null) {
    return [];
  }
  return collectFoldingRanges(doc.ast, doc.source);
});

documents.onDidOpen((event) => {
  scheduleDiagnostics(event.document);
});

documents.onDidChangeContent((event) => {
  scheduleDiagnostics(event.document);
});

documents.onDidClose((event) => {
  const uri = event.document.uri;
  debouncers.get(uri)?.cancel();
  debouncers.delete(uri);
  documentManager.delete(uri);
  connection.sendDiagnostics({ uri, diagnostics: [] });
});

documents.listen(connection);
connection.listen();
