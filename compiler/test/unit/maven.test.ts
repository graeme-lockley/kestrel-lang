import { describe, it, expect } from 'vitest';
import { mkdirSync, writeFileSync, rmSync } from 'fs';
import { join } from 'path';
import { tmpdir } from 'os';
import { parseMavenSpecifier, resolveMavenSpecifiers } from '../../src/maven.js';

describe('maven specifiers', () => {
  it('parses maven coordinates', () => {
    const parsed = parseMavenSpecifier('maven:org.apache.commons:commons-lang3:3.20.0');
    expect(parsed.groupId).toBe('org.apache.commons');
    expect(parsed.artifactId).toBe('commons-lang3');
    expect(parsed.version).toBe('3.20.0');
    expect(parsed.ga).toBe('org.apache.commons:commons-lang3');
  });

  it('resolves from local cache without download', () => {
    const cacheRoot = join(tmpdir(), `kestrel-maven-test-${Date.now()}`);
    const oldCache = process.env.KESTREL_MAVEN_CACHE;
    process.env.KESTREL_MAVEN_CACHE = cacheRoot;
    const jarPath = join(
      cacheRoot,
      'org',
      'example',
      'demo',
      '1.2.3',
      'demo-1.2.3.jar'
    );
    mkdirSync(join(cacheRoot, 'org', 'example', 'demo', '1.2.3'), { recursive: true });
    writeFileSync(jarPath, 'fake-jar');

    try {
      const deps = resolveMavenSpecifiers(['maven:org.example:demo:1.2.3']);
      expect(deps.length).toBe(1);
      expect(deps[0]?.jarPath).toBe(jarPath);
      expect(deps[0]?.ga).toBe('org.example:demo');
      expect(deps[0]?.version).toBe('1.2.3');
    } finally {
      if (oldCache == null) delete process.env.KESTREL_MAVEN_CACHE;
      else process.env.KESTREL_MAVEN_CACHE = oldCache;
      rmSync(cacheRoot, { recursive: true, force: true });
    }
  });

  it('rejects path-traversal groupId', () => {
    expect(() => parseMavenSpecifier('maven:../../../etc:passwd:1.0')).toThrow(/Invalid maven coordinate segment/);
  });

  it('rejects space in artifactId', () => {
    expect(() => parseMavenSpecifier('maven:com.example:my lib:1.0')).toThrow(/Invalid maven coordinate segment/);
  });

  it('rejects null byte in version', () => {
    expect(() => parseMavenSpecifier('maven:com.example:demo:1.0\x00evil')).toThrow(/Invalid maven coordinate segment/);
  });

  it('accepts valid coordinates with dots and hyphens', () => {
    const parsed = parseMavenSpecifier('maven:org.apache.commons:commons-lang3:3.20.0');
    expect(parsed.groupId).toBe('org.apache.commons');
    expect(parsed.artifactId).toBe('commons-lang3');
    expect(parsed.version).toBe('3.20.0');
  });
});
