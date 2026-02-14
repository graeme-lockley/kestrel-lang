/**
 * Kestrel compiler — parse, typecheck, emit .kbc bytecode.
 */
import { tokenize } from './lexer/index.js';
import { parse } from './parser/index.js';
import { typecheck } from './typecheck/index.js';
import { codegen } from './codegen/codegen.js';
import { writeKbc, writeMinimalKbc } from './bytecode/write.js';

export function compile(source: string): { ok: true; ast: import('./parser/index.js').Program } | { ok: false; errors: string[] } {
  try {
    const tokens = tokenize(source);
    const ast = parse(tokens);
    const tc = typecheck(ast);
    if (!tc.ok) return { ok: false, errors: tc.errors };
    return { ok: true, ast };
  } catch (e) {
    const err = e as Error & { offset?: number; line?: number; column?: number };
    const msg = err.message + (err.line != null ? ` at ${err.line}:${err.column}` : '');
    return { ok: false, errors: [msg] };
  }
}

/** Emit .kbc from typed AST (codegen + full sections). */
export function emitKbc(ast: import('./parser/index.js').Program): Uint8Array {
  const { stringTable, constantPool, code, functionTable, importSpecifierIndices, shapes, adts } = codegen(ast);
  return writeKbc(stringTable, constantPool, code, functionTable, importSpecifierIndices, shapes, adts);
}

export { tokenize } from './lexer/index.js';
export { parse, ParseError } from './parser/index.js';
export type { Program } from './parser/index.js';
