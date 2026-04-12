export interface CompilerLocation {
  file: string;
  line: number;
  column: number;
  endLine?: number;
  endColumn?: number;
}

export interface CompilerDiagnostic {
  severity: 'error' | 'warning';
  code: string;
  message: string;
  location: CompilerLocation;
  related?: Array<{ message: string; location: CompilerLocation }>;
  hint?: string;
  suggestion?: string;
}

export interface DocumentState {
  source: string;
  ast: unknown | null;
  diagnostics: CompilerDiagnostic[];
}

export class DocumentManager {
  private readonly docs = new Map<string, DocumentState>();

  public update(uri: string, source: string, ast: unknown | null, diagnostics: CompilerDiagnostic[]): void {
    this.docs.set(uri, { source, ast, diagnostics });
  }

  public get(uri: string): DocumentState | undefined {
    return this.docs.get(uri);
  }

  public delete(uri: string): void {
    this.docs.delete(uri);
  }
}
