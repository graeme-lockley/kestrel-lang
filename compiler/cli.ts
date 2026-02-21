#!/usr/bin/env node
/**
 * CLI: kestrel-compiler <input.ks> [-o output.kbc] [--stale-file path]
 * Parse input, resolve imports, emit .kbc to output (default: stdout or <input>.kbc).
 * If --stale-file is given, only print "Compiling X" for paths listed in that file (one path per line).
 * When -o is used, getOutputPaths writes the entry to -o and deps to KESTREL_CACHE mirror (07 §5).
 */
import { resolve, basename, dirname, join } from 'path';
import { writeFileSync, readFileSync } from 'fs';
import { homedir } from 'os';
import { compileFile } from './src/compile-file.js';

const args = process.argv.slice(2);
if (args.length < 1) {
  process.stderr.write('Usage: kestrel-compiler <input.ks> [-o output.kbc] [--stale-file path]\n');
  process.exit(1);
}
const inputPath = args[0]!;
const outIdx = args.indexOf('-o');
const outputPath = outIdx >= 0 ? args[outIdx + 1] : inputPath.replace(/\.ks$/, '') + '.kbc';
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

const entryAbs = resolve(inputPath);
const cacheRoot = process.env.KESTREL_CACHE || join(homedir(), '.kestrel', 'kbc');
function getOutputPaths(sourcePath: string): { kbc: string; kti: string } {
  const abs = resolve(sourcePath);
  if (abs === entryAbs) return { kbc: outputPath, kti: outputPath.replace(/\.kbc$/, '.kti') };
  const root = dirname(abs).match(/^[A-Za-z]:[\\/]/)?.[0] ?? (abs.startsWith('/') ? '/' : '');
  const relDir = root ? (process.platform === 'win32' ? dirname(abs).replace(/^[A-Za-z]:[\\/]/, '').replace(/\\/g, '/') : dirname(abs).slice(1)) : dirname(abs);
  const base = basename(abs, '.ks');
  return { kbc: join(cacheRoot, relDir, base + '.kbc'), kti: join(cacheRoot, relDir, base + '.kti') };
}

const result = compileFile(resolve(inputPath), {
  projectRoot: process.cwd(),
  stalePaths,
  getOutputPaths,
  onCompilingFile: (absolutePath, durationMs) => {
    process.stderr.write('\x1b[90mCompiling ' + basename(absolutePath) + ' (' + durationMs + 'ms)\x1b[0m\n');
  },
});
if (!result.ok) {
  process.stderr.write(result.errors.join('\n') + '\n');
  process.exit(1);
}
writeFileSync(outputPath, result.kbc);
const depsPath = outputPath + '.deps';
writeFileSync(depsPath, result.dependencyPaths.join('\n') + '\n');
