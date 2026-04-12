import * as path from 'node:path';
import { pathToFileURL } from 'node:url';

import {
  DiagnosticSeverity,
  type Diagnostic,
  type DiagnosticRelatedInformation,
  type Location,
  type Range,
} from 'vscode-languageserver/node';

import type { CompilerDiagnostic, CompilerLocation } from './document-manager';

function toRange(loc: CompilerLocation): Range {
  const startLine = Math.max(loc.line - 1, 0);
  const startChar = Math.max(loc.column - 1, 0);
  const endLine = Math.max((loc.endLine ?? loc.line) - 1, 0);
  const endChar = Math.max((loc.endColumn ?? (loc.column + 1)) - 1, 0);
  return {
    start: { line: startLine, character: startChar },
    end: { line: endLine, character: Math.max(endChar, startChar + 1) },
  };
}

function toFileUri(file: string, defaultUri: string): string {
  if (path.isAbsolute(file)) {
    return pathToFileURL(file).toString();
  }
  return defaultUri;
}

function buildRelatedInformation(diag: CompilerDiagnostic, defaultUri: string): DiagnosticRelatedInformation[] | undefined {
  const related: DiagnosticRelatedInformation[] = [];

  for (const rel of diag.related ?? []) {
    const location: Location = {
      uri: toFileUri(rel.location.file, defaultUri),
      range: toRange(rel.location),
    };
    related.push({ location, message: rel.message });
  }

  const baseLocation: Location = {
    uri: defaultUri,
    range: toRange(diag.location),
  };

  if (diag.hint != null && diag.hint.length > 0) {
    related.push({ location: baseLocation, message: `hint: ${diag.hint}` });
  }
  if (diag.suggestion != null && diag.suggestion.length > 0) {
    related.push({ location: baseLocation, message: `suggestion: ${diag.suggestion}` });
  }

  return related.length > 0 ? related : undefined;
}

export function compilerDiagnosticToLsp(diag: CompilerDiagnostic, uri: string): Diagnostic {
  return {
    severity: diag.severity === 'warning' ? DiagnosticSeverity.Warning : DiagnosticSeverity.Error,
    code: diag.code,
    source: 'kestrel',
    message: diag.message,
    range: toRange(diag.location),
    relatedInformation: buildRelatedInformation(diag, uri),
  };
}

export function toLspDiagnostics(uri: string, diagnostics: CompilerDiagnostic[]): Diagnostic[] {
  return diagnostics.map((diag) => compilerDiagnosticToLsp(diag, uri));
}
