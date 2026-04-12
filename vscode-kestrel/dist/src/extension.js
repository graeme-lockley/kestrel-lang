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
exports.activate = activate;
exports.deactivate = deactivate;
const path = __importStar(require("node:path"));
const vscode = __importStar(require("vscode"));
const node_1 = require("vscode-languageclient/node");
let client;
function shellEscape(arg) {
    return `"${arg.replaceAll('"', '\\"')}"`;
}
function kestrelExecutable() {
    return vscode.workspace.getConfiguration('kestrel').get('executable', 'kestrel');
}
function runTestCommand(testName, uri, debug) {
    const filePath = vscode.Uri.parse(uri).fsPath;
    const terminal = vscode.window.createTerminal(debug ? 'Kestrel Debug Test' : 'Kestrel Test');
    const mode = debug ? '--verbose' : '--summary';
    const cmd = `${kestrelExecutable()} test ${mode} --filter ${shellEscape(testName)} ${shellEscape(filePath)}`;
    terminal.show(true);
    terminal.sendText(cmd);
}
async function activate(context) {
    const config = vscode.workspace.getConfiguration('kestrel');
    const serverModule = context.asAbsolutePath(path.join('dist', 'src', 'server', 'server.js'));
    const serverOptions = {
        run: { module: serverModule, transport: node_1.TransportKind.ipc },
        debug: {
            module: serverModule,
            transport: node_1.TransportKind.ipc,
            options: { execArgv: ['--nolazy', '--inspect=6010'] },
        },
    };
    const clientOptions = {
        documentSelector: [{ scheme: 'file', language: 'kestrel' }],
        initializationOptions: {
            debounceMs: config.get('lsp.debounceMs', 250),
            executable: config.get('executable', 'kestrel'),
            formatterEnabled: config.get('formatter.enabled', true),
        },
        synchronize: {
            fileEvents: vscode.workspace.createFileSystemWatcher('**/*.ks'),
        },
    };
    context.subscriptions.push(vscode.commands.registerCommand('kestrel.runTest', (testName, uri) => {
        runTestCommand(testName, uri, false);
    }), vscode.commands.registerCommand('kestrel.debugTest', (testName, uri) => {
        runTestCommand(testName, uri, true);
    }));
    client = new node_1.LanguageClient('kestrel-language-server', 'Kestrel Language Server', serverOptions, clientOptions);
    await client.start();
}
async function deactivate() {
    if (client == null) {
        return;
    }
    await client.stop();
}
//# sourceMappingURL=extension.js.map