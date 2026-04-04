/**
 * Compile-time diagnostic types (spec 10).
 */
import type { Span } from '../lexer/types.js';

export type Severity = 'error' | 'warning';

export interface SourceLocation {
  file: string;
  line: number;
  column: number;
  endLine?: number;
  endColumn?: number;
  offset?: number;
  endOffset?: number;
}

export interface Diagnostic {
  severity: Severity;
  code: string;
  message: string;
  location: SourceLocation;
  sourceLine?: string;
  related?: Array<{ message: string; location: SourceLocation }>;
  suggestion?: string;
  hint?: string;
}

/** Error code prefixes per spec 10 §4. */
export const CODES = {
  parse: {
    unexpected_token: 'parse:unexpected_token',
    expected_semicolon: 'parse:expected_semicolon',
    unmatched_brace: 'parse:unmatched_brace',
    expected_expr: 'parse:expected_expr',
  },
  resolve: {
    module_not_found: 'resolve:module_not_found',
    stdlib_not_configured: 'resolve:stdlib_not_configured',
    url_not_supported: 'resolve:url_not_supported',
  },
  type: {
    unknown_variable: 'type:unknown_variable',
    unify: 'type:unify',
    non_exhaustive_match: 'type:non_exhaustive_match',
    check: 'type:check',
    break_outside_loop: 'type:break_outside_loop',
    continue_outside_loop: 'type:continue_outside_loop',
    /** `e is T` where T does not overlap the inferred type of `e` (06 §4). */
    narrow_impossible: 'type:narrow_impossible',
    /** `is` on an imported opaque ADT using a constructor or non-name RHS (07 §5.3). */
    narrow_opaque: 'type:narrow_opaque',
    /** `ignore` applied to an expression of type `Unit`; use a bare expression statement instead. */
    ignore_unit: 'type:ignore_unit',
  },
  export: {
    not_exported: 'export:not_exported',
    import_conflict: 'export:import_conflict',
    reexport_conflict: 'export:reexport_conflict',
  },
  file: {
    read_error: 'file:read_error',
    circular_import: 'file:circular_import',
  },
  compile: {
    jvm_namespace_constructor: 'compile:jvm_namespace_constructor',
  },
} as const;

/** 1-based line and column for the character at offset in source. */
export function lineColumnFromOffset(source: string, offset: number): { line: number; column: number } {
  if (offset < 0 || offset >= source.length) return { line: 1, column: 1 };
  const before = source.slice(0, offset);
  const line = (before.match(/\n/g)?.length ?? 0) + 1;
  const startOfLine = before.lastIndexOf('\n') + 1;
  const column = offset - startOfLine + 1;
  return { line, column };
}

/** Build SourceLocation from AST/token Span and file path. Optional source computes endLine/endColumn. */
export function locationFromSpan(file: string, span: Span, source?: string): SourceLocation {
  const loc: SourceLocation = {
    file,
    line: span.line,
    column: span.column,
    offset: span.start,
    endOffset: span.end,
  };
  if (source != null && span.end != null && span.end <= source.length) {
    const end = lineColumnFromOffset(source, span.end);
    loc.endLine = end.line;
    loc.endColumn = end.column;
  }
  return loc;
}

/** Location when only file is known (e.g. circular import). */
export function locationFileOnly(file: string): SourceLocation {
  return { file, line: 1, column: 1 };
}
