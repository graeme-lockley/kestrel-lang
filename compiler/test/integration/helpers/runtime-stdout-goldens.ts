/**
 * Expected runtime stdout lines for runtime conformance (spec 08 §3.2).
 * Source files list golden lines as full-line `//` comments whose bodies are not
 * documentation (see isDocOnlyCommentBody). Order matches println output order.
 */
export function extractExpectedStdoutLines(source: string): string[] {
  const lines = source.split(/\n/);
  const out: string[] = [];
  for (const line of lines) {
    const m = line.match(/^\s*\/\/\s?(.*)$/);
    if (!m) continue;
    const body = m[1] ?? '';
    const trimmed = body.trim();
    if (trimmed === '') continue;
    if (isDocOnlyCommentBody(trimmed)) continue;
    out.push(trimmed);
  }
  return out;
}

/** True when this // line is prose for readers, not an expected println line. */
function isDocOnlyCommentBody(t: string): boolean {
  if (/^Runtime conformance:/i.test(t)) return true;
  if (/^For now:/i.test(t)) return true;
  if (/^EXPECT/i.test(t)) return true;
  if (/^E2E_/i.test(t)) return true;
  if (/^THROW must/i.test(t)) return true;
  if (/^Re-throw/i.test(t)) return true;
  if (/^Test \d+:/i.test(t)) return true;
  if (/^throw from/i.test(t)) return true;
  if (/^multiple nested try/i.test(t)) return true;
  if (/^Full await\/Task execution/i.test(t)) return true;
  if (/\bstdlib tests\b/i.test(t)) return true;
  if (/\bParse note:/i.test(t)) return true;
  if (/block result/i.test(t)) return true;
  return false;
}
