import { describe, it, expect, beforeAll } from 'vitest';
import { execSync } from 'child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import { fileURLToPath } from 'node:url';
import { compileFileJvm } from '../../src/compile-file-jvm.js';

const compilerRoot = fileURLToPath(new URL('../..', import.meta.url));
const kestrelRoot = join(compilerRoot, '..');
const stdlibDir = join(kestrelRoot, 'stdlib');
const runtimeDir = join(kestrelRoot, 'runtime', 'jvm');
const runtimeJar = join(kestrelRoot, 'runtime', 'jvm', 'kestrel-runtime.jar');

describe('JVM runtime stdlib async wiring', () => {
  beforeAll(() => {
    execSync('./build.sh', {
      cwd: runtimeDir,
      stdio: 'pipe',
    });
  });

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
  val t =
    match (await Fs.readText(${JSON.stringify(fixturePath)})) {
      Ok(v) => v,
      Err(_) => ""
    };
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

  it('await Fs.readText(...) returns Err(NotFound) for missing path', () => {
    const tmpRoot = mkdtempSync(join(tmpdir(), 'kestrel-runtime-stdlib-missing-'));
    const missingPath = join(tmpRoot, '__missing__.txt');
    const srcPath = join(tmpRoot, 'RuntimeStdlibMissing.ks');

    writeFileSync(
      srcPath,
      `import * as Fs from "kestrel:fs"
import { NotFound } from "kestrel:fs"

async fun run(): Task<Unit> = {
  val caught =
    match (await Fs.readText(${JSON.stringify(missingPath)})) {
      Err(NotFound) => 1,
      _ => 0
  };
  println(caught);
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

      const mainClass = compileResult.mainClass.replace(/\//g, '.');
      const stdout = execSync(`java -cp "${runtimeJar}:${tmpRoot}" "${mainClass}"`, {
        cwd: kestrelRoot,
        encoding: 'utf-8',
        stdio: ['pipe', 'pipe', 'pipe'],
      });
      expect(stdout).toBe('1\n');
    } finally {
      rmSync(tmpRoot, { recursive: true, force: true });
    }
  });

  it('Fs.readText launches work before await on two files', () => {
    const tmpRoot = mkdtempSync(join(tmpdir(), 'kestrel-runtime-stdlib-overlap-'));
    const leftPath = join(tmpRoot, 'left.txt');
    const rightPath = join(tmpRoot, 'right.txt');
    const srcPath = join(tmpRoot, 'RuntimeStdlibOverlap.ks');
    const payloadBytes = 16 * 1024 * 1024;

    writeFileSync(leftPath, 'a'.repeat(payloadBytes));
    writeFileSync(rightPath, 'b'.repeat(payloadBytes));

    writeFileSync(
      srcPath,
      `import * as Fs from "kestrel:fs"
import * as Str from "kestrel:string"

async fun run(): Task<Unit> = {
  val launchStart = __now_ms();
  val leftTask = Fs.readText(${JSON.stringify(leftPath)});
  val rightTask = Fs.readText(${JSON.stringify(rightPath)});
  val launchedMs = __now_ms() - launchStart;

  val waitStart = __now_ms();
  val left =
    match (await leftTask) {
      Ok(v) => v,
      Err(_) => ""
    };
  val right =
    match (await rightTask) {
      Ok(v) => v,
      Err(_) => ""
    };
  val waitedMs = __now_ms() - waitStart;

  println(Str.length(left) + Str.length(right));
  println(if (launchedMs < waitedMs) "overlap" else "serial");
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

      const mainClass = compileResult.mainClass.replace(/\//g, '.');
      const stdout = execSync(`java -cp "${runtimeJar}:${tmpRoot}" "${mainClass}"`, {
        cwd: kestrelRoot,
        encoding: 'utf-8',
        stdio: ['pipe', 'pipe', 'pipe'],
      });
      expect(stdout).toBe(`${payloadBytes * 2}\noverlap\n`);
    } finally {
      rmSync(tmpRoot, { recursive: true, force: true });
    }
  });

  it('await Fs.listDir(...) returns entries for a known fixture directory', () => {
    const tmpRoot = mkdtempSync(join(tmpdir(), 'kestrel-runtime-stdlib-listdir-'));
    const fixtureDir = join(kestrelRoot, 'tests', 'fixtures', 'fs', 'list_sample');
    const srcPath = join(tmpRoot, 'RuntimeStdlibListDir.ks');

    writeFileSync(
      srcPath,
      `import * as Fs from "kestrel:fs"
import * as Lst from "kestrel:list"
import * as Str from "kestrel:string"

fun entryContains(entries: List<String>, needle: String): Bool =
  Lst.any(entries, (entry: String) => Str.contains(needle, entry))

async fun run(): Task<Unit> = {
  val result = await Fs.listDir(${JSON.stringify(fixtureDir)});
  val count =
    match (result) {
      Ok(entries) => Lst.length(entries),
      Err(_) => 0
    };
  val matched =
    match (result) {
      Ok(entries) => {
        val a = if (entryContains(entries, "a.txt\tfile")) 1 else 0;
        val b = if (entryContains(entries, "b.txt\tfile")) 1 else 0;
        a + b
      }
      Err(_) => 0
    };
  println(count);
  println(matched);
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

      const mainClass = compileResult.mainClass.replace(/\//g, '.');
      const stdout = execSync(`java -cp "${runtimeJar}:${tmpRoot}" "${mainClass}"`, {
        cwd: kestrelRoot,
        encoding: 'utf-8',
        stdio: ['pipe', 'pipe', 'pipe'],
      });
      expect(stdout).toBe('2\n2\n');
    } finally {
      rmSync(tmpRoot, { recursive: true, force: true });
    }
  });

  it('await Fs.listDir(...) returns Err(NotFound) for a missing directory', () => {
    const tmpRoot = mkdtempSync(join(tmpdir(), 'kestrel-runtime-stdlib-listdir-missing-'));
    const missingDir = join(tmpRoot, '__missing__');
    const srcPath = join(tmpRoot, 'RuntimeStdlibListDirMissing.ks');

    writeFileSync(
      srcPath,
      `import * as Fs from "kestrel:fs"
import { NotFound } from "kestrel:fs"

async fun run(): Task<Unit> = {
  val caught =
    match (await Fs.listDir(${JSON.stringify(missingDir)})) {
      Err(NotFound) => 1,
      _ => 0
    };
  println(caught);
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

      const mainClass = compileResult.mainClass.replace(/\//g, '.');
      const stdout = execSync(`java -cp "${runtimeJar}:${tmpRoot}" "${mainClass}"`, {
        cwd: kestrelRoot,
        encoding: 'utf-8',
        stdio: ['pipe', 'pipe', 'pipe'],
      });
      expect(stdout).toBe('1\n');
    } finally {
      rmSync(tmpRoot, { recursive: true, force: true });
    }
  });
});
