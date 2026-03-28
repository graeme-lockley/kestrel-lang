/**
 * Unit tests for unification (spec 06 §3, occurs check).
 */
import { describe, it, expect, beforeEach } from 'vitest';
import { unify, unifySubtype, applySubst, UnifyError } from '../../../src/types/unify.js';
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

describe('unifySubtype', () => {
  beforeEach(() => resetVarId());

  const uIntBool = { kind: 'union' as const, left: tInt, right: tBool };

  it('allows Int assignable to Int | Bool', () => {
    const subst = new Map<number, import('../../../src/types/internal.js').InternalType>();
    unifySubtype(tInt, uIntBool, subst);
    expect(applySubst(tInt, subst)).toEqual(tInt);
  });

  it('allows Bool assignable to Int | Bool', () => {
    const subst = new Map<number, import('../../../src/types/internal.js').InternalType>();
    unifySubtype(tBool, uIntBool, subst);
  });

  it('rejects Int | Bool assignable to Int', () => {
    const subst = new Map<number, import('../../../src/types/internal.js').InternalType>();
    expect(() => unifySubtype(uIntBool, tInt, subst)).toThrow(UnifyError);
  });

  it('allows nested union on expected side', () => {
    const subst = new Map<number, import('../../../src/types/internal.js').InternalType>();
    const uBoolString = { kind: 'union' as const, left: tBool, right: { kind: 'prim' as const, name: 'String' as const } };
    const outer = { kind: 'union' as const, left: tInt, right: uBoolString };
    unifySubtype(tInt, outer, subst);
    unifySubtype({ kind: 'prim', name: 'String' }, outer, subst);
  });

  it('requires both arms when actual is union and expected is concrete', () => {
    const subst = new Map<number, import('../../../src/types/internal.js').InternalType>();
    const u = { kind: 'union' as const, left: tInt, right: { kind: 'prim', name: 'String' as const } };
    expect(() => unifySubtype(u, tInt, subst)).toThrow(UnifyError);
  });

  it('expected intersection requires actual to match both conjuncts', () => {
    const subst = new Map<number, import('../../../src/types/internal.js').InternalType>();
    const inter = { kind: 'inter' as const, left: tInt, right: tInt };
    unifySubtype(tInt, inter, subst);
  });

  it('function subtype: wider parameter domain is subtype of narrower (contravariance)', () => {
    const subst = new Map<number, import('../../../src/types/internal.js').InternalType>();
    const narrowDom = { kind: 'arrow' as const, params: [tInt], return: tInt };
    const wideDom = { kind: 'arrow' as const, params: [uIntBool], return: tInt };
    // (Int|Bool -> Int) ≤ (Int -> Int): may pass a function that accepts Int|Bool where only Int is passed.
    unifySubtype(wideDom, narrowDom, subst);
  });

  it('function subtype rejects when parameter domain is too narrow for expected', () => {
    const subst = new Map<number, import('../../../src/types/internal.js').InternalType>();
    const wideArg = { kind: 'arrow' as const, params: [uIntBool], return: tInt };
    const narrowArg = { kind: 'arrow' as const, params: [tInt], return: tInt };
    // (Int -> Int) ⋠ ((Int|Bool) -> Int): callee may call with Bool.
    expect(() => unifySubtype(narrowArg, wideArg, subst)).toThrow(UnifyError);
  });
});
