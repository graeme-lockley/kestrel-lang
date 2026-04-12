"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.provideSignatureHelp = provideSignatureHelp;
const compiler_bridge_1 = require("../compiler-bridge");
function offsetFromPosition(source, pos) {
    let line = 0;
    let col = 0;
    for (let i = 0; i < source.length; i++) {
        if (line === pos.line && col === pos.character)
            return i;
        if (source.charCodeAt(i) === 10) {
            line++;
            col = 0;
        }
        else {
            col++;
        }
    }
    return source.length;
}
function findCallStart(source, offset) {
    let depth = 0;
    for (let i = offset - 1; i >= 0; i--) {
        const ch = source[i];
        if (ch === ')')
            depth++;
        else if (ch === '(') {
            if (depth === 0)
                return i;
            depth--;
        }
    }
    return null;
}
function identifierBefore(source, openParen) {
    let i = openParen - 1;
    while (i >= 0 && /\s/.test(source[i] ?? ''))
        i--;
    let end = i + 1;
    while (i >= 0 && /[A-Za-z0-9_]/.test(source[i] ?? ''))
        i--;
    const start = i + 1;
    if (start >= end)
        return null;
    const name = source.slice(start, end);
    return /^[A-Za-z_][A-Za-z0-9_]*$/.test(name) ? name : null;
}
function activeParamIndex(source, start, offset) {
    let depth = 0;
    let commas = 0;
    for (let i = start; i < offset && i < source.length; i++) {
        const ch = source[i];
        if (ch === '(')
            depth++;
        else if (ch === ')') {
            if (depth > 0)
                depth--;
        }
        else if (ch === ',' && depth === 0) {
            commas++;
        }
    }
    return commas;
}
async function provideSignatureHelp(ast, source, position) {
    if (ast == null || typeof ast !== 'object') {
        return null;
    }
    const offset = offsetFromPosition(source, position);
    const openParen = findCallStart(source, offset);
    if (openParen == null) {
        return null;
    }
    const calleeName = identifierBefore(source, openParen);
    if (calleeName == null) {
        return null;
    }
    const program = ast;
    const decl = (program.body ?? []).find((node) => {
        if (node == null || typeof node !== 'object')
            return false;
        const d = node;
        return d.kind === 'FunDecl' && d.name === calleeName;
    });
    if (decl == null || decl.name == null) {
        return null;
    }
    const params = decl.params ?? [];
    const paramInfos = [];
    const rendered = [];
    for (const p of params) {
        const name = p.name ?? '_';
        const t = await (0, compiler_bridge_1.inferredTypeText)(p);
        const text = `${name}: ${t ?? 'Unknown'}`;
        rendered.push(text);
        paramInfos.push({ label: text });
    }
    const ret = decl.returnType != null ? (await (0, compiler_bridge_1.inferredTypeText)(decl.returnType)) : null;
    const label = `${decl.name}(${rendered.join(', ')})${ret != null ? `: ${ret}` : ''}`;
    const signature = {
        label,
        parameters: paramInfos,
    };
    const active = Math.min(activeParamIndex(source, openParen + 1, offset), Math.max(0, params.length - 1));
    return {
        signatures: [signature],
        activeSignature: 0,
        activeParameter: active,
    };
}
//# sourceMappingURL=signatureHelp.js.map