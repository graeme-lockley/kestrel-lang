import * as vscode from 'vscode';

export function activate(context: vscode.ExtensionContext): void {
  const msg = vscode.window.setStatusBarMessage('Kestrel extension active', 2500);
  context.subscriptions.push(msg);
}

export function deactivate(): void {
  // No-op for scaffold story; language server wiring lands in S10-02.
}
