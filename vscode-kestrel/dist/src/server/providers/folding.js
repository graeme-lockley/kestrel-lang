"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.collectFoldingRanges = collectFoldingRanges;
function hasSpan(node) {
    if (node == null || typeof node !== 'object') {
        return false;
    }
    const span = node.span;
    return span != null && typeof span.line === 'number';
}
function pushRangeFromSpan(out, span) {
    const startLine = span.line - 1;
    const endLine = (span.endLine ?? span.line) - 1;
    if (endLine > startLine) {
        out.push({ startLine, endLine });
    }
}
function walk(node, out) {
    if (node == null || typeof node !== 'object') {
        return;
    }
    const kind = node.kind;
    if (kind === 'BlockExpr' || kind === 'TypeDecl' || kind === 'IfExpr' || kind === 'WhileExpr' || kind === 'MatchExpr' || kind === 'TryExpr') {
        if (hasSpan(node)) {
            pushRangeFromSpan(out, node.span);
        }
    }
    for (const [key, value] of Object.entries(node)) {
        if (key === 'span') {
            continue;
        }
        if (Array.isArray(value)) {
            for (const item of value) {
                walk(item, out);
            }
            continue;
        }
        walk(value, out);
    }
}
function commentFoldingRanges(source) {
    const out = [];
    const re = /\/\*[\s\S]*?\*\//g;
    let m;
    while ((m = re.exec(source)) != null) {
        const text = m[0];
        const startOffset = m.index;
        const endOffset = m.index + text.length;
        const beforeStart = source.slice(0, startOffset);
        const beforeEnd = source.slice(0, endOffset);
        const startLine = (beforeStart.match(/\n/g)?.length ?? 0);
        const endLine = (beforeEnd.match(/\n/g)?.length ?? 0);
        if (endLine > startLine) {
            out.push({ startLine, endLine });
        }
    }
    return out;
}
function collectFoldingRanges(ast, source) {
    const out = [];
    walk(ast, out);
    out.push(...commentFoldingRanges(source));
    return out;
}
//# sourceMappingURL=folding.js.map