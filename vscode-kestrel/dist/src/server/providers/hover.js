"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.buildHover = buildHover;
const compiler_bridge_1 = require("../compiler-bridge");
function offsetFromPosition(source, pos) {
    let line = 0;
    let column = 0;
    for (let i = 0; i < source.length; i++) {
        if (line === pos.line && column === pos.character) {
            return i;
        }
        const ch = source.charCodeAt(i);
        if (ch === 10) {
            line++;
            column = 0;
        }
        else {
            column++;
        }
    }
    return source.length;
}
async function buildHover(source, ast, position) {
    const offset = offsetFromPosition(source, position);
    const typeText = await (0, compiler_bridge_1.hoverTypeAtOffset)(ast, offset);
    if (typeText == null) {
        return null;
    }
    return {
        contents: {
            kind: 'markdown',
            value: `\`\`\`kestrel\n${typeText}\n\`\`\``,
        },
    };
}
//# sourceMappingURL=hover.js.map