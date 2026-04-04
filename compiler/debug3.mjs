import { compileFileJvm } from './dist/src/compile-file-jvm.js';
import { writeFileSync, mkdirSync, rmSync } from 'fs';
import { join } from 'path';
import { fileURLToPath } from 'url';
import { tmpdir } from 'os';
import { mkdtempSync } from 'fs';

const compilerRoot = fileURLToPath(new URL('.', import.meta.url));
const kestrelRoot = join(compilerRoot, '..');
const stdlibDir = join(kestrelRoot, 'stdlib');

const tmpDir = mkdtempSync(join(tmpdir(), 'kestrel-http-test-'));
const srcPath = join(tmpDir, 'TestHttp.ks');

writeFileSync(srcPath, `import * as Http from "kestrel:http"

fun main(): Unit = {
  println("http module resolved")
}
`);

const result = compileFileJvm(srcPath, {
  projectRoot: kestrelRoot,
  stdlibDir,
});
if (!result.ok) {
  console.error('FAIL:', result.diagnostics.map(d => d.message).join('\n'));
} else {
  console.log('PASS: import kestrel:http compiles OK');
}

rmSync(tmpDir, { recursive: true, force: true });
