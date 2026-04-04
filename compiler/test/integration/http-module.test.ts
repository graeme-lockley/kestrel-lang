/**
 * Integration tests for kestrel:http module resolution (S03-01).
 *
 * Verifies that:
 * - `import * as Http from "kestrel:http"` resolves without error via stdlib
 * - All exported function names are usable in expressions after import
 * - The Http namespace is accessible in Kestrel code
 */
import { describe, it, expect } from 'vitest';
import { writeFileSync, mkdirSync, rmSync } from 'fs';
import { join } from 'path';
import { fileURLToPath } from 'node:url';
import { mkdtempSync } from 'fs';
import { tmpdir } from 'os';
import { compileFileJvm } from '../../src/compile-file-jvm.js';

const compilerRoot = fileURLToPath(new URL('../..', import.meta.url));
const kestrelRoot = join(compilerRoot, '..');
const stdlibDir = join(kestrelRoot, 'stdlib');

describe('kestrel:http module: stdlib resolution (S03-01)', () => {
  it('import * as Http from "kestrel:http" resolves without error', () => {
    const tmpDir = mkdtempSync(join(tmpdir(), 'kestrel-http-module-'));
    const srcPath = join(tmpDir, 'TestHttpImport.ks');
    writeFileSync(srcPath, `import * as Http from "kestrel:http"

fun main(): Unit = {
  println("ok")
}
`);
    try {
      const result = compileFileJvm(srcPath, { projectRoot: kestrelRoot, stdlibDir });
      if (!result.ok) {
        console.error('Compile errors:', result.diagnostics.map((d) => d.message).join('\n'));
      }
      expect(result.ok).toBe(true);
    } finally {
      rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  it('Http.nowMs is callable and returns Int', () => {
    const tmpDir = mkdtempSync(join(tmpdir(), 'kestrel-http-nowms-'));
    const srcPath = join(tmpDir, 'TestHttpNowMs.ks');
    writeFileSync(srcPath, `import * as Http from "kestrel:http"

fun main(): Unit = {
  val t = Http.nowMs()
  println(t)
}
`);
    try {
      const result = compileFileJvm(srcPath, { projectRoot: kestrelRoot, stdlibDir });
      expect(result.ok).toBe(true);
    } finally {
      rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  it('Http.Server, Http.Request, Http.Response opaque types are exported', () => {
    const tmpDir = mkdtempSync(join(tmpdir(), 'kestrel-http-types-'));
    const srcPath = join(tmpDir, 'TestHttpTypes.ks');
    writeFileSync(srcPath, `import * as Http from "kestrel:http"

fun acceptServer(s: Http.Server): Unit = ()
fun acceptRequest(r: Http.Request): Unit = ()
fun acceptResponse(r: Http.Response): Unit = ()
`);
    try {
      const result = compileFileJvm(srcPath, { projectRoot: kestrelRoot, stdlibDir });
      if (!result.ok) {
        console.error('Compile errors:', result.diagnostics.map((d) => d.message).join('\n'));
      }
      expect(result.ok).toBe(true);
    } finally {
      rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  it('Http.get is callable with a String argument', () => {
    const tmpDir = mkdtempSync(join(tmpdir(), 'kestrel-http-get-'));
    const srcPath = join(tmpDir, 'TestHttpGet.ks');
    writeFileSync(srcPath, `import * as Http from "kestrel:http"

fun getRef(): (String) -> Task<Http.Response> = Http.get
`);
    try {
      const result = compileFileJvm(srcPath, { projectRoot: kestrelRoot, stdlibDir });
      if (!result.ok) {
        console.error('Compile errors:', result.diagnostics.map((d) => d.message).join('\n'));
      }
      expect(result.ok).toBe(true);
    } finally {
      rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  it('Http.makeResponse is callable with Int and String arguments', () => {
    const tmpDir = mkdtempSync(join(tmpdir(), 'kestrel-http-makeresponse-'));
    const srcPath = join(tmpDir, 'TestHttpMakeResponse.ks');
    writeFileSync(srcPath, `import * as Http from "kestrel:http"

fun buildResp(): Http.Response = Http.makeResponse(200, "ok")
`);
    try {
      const result = compileFileJvm(srcPath, { projectRoot: kestrelRoot, stdlibDir });
      if (!result.ok) {
        console.error('Compile errors:', result.diagnostics.map((d) => d.message).join('\n'));
      }
      expect(result.ok).toBe(true);
    } finally {
      rmSync(tmpDir, { recursive: true, force: true });
    }
  });
});
