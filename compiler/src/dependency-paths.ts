/**
 * Deduplicate dependency paths while preserving first-seen order.
 * Shrinks .deps files and reduces redundant staleness checks in the shell wrapper.
 */
export function uniqueDependencyPaths(paths: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const p of paths) {
    if (!seen.has(p)) {
      seen.add(p);
      out.push(p);
    }
  }
  return out;
}
