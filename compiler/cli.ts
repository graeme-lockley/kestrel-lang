#!/usr/bin/env node
/**
 * CLI: kestrel-compiler <input.ks> [-o output.kbc] [--stale-file path] [--format=json]
 * Parse input, resolve imports, emit .kbc. When -o is omitted, entry and deps go under KESTREL_CACHE
 * (~/.kestrel/kbc/ by default), mirroring the source path so we never write into the source tree.
 * When -o is used, the entry is written to that path and deps still go to the cache.
 * If --stale-file is given, only print "Compiling X" for paths listed in that file (one path per line).
 * If --format=json, emit diagnostics as JSONL on failure (spec 10).
 */
import { resolve, basename, dirname, join } from 'path';
import { writeFileSync, readFileSync } from 'fs';
import { homedir } from 'os';
import { compileFile } from './src/compile-file.js';
import { compileFileJvm } from './src/compile-file-jvm.js';
import { report } from './src/diagnostics/index.js';

const args = process.argv.slice(2);
if (args.length < 1) {
  process.stderr.write('Usage: kestrel-compiler <input.ks> [-o output.kbc|outputDir] [--target vm|jvm] [--stale-file path] [--format=json]\n');
  process.exit(1);
}
const inputPath = args[0]!;
const outIdx = args.indexOf('-o');
const targetJvm = args.includes('--target') && args[args.indexOf('--target') + 1] === 'jvm';
const entryResolved = resolve(inputPath);
const cacheRoot = targetJvm
  ? (process.env.KESTREL_JVM_CACHE || join(homedir(), '.kestrel', 'jvm'))
  : (process.env.KESTREL_CACHE || join(homedir(), '.kestrel', 'kbc'));
// When -o is omitted: put entry in cache so we don't write into source dir (especially stdlib).
function defaultEntryOutputPath(): string {
  const root = dirname(entryResolved).match(/^[A-Za-z]:[\\/]/)?.[0] ?? (entryResolved.startsWith('/') ? '/' : '');
  const relDir = root
    ? (process.platform === 'win32'
        ? dirname(entryResolved).replace(/^[A-Za-z]:[\\/]/, '').replace(/\\/g, '/')
        : dirname(entryResolved).slice(1))
    : dirname(entryResolved);
  const base = basename(entryResolved, '.ks');
  // For JVM, we always emit into the cache root. Stable class naming (based on absolute path)
  // ensures collisions don't occur, and this keeps JVM output independent of cwd.
  if (targetJvm) return cacheRoot;
  return join(cacheRoot, relDir, base + '.kbc');
}
const outputPath = outIdx >= 0 ? args[outIdx + 1]! : defaultEntryOutputPath();
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

if (targetJvm) {
  const jvmCacheRoot = process.env.KESTREL_JVM_CACHE || join(homedir(), '.kestrel', 'jvm');
  // When -o is provided, treat it as the JVM cache root override.
  const classDir = outIdx >= 0 ? outputPath : jvmCacheRoot;
  const getClassOutputDir = (_sourcePath: string): string => {
    return classDir;
  };
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
            /* fall back */
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
}

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
writeFileSync(outputPath, result.kbc);
const depsPath = outputPath + '.deps';
writeFileSync(depsPath, result.dependencyPaths.join('\n') + '\n');
