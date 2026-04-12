"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
const vitest_1 = require("vitest");
const bridge = __importStar(require("../../src/server/compiler-bridge"));
const inlayHints_1 = require("../../src/server/providers/inlayHints");
(0, vitest_1.describe)('collectInlayHints', () => {
    (0, vitest_1.it)('adds inlay hints for untyped val declarations', async () => {
        const spy = vitest_1.vi.spyOn(bridge, 'inferredTypeText').mockResolvedValue('Int');
        const ast = {
            kind: 'Program',
            body: [
                {
                    kind: 'ValDecl',
                    name: 'x',
                    span: { line: 1, column: 5 },
                    value: { kind: 'LiteralExpr' },
                },
            ],
        };
        const hints = await (0, inlayHints_1.collectInlayHints)(ast);
        (0, vitest_1.expect)(hints).toHaveLength(1);
        (0, vitest_1.expect)(hints[0]?.label).toBe(': Int');
        spy.mockRestore();
    });
    (0, vitest_1.it)('does not add hints for explicitly typed val declarations', async () => {
        const spy = vitest_1.vi.spyOn(bridge, 'inferredTypeText').mockResolvedValue('Int');
        const ast = {
            kind: 'Program',
            body: [
                {
                    kind: 'ValDecl',
                    name: 'x',
                    span: { line: 1, column: 5 },
                    type: { kind: 'PrimType', name: 'Int' },
                    value: { kind: 'LiteralExpr' },
                },
            ],
        };
        const hints = await (0, inlayHints_1.collectInlayHints)(ast);
        (0, vitest_1.expect)(hints).toHaveLength(0);
        spy.mockRestore();
    });
});
//# sourceMappingURL=inlayHints.test.js.map