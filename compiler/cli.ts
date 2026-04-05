#!/usr/bin/env node
/**
 * CLI: kestrel-compiler <input.ks> [-o outputDir] [--target jvm] [--stale-file path] [--format=json]
 *      [--refresh] [--allow-http] [--status]
 * Parse input, resolve imports, emit JVM .class files.
 * When -o is omitted, output goes under KESTREL_JVM_CACHE (~/.kestrel/jvm/ by default).
 * If --stale-file is given, only print "Compiling X" for paths listed in that file (one path per line).
 * If --format=json, emit diagnostics as JSONL on failure (spec 10).
 * If --refresh, force re-download of all URL dependencies.
 * If --allow-http, allow http:// (non-TLS) URL imports.
 * If --status, print URL dependency cache status report and exit 0 (no compilation).
 */
import { resolve, basename, join } from 'path';
import { readFileSync } from 'fs';
import { homedir } from 'os';
import { compileFileJvm } from './src/compile-file-jvm.js';
import { report } from './src/diagnostics/index.js';
import {
  defaultCacheRoot,
  defaultTtlSecs,
  prefetchUrlDependencies,
  buildStatusEntries,
  formatStatusReport,
} from './src/url-cache.js';
import type { Diagnostic } from './src/diagnostics/types.js';
import { CODES, locationFileOnly } from './src/diagnostics/types.js';

(async () => {
  const args = process.argv.slice(2);
  if (args.length < 1) {
    process.stderr.write('Usage: kestrel-compiler <input.ks> [-o outputDir] [--target jvm] [--stale-file path] [--format=json] [--refresh] [--allow-http] [--status]\n');
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
  const formatJson = args.includes('--format=json');
  const refresh = args.includes('--refresh');
  const allowHttp = args.includes('--allow-http');
  const statusMode = args.includes('--status');

  const urlCacheRoot = defaultCacheRoot();
  const jvmCacheRoot = process.env.KESTREL_JVM_CACHE || join(homedir(), '.kestrel', 'jvm');
  const outputPath = outIdx >= 0 ? args[outIdx + 1]! : jvmCacheRoot;
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

  // --status mode: resolve dep graph, print cache status, exit (no compilation)
  if (statusMode) {
    const entries = await buildStatusEntries(resolve(inputPath), urlCacheRoot, defaultTtlSecs());
    process.stdout.write(formatStatusReport(entries) + '\n');
    process.exit(0);
  }

  // Pre-fetch phase: fetch all URL dependencies into cache
  const fetchErrors = await prefetchUrlDependencies(resolve(inputPath), {
    cacheRoot: urlCacheRoot,
    allowHttp,
    refresh,
  });

  if (fetchErrors.length > 0) {
    const diagnostics: Diagnostic[] = fetchErrors.map((e) => ({
      severity: 'error' as const,
      code: CODES.resolve.module_not_found,
      message: e.error,
      location: locationFileOnly(e.importingFile),
    }));
    report(diagnostics, {
      format: formatJson ? 'json' : 'human',
      color: !process.env.NO_COLOR && process.stderr.isTTY,
      stream: process.stderr,
      sourceByPath: new Map(),
    });
    process.exit(1);
  }

  const classDir = outputPath;
  const getClassOutputDir = (_sourcePath: string): string => classDir;
  const result = compileFileJvm(resolve(inputPath), {
    projectRoot: process.cwd(),
    stalePaths,
    getClassOutputDir,
    urlCacheRoot,
    allowHttp,
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
})().catch((err) => {
  process.stderr.write(`kestrel-compiler: unexpected error: ${err instanceof Error ? err.message : String(err)}\n`);
  process.exit(1);
});

