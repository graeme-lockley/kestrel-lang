import type { NodeBase, Program } from './nodes.js';

function hasSpan(node: unknown): node is NodeBase & { span: { start: number; end: number } } {
  if (node == null || typeof node !== 'object') {
    return false;
  }
  const span = (node as { span?: { start?: unknown; end?: unknown } }).span;
  return span != null && typeof span.start === 'number' && typeof span.end === 'number';
}

function isNode(value: unknown): value is NodeBase {
  return value != null && typeof value === 'object' && 'kind' in (value as object);
}

function walk(node: NodeBase, offset: number): NodeBase | null {
  let best: NodeBase | null = null;

  if (hasSpan(node) && node.span.start <= offset && offset < node.span.end) {
    best = node;
  }

  for (const [key, value] of Object.entries(node as Record<string, unknown>)) {
    if (key === 'span') {
      continue;
    }

    if (Array.isArray(value)) {
      for (const item of value) {
        if (isNode(item)) {
          const child = walk(item, offset);
          if (child != null) {
            best = child;
          }
        }
      }
      continue;
    }

    if (isNode(value)) {
      const child = walk(value, offset);
      if (child != null) {
        best = child;
      }
    }
  }

  return best;
}

export function findNodeAtOffset(program: Program, offset: number): NodeBase | null {
  return walk(program, offset);
}
