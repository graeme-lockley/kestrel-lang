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
const node_fs_1 = require("node:fs");
const node_path_1 = require("node:path");
const oniguruma = __importStar(require("vscode-oniguruma"));
const vscode_textmate_1 = require("vscode-textmate");
const vitest_1 = require("vitest");
const here = __dirname;
const root = (0, node_path_1.join)(here, '..', '..');
const grammarPath = (0, node_path_1.join)(root, 'syntaxes', 'kestrel.tmLanguage.json');
let wasmLoaded = false;
async function loadRegistry() {
    if (!wasmLoaded) {
        const onigWasmPath = (0, node_path_1.join)(root, 'node_modules', 'vscode-oniguruma', 'release', 'onig.wasm');
        const wasmBin = (0, node_fs_1.readFileSync)(onigWasmPath);
        const wasmBuffer = wasmBin.buffer.slice(wasmBin.byteOffset, wasmBin.byteOffset + wasmBin.byteLength);
        await oniguruma.loadWASM(wasmBuffer);
        wasmLoaded = true;
    }
    return new vscode_textmate_1.Registry({
        onigLib: Promise.resolve({
            createOnigScanner: (patterns) => new oniguruma.OnigScanner(patterns),
            createOnigString: (s) => new oniguruma.OnigString(s)
        }),
        loadGrammar: async (scopeName) => {
            if (scopeName !== 'source.kestrel') {
                return null;
            }
            const raw = (0, node_fs_1.readFileSync)(grammarPath, 'utf8');
            return JSON.parse(raw);
        }
    });
}
async function tokenize(line) {
    const registry = await loadRegistry();
    const grammar = await registry.loadGrammar('source.kestrel');
    if (!grammar) {
        throw new Error('Failed to load grammar');
    }
    return grammar.tokenizeLine(line, null).tokens;
}
(0, vitest_1.describe)('kestrel TextMate grammar', () => {
    (0, vitest_1.it)('scopes keywords as keyword.control.kestrel', async () => {
        const tokens = await tokenize('fun add(a: Int): Int = 1');
        const keyword = tokens.find((t) => t.scopes.includes('keyword.control.kestrel'));
        (0, vitest_1.expect)(keyword).toBeDefined();
    });
    (0, vitest_1.it)('scopes True/False as constant.language.boolean.kestrel', async () => {
        const tokens = await tokenize('val x = True');
        const bool = tokens.find((t) => t.scopes.includes('constant.language.boolean.kestrel'));
        (0, vitest_1.expect)(bool).toBeDefined();
    });
    (0, vitest_1.it)('scopes PascalCase names as entity.name.type.kestrel', async () => {
        const tokens = await tokenize('val x: Option<Int> = None');
        const typeToken = tokens.find((t) => t.scopes.includes('entity.name.type.kestrel'));
        (0, vitest_1.expect)(typeToken).toBeDefined();
    });
    (0, vitest_1.it)('scopes string literals as string.quoted.double.kestrel', async () => {
        const tokens = await tokenize('val s = "hello"');
        const str = tokens.find((t) => t.scopes.includes('string.quoted.double.kestrel'));
        (0, vitest_1.expect)(str).toBeDefined();
    });
});
//# sourceMappingURL=grammar.test.js.map