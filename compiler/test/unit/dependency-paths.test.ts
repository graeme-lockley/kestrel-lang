import { describe, it, expect } from 'vitest';
import { uniqueDependencyPaths } from '../../src/dependency-paths.js';

describe('uniqueDependencyPaths', () => {
  it('preserves first-seen order and drops duplicates', () => {
    expect(uniqueDependencyPaths(['a', 'b', 'a', 'c', 'b'])).toEqual(['a', 'b', 'c']);
  });

  it('returns empty for empty input', () => {
    expect(uniqueDependencyPaths([])).toEqual([]);
  });

  it('keeps distinct paths', () => {
    expect(uniqueDependencyPaths(['/x/a.ks', '/x/b.kbc'])).toEqual(['/x/a.ks', '/x/b.kbc']);
  });
});
