/**
 * Unit tests for generalise and instantiate (spec 06 §3).
 */
import { describe, it, expect, beforeEach } from 'vitest';
import {
  freshVar,
  generalize,
  instantiate,
  freeVars,
  tInt,
  tBool,
  resetVarId,
} from '../../../src/types/internal.js';

describe('generalise', () => {
  beforeEach(() => resetVarId());

  it('generalises type with free vars (result is scheme)', () => {
    const v = freshVar();
    const arrow = { kind: 'arrow' as const, params: [v], return: tInt };
    const envVars = new Set<number>();
    const scheme = generalize(arrow, envVars);
    expect(scheme.kind).toBe('scheme');
    if (scheme.kind === 'scheme') {
      expect(scheme.vars).toHaveLength(1);
      expect(scheme.vars[0]).toBe(v.id);
      expect(scheme.body).toEqual(arrow);
    }
  });

  it('generalise with env containing the var returns type unchanged', () => {
    const v = freshVar();
    const arrow = { kind: 'arrow' as const, params: [v], return: tInt };
    const envVars = new Set([v.id]);
    const result = generalize(arrow, envVars);
    expect(result).toEqual(arrow);
    expect(result.kind).not.toBe('scheme');
  });

  it('generalise of primitive with no free vars returns type unchanged', () => {
    const result = generalize(tInt, new Set());
    expect(result).toEqual(tInt);
  });
});

describe('instantiate', () => {
  beforeEach(() => resetVarId());

  it('instantiate of non-scheme returns type unchanged', () => {
    expect(instantiate(tInt)).toEqual(tInt);
    expect(instantiate(tBool)).toEqual(tBool);
  });

  it('instantiate of scheme yields type with fresh vars', () => {
    const v = freshVar();
    const scheme = { kind: 'scheme' as const, vars: [v.id], body: { kind: 'arrow' as const, params: [v], return: tInt } };
    const inst = instantiate(scheme);
    expect(inst.kind).toBe('arrow');
    if (inst.kind === 'arrow') {
      expect(inst.params).toHaveLength(1);
      expect(inst.params[0]!.kind).toBe('var');
      expect((inst.params[0] as { id: number }).id).not.toBe(v.id);
      expect(inst.return).toEqual(tInt);
    }
  });

  it('round-trip generalise then instantiate yields equivalent shape', () => {
    const v = freshVar();
    const arrow = { kind: 'arrow' as const, params: [v], return: tInt };
    const scheme = generalize(arrow, new Set());
    const inst = instantiate(scheme);
    expect(inst.kind).toBe('arrow');
    if (inst.kind === 'arrow') {
      expect(inst.params.length).toBe(1);
      expect(inst.return).toEqual(tInt);
    }
  });
});
