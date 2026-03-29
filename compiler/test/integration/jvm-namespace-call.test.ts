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
      `import * as Str from "kestrel:string"

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

  it('JVM-compiles kestrel:option (Some(_) must POP payload; avoids VerifyError)', () => {
    const srcPath = join(stdlibDir, 'kestrel', 'option.ks');
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
