"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const node_1 = require("vscode-languageserver/node");
const vscode_languageserver_textdocument_1 = require("vscode-languageserver-textdocument");
const compiler_bridge_1 = require("./compiler-bridge");
const debounce_1 = require("./debounce");
const diagnostics_1 = require("./diagnostics");
const document_manager_1 = require("./document-manager");
const codeActions_1 = require("./providers/codeActions");
const codeLens_1 = require("./providers/codeLens");
const completion_1 = require("./providers/completion");
const definition_1 = require("./providers/definition");
const folding_1 = require("./providers/folding");
const formatting_1 = require("./providers/formatting");
const hover_1 = require("./providers/hover");
const inlayHints_1 = require("./providers/inlayHints");
const semanticTokens_1 = require("./providers/semanticTokens");
const signatureHelp_1 = require("./providers/signatureHelp");
const symbols_1 = require("./providers/symbols");
const connection = (0, node_1.createConnection)(node_1.ProposedFeatures.all);
const documents = new node_1.TextDocuments(vscode_languageserver_textdocument_1.TextDocument);
const documentManager = new document_manager_1.DocumentManager();
const debouncers = new Map();
const DEFAULT_DEBOUNCE_MS = 250;
let debounceMs = DEFAULT_DEBOUNCE_MS;
let kestrelExecutable = 'kestrel';
let formatterEnabled = true;
function scheduleDiagnostics(doc) {
    const uri = doc.uri;
    let scheduler = debouncers.get(uri);
    if (scheduler == null) {
        scheduler = new debounce_1.DebouncedScheduler(debounceMs);
        debouncers.set(uri, scheduler);
    }
    scheduler.cancel();
    scheduler = new debounce_1.DebouncedScheduler(debounceMs);
    debouncers.set(uri, scheduler);
    scheduler.schedule(async () => {
        const source = doc.getText();
        const result = await (0, compiler_bridge_1.compileSource)(source, uri);
        documentManager.update(uri, source, result.ast, result.diagnostics);
        connection.sendDiagnostics({ uri, diagnostics: (0, diagnostics_1.toLspDiagnostics)(uri, result.diagnostics) });
    });
}
connection.onInitialize((params) => {
    const init = params.initializationOptions;
    const configuredDebounce = init?.debounceMs;
    if (typeof configuredDebounce === 'number' && configuredDebounce > 0) {
        debounceMs = configuredDebounce;
    }
    if (typeof init?.executable === 'string' && init.executable.length > 0) {
        kestrelExecutable = init.executable;
    }
    if (typeof init?.formatterEnabled === 'boolean') {
        formatterEnabled = init.formatterEnabled;
    }
    return {
        capabilities: {
            textDocumentSync: node_1.TextDocumentSyncKind.Incremental,
            hoverProvider: true,
            documentSymbolProvider: true,
            foldingRangeProvider: true,
            documentFormattingProvider: true,
            documentRangeFormattingProvider: true,
            codeLensProvider: {
                resolveProvider: false,
            },
            definitionProvider: true,
            completionProvider: {
                triggerCharacters: ['.'],
            },
            codeActionProvider: {
                codeActionKinds: ['quickfix'],
            },
            signatureHelpProvider: {
                triggerCharacters: ['(', ','],
            },
            semanticTokensProvider: {
                full: true,
                legend: semanticTokens_1.semanticTokenLegend,
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
    return (0, definition_1.findDefinition)(doc.ast, doc.source, params.textDocument.uri, params.position);
});
connection.onCompletion((params) => {
    const doc = documentManager.get(params.textDocument.uri);
    if (doc == null) {
        return [];
    }
    return (0, completion_1.collectCompletions)(doc.ast);
});
connection.onCodeAction((params) => {
    const doc = documentManager.get(params.textDocument.uri);
    if (doc == null) {
        return [];
    }
    return (0, codeActions_1.collectCodeActions)(params.textDocument.uri, doc.source, params.context.diagnostics, doc.diagnostics);
});
connection.onSignatureHelp(async (params) => {
    const doc = documentManager.get(params.textDocument.uri);
    if (doc == null) {
        return null;
    }
    return (0, signatureHelp_1.provideSignatureHelp)(doc.ast, doc.source, params.position);
});
connection.languages.semanticTokens.on(async (params) => {
    const doc = documentManager.get(params.textDocument.uri);
    if (doc == null) {
        return { data: [] };
    }
    return (0, semanticTokens_1.collectSemanticTokens)(doc.source);
});
connection.languages.inlayHint.on(async (params) => {
    const doc = documentManager.get(params.textDocument.uri);
    if (doc == null) {
        return [];
    }
    return (0, inlayHints_1.collectInlayHints)(doc.ast);
});
connection.onHover(async (params) => {
    const doc = documentManager.get(params.textDocument.uri);
    if (doc == null) {
        return null;
    }
    return (0, hover_1.buildHover)(doc.source, doc.ast, params.position);
});
connection.onDocumentSymbol((params) => {
    const doc = documentManager.get(params.textDocument.uri);
    if (doc == null) {
        return [];
    }
    return (0, symbols_1.collectDocumentSymbols)(doc.ast);
});
connection.onFoldingRanges((params) => {
    const doc = documentManager.get(params.textDocument.uri);
    if (doc == null) {
        return [];
    }
    return (0, folding_1.collectFoldingRanges)(doc.ast, doc.source);
});
connection.onDocumentFormatting(async (params) => {
    const doc = documentManager.get(params.textDocument.uri);
    if (doc == null) {
        return [];
    }
    return (0, formatting_1.formatDocument)(doc.source, { executable: kestrelExecutable, enabled: formatterEnabled });
});
connection.onDocumentRangeFormatting(async (params) => {
    const doc = documentManager.get(params.textDocument.uri);
    if (doc == null) {
        return [];
    }
    return (0, formatting_1.formatDocumentRange)(doc.source, { executable: kestrelExecutable, enabled: formatterEnabled }, params.range);
});
connection.onCodeLens((params) => {
    const doc = documentManager.get(params.textDocument.uri);
    if (doc == null) {
        return [];
    }
    return (0, codeLens_1.collectTestCodeLenses)(params.textDocument.uri, doc.source);
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
//# sourceMappingURL=server.js.map