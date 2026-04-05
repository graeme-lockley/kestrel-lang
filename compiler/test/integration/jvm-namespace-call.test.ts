import { describe, it, expect } from 'vitest';
import { mkdirSync, writeFileSync, rmSync } from 'fs';
import { join } from 'path';
import { fileURLToPath } from 'node:url';
import { compileFileJvm } from '../../src/compile-file-jvm.js';

const compilerRoot = fileURLToPath(new URL('../..', import.meta.url));
const kestrelRoot = join(compilerRoot, '..');
const stdlibDir = join(kestrelRoot, 'stdlib');

describe('JVM codegen: namespace-qualified calls', () => {
  it('compiles Str.length(...) from import * as Str (FieldExpr callee)', () => {
    const tmpDir = join(compilerRoot, 'test', 'integration', '_tmp_jvm_ns_call');
    mkdirSync(tmpDir, { recursive: true });
    const srcPath = join(tmpDir, 'NsCall.ks');
    writeFileSync(
      srcPath,
      `import * as Str from "kestrel:data/string"

export fun main(): Unit = println(Str.length("hi"))
`
    );
    try {
      const result = compileFileJvm(srcPath, {
        projectRoot: kestrelRoot,
        stdlibDir,
        getClassOutputDir: () => tmpDir,
      });
      expect(result.ok).toBe(true);
    } finally {
      rmSync(tmpDir, { recursive: true, force: true });
    }
  });

  it('JVM-compiles kestrel:data/option (Some(_) must POP payload; avoids VerifyError)', () => {
    const srcPath = join(stdlibDir, 'kestrel', 'data', 'option.ks');
    const tmpDir = join(compilerRoot, 'test', 'integration', '_tmp_jvm_option');
    mkdirSync(tmpDir, { recursive: true });
    try {
      const result = compileFileJvm(srcPath, {
        projectRoot: kestrelRoot,
        stdlibDir,
        getClassOutputDir: () => tmpDir,
      });
      expect(result.ok).toBe(true);
    } finally {
      rmSync(tmpDir, { recursive: true, force: true });
    }
  });
});

describe('JVM codegen: class name sanitization', () => {
  it('generates a valid Java class name when the source path contains hyphens', () => {
    // Simulate a project checked out into a directory with hyphens (e.g. "kestrel-lang").
    // The returned mainClass must consist solely of valid Java identifier segments.
    const tmpDir = join(compilerRoot, 'test', 'integration', '_tmp_jvm-hyphen-dir');
    mkdirSync(tmpDir, { recursive: true });
    const srcPath = join(tmpDir, 'hello.ks');
    writeFileSync(srcPath, 'fun main(): Unit = println("hi")\n');
    try {
      const result = compileFileJvm(srcPath, {
        projectRoot: kestrelRoot,
        stdlibDir,
        getClassOutputDir: () => tmpDir,
      });
      expect(result.ok).toBe(true);
      if (result.ok) {
        // mainClass uses '/' as segment separator (JVM internal name).
        // Each segment must be a valid Java identifier (letters, digits, underscore only).
        const segments = result.mainClass.split('/');
        for (const seg of segments) {
          expect(seg).toMatch(/^[a-zA-Z0-9_]+$/);
        }
      }
    } finally {
      rmSync(tmpDir, { recursive: true, force: true });
    }
  });
});
