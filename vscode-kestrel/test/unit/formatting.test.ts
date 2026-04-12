import { describe, expect, it } from 'vitest';

import { testFormatDocument } from '../../src/server/providers/formatting';

describe('formatting provider', () => {
  it('returns a full-document edit when formatter output differs', async () => {
    const edits = await testFormatDocument(
      'val x = 1   \n',
      { executable: 'kestrel', enabled: true },
      async () => ({ ok: true, output: 'val x = 1\n' }),
    );

    expect(edits).toHaveLength(1);
    expect(edits[0]?.newText).toBe('val x = 1\n');
    expect(edits[0]?.range.start.line).toBe(0);
  });

  it('returns no edits when output is identical', async () => {
    const source = 'val x = 1\n';
    const edits = await testFormatDocument(
      source,
      { executable: 'kestrel', enabled: true },
      async () => ({ ok: true, output: source }),
    );
    expect(edits).toHaveLength(0);
  });

  it('returns no edits when formatter fails', async () => {
    const edits = await testFormatDocument(
      'val x =\n',
      { executable: 'kestrel', enabled: true },
      async () => ({ ok: false, output: '' }),
    );
    expect(edits).toHaveLength(0);
  });
});
