# JVM: SPREAD instruction (record spread)

## Sequence: S06-01
## Tier: Archival / verification (feature implemented)
## Former ID: 30

## Epic

- Epic: [E06 Runtime Modernization and DX](../epics/unplanned/E06-runtime-modernization-and-dx.md)
- Companion stories: 71, 72

## Summary

The compiler emits the **SPREAD** opcode (`0x19`) for record spread expressions `{ ...r, x = v }`. This story originally tracked VM support when SPREAD was missing.

## Resolution

- SPREAD is implemented in the JVM runtime and covered by language tests (e.g. record spread in `tests/unit/records.test.ks`).
- Completed kanban entries include `docs/kanban/done/49-vm-spread-instruction.md` and related compiler record-spread work (`38-compiler-record-spread-codegen.md`).

## Purpose of this file

- Keeps historical context for anyone searching for "spread".
- When picking up work, use this story only for **verification** (regression test on JVM side) or **close immediately** by marking tasks done.

## Acceptance Criteria (verification-only)

- [x] Confirm SPREAD opcode is handled in the JVM runtime and matches spec 04 §1.8 behaviour.
- [x] Confirm E2E or unit coverage exists for `{ ...r, field = value }` on the JVM target.
- [x] If all confirmed: move through **planned** (if any new tasks/tests/docs are needed) and **doing**, then to `docs/kanban/done/`, or delete after noting merge with done story (project preference).

## Spec References

- 04-bytecode-isa §1.8 (SPREAD)
- 01-language (record literals with spread)

## Impact analysis

| Area | Change |
|------|--------|
| JVM runtime | `KRecord.spread()` — already implemented; no change needed |
| JVM codegen | `codegen.ts` emits `KRecord.spread` calls for `{ ...base, field = val }` — already implemented |
| Tests | `tests/unit/records.test.ks` — "record spread" group already covers preserve, add, and override |

## Tasks

- [x] Confirm `KRecord.spread()` exists in `runtime/jvm/src/kestrel/runtime/KRecord.java`
- [x] Confirm JVM codegen emits spread in `compiler/src/jvm-codegen/codegen.ts`
- [x] Confirm unit tests exist in `tests/unit/records.test.ks` under "record spread" group
- [x] Run `cd compiler && npm run build && npm test`
- [x] Run `./scripts/kestrel test`

## Tests to add

None — coverage already exists.

## Documentation and specs to update

None — implementation is correct per spec.

## Build notes

- 2026-04-05: Verified. `KRecord.spread()` in KRecord.java implements record spread. The JVM codegen emits `KRecord.spread(base, overrides)` for `{ ...r, field = v }` expressions. The "record spread" group in `tests/unit/records.test.ks` covers: preserve base field, add new field, override existing field. No code changes required; closing as verified.
