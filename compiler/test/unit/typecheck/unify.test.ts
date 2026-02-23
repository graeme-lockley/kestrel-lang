/**
 * Unit tests for unification (spec 06 §3, occurs check).
 */
import { describe, it, expect, beforeEach } from 'vitest';
import { unify, applySubst, UnifyError } from '../../../src/types/unify.js';
import { freshVar, tInt, tBool, resetVarId } from '../../../src/types/internal.js';

describe('unify', () => {
  beforeEach(() => resetVarId());
  it('unifies same primitive type (success)', () => {
    const subst = new Map<number, import('../../../src/types/internal.js').InternalType>();
    unify(tInt, tInt, subst);
    expect(subst.size).toBe(0);
    expect(applySubst(tInt, subst)).toEqual(tInt);
  });

  it('unifies var with concrete type (success)', () => {
    const subst = new Map<number, import('../../../src/types/internal.js').InternalType>();
    const v = freshVar();
    unify(v, tInt, subst);
    expect(applySubst(v, subst)).toEqual(tInt);
    expect(applySubst(tInt, subst)).toEqual(tInt);
  });

  it('unifies concrete type with var (success)', () => {
    const subst = new Map<number, import('../../../src/types/internal.js').InternalType>();
    const v = freshVar();
    unify(tBool, v, subst);
    expect(applySubst(v, subst)).toEqual(tBool);
  });

  it('unifies Int vs Bool (throws UnifyError)', () => {
    const subst = new Map<number, import('../../../src/types/internal.js').InternalType>();
    expect(() => unify(tInt, tBool, subst)).toThrow(UnifyError);
    expect(subst.size).toBe(0);
  });

  it('equi-recursive: α = List<α> unifies (no occurs check error)', () => {
    const subst = new Map<number, import('../../../src/types/internal.js').InternalType>();
    const v = freshVar();
    const listV = { kind: 'app' as const, name: 'List', args: [v] };
    expect(() => unify(v, listV, subst)).not.toThrow();
    expect(subst.size).toBe(1);
  });

  it('unifies two vars (success, subst maps one to the other)', () => {
    const subst = new Map<number, import('../../../src/types/internal.js').InternalType>();
    const a = freshVar();
    const b = freshVar();
    unify(a, b, subst);
    expect(subst.size).toBe(1);
    unify(applySubst(a, subst), applySubst(b, subst), subst);
  });

  it('unifies arrow types (success)', () => {
    const subst = new Map<number, import('../../../src/types/internal.js').InternalType>();
    const arrow1 = { kind: 'arrow' as const, params: [tInt], return: tBool };
    const arrow2 = { kind: 'arrow' as const, params: [tInt], return: tBool };
    unify(arrow1, arrow2, subst);
    expect(applySubst(arrow1.return, subst)).toEqual(tBool);
  });

  it('arrow type param count mismatch throws', () => {
    const subst = new Map<number, import('../../../src/types/internal.js').InternalType>();
    const oneParam = { kind: 'arrow' as const, params: [tInt], return: tBool };
    const twoParams = { kind: 'arrow' as const, params: [tInt, tInt], return: tBool };
    expect(() => unify(oneParam, twoParams, subst)).toThrow(UnifyError);
  });
});
