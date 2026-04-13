import { describe, expect, it } from 'vitest';

import { compileWorkspace } from '../../src/server/compiler-bridge';
import { buildRenameEdit } from '../../src/server/providers/rename';
import { createTempWorkspace } from './workspaceTestUtils';

describe('buildRenameEdit', () => {
  it('renames a selected binding across files without touching shadowed locals or text mentions', async () => {
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
      const edit = buildRenameEdit(mainUri, source, { line: 6, character: 14 }, 'sum', workspaceIndex);

      expect(edit).not.toBeNull();
      expect(Object.keys(edit?.changes ?? {})).toContain(workspace.uriFor('lib.ks'));
      expect(Object.keys(edit?.changes ?? {})).toContain(mainUri);
      expect(edit?.changes?.[mainUri]).toHaveLength(2);
    } finally {
      workspace.dispose();
    }
  });

  it('rejects invalid identifiers', async () => {
    const workspace = createTempWorkspace({
      'main.ks': 'val n = add(1, 2)\n',
    });

    try {
      const workspaceIndex = await compileWorkspace(workspace.rootDir);
      const mainUri = workspace.uriFor('main.ks');
      const source = workspaceIndex.sourcesByUri.get(mainUri) ?? '';
      const edit = buildRenameEdit(mainUri, source, { line: 0, character: 9 }, '1bad', workspaceIndex);
      expect(edit).toBeNull();
    } finally {
      workspace.dispose();
    }
  });
});
