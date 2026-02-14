#!/usr/bin/env node
/**
 * CLI: kestrel-compiler <input.ks> [-o output.kbc]
 * Parse input, emit .kbc to output (default: stdout or <input>.kbc).
 */
import { readFileSync, writeFileSync } from 'fs';
import { compile, emitKbc } from './src/index.js';

const args = process.argv.slice(2);
if (args.length < 1) {
  process.stderr.write('Usage: kestrel-compiler <input.ks> [-o output.kbc]\n');
  process.exit(1);
}
const inputPath = args[0]!;
const outIdx = args.indexOf('-o');
const outputPath = outIdx >= 0 ? args[outIdx + 1] : inputPath.replace(/\.ks$/, '') + '.kbc';

const source = readFileSync(inputPath, 'utf-8');
const result = compile(source);
if (!result.ok) {
  process.stderr.write(result.errors.join('\n') + '\n');
  process.exit(1);
}
const kbc = emitKbc(result.ast);
writeFileSync(outputPath, kbc);
process.stderr.write(`Wrote ${outputPath} (${kbc.length} bytes)\n`);
