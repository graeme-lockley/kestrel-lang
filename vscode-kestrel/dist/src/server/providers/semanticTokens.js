"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.semanticTokenLegend = void 0;
exports.collectSemanticTokens = collectSemanticTokens;
const node_1 = require("vscode-languageserver/node");
const compiler_bridge_1 = require("../compiler-bridge");
exports.semanticTokenLegend = {
    tokenTypes: ['keyword', 'type', 'enumMember', 'function', 'variable', 'string', 'number', 'operator'],
    tokenModifiers: [],
};
function tokenTypeIndex(name) {
    const index = exports.semanticTokenLegend.tokenTypes.indexOf(name);
    return index >= 0 ? index : exports.semanticTokenLegend.tokenTypes.indexOf('variable');
}
function classify(token, prev) {
    if (token.kind == null)
        return null;
    if (token.kind === 'keyword')
        return 'keyword';
    if (token.kind === 'string' || token.kind === 'char')
        return 'string';
    if (token.kind === 'int' || token.kind === 'float')
        return 'number';
    if (token.kind === 'op')
        return 'operator';
    if (token.kind !== 'ident')
        return null;
    const value = token.value ?? '';
    if (prev?.kind === 'keyword' && prev.value === 'fun')
        return 'function';
    if (/^[A-Z]/.test(value))
        return 'type';
    return 'variable';
}
async function collectSemanticTokens(source) {
    const tokens = await (0, compiler_bridge_1.tokenizeSource)(source);
    const builder = new node_1.SemanticTokensBuilder();
    let prev = null;
    for (const token of tokens) {
        const kind = classify(token, prev);
        prev = token;
        if (kind == null) {
            continue;
        }
        const t = token;
        if (t.span == null) {
            continue;
        }
        const length = Math.max(1, t.span.end - t.span.start);
        builder.push(t.span.line - 1, t.span.column - 1, length, tokenTypeIndex(kind), 0);
    }
    return builder.build();
}
//# sourceMappingURL=semanticTokens.js.map