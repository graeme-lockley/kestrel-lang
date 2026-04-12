import type { Position, SignatureHelp, SignatureInformation, ParameterInformation } from 'vscode-languageserver/node';

import { inferredTypeText } from '../compiler-bridge';

function offsetFromPosition(source: string, pos: Position): number {
  let line = 0;
  let col = 0;
  for (let i = 0; i < source.length; i++) {
    if (line === pos.line && col === pos.character) return i;
    if (source.charCodeAt(i) === 10) {
      line++;
      col = 0;
    } else {
      col++;
    }
  }
  return source.length;
}

function findCallStart(source: string, offset: number): number | null {
  let depth = 0;
  for (let i = offset - 1; i >= 0; i--) {
    const ch = source[i];
    if (ch === ')') depth++;
    else if (ch === '(') {
      if (depth === 0) return i;
      depth--;
    }
  }
  return null;
}

function identifierBefore(source: string, openParen: number): string | null {
  let i = openParen - 1;
  while (i >= 0 && /\s/.test(source[i] ?? '')) i--;
  let end = i + 1;
  while (i >= 0 && /[A-Za-z0-9_]/.test(source[i] ?? '')) i--;
  const start = i + 1;
  if (start >= end) return null;
  const name = source.slice(start, end);
  return /^[A-Za-z_][A-Za-z0-9_]*$/.test(name) ? name : null;
}

function activeParamIndex(source: string, start: number, offset: number): number {
  let depth = 0;
  let commas = 0;
  for (let i = start; i < offset && i < source.length; i++) {
    const ch = source[i];
    if (ch === '(') depth++;
    else if (ch === ')') {
      if (depth > 0) depth--;
    } else if (ch === ',' && depth === 0) {
      commas++;
    }
  }
  return commas;
}

export async function provideSignatureHelp(ast: unknown | null, source: string, position: Position): Promise<SignatureHelp | null> {
  if (ast == null || typeof ast !== 'object') {
    return null;
  }

  const offset = offsetFromPosition(source, position);
  const openParen = findCallStart(source, offset);
  if (openParen == null) {
    return null;
  }

  const calleeName = identifierBefore(source, openParen);
  if (calleeName == null) {
    return null;
  }

  const program = ast as { body?: unknown[] };
  const decl = (program.body ?? []).find((node) => {
    if (node == null || typeof node !== 'object') return false;
    const d = node as { kind?: string; name?: string };
    return d.kind === 'FunDecl' && d.name === calleeName;
  }) as { name?: string; params?: Array<{ name?: string }>; returnType?: unknown } | undefined;

  if (decl == null || decl.name == null) {
    return null;
  }

  const params = decl.params ?? [];
  const paramInfos: ParameterInformation[] = [];
  const rendered: string[] = [];
  for (const p of params) {
    const name = p.name ?? '_';
    const t = await inferredTypeText(p);
    const text = `${name}: ${t ?? 'Unknown'}`;
    rendered.push(text);
    paramInfos.push({ label: text });
  }

  const ret = decl.returnType != null ? (await inferredTypeText(decl.returnType)) : null;
  const label = `${decl.name}(${rendered.join(', ')})${ret != null ? `: ${ret}` : ''}`;
  const signature: SignatureInformation = {
    label,
    parameters: paramInfos,
  };

  const active = Math.min(activeParamIndex(source, openParen + 1, offset), Math.max(0, params.length - 1));
  return {
    signatures: [signature],
    activeSignature: 0,
    activeParameter: active,
  };
}
