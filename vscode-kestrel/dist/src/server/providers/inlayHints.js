"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.collectInlayHints = collectInlayHints;
const compiler_bridge_1 = require("../compiler-bridge");
function hintPosition(span, name) {
    return { line: Math.max(0, span.line - 1), character: Math.max(0, span.column - 1 + name.length) };
}
async function collectInlayHints(ast) {
    if (ast == null || typeof ast !== 'object') {
        return [];
    }
    const out = [];
    const program = ast;
    for (const node of program.body ?? []) {
        if (node == null || typeof node !== 'object') {
            continue;
        }
        const d = node;
        if ((d.kind === 'ValDecl' || d.kind === 'VarDecl') && d.type == null && d.name != null && d.span != null && d.value != null) {
            const text = await (0, compiler_bridge_1.inferredTypeText)(d.value);
            if (text != null) {
                out.push({
                    position: hintPosition(d.span, d.name),
                    label: `: ${text}`,
                });
            }
        }
        if (d.kind === 'FunDecl') {
            for (const p of d.params ?? []) {
                if (p.name == null || p.type != null || p.span == null) {
                    continue;
                }
                const text = await (0, compiler_bridge_1.inferredTypeText)(p);
                if (text != null) {
                    out.push({
                        position: hintPosition(p.span, p.name),
                        label: `: ${text}`,
                    });
                }
            }
        }
    }
    return out;
}
//# sourceMappingURL=inlayHints.js.map