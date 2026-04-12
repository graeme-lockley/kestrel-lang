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
    documentManager.update(uri, source, result.diagnostics);
    connection.sendDiagnostics({ uri, diagnostics: toLspDiagnostics(uri, result.diagnostics) });
  });
}

connection.onInitialize((_params: InitializeParams) => {
  return {
    capabilities: {
      textDocumentSync: TextDocumentSyncKind.Incremental,
    },
  };
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
