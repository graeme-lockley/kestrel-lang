import { spawn } from 'node:child_process';

import type { Range, TextEdit } from 'vscode-languageserver/node';

export interface FormatterSettings {
  executable: string;
  enabled: boolean;
}

interface FormatterResult {
  ok: boolean;
  output: string;
}

type FormatterRunner = (source: string, executable: string) => Promise<FormatterResult>;

function fullRange(source: string): Range {
  const lines = source.split('\n');
  const endLine = Math.max(0, lines.length - 1);
  const endChar = (lines[endLine] ?? '').length;
  return {
    start: { line: 0, character: 0 },
    end: { line: endLine, character: endChar },
  };
}

async function runFormatter(source: string, executable: string): Promise<FormatterResult> {
  return new Promise((resolve) => {
    const child = spawn(executable, ['fmt', '--stdin'], { stdio: 'pipe' });
    let stdout = '';

    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString();
    });

    child.on('error', () => {
      resolve({ ok: false, output: '' });
    });

    child.on('close', (code) => {
      if (code === 0) {
        resolve({ ok: true, output: stdout });
      } else {
        resolve({ ok: false, output: '' });
      }
    });

    child.stdin.end(source);
  });
}

async function formatWithRunner(
  source: string,
  settings: FormatterSettings,
  runner: FormatterRunner,
): Promise<TextEdit[]> {
  if (!settings.enabled) {
    return [];
  }

  const result = await runner(source, settings.executable);
  if (!result.ok) {
    return [];
  }

  if (result.output === source) {
    return [];
  }

  return [{ range: fullRange(source), newText: result.output }];
}

export async function formatDocument(source: string, settings: FormatterSettings): Promise<TextEdit[]> {
  return formatWithRunner(source, settings, runFormatter);
}

export async function formatDocumentRange(
  source: string,
  settings: FormatterSettings,
  _range: Range,
): Promise<TextEdit[]> {
  return formatWithRunner(source, settings, runFormatter);
}

export async function testFormatDocument(
  source: string,
  settings: FormatterSettings,
  runner: FormatterRunner,
): Promise<TextEdit[]> {
  return formatWithRunner(source, settings, runner);
}
