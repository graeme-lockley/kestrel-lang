/**
 * Compile-time diagnostics (spec 10).
 */
export type { Diagnostic, Severity, SourceLocation } from './types.js';
export { CODES, locationFromSpan, locationFileOnly } from './types.js';
export { report, type ReportOptions } from './reporter.js';
