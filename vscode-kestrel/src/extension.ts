import * as path from 'node:path';

import * as vscode from 'vscode';
import {
  LanguageClient,
  type LanguageClientOptions,
  TransportKind,
  type ServerOptions,
} from 'vscode-languageclient/node';

let client: LanguageClient | undefined;

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
    synchronize: {
      fileEvents: vscode.workspace.createFileSystemWatcher('**/*.ks'),
    },
  };

  client = new LanguageClient('kestrel-language-server', 'Kestrel Language Server', serverOptions, clientOptions);
  await client.start();
}

export async function deactivate(): Promise<void> {
  if (client == null) {
    return;
  }
  await client.stop();
}
