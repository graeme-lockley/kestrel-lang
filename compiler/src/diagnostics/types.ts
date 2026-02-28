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
  },
  export: {
    not_exported: 'export:not_exported',
  },
  file: {
    read_error: 'file:read_error',
    circular_import: 'file:circular_import',
  },
} as const;

/** Build SourceLocation from AST/token Span and file path. */
export function locationFromSpan(file: string, span: Span): SourceLocation {
  return {
    file,
    line: span.line,
    column: span.column,
    offset: span.start,
    endOffset: span.end,
  };
}

/** Location when only file is known (e.g. circular import). */
export function locationFileOnly(file: string): SourceLocation {
  return { file, line: 1, column: 1 };
}
