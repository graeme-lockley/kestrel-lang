# VM: SPREAD instruction (record spread)

## Sequence: 64
## Tier: Archival / verification (feature implemented)
## Former ID: 30

## Summary

The compiler emits the **SPREAD** opcode (`0x19`) for record spread expressions `{ ...r, x = v }`. This story originally tracked VM support when SPREAD was missing.

## Resolution

- SPREAD is implemented in `vm/src/exec.zig` and covered by language tests (e.g. record spread in `tests/unit/records.test.ks`).
- Completed kanban entries include `docs/kanban/done/49-vm-spread-instruction.md` and related compiler record-spread work (`38-compiler-record-spread-codegen.md`).

## Purpose of this file

- Keeps historical context for anyone searching for "vm spread".
- When picking up work, use this story only for **verification** (regression test on VM side) or **close immediately** by marking tasks done.

## Acceptance Criteria (verification-only)

- [ ] Confirm SPREAD opcode is handled in `exec.zig` and matches spec 04 §1.8 behaviour.
- [ ] Confirm E2E or unit coverage exists for `{ ...r, field = value }` on the default VM target.
- [ ] If all confirmed: move through **planned** (if any new tasks/tests/docs are needed) and **doing**, then to `docs/kanban/done/`, or delete after noting merge with done story (project preference).

## Spec References

- 04-bytecode-isa §1.8 (SPREAD)
- 01-language (record literals with spread)
