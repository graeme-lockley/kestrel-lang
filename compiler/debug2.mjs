import { compile } from './dist/src/index.js';

const tests = [
  ['val annotated', `val resp: Int = 42`],
  ['fun get alone', `fun get(url: String): Int = 42`],
  ['fun get + typed val', `fun get(url: String): Int = 42\nval resp: Int = get("x")`],
  ['throwable', `export exception Ex\nfun get(url: String): Int = throw Ex\nval resp: Int = get("x")`],
];

for (const [label, code] of tests) {
  const r = compile(code);
  if (!r.ok) {
    console.error(`FAIL [${label}]:`);
    r.diagnostics.forEach(d => console.error('  -', d.message));
  } else {
    console.log(`PASS [${label}]`);
  }
}
