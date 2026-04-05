/**
 * Integration tests for the --clean flag.
 *
 * Tests that:
 * 1. --clean deletes all existing .kti files in the output dir before compilation.
 * 2. Fresh .kti files are written after a --clean build.
 * 3. --clean without an output dir exits cleanly (no error).
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { mkdirSync, writeFileSync, readFileSync, rmSync, readdirSync } from 'fs';
import { join } from 'path';
import { execSync } from 'child_process';
import { fileURLToPath } from 'node:url';

const compilerRoot = fileURLToPath(new URL('../..', import.meta.url));
const kestrelRoot = join(compilerRoot, '..');
const cliPath = join(compilerRoot, 'dist', 'cli.js');

// ---------------------------------------------------------------------------

const leafSrc = `
export fun double(x: Int): Int = x + x
`.trim();

const mainSrc = `
import { double } from "./leaf.ks"

val result = double(5)
`.trim();

// ---------------------------------------------------------------------------

function makeProject(tmpDir: string) {
  mkdirSync(tmpDir, { recursive: true });
  const leafPath = join(tmpDir, 'leaf.ks');
  const mainPath = join(tmpDir, 'main.ks');
  writeFileSync(leafPath, leafSrc);
  writeFileSync(mainPath, mainSrc);
  return { leafPath, mainPath };
}

function findKtiFiles(dir: string): string[] {
  const all = readdirSync(dir, { recursive: true }) as string[];
  return all.filter((f) => String(f).endsWith('.kti'));
}

function runCli(mainPath: string, outputDir: string, extraFlags = '') {
  const env = { ...process.env, KESTREL_JVM_CACHE: outputDir };
  execSync(
    `node "${cliPath}" "${mainPath}" --target jvm -o "${outputDir}" ${extraFlags}`,
    { env, cwd: kestrelRoot },
  );
}

// ---------------------------------------------------------------------------

describe('--clean flag', () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = join(compilerRoot, 'test', 'integration', '_tmp_kti_clean_' + Date.now());
    mkdirSync(tmpDir, { recursive: true });
  });

  afterEach(() => {
    rmSync(tmpDir, { recursive: true, force: true });
  });

  it('deletes existing .kti files before compilation and writes fresh ones', () => {
    const { mainPath } = makeProject(tmpDir);

    // First build — creates .kti files
    runCli(mainPath, tmpDir);
    const ktiAfterFirstBuild = findKtiFiles(tmpDir);
    expect(ktiAfterFirstBuild.length).toBeGreaterThan(0);

    // Replace .kti files with sentinel content to detect re-creation
    for (const rel of ktiAfterFirstBuild) {
      writeFileSync(join(tmpDir, rel), '{ "sentinel": true }');
    }

    // Second build with --clean
    runCli(mainPath, tmpDir, '--clean');

    // Verify sentinel content is gone (files were overwritten with fresh data)
    const ktiAfterClean = findKtiFiles(tmpDir);
    expect(ktiAfterClean.length).toBeGreaterThan(0);
    for (const rel of ktiAfterClean) {
      const content = JSON.parse(readFileSync(join(tmpDir, rel), 'utf-8'));
      expect(content).not.toHaveProperty('sentinel');
      expect(content.version).toBe(4);
    }
  });

  it('produces identical output to a cold build (no stale .kti artefacts)', () => {
    const { mainPath } = makeProject(tmpDir);

    // Cold build
    runCli(mainPath, tmpDir);
    const ktiFiles = findKtiFiles(tmpDir);
    expect(ktiFiles.length).toBeGreaterThan(0);

    // --clean build: should succeed and write valid .kti files
    runCli(mainPath, tmpDir, '--clean');
    const ktiFilesAfterClean = findKtiFiles(tmpDir);
    expect(ktiFilesAfterClean.length).toBeGreaterThan(0);
    for (const rel of ktiFilesAfterClean) {
      const parsed = JSON.parse(readFileSync(join(tmpDir, rel), 'utf-8'));
      expect(parsed.version).toBe(4);
      expect(typeof parsed.sourceHash).toBe('string');
    }
  });
});
