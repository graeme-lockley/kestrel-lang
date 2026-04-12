"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.collectCompletions = collectCompletions;
const node_1 = require("vscode-languageserver/node");
const KEYWORDS = [
    'as', 'fun', 'type', 'val', 'var', 'mut', 'if', 'else', 'while', 'break', 'continue', 'match', 'try', 'catch', 'throw',
    'async', 'await', 'export', 'import', 'from', 'exception', 'is', 'opaque', 'extern', 'True', 'False',
];
function pushUnique(out, seen, item) {
    if (seen.has(item.label)) {
        return;
    }
    seen.add(item.label);
    out.push(item);
}
function collectCompletions(ast) {
    const out = [];
    const seen = new Set();
    for (const kw of KEYWORDS) {
        pushUnique(out, seen, { label: kw, kind: node_1.CompletionItemKind.Keyword });
    }
    if (ast == null || typeof ast !== 'object') {
        return out;
    }
    const program = ast;
    for (const imp of program.imports ?? []) {
        if (imp == null || typeof imp !== 'object')
            continue;
        const n = imp;
        if (n.kind === 'NamedImport') {
            for (const spec of n.specs ?? []) {
                if (spec.local != null) {
                    pushUnique(out, seen, { label: spec.local, kind: node_1.CompletionItemKind.Variable });
                }
            }
        }
    }
    for (const node of program.body ?? []) {
        if (node == null || typeof node !== 'object')
            continue;
        const d = node;
        if (d.name != null) {
            let kind = node_1.CompletionItemKind.Variable;
            if (d.kind === 'FunDecl' || d.kind === 'ExternFunDecl') {
                kind = node_1.CompletionItemKind.Function;
            }
            else if (d.kind === 'TypeDecl' || d.kind === 'ExternTypeDecl') {
                kind = node_1.CompletionItemKind.Class;
            }
            else if (d.kind === 'ExceptionDecl') {
                kind = node_1.CompletionItemKind.Event;
            }
            pushUnique(out, seen, { label: d.name, kind });
        }
        if (d.kind === 'FunDecl') {
            for (const param of d.params ?? []) {
                if (param.name != null) {
                    pushUnique(out, seen, { label: param.name, kind: node_1.CompletionItemKind.Variable });
                }
            }
        }
        if (d.kind === 'TypeDecl' && d.body?.kind === 'ADTBody') {
            for (const ctor of d.body.constructors ?? []) {
                if (ctor.name != null) {
                    pushUnique(out, seen, { label: ctor.name, kind: node_1.CompletionItemKind.Constructor });
                }
            }
        }
    }
    return out;
}
//# sourceMappingURL=completion.js.map