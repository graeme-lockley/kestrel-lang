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
exports.compileSource = compileSource;
exports.hoverTypeAtOffset = hoverTypeAtOffset;
exports.inferredTypeText = inferredTypeText;
exports.tokenizeSource = tokenizeSource;
const fs = __importStar(require("node:fs"));
const path = __importStar(require("node:path"));
const node_url_1 = require("node:url");
let compileFnPromise;
let helperModulesPromise;
async function loadCompileFn() {
    if (compileFnPromise != null) {
        return compileFnPromise;
    }
    compileFnPromise = (async () => {
        const compilerEntry = path.join(resolveCompilerDistSrcDir(), 'index.js');
        const moduleUrl = (0, node_url_1.pathToFileURL)(compilerEntry).href;
        const mod = (await Promise.resolve(`${moduleUrl}`).then(s => __importStar(require(s))));
        if (typeof mod.compile !== 'function') {
            throw new Error('Failed to load compile() from compiler/dist/index.js');
        }
        return mod.compile;
    })();
    return compileFnPromise;
}
function resolveCompilerDistSrcDir() {
    const candidates = [
        path.resolve(__dirname, '../../compiler/dist/src'),
        path.resolve(__dirname, '../../../../compiler/dist/src'),
        path.resolve(__dirname, '../../../compiler/dist/src'),
        path.resolve(process.cwd(), 'compiler/dist/src'),
        path.resolve(process.cwd(), '../compiler/dist/src'),
        path.resolve(process.cwd(), '../../compiler/dist/src'),
    ];
    for (const c of candidates) {
        if (fs.existsSync(path.join(c, 'index.js'))) {
            return c;
        }
    }
    throw new Error('Unable to locate compiler/dist/src directory from vscode-kestrel server context');
}
async function compileSource(source, sourceFile) {
    const compile = await loadCompileFn();
    const result = compile(source, { sourceFile });
    const diagnostics = result.ok ? [] : result.diagnostics;
    const { tokenize, parse, typecheck } = await loadHelperModules();
    const tokens = tokenize(source);
    const parsed = parse(tokens);
    if ('ok' in parsed && parsed.ok === false) {
        return { ast: null, diagnostics };
    }
    const ast = parsed;
    typecheck(ast, { sourceFile, sourceContent: source });
    return { ast, diagnostics };
}
async function loadHelperModules() {
    if (helperModulesPromise != null) {
        return helperModulesPromise;
    }
    helperModulesPromise = (async () => {
        const compilerDist = resolveCompilerDistSrcDir();
        const parserModule = (0, node_url_1.pathToFileURL)(path.join(compilerDist, 'parser', 'index.js')).href;
        const typecheckModule = (0, node_url_1.pathToFileURL)(path.join(compilerDist, 'typecheck', 'index.js')).href;
        const astModule = (0, node_url_1.pathToFileURL)(path.join(compilerDist, 'ast', 'index.js')).href;
        const typesModule = (0, node_url_1.pathToFileURL)(path.join(compilerDist, 'types', 'index.js')).href;
        const rootModule = (0, node_url_1.pathToFileURL)(path.join(compilerDist, 'index.js')).href;
        const [parser, typecheck, ast, types, root] = await Promise.all([
            Promise.resolve(`${parserModule}`).then(s => __importStar(require(s))),
            Promise.resolve(`${typecheckModule}`).then(s => __importStar(require(s))),
            Promise.resolve(`${astModule}`).then(s => __importStar(require(s))),
            Promise.resolve(`${typesModule}`).then(s => __importStar(require(s))),
            Promise.resolve(`${rootModule}`).then(s => __importStar(require(s))),
        ]);
        return {
            tokenize: root.tokenize,
            parse: parser.parse,
            typecheck: typecheck.typecheck,
            findNodeAtOffset: ast.findNodeAtOffset,
            getInferredType: typecheck.getInferredType,
            printType: types.printType,
        };
    })();
    return helperModulesPromise;
}
async function hoverTypeAtOffset(ast, offset) {
    if (ast == null) {
        return null;
    }
    const { findNodeAtOffset, getInferredType, printType } = await loadHelperModules();
    const node = findNodeAtOffset(ast, offset);
    if (node == null) {
        return null;
    }
    const inferred = getInferredType(node);
    if (inferred == null) {
        return null;
    }
    return printType(inferred);
}
async function inferredTypeText(node) {
    const { getInferredType, printType } = await loadHelperModules();
    const inferred = getInferredType(node);
    if (inferred == null) {
        return null;
    }
    return printType(inferred);
}
async function tokenizeSource(source) {
    const { tokenize } = await loadHelperModules();
    return tokenize(source);
}
//# sourceMappingURL=compiler-bridge.js.map