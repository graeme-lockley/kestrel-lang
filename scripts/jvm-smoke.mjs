#!/usr/bin/env node
import { compile, emitJvm } from '../compiler/dist/src/index.js';
import { readFileSync, writeFileSync, mkdirSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, '..');

const src = readFileSync(join(root, 'tests/jvm/hello.ks'), 'utf-8');
const r = compile(src, { sourceFile: 'tests/jvm/hello.ks' });
if (!r.ok) {
  console.error(r.diagnostics);
  process.exit(1);
}
const jvm = emitJvm(r.ast, { sourceFile: 'tests/jvm/hello.ks' });
const outDir = join(root, 'tests/jvm/out');
mkdirSync(outDir, { recursive: true });
const classPath = join(outDir, jvm.className.replace(/\//g, '/') + '.class');
mkdirSync(dirname(classPath), { recursive: true });
writeFileSync(classPath, jvm.classBytes);
console.log('Wrote', classPath);
console.log('ClassName', jvm.className);
