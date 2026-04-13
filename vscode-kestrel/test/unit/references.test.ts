import { describe, expect, it } from 'vitest';

import { compileWorkspace } from '../../src/server/compiler-bridge';
import { findReferences } from '../../src/server/providers/references';
import { createTempWorkspace } from './workspaceTestUtils';

describe('findReferences', () => {
  it('collects only binding-correct references across workspace files', async () => {
    const workspace = createTempWorkspace({
      'lib.ks': 'export fun add(a: Int, b: Int): Int = a + b\n',
      'main.ks': [
        'import { add } from "./lib.ks"',
        'val note = "add"',
        'fun demo(x: Int): Int = {',
        '  val add = x',
        '  add',
        '}',
        'val result = add(1, 2)',
        '// add',
      ].join('\n'),
    });

    try {
      const workspaceIndex = await compileWorkspace(workspace.rootDir);
      const mainUri = workspace.uriFor('main.ks');
      const source = workspaceIndex.sourcesByUri.get(mainUri) ?? '';
      const refs = findReferences(mainUri, source, { line: 6, character: 14 }, workspaceIndex);

      const refsInMain = refs.filter((ref) => ref.uri === mainUri);
      expect(refs).toHaveLength(3);
      expect(refs.some((ref) => ref.uri === workspace.uriFor('lib.ks'))).toBe(true);
      expect(refsInMain).toHaveLength(2);
    } finally {
      workspace.dispose();
    }
  });
});
