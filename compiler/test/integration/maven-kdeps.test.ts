import { describe, it, expect } from 'vitest';
import { mkdirSync, writeFileSync, readFileSync, rmSync, existsSync } from 'fs';
import { join } from 'path';
import { fileURLToPath } from 'node:url';
import { compileFileJvm } from '../../src/compile-file-jvm.js';

const compilerRoot = fileURLToPath(new URL('../..', import.meta.url));
const kestrelRoot = join(compilerRoot, '..');
const stdlibDir = join(kestrelRoot, 'stdlib');

describe('maven imports', () => {
  it('emits .kdeps sidecar for maven imports', () => {
    const tmpDir = join(compilerRoot, 'test', 'integration', `_tmp_maven_kdeps_${Date.now()}`);
    const cacheRoot = join(tmpDir, 'maven-cache');
    const srcPath = join(tmpDir, 'main.ks');
    const oldCache = process.env.KESTREL_MAVEN_CACHE;

    mkdirSync(join(cacheRoot, 'org', 'example', 'demo', '1.2.3'), { recursive: true });
    writeFileSync(join(cacheRoot, 'org', 'example', 'demo', '1.2.3', 'demo-1.2.3.jar'), 'fake-jar');
    mkdirSync(tmpDir, { recursive: true });
    writeFileSync(
      srcPath,
      'import "maven:org.example:demo:1.2.3"\nfun main(): Unit = println("ok")\n'
    );

    process.env.KESTREL_MAVEN_CACHE = cacheRoot;

    try {
      const result = compileFileJvm(srcPath, {
        projectRoot: kestrelRoot,
        stdlibDir,
        getClassOutputDir: () => tmpDir,
      });
      expect(result.ok).toBe(true);
      if (!result.ok) return;

      const kdepsPath = join(tmpDir, `${result.mainClass}.kdeps`);
      expect(existsSync(kdepsPath)).toBe(true);
      const kdeps = JSON.parse(readFileSync(kdepsPath, 'utf-8')) as {
        maven: Record<string, string>;
        jars: Record<string, string>;
      };
      expect(kdeps.maven['org.example:demo']).toBe('1.2.3');
      expect(kdeps.jars['org.example:demo']).toContain('demo-1.2.3.jar');
    } finally {
      if (oldCache == null) delete process.env.KESTREL_MAVEN_CACHE;
      else process.env.KESTREL_MAVEN_CACHE = oldCache;
      rmSync(tmpDir, { recursive: true, force: true });
    }
  });
});
