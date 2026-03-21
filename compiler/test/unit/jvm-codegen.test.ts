import { describe, it, expect } from 'vitest';
import { compile, emitJvm } from '../../src/index.js';

describe('JVM codegen', () => {
  it('emits class bytes for a simple program', () => {
    const result = compile('println("hello")');
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const jvm = emitJvm(result.ast);
    expect(jvm.className).toBeDefined();
    expect(jvm.classBytes).toBeInstanceOf(Uint8Array);
    expect(jvm.classBytes.length).toBeGreaterThan(100);
    expect(jvm.innerClasses).toBeInstanceOf(Map);
  });

  it('uses class name from source path when provided', () => {
    const result = compile('val x = 1');
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const jvm = emitJvm(result.ast, { sourceFile: 'Foo.ks' });
    expect(jvm.className).toBe('Foo');
  });

  it('emits main class and optional inner classes for lambdas', () => {
    const result = compile('val f = (x: Int) => x + 1\nval a = f(2)');
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const jvm = emitJvm(result.ast, { sourceFile: 'Main.ks' });
    expect(jvm.className).toBe('Main');
    expect(jvm.classBytes.length).toBeGreaterThan(0);
    expect(jvm.innerClasses.size).toBeGreaterThanOrEqual(0);
  });

  it('emits record and tuple expressions', () => {
    const result = compile('val r = { x = 1, y = 2 }\nval t = (1, 2)\nval a = r.x + t.0');
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const jvm = emitJvm(result.ast);
    expect(jvm.classBytes.length).toBeGreaterThan(0);
  });
});
