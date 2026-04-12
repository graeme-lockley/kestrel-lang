import * as path from 'node:path';

import * as vscode from 'vscode';
import {
  LanguageClient,
  type LanguageClientOptions,
  TransportKind,
  type ServerOptions,
} from 'vscode-languageclient/node';

let client: LanguageClient | undefined;

function shellEscape(arg: string): string {
  return `"${arg.replaceAll('"', '\\"')}"`;
}

function kestrelExecutable(): string {
  return vscode.workspace.getConfiguration('kestrel').get<string>('executable', 'kestrel');
}

function runTestCommand(testName: string, uri: string, debug: boolean): void {
  const filePath = vscode.Uri.parse(uri).fsPath;
  const terminal = vscode.window.createTerminal(debug ? 'Kestrel Debug Test' : 'Kestrel Test');
  const mode = debug ? '--verbose' : '--summary';
  const cmd = `${kestrelExecutable()} test ${mode} --filter ${shellEscape(testName)} ${shellEscape(filePath)}`;
  terminal.show(true);
  terminal.sendText(cmd);
}

export async function activate(context: vscode.ExtensionContext): Promise<void> {
  const serverModule = context.asAbsolutePath(path.join('dist', 'src', 'server', 'server.js'));

  const serverOptions: ServerOptions = {
    run: { module: serverModule, transport: TransportKind.ipc },
    debug: {
      module: serverModule,
      transport: TransportKind.ipc,
      options: { execArgv: ['--nolazy', '--inspect=6010'] },
    },
  };

  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: 'file', language: 'kestrel' }],
    initializationOptions: {
      debounceMs: vscode.workspace.getConfiguration('kestrel').get<number>('lsp.debounceMs', 250),
    },
    synchronize: {
      fileEvents: vscode.workspace.createFileSystemWatcher('**/*.ks'),
    },
  };

  context.subscriptions.push(
    vscode.commands.registerCommand('kestrel.runTest', (testName: string, uri: string) => {
      runTestCommand(testName, uri, false);
    }),
    vscode.commands.registerCommand('kestrel.debugTest', (testName: string, uri: string) => {
      runTestCommand(testName, uri, true);
    }),
  );

  client = new LanguageClient('kestrel-language-server', 'Kestrel Language Server', serverOptions, clientOptions);
  await client.start();
}

export async function deactivate(): Promise<void> {
  if (client == null) {
    return;
  }
  await client.stop();
}
