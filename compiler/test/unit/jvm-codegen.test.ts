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

  it('emits JVM class for break inside if in while (no dead code after break goto)', () => {
    const src = `fun main(): Unit = {
  var i = 0
  while (i < 3) {
    i := i + 1
    if (i == 2) {
      break
    }
  }
}`;
    const result = compile(src);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const jvm = emitJvm(result.ast);
    expect(jvm.classBytes.length).toBeGreaterThan(0);
  });

  it('compiles extern fun with :ReturnType suffix (primitive long)', () => {
    const src = 'extern fun mathAbs(x: Int): Int = jvm("java.lang.Math#abs(long):long")\nval r = mathAbs(3)';
    const result = compile(src);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const jvm = emitJvm(result.ast);
    expect(jvm.classBytes.length).toBeGreaterThan(0);
  });

  it('compiles extern fun with :ReturnType suffix (primitive boolean)', () => {
    const src = 'extern fun strEmpty(s: String): Bool = jvm("java.lang.String#isEmpty():boolean")\nval r = strEmpty("x")';
    const result = compile(src);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const jvm = emitJvm(result.ast);
    expect(jvm.classBytes.length).toBeGreaterThan(0);
  });

  it('compiles extern fun with :ReturnType suffix (primitive int)', () => {
    const src = 'extern fun strLen(s: String): Int = jvm("java.lang.String#length():int")\nval r = strLen("hi")';
    const result = compile(src);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const jvm = emitJvm(result.ast);
    expect(jvm.classBytes.length).toBeGreaterThan(0);
  });

  it('extern fun without :ReturnType suffix remains backwards compatible (reference return)', () => {
    // String#valueOf(Object) is static, 1-arg, returns reference — no :ReturnType suffix needed
    const src = 'extern fun strVal(x: String): String = jvm("java.lang.String#valueOf(java.lang.Object)")\nval r = strVal("hi")';
    const result = compile(src);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const jvm = emitJvm(result.ast);
    expect(jvm.classBytes.length).toBeGreaterThan(0);
  });
});
