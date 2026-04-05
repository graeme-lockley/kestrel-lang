import { describe, it, expect, beforeAll } from 'vitest';
import { execSync } from 'child_process';
import { mkdtempSync, writeFileSync, rmSync, readFileSync } from 'fs';
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
      `import * as Fs from "kestrel:io/fs"
import * as Str from "kestrel:data/string"

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
      `import * as Fs from "kestrel:io/fs"
import { NotFound } from "kestrel:io/fs"

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
      `import * as Fs from "kestrel:io/fs"
import * as Str from "kestrel:data/string"
import * as Basics from "kestrel:data/basics"

async fun run(): Task<Unit> = {
  val launchStart = Basics.nowMs();
  val leftTask = Fs.readText(${JSON.stringify(leftPath)});
  val rightTask = Fs.readText(${JSON.stringify(rightPath)});
  val launchedMs = Basics.nowMs() - launchStart;

  val waitStart = Basics.nowMs();
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
  val waitedMs = Basics.nowMs() - waitStart;

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
      `import * as Fs from "kestrel:io/fs"
import { File, Dir, DirEntry } from "kestrel:io/fs"
import * as Lst from "kestrel:data/list"
import * as Str from "kestrel:data/string"

fun hasFile(entries: List<DirEntry>, name: String): Bool =
  Lst.any(entries, (e: DirEntry) => match (e) {
    File(p) => Str.contains(name, p),
    Dir(_) => False
  })

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
        val a = if (hasFile(entries, "a.txt")) 1 else 0;
        val b = if (hasFile(entries, "b.txt")) 1 else 0;
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
      `import * as Fs from "kestrel:io/fs"
import { NotFound } from "kestrel:io/fs"

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

  it('await Fs.writeText(...) returns Ok(()) and content is readable back', () => {
    const tmpRoot = mkdtempSync(join(tmpdir(), 'kestrel-runtime-stdlib-writetext-'));
    const outPath = join(tmpRoot, 'written.txt');
    const srcPath = join(tmpRoot, 'RuntimeStdlibWriteText.ks');

    writeFileSync(
      srcPath,
      `import * as Fs from "kestrel:io/fs"
import * as Str from "kestrel:data/string"

async fun run(): Task<Unit> = {
  val writeResult = await Fs.writeText(${JSON.stringify(outPath)}, "hello write\\n");
  val ok =
    match (writeResult) {
      Ok(_) => 1,
      _ => 0
    };
  println(ok);
  val text =
    match (await Fs.readText(${JSON.stringify(outPath)})) {
      Ok(v) => v,
      Err(_) => ""
    };
  println(Str.length(text));
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
      expect(stdout).toBe('1\n12\n');
    } finally {
      rmSync(tmpRoot, { recursive: true, force: true });
    }
  });

  it('await Fs.writeText(...) returns Err(NotFound) for missing parent directory', () => {
    const tmpRoot = mkdtempSync(join(tmpdir(), 'kestrel-runtime-stdlib-writetext-missing-'));
    const badPath = join(tmpRoot, '__no_such_parent__', 'out.txt');
    const srcPath = join(tmpRoot, 'RuntimeStdlibWriteTextMissing.ks');

    writeFileSync(
      srcPath,
      `import * as Fs from "kestrel:io/fs"
import { NotFound } from "kestrel:io/fs"

async fun run(): Task<Unit> = {
  val caught =
    match (await Fs.writeText(${JSON.stringify(badPath)}, "x")) {
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

  it('await Process.runProcess(...) captures combined output and returns Ok(ProcessResult)', () => {
    const tmpRoot = mkdtempSync(join(tmpdir(), 'kestrel-runtime-stdlib-runprocess-'));
    const srcPath = join(tmpRoot, 'RuntimeStdlibRunProcess.ks');

    writeFileSync(
      srcPath,
      `import * as Process from "kestrel:sys/process"

async fun run(): Task<Unit> = {
  match (await Process.runProcess("sh", ["-c", "echo out-line; echo err-line 1>&2; exit 7"])) {
    Ok(r) => {
      println("exit:\${r.exitCode}");
      println("stdout:\${r.stdout}");
      ()
    },
    Err(_) => {
      println("error");
      ()
    }
  }
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
      expect(stdout).toBe('exit:7\nstdout:out-line\nerr-line\n\n');
    } finally {
      rmSync(tmpRoot, { recursive: true, force: true });
    }
  });

  it('await Process.runProcess(...) returns Err(ProcessSpawnError(_)) for missing binary', () => {
    const tmpRoot = mkdtempSync(join(tmpdir(), 'kestrel-runtime-stdlib-runprocess-missing-'));
    const srcPath = join(tmpRoot, 'RuntimeStdlibRunProcessMissing.ks');

    writeFileSync(
      srcPath,
      `import * as Process from "kestrel:sys/process"
import { ProcessSpawnError } from "kestrel:sys/process"

async fun run(): Task<Unit> = {
  val caught =
    match (await Process.runProcess("__definitely_missing_binary_xyz__", [])) {
      Err(ProcessSpawnError(_)) => "spawn-error",
      _ => "unexpected"
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
      expect(stdout).toBe('spawn-error\n');
    } finally {
      rmSync(tmpRoot, { recursive: true, force: true });
    }
  });

  it('test runner generation awaits each suite run call inside async main', () => {
    execSync('./scripts/kestrel test --summary tests/unit/async_virtual_threads.test.ks', {
      cwd: kestrelRoot,
      stdio: 'pipe',
    });

    const generatedRunner = readFileSync(join(kestrelRoot, '.kestrel_test_runner.ks'), 'utf-8');
    expect(generatedRunner).toContain('async fun main(): Task<Unit> = {');
    expect(generatedRunner).toContain('await run0(root)');
    expect(generatedRunner).not.toMatch(/\nrun\d+\(root\)\n/);
  });
});
