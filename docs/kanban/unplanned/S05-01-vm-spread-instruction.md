# JVM: SPREAD instruction (record spread)

## Sequence: S05-01
## Tier: Archival / verification (feature implemented)
## Former ID: 30

## Epic

- Epic: [E05 Runtime Modernization and DX](../epics/unplanned/E05-runtime-modernization-and-dx.md)
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

- [ ] Confirm SPREAD opcode is handled in the JVM runtime and matches spec 04 §1.8 behaviour.
- [ ] Confirm E2E or unit coverage exists for `{ ...r, field = value }` on the JVM target.
- [ ] If all confirmed: move through **planned** (if any new tasks/tests/docs are needed) and **doing**, then to `docs/kanban/done/`, or delete after noting merge with done story (project preference).

## Spec References

- 04-bytecode-isa §1.8 (SPREAD)
- 01-language (record literals with spread)
