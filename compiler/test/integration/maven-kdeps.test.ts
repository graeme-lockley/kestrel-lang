import { describe, it, expect } from 'vitest';
import { mkdirSync, writeFileSync, readFileSync, rmSync, existsSync } from 'fs';
import { join, resolve as pathResolve, dirname as pathDirname, basename as pathBasename } from 'path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'child_process';
import { compileFileJvm } from '../../src/compile-file-jvm.js';

const compilerRoot = fileURLToPath(new URL('../..', import.meta.url));
const kestrelRoot = join(compilerRoot, '..');
const stdlibDir = join(kestrelRoot, 'stdlib');
const resolverScript = join(kestrelRoot, 'scripts', 'resolve-maven-classpath.mjs');

/** Create a fake jar in a temp maven cache and return the cache root. */
function populateCache(cacheRoot: string, groupId: string, artifactId: string, version: string): string {
  const jarDir = join(cacheRoot, ...groupId.split('.'), artifactId, version);
  mkdirSync(jarDir, { recursive: true });
  writeFileSync(join(jarDir, `${artifactId}-${version}.jar`), 'fake-jar');
  return join(jarDir, `${artifactId}-${version}.jar`);
}

function withMavenEnv(cacheRoot: string, fn: () => void): void {
  const old = process.env.KESTREL_MAVEN_CACHE;
  process.env.KESTREL_MAVEN_CACHE = cacheRoot;
  try {
    fn();
  } finally {
    if (old == null) delete process.env.KESTREL_MAVEN_CACHE;
    else process.env.KESTREL_MAVEN_CACHE = old;
  }
}

// ---------------------------------------------------------------------------
// compile-file-jvm: .kdeps sidecar emission
// ---------------------------------------------------------------------------

describe('maven imports: .kdeps sidecar emission', () => {
  it('emits .kdeps sidecar for a single maven import', () => {
    const tmpDir = join(compilerRoot, 'test', 'integration', `_tmp_maven_kdeps_${Date.now()}`);
    const cacheRoot = join(tmpDir, 'maven-cache');
    const srcPath = join(tmpDir, 'main.ks');
    mkdirSync(tmpDir, { recursive: true });
    populateCache(cacheRoot, 'org.example', 'demo', '1.2.3');
    writeFileSync(srcPath, 'import "maven:org.example:demo:1.2.3"\nfun main(): Unit = println("ok")\n');

    withMavenEnv(cacheRoot, () => {
      const result = compileFileJvm(srcPath, {
        projectRoot: kestrelRoot,
        stdlibDir,
        getClassOutputDir: () => tmpDir,
      });
      expect(result.ok).toBe(true);
      if (!result.ok) return;

      const kdepsPath = join(tmpDir, `${result.mainClass}.kdeps`);
      expect(existsSync(kdepsPath), 'kdeps file should exist').toBe(true);
      const kdeps = JSON.parse(readFileSync(kdepsPath, 'utf-8')) as {
        maven: Record<string, string>;
        jars: Record<string, string>;
      };
      expect(kdeps.maven['org.example:demo']).toBe('1.2.3');
      expect(kdeps.jars['org.example:demo']).toContain('demo-1.2.3.jar');
    });

    rmSync(tmpDir, { recursive: true, force: true });
  });

  it('records multiple maven imports in .kdeps', () => {
    const tmpDir = join(compilerRoot, 'test', 'integration', `_tmp_maven_multi_${Date.now()}`);
    const cacheRoot = join(tmpDir, 'maven-cache');
    const srcPath = join(tmpDir, 'main.ks');
    mkdirSync(tmpDir, { recursive: true });
    populateCache(cacheRoot, 'org.example', 'alpha', '1.0.0');
    populateCache(cacheRoot, 'org.example', 'beta', '2.0.0');
    writeFileSync(
      srcPath,
      `import "maven:org.example:alpha:1.0.0"\nimport "maven:org.example:beta:2.0.0"\nfun main(): Unit = println("ok")\n`
    );

    withMavenEnv(cacheRoot, () => {
      const result = compileFileJvm(srcPath, {
        projectRoot: kestrelRoot,
        stdlibDir,
        getClassOutputDir: () => tmpDir,
      });
      expect(result.ok).toBe(true);
      if (!result.ok) return;

      const kdepsPath = join(tmpDir, `${result.mainClass}.kdeps`);
      expect(existsSync(kdepsPath), 'kdeps file should exist').toBe(true);
      const kdeps = JSON.parse(readFileSync(kdepsPath, 'utf-8')) as {
        maven: Record<string, string>;
        jars: Record<string, string>;
      };
      expect(kdeps.maven['org.example:alpha']).toBe('1.0.0');
      expect(kdeps.maven['org.example:beta']).toBe('2.0.0');
      expect(kdeps.jars['org.example:alpha']).toContain('alpha-1.0.0.jar');
      expect(kdeps.jars['org.example:beta']).toContain('beta-2.0.0.jar');
    });

    rmSync(tmpDir, { recursive: true, force: true });
  });

  it('fails compilation when maven import is non-side-effect form', () => {
    const tmpDir = join(compilerRoot, 'test', 'integration', `_tmp_maven_named_${Date.now()}`);
    const cacheRoot = join(tmpDir, 'maven-cache');
    const srcPath = join(tmpDir, 'main.ks');
    mkdirSync(tmpDir, { recursive: true });
    populateCache(cacheRoot, 'org.example', 'demo', '1.0.0');
    // Named import of a maven specifier — should be rejected
    writeFileSync(srcPath, 'import { Foo } from "maven:org.example:demo:1.0.0"\nfun main(): Unit = println("ok")\n');

    withMavenEnv(cacheRoot, () => {
      const result = compileFileJvm(srcPath, {
        projectRoot: kestrelRoot,
        stdlibDir,
        getClassOutputDir: () => tmpDir,
      });
      expect(result.ok).toBe(false);
      if (result.ok) return;
      const msgs = result.diagnostics.map((d) => d.message).join('\n');
      expect(msgs).toContain('maven imports are classpath declarations only');
    });

    rmSync(tmpDir, { recursive: true, force: true });
  });

  it('fails compilation for malformed maven specifier (too few parts)', () => {
    const tmpDir = join(compilerRoot, 'test', 'integration', `_tmp_maven_bad_${Date.now()}`);
    const cacheRoot = join(tmpDir, 'maven-cache');
    const srcPath = join(tmpDir, 'main.ks');
    mkdirSync(tmpDir, { recursive: true });
    // maven:bad — only one segment, no version
    writeFileSync(srcPath, 'import "maven:bad"\nfun main(): Unit = println("ok")\n');

    withMavenEnv(cacheRoot, () => {
      const result = compileFileJvm(srcPath, {
        projectRoot: kestrelRoot,
        stdlibDir,
        getClassOutputDir: () => tmpDir,
      });
      expect(result.ok).toBe(false);
      if (result.ok) return;
      const msgs = result.diagnostics.map((d) => d.message).join('\n');
      expect(msgs).toContain('maven resolution failed');
    });

    rmSync(tmpDir, { recursive: true, force: true });
  });

  it('fails compilation for maven specifier missing version (two parts only)', () => {
    const tmpDir = join(compilerRoot, 'test', 'integration', `_tmp_maven_nover_${Date.now()}`);
    const cacheRoot = join(tmpDir, 'maven-cache');
    const srcPath = join(tmpDir, 'main.ks');
    mkdirSync(tmpDir, { recursive: true });
    writeFileSync(srcPath, 'import "maven:org.example:demo"\nfun main(): Unit = println("ok")\n');

    withMavenEnv(cacheRoot, () => {
      const result = compileFileJvm(srcPath, {
        projectRoot: kestrelRoot,
        stdlibDir,
        getClassOutputDir: () => tmpDir,
      });
      expect(result.ok).toBe(false);
      if (result.ok) return;
      const msgs = result.diagnostics.map((d) => d.message).join('\n');
      expect(msgs).toContain('maven resolution failed');
    });

    rmSync(tmpDir, { recursive: true, force: true });
  });
});

// ---------------------------------------------------------------------------
// resolve-maven-classpath.mjs: classpath resolution script
// ---------------------------------------------------------------------------

/**
 * Derive the class-internal name for a source path, mirroring the logic in
 * scripts/resolve-maven-classpath.mjs:classInternalNameForSource.
 */
function classInternalNameForSource(sourcePath: string): string {
  const abs = pathResolve(sourcePath).replace(/\\/g, '/');
  const rel = abs.startsWith('/') ? abs.slice(1) : abs;
  const dir = pathDirname(rel);
  const base = pathBasename(rel, '.ks').replace(/[^a-zA-Z0-9_]/g, '_');
  const classBase = base.slice(0, 1).toUpperCase() + base.slice(1);
  if (!dir || dir === '.') return classBase;
  return `${dir.replace(/[^a-zA-Z0-9_/]/g, '_')}/${classBase}`;
}

/** Compute the .kdeps path for a source file and ensure its parent directory exists. */
function kdepsFileForSource(classDir: string, sourcePath: string): string {
  const internal = classInternalNameForSource(sourcePath);
  const kdepsPath = join(classDir, `${internal}.kdeps`);
  mkdirSync(pathDirname(kdepsPath), { recursive: true });
  return kdepsPath;
}

/** Compute the .class.deps path for a source file and ensure its parent directory exists. */
function classDepsFileForSource(classDir: string, sourcePath: string): string {
  const internal = classInternalNameForSource(sourcePath);
  const depsPath = join(classDir, `${internal}.class.deps`);
  mkdirSync(pathDirname(depsPath), { recursive: true });
  return depsPath;
}

function makeKdeps(maven: Record<string, string>, jars: Record<string, string>): string {
  return JSON.stringify({ maven, jars });
}

function runResolver(
  entrySource: string,
  classDir: string,
  env: Record<string, string> = {}
): { status: number | null; stdout: string; stderr: string } {
  const r = spawnSync(process.execPath, [resolverScript, entrySource, classDir], {
    encoding: 'utf-8',
    env: { ...process.env, ...env },
  });
  return { status: r.status, stdout: r.stdout ?? '', stderr: r.stderr ?? '' };
}

describe('resolve-maven-classpath: classpath builder', () => {
  it('outputs the jar path for a single dependency', () => {
    const tmpDir = join(compilerRoot, 'test', 'integration', `_tmp_resolver_single_${Date.now()}`);
    mkdirSync(tmpDir, { recursive: true });

    const srcPath = join(tmpDir, 'main.ks');
    writeFileSync(srcPath, '');

    const jarPath = join(tmpDir, 'alpha-1.0.0.jar');
    writeFileSync(jarPath, 'fake-jar');
    writeFileSync(
      kdepsFileForSource(tmpDir, srcPath),
      makeKdeps({ 'org.example:alpha': '1.0.0' }, { 'org.example:alpha': jarPath })
    );

    const { status, stdout, stderr } = runResolver(srcPath, tmpDir);
    expect(stderr).toBe('');
    expect(status).toBe(0);
    expect(stdout).toContain('alpha-1.0.0.jar');

    rmSync(tmpDir, { recursive: true, force: true });
  });

  it('combines classpath from multiple jars', () => {
    const tmpDir = join(compilerRoot, 'test', 'integration', `_tmp_resolver_multi_${Date.now()}`);
    mkdirSync(tmpDir, { recursive: true });

    const srcPath = join(tmpDir, 'main.ks');
    writeFileSync(srcPath, '');

    const jarA = join(tmpDir, 'alpha-1.0.0.jar');
    const jarB = join(tmpDir, 'beta-2.0.0.jar');
    writeFileSync(jarA, 'fake');
    writeFileSync(jarB, 'fake');
    writeFileSync(
      kdepsFileForSource(tmpDir, srcPath),
      makeKdeps(
        { 'org.example:alpha': '1.0.0', 'org.example:beta': '2.0.0' },
        { 'org.example:alpha': jarA, 'org.example:beta': jarB }
      )
    );

    const { status, stdout, stderr } = runResolver(srcPath, tmpDir);
    expect(stderr).toBe('');
    expect(status).toBe(0);
    expect(stdout).toContain('alpha-1.0.0.jar');
    expect(stdout).toContain('beta-2.0.0.jar');

    rmSync(tmpDir, { recursive: true, force: true });
  });

  it('succeeds when the same version appears in two transitive modules', () => {
    const tmpDir = join(compilerRoot, 'test', 'integration', `_tmp_resolver_same_${Date.now()}`);
    mkdirSync(tmpDir, { recursive: true });

    const mainSrc = join(tmpDir, 'main.ks');
    const depSrc = join(tmpDir, 'dep.ks');
    writeFileSync(mainSrc, '');
    writeFileSync(depSrc, '');

    const jar = join(tmpDir, 'alpha-1.0.0.jar');
    writeFileSync(jar, 'fake');

    // main.ks depends on dep.ks
    writeFileSync(classDepsFileForSource(tmpDir, mainSrc), depSrc + '\n');
    writeFileSync(
      kdepsFileForSource(tmpDir, mainSrc),
      makeKdeps({ 'org.example:alpha': '1.0.0' }, { 'org.example:alpha': jar })
    );
    writeFileSync(
      kdepsFileForSource(tmpDir, depSrc),
      makeKdeps({ 'org.example:alpha': '1.0.0' }, { 'org.example:alpha': jar })
    );

    const { status, stderr } = runResolver(mainSrc, tmpDir);
    expect(stderr).toBe('');
    expect(status).toBe(0);

    rmSync(tmpDir, { recursive: true, force: true });
  });
});

describe('resolve-maven-classpath: conflict detection', () => {
  it('exits with code 2 and conflict message when two modules require different versions', () => {
    const tmpDir = join(compilerRoot, 'test', 'integration', `_tmp_resolver_conflict_${Date.now()}`);
    mkdirSync(tmpDir, { recursive: true });

    const mainSrc = join(tmpDir, 'main.ks');
    const depSrc = join(tmpDir, 'dep.ks');
    writeFileSync(mainSrc, '');
    writeFileSync(depSrc, '');

    const jar1 = join(tmpDir, 'alpha-1.0.0.jar');
    const jar2 = join(tmpDir, 'alpha-2.0.0.jar');
    writeFileSync(jar1, 'fake');
    writeFileSync(jar2, 'fake');

    // main.ks depends on dep.ks
    writeFileSync(classDepsFileForSource(tmpDir, mainSrc), depSrc + '\n');
    writeFileSync(
      kdepsFileForSource(tmpDir, mainSrc),
      makeKdeps({ 'org.example:alpha': '1.0.0' }, { 'org.example:alpha': jar1 })
    );
    writeFileSync(
      kdepsFileForSource(tmpDir, depSrc),
      makeKdeps({ 'org.example:alpha': '2.0.0' }, { 'org.example:alpha': jar2 })
    );

    const { status, stderr } = runResolver(mainSrc, tmpDir);
    expect(status).toBe(2);
    expect(stderr).toContain('Dependency conflict:');
    expect(stderr).toContain('org.example:alpha');
    expect(stderr).toContain('1.0.0');
    expect(stderr).toContain('2.0.0');
    expect(stderr).toContain('Fix:');

    rmSync(tmpDir, { recursive: true, force: true });
  });
});

describe('resolve-maven-classpath: missing jar', () => {
  it('exits with code 1 and error message when a jar file is absent from disk', () => {
    const tmpDir = join(compilerRoot, 'test', 'integration', `_tmp_resolver_missing_${Date.now()}`);
    mkdirSync(tmpDir, { recursive: true });

    const srcPath = join(tmpDir, 'main.ks');
    writeFileSync(srcPath, '');

    const missingJar = join(tmpDir, 'gone-1.0.0.jar');
    // Intentionally do NOT create the jar file
    writeFileSync(
      kdepsFileForSource(tmpDir, srcPath),
      makeKdeps({ 'org.example:gone': '1.0.0' }, { 'org.example:gone': missingJar })
    );

    const { status, stderr } = runResolver(srcPath, tmpDir);
    expect(status).toBe(1);
    expect(stderr).toContain('maven artifact missing');
    expect(stderr).toContain('gone-1.0.0.jar');

    rmSync(tmpDir, { recursive: true, force: true });
  });
});
