#!/usr/bin/env node
/**
 * CLI: kestrel-compiler <input.ks> [-o output.kbc]
 * Parse input, resolve imports, emit .kbc to output (default: stdout or <input>.kbc).
 */
import { resolve } from 'path';
import { writeFileSync } from 'fs';
import { compileFile } from './src/compile-file.js';

const args = process.argv.slice(2);
if (args.length < 1) {
  process.stderr.write('Usage: kestrel-compiler <input.ks> [-o output.kbc]\n');
  process.exit(1);
}
const inputPath = args[0]!;
const outIdx = args.indexOf('-o');
const outputPath = outIdx >= 0 ? args[outIdx + 1] : inputPath.replace(/\.ks$/, '') + '.kbc';

const result = compileFile(resolve(inputPath), { projectRoot: process.cwd() });
if (!result.ok) {
  process.stderr.write(result.errors.join('\n') + '\n');
  process.exit(1);
}
writeFileSync(outputPath, result.kbc);
process.stderr.write(`Wrote ${outputPath} (${result.kbc.length} bytes)\n`);
