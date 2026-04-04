import { mkdirSync, existsSync, renameSync, rmSync, readFileSync, statSync } from 'fs';
import { join, dirname } from 'path';
import { homedir } from 'os';
import { spawnSync } from 'child_process';
import { createHash } from 'crypto';

export interface MavenCoordinate {
  spec: string;
  coordinate: string;
  ga: string;
  groupId: string;
  artifactId: string;
  version: string;
}

export interface MavenResolvedDependency extends MavenCoordinate {
  jarPath: string;
  sha1: string;
}

const MAVEN_SEGMENT_RE = /^[a-zA-Z0-9._\-]+$/;

function sanitizeSegment(value: string): string {
  return value.trim();
}

export function isMavenSpecifier(spec: string): boolean {
  return spec.startsWith('maven:');
}

export function parseMavenSpecifier(spec: string): MavenCoordinate {
  if (!isMavenSpecifier(spec)) {
    throw new Error(`Not a maven specifier: ${spec}`);
  }
  const rest = spec.slice('maven:'.length);
  const parts = rest.split(':').map((p) => sanitizeSegment(p));
  if (parts.length !== 3 || parts.some((p) => p.length === 0)) {
    throw new Error(`Invalid maven specifier: ${spec}; expected maven:groupId:artifactId:version`);
  }
  for (const part of parts) {
    if (!MAVEN_SEGMENT_RE.test(part)) {
      throw new Error(`Invalid maven coordinate segment '${part}' in '${spec}'; segments must match [a-zA-Z0-9._-]`);
    }
  }
  const [groupId, artifactId, version] = parts;
  return {
    spec,
    coordinate: `${groupId}:${artifactId}:${version}`,
    ga: `${groupId}:${artifactId}`,
    groupId,
    artifactId,
    version,
  };
}

function mavenCacheRoot(): string {
  return process.env.KESTREL_MAVEN_CACHE || join(homedir(), '.kestrel', 'maven');
}

function mavenRepoRoot(): string {
  const repo = process.env.KESTREL_MAVEN_REPO || 'https://repo1.maven.org/maven2';
  return repo.endsWith('/') ? repo.slice(0, -1) : repo;
}

function artifactFileName(artifactId: string, version: string): string {
  return `${artifactId}-${version}.jar`;
}

function localJarPath(coord: MavenCoordinate): string {
  return join(
    mavenCacheRoot(),
    ...coord.groupId.split('.'),
    coord.artifactId,
    coord.version,
    artifactFileName(coord.artifactId, coord.version)
  );
}

function remoteJarUrl(coord: MavenCoordinate): string {
  const groupPath = coord.groupId.split('.').join('/');
  return `${mavenRepoRoot()}/${groupPath}/${coord.artifactId}/${coord.version}/${artifactFileName(coord.artifactId, coord.version)}`;
}

function computeSha1(filePath: string): string {
  const content = readFileSync(filePath);
  return createHash('sha1').update(content).digest('hex');
}

function runCurl(args: string[]): string {
  const out = spawnSync('curl', args, { encoding: 'utf-8' });
  if (out.status !== 0) {
    const stderr = out.stderr?.trim() || out.stdout?.trim() || 'curl failed';
    throw new Error(stderr);
  }
  return out.stdout ?? '';
}

function fetchSha1(url: string): string {
  const body = runCurl(['-fsSL', `${url}.sha1`]).trim();
  const match = body.match(/\b([a-fA-F0-9]{40})\b/);
  if (!match) {
    throw new Error(`Could not parse SHA-1 from ${url}.sha1`);
  }
  return match[1]!.toLowerCase();
}

function renderStartDownload(coord: MavenCoordinate): void {
  if (!process.stderr.isTTY) {
    process.stderr.write(`\x1b[90mDownloading ${coord.coordinate}\x1b[0m\n`);
    return;
  }
  process.stderr.write(`\x1b[90mDownloading ${coord.coordinate} [>          ] 0%`);
}

function renderDoneDownload(coord: MavenCoordinate, filePath: string): void {
  const kb = Math.max(1, Math.round(statSync(filePath).size / 1024));
  if (!process.stderr.isTTY) {
    process.stderr.write(`\x1b[90mDownloaded ${coord.coordinate} (${kb} KB)\x1b[0m\n`);
    return;
  }
  process.stderr.write(`\rDownloading ${coord.coordinate} [==========] 100%\n\x1b[0m`);
  process.stderr.write(`\x1b[90mDownloaded ${coord.coordinate} (${kb} KB)\x1b[0m\n`);
}

function ensureJar(coord: MavenCoordinate): { jarPath: string; sha1: string } {
  const jarPath = localJarPath(coord);
  if (existsSync(jarPath)) {
    return { jarPath, sha1: computeSha1(jarPath) };
  }

  if (process.env.KESTREL_MAVEN_OFFLINE === '1' || process.env.KESTREL_MAVEN_OFFLINE === 'true') {
    throw new Error(`Offline mode enabled and artifact missing from cache: ${coord.coordinate}`);
  }

  mkdirSync(dirname(jarPath), { recursive: true });
  const tmpPath = `${jarPath}.download`;
  const url = remoteJarUrl(coord);

  renderStartDownload(coord);
  try {
    runCurl(['-fsSL', url, '-o', tmpPath]);
    const expectedSha1 = fetchSha1(url);
    const actualSha1 = computeSha1(tmpPath);
    if (expectedSha1 !== actualSha1) {
      throw new Error(`Checksum mismatch for ${coord.coordinate}: expected ${expectedSha1}, got ${actualSha1}`);
    }
    renameSync(tmpPath, jarPath);
    renderDoneDownload(coord, jarPath);
    return { jarPath, sha1: actualSha1 };
  } catch (err) {
    rmSync(tmpPath, { force: true });
    if (process.stderr.isTTY) process.stderr.write('\n');
    throw err;
  }
}

export function resolveMavenSpecifiers(specs: string[]): MavenResolvedDependency[] {
  const seen = new Set<string>();
  const out: MavenResolvedDependency[] = [];
  for (const spec of specs) {
    if (!isMavenSpecifier(spec)) continue;
    if (seen.has(spec)) continue;
    seen.add(spec);
    const coord = parseMavenSpecifier(spec);
    const { jarPath, sha1 } = ensureJar(coord);
    out.push({ ...coord, jarPath, sha1 });
  }
  return out;
}
