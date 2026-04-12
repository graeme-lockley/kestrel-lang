"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.collectDocumentSymbols = collectDocumentSymbols;
const node_1 = require("vscode-languageserver/node");
function rangeFromSpan(span) {
    const startLine = Math.max(0, span.line - 1);
    const startChar = Math.max(0, span.column - 1);
    const endLine = Math.max(0, (span.endLine ?? span.line) - 1);
    const endChar = Math.max(startChar + 1, (span.endColumn ?? span.column + 1) - 1);
    return {
        start: { line: startLine, character: startChar },
        end: { line: endLine, character: endChar },
    };
}
function symbolKind(kind) {
    switch (kind) {
        case 'FunDecl':
        case 'ExternFunDecl':
            return node_1.SymbolKind.Function;
        case 'ValDecl':
        case 'VarDecl':
            return node_1.SymbolKind.Variable;
        case 'TypeDecl':
        case 'ExternTypeDecl':
            return node_1.SymbolKind.Class;
        case 'ExceptionDecl':
            return node_1.SymbolKind.Event;
        default:
            return node_1.SymbolKind.Object;
    }
}
function collectDocumentSymbols(ast) {
    if (ast == null || typeof ast !== 'object') {
        return [];
    }
    const program = ast;
    const body = Array.isArray(program.body) ? program.body : [];
    const out = [];
    for (const item of body) {
        if (item == null || typeof item !== 'object') {
            continue;
        }
        const decl = item;
        if (decl.kind == null || decl.name == null || decl.span == null) {
            continue;
        }
        const range = rangeFromSpan(decl.span);
        const symbol = {
            name: decl.name,
            kind: symbolKind(decl.kind),
            range,
            selectionRange: range,
            children: [],
        };
        if (decl.kind === 'TypeDecl') {
            const typeBody = decl.body;
            if (typeBody?.kind === 'ADTBody' && Array.isArray(typeBody.constructors)) {
                for (const ctor of typeBody.constructors) {
                    if (ctor == null || typeof ctor !== 'object') {
                        continue;
                    }
                    const c = ctor;
                    if (c.name == null || c.span == null) {
                        continue;
                    }
                    const cr = rangeFromSpan(c.span);
                    symbol.children?.push({
                        name: c.name,
                        kind: node_1.SymbolKind.Constructor,
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
//# sourceMappingURL=symbols.js.map