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
const signatureHelp_1 = require("../../src/server/providers/signatureHelp");
(0, vitest_1.describe)('provideSignatureHelp', () => {
    (0, vitest_1.it)('builds signature and active parameter for second argument', async () => {
        const spy = vitest_1.vi.spyOn(bridge, 'inferredTypeText').mockResolvedValue('Int');
        const source = 'fun add(a: Int, b: Int): Int = a + b\nval x = add(1, 2)\n';
        const ast = {
            kind: 'Program',
            body: [
                {
                    kind: 'FunDecl',
                    name: 'add',
                    params: [{ name: 'a' }, { name: 'b' }],
                    returnType: { kind: 'PrimType', name: 'Int' },
                },
            ],
        };
        const sig = await (0, signatureHelp_1.provideSignatureHelp)(ast, source, { line: 1, character: 14 });
        (0, vitest_1.expect)(sig?.activeParameter).toBe(1);
        (0, vitest_1.expect)(sig?.signatures[0]?.label.startsWith('add(')).toBe(true);
        spy.mockRestore();
    });
    (0, vitest_1.it)('returns null when no matching function declaration exists', async () => {
        const source = 'val x = unknown(1)\n';
        const ast = { kind: 'Program', body: [] };
        const sig = await (0, signatureHelp_1.provideSignatureHelp)(ast, source, { line: 0, character: 14 });
        (0, vitest_1.expect)(sig).toBeNull();
    });
});
//# sourceMappingURL=signatureHelp.test.js.map