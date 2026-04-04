#!/usr/bin/env node
import { existsSync, readFileSync } from 'fs';
import { resolve, dirname, basename, join } from 'path';

function classInternalNameForSource(sourcePath) {
  const abs = resolve(sourcePath).replace(/\\/g, '/');
  const rel = abs.startsWith('/') ? abs.slice(1) : abs;
  const dir = dirname(rel);
  const base = basename(rel, '.ks').replace(/[^a-zA-Z0-9_]/g, '_');
  const first = base.slice(0, 1).toUpperCase();
  const rest = base.slice(1);
  const last = `${first}${rest}`;
  if (dir === '.') return last;
  return `${dir.replace(/[^a-zA-Z0-9_/]/g, '_')}/${last}`;
}

function classFileForSource(classDir, sourcePath) {
  const internal = classInternalNameForSource(sourcePath);
  return resolve(classDir, `${internal}.class`);
}

function readLines(filePath) {
  if (!existsSync(filePath)) return [];
  return readFileSync(filePath, 'utf-8')
    .split('\n')
    .map((l) => l.trim())
    .filter(Boolean);
}

function deriveJarPath(ga, version) {
  const [groupId, artifactId] = ga.split(':');
  if (!groupId || !artifactId) return '';
  const cache = process.env.KESTREL_MAVEN_CACHE || `${process.env.HOME}/.kestrel/maven`;
  return resolve(cache, ...groupId.split('.'), artifactId, version, `${artifactId}-${version}.jar`);
}

const [, , entrySourceArg, classDirArg] = process.argv;
if (!entrySourceArg || !classDirArg) {
  process.stderr.write('usage: resolve-maven-classpath.mjs <entry-source.ks> <class-dir>\n');
  process.exit(1);
}

const classDir = resolve(classDirArg);
const queue = [resolve(entrySourceArg)];
const seenSources = new Set();
const versionsByGa = new Map();
const sourceByGa = new Map();
const jarPaths = new Set();

while (queue.length > 0) {
  const source = queue.shift();
  if (!source || seenSources.has(source)) continue;
  seenSources.add(source);

  const classFile = classFileForSource(classDir, source);
  const depsFile = `${classFile}.deps`;
  for (const dep of readLines(depsFile)) {
    if (dep.endsWith('.ks')) queue.push(resolve(dep));
  }

  const kdepsPath = classFile.replace(/\.class$/, '.kdeps');
  if (!existsSync(kdepsPath)) continue;

  let parsed;
  try {
    parsed = JSON.parse(readFileSync(kdepsPath, 'utf-8'));
  } catch (err) {
    process.stderr.write(`kestrel: invalid kdeps file: ${kdepsPath}: ${String(err)}\n`);
    process.exit(1);
  }

  const maven = parsed?.maven ?? {};
  const jars = parsed?.jars ?? {};

  for (const [ga, version] of Object.entries(maven)) {
    if (typeof version !== 'string') continue;
    const seenVersion = versionsByGa.get(ga);
    if (seenVersion && seenVersion !== version) {
      const prevSource = sourceByGa.get(ga) ?? '<unknown>';
      process.stderr.write('Dependency conflict:\n');
      process.stderr.write(`  ${prevSource} requires ${ga}:${seenVersion}\n`);
      process.stderr.write(`  ${source} requires ${ga}:${version}\n`);
      process.stderr.write('Fix: align both imports to the same version.\n');
      process.exit(2);
    }
    if (!seenVersion) {
      versionsByGa.set(ga, version);
      sourceByGa.set(ga, source);
    }
    const jar = typeof jars[ga] === 'string' ? jars[ga] : deriveJarPath(ga, version);
    if (jar) jarPaths.add(resolve(jar));
  }
}

for (const jar of jarPaths) {
  if (!existsSync(jar)) {
    process.stderr.write(`kestrel: maven artifact missing: ${jar}\n`);
    process.exit(1);
  }
}

process.stdout.write(Array.from(jarPaths).join(':'));
