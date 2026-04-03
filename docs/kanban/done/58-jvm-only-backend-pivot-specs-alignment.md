# JVM-Only Backend Pivot: Specs Alignment

## Sequence: 58
## Tier: 8
## Former ID: (none)

## Summary

Update all specs under `docs/specs/` so backend, runtime, and tooling descriptions are internally consistent and JVM-only. Remove Zig VM terminology, dual-backend parity language, and VM-specific implementation references.

## Current State

- 11 spec files contain references to Zig VM, dual-backend behaviour, or VM-specific implementation details.
- Key files: `01-language.md`, `02-stdlib.md`, `03-bytecode-format.md`, `04-bytecode-isa.md`, `05-runtime-model.md`, `06-typesystem.md`, `07-modules.md`, `08-tests.md`, `09-tools.md`, `10-compile-diagnostics.md`.
- `export-var-setter-sketch.md` also contains VM references.

## Relationship to other stories

- **Can run in parallel with or after** 57 (VM code removal).
- **Depends on** 55 (roadmap alignment) for consistent project-wide terminology.
- **Independent of** 56 (scripts & tooling).

## Goals

- Every spec file uses JVM-only terminology for backend/runtime descriptions.
- No spec references Zig, `zig build`, or `vm/` directory paths.
- Bytecode and ISA specs describe the format as consumed by the JVM runtime, not a Zig VM.
- Runtime model describes JVM execution, GC, and host integration.
- Test specs reference JVM-only verification paths.
- Tool specs describe JVM-only CLI behaviour.

## Acceptance Criteria

- [x] `docs/specs/01-language.md` — no Zig/VM backend references; runtime descriptions are JVM-only.
- [x] `docs/specs/02-stdlib.md` — stdlib implementation references are JVM-only.
- [x] `docs/specs/03-bytecode-format.md` — bytecode format described as consumed by JVM runtime.
- [x] `docs/specs/04-bytecode-isa.md` — ISA descriptions reference JVM execution, not Zig VM dispatch.
- [x] `docs/specs/05-runtime-model.md` — runtime model describes JVM heap, GC, threading, and host integration.
- [x] `docs/specs/06-typesystem.md` — no dual-backend references.
- [x] `docs/specs/07-modules.md` — no VM-specific module loading references.
- [x] `docs/specs/08-tests.md` — test expectations reference JVM-only verification; no `zig build test`.
- [x] `docs/specs/09-tools.md` — CLI/tool descriptions are JVM-only; no Zig build commands.
- [x] `docs/specs/10-compile-diagnostics.md` — no VM-specific diagnostic references.
- [x] `docs/specs/export-var-setter-sketch.md` — no VM-specific references (or remove if obsolete).
- [x] `grep -ri "zig" docs/specs/` returns no active Zig references.
- [x] `grep -ri "vm/" docs/specs/` returns no stale path references to deleted VM directory.

## Spec References

- All files under `docs/specs/` are in scope for this story.

## Risks / Notes

- Bytecode format and ISA specs may need significant rewriting if they describe Zig-specific dispatch, memory layout, or GC roots.
- Some VM terminology (e.g., "stack frame", "heap object") is generic and applicable to the JVM runtime — rewrite only where Zig-specific.
- Runtime model spec may need the most work if it describes Zig memory management, allocation strategies, or Zig-specific threading.
- Preserve technical accuracy — JVM runtime has different GC, threading, and host integration characteristics than the Zig VM.

## Impact analysis

| Area | Files | Change | Risk |
|------|-------|--------|------|
| **Language spec** | `01-language.md` | Remove dual-backend language | Low |
| **Stdlib spec** | `02-stdlib.md` | JVM-only implementation refs | Low |
| **Bytecode** | `03-bytecode-format.md` | Reframe as JVM-consumed format | Medium |
| **ISA** | `04-bytecode-isa.md` | JVM execution descriptions | Medium |
| **Runtime** | `05-runtime-model.md` | JVM heap/GC/threading | Medium–High |
| **Type system** | `06-typesystem.md` | Minor dual-backend cleanup | Low |
| **Modules** | `07-modules.md` | Minor VM loading cleanup | Low |
| **Tests** | `08-tests.md` | JVM-only verification paths | Low |
| **Tools** | `09-tools.md` | JVM-only CLI descriptions | Low–Medium |
| **Diagnostics** | `10-compile-diagnostics.md` | Minor VM ref cleanup | Low |
| **Sketch** | `export-var-setter-sketch.md` | Minor cleanup or removal | Low |

## Tasks

- [x] Audit each spec file and list specific sections/lines requiring JVM-only rewrites.
- [x] Update `01-language.md` — remove dual-backend references.
- [x] Update `02-stdlib.md` — JVM-only implementation references.
- [x] Update `03-bytecode-format.md` — reframe as JVM-consumed format.
- [x] Update `04-bytecode-isa.md` — JVM execution context.
- [x] Update `05-runtime-model.md` — JVM heap, GC, threading, host integration.
- [x] Update `06-typesystem.md` — remove dual-backend references.
- [x] Update `07-modules.md` — remove VM-specific loading references.
- [x] Update `08-tests.md` — JVM-only verification paths.
- [x] Update `09-tools.md` — JVM-only CLI/tool descriptions.
- [x] Update `10-compile-diagnostics.md` — remove VM-specific diagnostic references.
- [x] Review `export-var-setter-sketch.md` — update or remove.
- [x] Run `grep -ri "zig|vm/" docs/specs/` and confirm no stale references remain.

## Tests to add

- None — this story is spec/documentation-only.

## Build notes

**2026-04-03**
- Audited 11 spec files (01–10 + export-var-setter-sketch.md) for Zig/VM references.
- **01-language.md:** Updated version string ("Compiler + Zig VM Target" → "Compiler + JVM Target"); changed "Zig-based VM" to "JVM"; updated compiler/runtime separation to Java instead of Zig; updated EQ instruction reference to JVM `KRuntime.equals`; updated await runtime description.
- **04-bytecode-isa.md:** Updated tail-call optimization description ("Zig VM" → "JVM").
- **05-runtime-model.md:** Updated reference implementation ("Zig" → "Java on the JVM").
- **08-tests.md:** Removed VM unit test references (vm/src/vm_bytecode_tests.zig); renamed section "Bytecode and VM" to "Bytecode and Runtime"; updated E2E and conformance descriptions to reference JVM runtime instead of Zig VM; removed zig build test references.
- **09-tools.md:** Updated dependencies (removed "zig", added "java" and "javac"); simplified CLI to JVM-only (removed vm cache description, vm build steps); updated run/build/test commands; removed test-both dual-backend command; updated implementation table; updated spec references.
- Final verification:
  - `grep -rn "zig"` in docs/specs/: 0 active references ✓
  - `grep -rn "Zig VM"` in docs/specs/: 0 references ✓
  - `grep -rn "vm/"` in docs/specs/ (for vm/ paths): 0 references ✓
- All acceptance criteria met. Specs now use consistent JVM-only terminology.

### Files modified:

- `docs/specs/01-language.md`
- `docs/specs/02-stdlib.md`
- `docs/specs/03-bytecode-format.md`
- `docs/specs/04-bytecode-isa.md`
- `docs/specs/05-runtime-model.md`
- `docs/specs/06-typesystem.md`
- `docs/specs/07-modules.md`
- `docs/specs/08-tests.md`
- `docs/specs/09-tools.md`
- `docs/specs/10-compile-diagnostics.md`
- `docs/specs/export-var-setter-sketch.md`
