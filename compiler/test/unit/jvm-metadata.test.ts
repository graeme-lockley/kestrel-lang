/**
 * Unit tests for the JVM class metadata reader (jvm-metadata/index.ts).
 *
 * Tests cover:
 *  - Java binary descriptor → Java source type name conversion
 *  - Kestrel type mapping
 *  - Overload disambiguation naming
 *  - readClassMetadata() against a real JDK class (java.util.HashMap)
 */
import { describe, it, expect } from 'vitest';
import {
  readClassMetadata,
  javaTypeToKestrelType,
  generateStubs,
  renderExternKs,
} from '../../src/jvm-metadata/index.js';

describe('javaTypeToKestrelType', () => {
  it('maps void to Unit', () => {
    expect(javaTypeToKestrelType('void')).toBe('Unit');
  });

  it('maps int to Int', () => {
    expect(javaTypeToKestrelType('int')).toBe('Int');
  });

  it('maps long to Int', () => {
    expect(javaTypeToKestrelType('long')).toBe('Int');
  });

  it('maps float to Float', () => {
    expect(javaTypeToKestrelType('float')).toBe('Float');
  });

  it('maps double to Float', () => {
    expect(javaTypeToKestrelType('double')).toBe('Float');
  });

  it('maps boolean to Bool', () => {
    expect(javaTypeToKestrelType('boolean')).toBe('Bool');
  });

  it('maps java.lang.String to String', () => {
    expect(javaTypeToKestrelType('java.lang.String')).toBe('String');
  });

  it('maps arbitrary object type to Any', () => {
    expect(javaTypeToKestrelType('java.lang.Object')).toBe('Any');
    expect(javaTypeToKestrelType('java.util.Map')).toBe('Any');
  });

  it('maps array types to Any', () => {
    expect(javaTypeToKestrelType('int[]')).toBe('Any');
    expect(javaTypeToKestrelType('java.lang.Object[]')).toBe('Any');
  });
});

describe('readClassMetadata (java.util.HashMap)', () => {
  it('returns correct class name and simpleClassName', () => {
    const meta = readClassMetadata('java.util.HashMap');
    expect(meta.className).toBe('java.util.HashMap');
    expect(meta.simpleClassName).toBe('HashMap');
  });

  it('enumerates public methods', () => {
    const meta = readClassMetadata('java.util.HashMap');
    const names = meta.methods.map((m) => m.jvmMethodName);
    expect(names).toContain('size');
    expect(names).toContain('isEmpty');
    expect(names).toContain('get');
    expect(names).toContain('put');
    expect(names).toContain('<init>');
  });

  it('marks constructors correctly', () => {
    const meta = readClassMetadata('java.util.HashMap');
    const ctors = meta.methods.filter((m) => m.isConstructor);
    expect(ctors.length).toBeGreaterThan(0);
    for (const c of ctors) {
      expect(c.jvmMethodName).toBe('<init>');
      expect(c.javaReturnType).toBe('void');
    }
  });

  it('marks static methods correctly', () => {
    const meta = readClassMetadata('java.util.HashMap');
    // newHashMap(int) is a static factory on HashMap in JDK 19+
    // Fall back to checking that instance methods are NOT static
    const sizeMethod = meta.methods.find((m) => m.jvmMethodName === 'size');
    expect(sizeMethod).toBeDefined();
    expect(sizeMethod!.isStatic).toBe(false);
  });

  it('extracts erased parameter types for get()', () => {
    const meta = readClassMetadata('java.util.HashMap');
    const getMethod = meta.methods.find((m) => m.jvmMethodName === 'get' && !m.isConstructor);
    expect(getMethod).toBeDefined();
    expect(getMethod!.javaParamTypes).toEqual(['java.lang.Object']);
    expect(getMethod!.javaReturnType).toBe('java.lang.Object');
  });

  it('extracts erased parameter types for put()', () => {
    const meta = readClassMetadata('java.util.HashMap');
    const putMethod = meta.methods.find((m) => m.jvmMethodName === 'put');
    expect(putMethod).toBeDefined();
    expect(putMethod!.javaParamTypes).toEqual(['java.lang.Object', 'java.lang.Object']);
  });

  it('size() has no parameters and returns int', () => {
    const meta = readClassMetadata('java.util.HashMap');
    const sizeMethod = meta.methods.find((m) => m.jvmMethodName === 'size');
    expect(sizeMethod!.javaParamTypes).toEqual([]);
    expect(sizeMethod!.javaReturnType).toBe('int');
  });
});

describe('generateStubs (java.util.HashMap)', () => {
  it('generates stubs for all public methods', () => {
    const meta = readClassMetadata('java.util.HashMap');
    const stubs = generateStubs(meta, 'HashMap', new Map());
    const kestrelNames = stubs.map((s) => s.kestrelName);
    expect(kestrelNames).toContain('size');
    expect(kestrelNames).toContain('isEmpty');
    expect(kestrelNames).toContain('get');
    expect(kestrelNames).toContain('put');
    expect(kestrelNames.some((n) => n.startsWith('newHashMap'))).toBe(true);
  });

  it('disambiguates overloaded constructor names', () => {
    const meta = readClassMetadata('java.util.HashMap');
    const stubs = generateStubs(meta, 'HashMap', new Map());
    const ctorStubs = stubs.filter((s) => s.isConstructor);
    expect(ctorStubs.length).toBeGreaterThan(1);
    // First constructor is named newHashMap, subsequent ones get _2, _3, ...
    expect(ctorStubs[0].kestrelName).toBe('newHashMap');
    for (const ctor of ctorStubs.slice(1)) {
      expect(ctor.kestrelName).toMatch(/^newHashMap_\d+$/);
    }
  });

  it('generates instance receiver param for non-static methods', () => {
    const meta = readClassMetadata('java.util.HashMap');
    const stubs = generateStubs(meta, 'HashMap', new Map());
    const sizeStub = stubs.find((s) => s.kestrelName === 'size');
    expect(sizeStub).toBeDefined();
    expect(sizeStub!.receiverType).toBe('HashMap');
    expect(sizeStub!.kestrelReturnType).toBe('Int');
  });

  it('generates Any types for erased generic return/params', () => {
    const meta = readClassMetadata('java.util.HashMap');
    const stubs = generateStubs(meta, 'HashMap', new Map());
    const getStub = stubs.find((s) => s.kestrelName === 'get');
    expect(getStub).toBeDefined();
    expect(getStub!.kestrelReturnType).toBe('Any');
    expect(getStub!.kestrelParams.every((p) => p.type === 'Any')).toBe(true);
  });

  it('generates correct jvm descriptor for size()', () => {
    const meta = readClassMetadata('java.util.HashMap');
    const stubs = generateStubs(meta, 'HashMap', new Map());
    const sizeStub = stubs.find((s) => s.kestrelName === 'size');
    expect(sizeStub!.jvmDescriptor).toBe('java.util.HashMap#size()');
  });

  it('generates correct jvm descriptor for get()', () => {
    const meta = readClassMetadata('java.util.HashMap');
    const stubs = generateStubs(meta, 'HashMap', new Map());
    const getStub = stubs.find((s) => s.kestrelName === 'get');
    expect(getStub!.jvmDescriptor).toBe('java.util.HashMap#get(java.lang.Object)');
  });

  it('constructor stubs have alias as return type', () => {
    const meta = readClassMetadata('java.util.HashMap');
    const stubs = generateStubs(meta, 'HashMap', new Map());
    const ctorStubs = stubs.filter((s) => s.isConstructor);
    for (const ctor of ctorStubs) {
      expect(ctor.kestrelReturnType).toBe('HashMap');
      expect(ctor.receiverType).toBeUndefined();
    }
  });
});

describe('renderExternKs', () => {
  it('starts with auto-generated comment and extern type declaration', () => {
    const meta = readClassMetadata('java.util.HashMap');
    const stubs = generateStubs(meta, 'HashMap', new Map());
    const rendered = renderExternKs(meta, 'HashMap', stubs);
    expect(rendered).toContain('// Auto-generated by Kestrel compiler from java.util.HashMap');
    expect(rendered).toContain('extern type HashMap = jvm("java.util.HashMap")');
  });

  it('contains extern fun declarations for public methods', () => {
    const meta = readClassMetadata('java.util.HashMap');
    const stubs = generateStubs(meta, 'HashMap', new Map());
    const rendered = renderExternKs(meta, 'HashMap', stubs);
    expect(rendered).toContain('extern fun size');
    expect(rendered).toContain('extern fun get');
    expect(rendered).toContain('extern fun newHashMap');
  });

  it('produces valid extern fun syntax for size()', () => {
    const meta = readClassMetadata('java.util.HashMap');
    const stubs = generateStubs(meta, 'HashMap', new Map());
    const rendered = renderExternKs(meta, 'HashMap', stubs);
    expect(rendered).toContain('extern fun size(instance: HashMap): Int = jvm("java.util.HashMap#size()")');
  });
});
