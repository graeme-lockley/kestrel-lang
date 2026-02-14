/**
 * Type representation and unification (spec 06).
 */
export type { InternalType } from './internal.js';
export { freshVar, prim, tInt, tFloat, tBool, tString, tUnit, resetVarId, freeVars, generalize, instantiate } from './internal.js';
export { unify, substitute, applySubst, UnifyError } from './unify.js';
export { astTypeToInternal } from './from-ast.js';
