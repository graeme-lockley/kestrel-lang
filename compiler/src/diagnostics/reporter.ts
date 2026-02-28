/**
 * Report diagnostics in human or JSON format (spec 10 §6, §7).
 */
import { readFileSync } from 'fs';
import { resolve } from 'path';
import type { Diagnostic, SourceLocation } from './types.js';

const TAB_WIDTH = 4;

export interface ReportOptions {
  format: 'human' | 'json';
  color?: boolean;
  projectRoot?: string;
  sourceByPath?: Map<string, string>;
  stream?: NodeJS.WritableStream;
}

function expandTabs(s: string): string {
  return s.replace(/\t/g, ' '.repeat(TAB_WIDTH));
}

function getFullSource(location: SourceLocation, options: ReportOptions): string | undefined {
  const path = location.file;
  if (!path || path === '<source>') return undefined;
  const normalized = resolve(path);
  const fromMap = options.sourceByPath?.get(path) ?? options.sourceByPath?.get(normalized);
  if (fromMap) return fromMap;
  try {
    return readFileSync(path, 'utf-8');
  } catch {
    try {
      return readFileSync(normalized, 'utf-8');
    } catch {
      return undefined;
    }
  }
}

/** 1-based line and column of the character at offset. */
function lineColumnFromOffset(source: string, offset: number): { line: number; column: number } {
  if (offset < 0 || offset >= source.length) return { line: 1, column: 1 };
  const before = source.slice(0, offset);
  const line = (before.match(/\n/g)?.length ?? 0) + 1;
  const startOfLine = before.lastIndexOf('\n') + 1;
  const column = offset - startOfLine + 1;
  return { line, column };
}

/** 0-based column on the line containing offset (for caret placement). */
function caretCol0FromOffset(source: string, offset: number): number {
  if (offset < 0 || offset >= source.length) return 0;
  const before = source.slice(0, offset);
  const startOfLine = before.lastIndexOf('\n') + 1;
  return offset - startOfLine;
}

function getSourceLine(location: SourceLocation, options: ReportOptions): string | undefined {
  const source = getFullSource(location, options);
  if (!source) return undefined;
  const lines = source.split(/\r?\n/);
  const lineIndex = location.line - 1;
  if (lineIndex < 0 || lineIndex >= lines.length) return undefined;
  return expandTabs(lines[lineIndex]!);
}

/** Caret line: align with source line. Source line prefix is " N | " (1 + lineNum.length + 3), caret prefix is "    " (4). */
function caretLine(
  location: SourceLocation,
  sourceLine: string | undefined,
  message: string,
  col0: number,
  lineNum: string
): string {
  if (!sourceLine) return `    ^ ${message}`;
  const sourcePrefixLen = 1 + lineNum.length + 3;
  const pad = Math.max(0, sourcePrefixLen - 4);
  const col = col0 + pad;
  const before = sourceLine.slice(0, col).replace(/[^\s]/g, ' ');
  const spanLen = Math.max(1, (location.endColumn ?? location.column) - location.column);
  const caret = '^'.repeat(spanLen);
  return `    ${before}${caret} ${message}`;
}

const dim = (s: string) => `\x1b[2m${s}\x1b[0m`;
const red = (s: string) => `\x1b[31m${s}\x1b[0m`;
const yellow = (s: string) => `\x1b[33m${s}\x1b[0m`;

function formatHuman(diagnostics: Diagnostic[], options: ReportOptions): string {
  const out: string[] = [];
  const color = options.color ?? false;
  const stream = options.stream ?? process.stderr;

  for (const d of diagnostics) {
    const loc = d.location;
    const fileDisplay = loc.file || '<source>';
    const source = getFullSource(loc, options);

    const fromOffset =
      source != null && loc.offset !== undefined
        ? lineColumnFromOffset(source, loc.offset)
        : null;
    const displayLine = fromOffset?.line ?? loc.line;
    const displayColumn = fromOffset?.column ?? loc.column;
    const col0 =
      source != null && loc.offset !== undefined
        ? caretCol0FromOffset(source, loc.offset)
        : loc.column - 1;

    const header = `  --> ${fileDisplay}:${displayLine}:${displayColumn}`;
    const lineNum = String(displayLine);
    const src = d.sourceLine ?? getSourceLine(loc, options);
    const caretStr = caretLine(loc, src, d.message, col0, lineNum);

    if (color && (stream as NodeJS.WriteStream & { isTTY?: boolean }).isTTY) {
      out.push(dim(header));
      out.push('   |');
      out.push(dim(` ${lineNum} |`) + ` ${src ?? ''}`);
      out.push(d.severity === 'warning' ? yellow(caretStr) : red(caretStr));
      if (d.hint) out.push(dim(`   = hint: ${d.hint}`));
      if (d.suggestion) out.push(dim(`   = note: ${d.suggestion}`));
    } else {
      out.push(header);
      out.push('   |');
      out.push(` ${lineNum} | ${src ?? ''}`);
      out.push(caretStr);
      if (d.hint) out.push(`   = hint: ${d.hint}`);
      if (d.suggestion) out.push(`   = note: ${d.suggestion}`);
    }
    out.push('');
  }
  return out.join('\n');
}

function formatJson(diagnostics: Diagnostic[]): string {
  return diagnostics.map((d) => JSON.stringify(d)).join('\n') + (diagnostics.length ? '\n' : '');
}

export function report(diagnostics: Diagnostic[], options: ReportOptions): void {
  const stream = options.stream ?? process.stderr;
  if (options.format === 'json') {
    stream.write(formatJson(diagnostics));
  } else {
    stream.write(formatHuman(diagnostics, options));
  }
}
