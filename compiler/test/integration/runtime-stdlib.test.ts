import { describe, it, expect } from 'vitest';
import { execSync } from 'child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import { fileURLToPath } from 'node:url';
import { compileFileJvm } from '../../src/compile-file-jvm.js';

const compilerRoot = fileURLToPath(new URL('../..', import.meta.url));
const kestrelRoot = join(compilerRoot, '..');
const stdlibDir = join(kestrelRoot, 'stdlib');
const runtimeJar = join(kestrelRoot, 'runtime', 'jvm', 'kestrel-runtime.jar');

describe('JVM runtime stdlib async wiring', () => {
  it('await Fs.readText(...) through KTask plumbing prints expected length', () => {
    const tmpRoot = mkdtempSync(join(tmpdir(), 'kestrel-runtime-stdlib-'));
    const fixturePath = join(tmpRoot, 'fixture.txt');
    const srcPath = join(tmpRoot, 'RuntimeStdlibAsync.ks');
    writeFileSync(fixturePath, 'abc');

    writeFileSync(
      srcPath,
      `import * as Fs from "kestrel:fs"
import * as Str from "kestrel:string"

async fun run(): Task<Unit> = {
  val t = await Fs.readText(${JSON.stringify(fixturePath)});
  println(Str.length(t));
  ()
}

run()
`
    );

    try {
      const compileResult = compileFileJvm(srcPath, {
        projectRoot: kestrelRoot,
        stdlibDir,
        getClassOutputDir: () => tmpRoot,
      });
      expect(compileResult.ok).toBe(true);
      if (!compileResult.ok) return;

      execSync('./build.sh', {
        cwd: join(kestrelRoot, 'runtime', 'jvm'),
        stdio: 'pipe',
      });

      const mainClass = compileResult.mainClass.replace(/\//g, '.');
      const stdout = execSync(`java -cp "${runtimeJar}:${tmpRoot}" "${mainClass}"`, {
        cwd: kestrelRoot,
        encoding: 'utf-8',
        stdio: ['pipe', 'pipe', 'pipe'],
      });
      expect(stdout).toBe('3\n');
    } finally {
      rmSync(tmpRoot, { recursive: true, force: true });
    }
  });
});
