import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import * as path from 'node:path';
import { pathToFileURL } from 'node:url';

export interface TempWorkspace {
  rootDir: string;
  uriFor: (relativePath: string) => string;
  dispose: () => void;
}

export function createTempWorkspace(files: Record<string, string>): TempWorkspace {
  const rootDir = mkdtempSync(path.join(tmpdir(), 'kestrel-vscode-'));
  for (const [relativePath, content] of Object.entries(files)) {
    const filePath = path.join(rootDir, relativePath);
    mkdirSync(path.dirname(filePath), { recursive: true });
    writeFileSync(filePath, content, 'utf8');
  }

  return {
    rootDir,
    uriFor(relativePath: string): string {
      return pathToFileURL(path.join(rootDir, relativePath)).href;
    },
    dispose(): void {
      rmSync(rootDir, { recursive: true, force: true });
    },
  };
}