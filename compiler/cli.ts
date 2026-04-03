#!/usr/bin/env node
/**
 * CLI: kestrel-compiler <input.ks> [-o outputDir] [--target jvm] [--stale-file path] [--format=json]
 * Parse input, resolve imports, emit JVM .class files.
 * When -o is omitted, output goes under KESTREL_JVM_CACHE (~/.kestrel/jvm/ by default).
 * If --stale-file is given, only print "Compiling X" for paths listed in that file (one path per line).
 * If --format=json, emit diagnostics as JSONL on failure (spec 10).
 */
import { resolve, basename, dirname, join } from 'path';
import { readFileSync } from 'fs';
import { homedir } from 'os';
import { compileFileJvm } from './src/compile-file-jvm.js';
import { report } from './src/diagnostics/index.js';

const args = process.argv.slice(2);
if (args.length < 1) {
  process.stderr.write('Usage: kestrel-compiler <input.ks> [-o outputDir] [--target jvm] [--stale-file path] [--format=json]\n');
  process.exit(1);
}
const inputPath = args[0]!;
const outIdx = args.indexOf('-o');
const targetIdx = args.indexOf('--target');
if (targetIdx >= 0) {
  const target = args[targetIdx + 1];
  if (target !== 'jvm') {
    process.stderr.write('Error: only --target jvm is supported\n');
    process.exit(1);
  }
}
const entryResolved = resolve(inputPath);
const cacheRoot = process.env.KESTREL_JVM_CACHE || join(homedir(), '.kestrel', 'jvm');
const outputPath = outIdx >= 0 ? args[outIdx + 1]! : cacheRoot;
const formatJson = args.includes('--format=json');
const staleIdx = args.indexOf('--stale-file');
const staleFilePath = staleIdx >= 0 ? args[staleIdx + 1] : undefined;
let stalePaths: Set<string> | undefined;
if (staleFilePath) {
  try {
    const content = readFileSync(staleFilePath, 'utf-8');
    stalePaths = new Set(content.split('\n').map((p) => p.trim()).filter(Boolean));
  } catch {
    stalePaths = new Set();
  }
}

const entryAbs = entryResolved;

const classDir = outputPath;
const getClassOutputDir = (_sourcePath: string): string => classDir;
const result = compileFileJvm(resolve(inputPath), {
  projectRoot: process.cwd(),
  stalePaths,
  getClassOutputDir,
  onCompilingFile: (absolutePath, durationMs) => {
    process.stderr.write('\x1b[90mCompiling ' + basename(absolutePath) + ' (' + durationMs + 'ms)\x1b[0m\n');
  },
});
if (!result.ok) {
  const sourceByPath = new Map<string, string>();
  for (const d of result.diagnostics) {
    const p = d.location?.file;
    if (p && p !== '<source>' && !sourceByPath.has(p)) {
      try {
        const content = readFileSync(p, 'utf-8');
        sourceByPath.set(p, content);
        sourceByPath.set(resolve(p), content);
      } catch {
        try {
          const content = readFileSync(resolve(p), 'utf-8');
          sourceByPath.set(p, content);
          sourceByPath.set(resolve(p), content);
        } catch {
          // reporter will fall back to loc.line/column
        }
      }
    }
  }
  report(result.diagnostics, {
    format: formatJson ? 'json' : 'human',
    color: !process.env.NO_COLOR && process.stderr.isTTY,
    stream: process.stderr,
    sourceByPath,
  });
  process.exit(1);
}
process.exit(0);
