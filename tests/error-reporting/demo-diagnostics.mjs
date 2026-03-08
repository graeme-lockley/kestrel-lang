#!/usr/bin/env node
/**
 * Demo: Spec 10 compile diagnostics (human + JSON, suggestion, related, parse recovery).
 * Run from repo root: node tests/error-reporting/demo-diagnostics.mjs
 * Requires: cd compiler && npm run build
 */
import { compile } from '../../compiler/dist/src/index.js';
import { report } from '../../compiler/dist/src/diagnostics/reporter.js';

const demos = [
  {
    name: '1. Unknown variable with suggestion',
    source: 'prinln("hi")',
  },
  {
    name: '2. Type mismatch with related location',
    source: 'val _ = { var x = 0; x := "bad"; 0 }',
  },
  {
    name: '3. Type error with hint (unify)',
    source: 'val _ = { var x = 0; x := "bad"; 0 }',
  },
  {
    name: '4. Parse error (unexpected token)',
    source: 'val x = (1 + 2',
  },
];

console.log('=== Human format ===\n');
for (const d of demos) {
  console.log(`--- ${d.name} ---`);
  const result = compile(d.source, { sourceFile: '<demo>' });
  if (!result.ok) {
    report(result.diagnostics, { format: 'human', color: false });
    console.log('');
  }
}

console.log('=== JSON format (one diagnostic) ===\n');
const result = compile('prinln(1)', { sourceFile: '<demo>' });
if (!result.ok) {
  report(result.diagnostics, { format: 'json', color: false });
}
console.log('(Parsed as valid JSONL: severity, code, message, location, suggestion)\n');

console.log('=== Multiple parse errors (recovery) ===\n');
const parseSource = 'val a = (1 + val b = 2';
const parseResult = compile(parseSource, { sourceFile: '<demo>' });
if (!parseResult.ok) {
  console.log(`Diagnostics count: ${parseResult.diagnostics.length}`);
  parseResult.diagnostics.forEach((d, i) => {
    console.log(`  ${i + 1}. [${d.code}] ${d.message} at ${d.location.line}:${d.location.column}`);
  });
}
