# Async/Await: Real Suspension and Event Loop

## Sequence: 55
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: 22

## Summary

The current AWAIT implementation only handles **completed** tasks (synchronous returns). If a task is pending, the VM pushes **unit** instead of suspending the caller—so `await` does not actually yield. For real async (file I/O, HTTP, timers), the runtime must **suspend the current frame** when AWAIT sees a suspended TASK, drive work from a **single-threaded event loop** in the spirit of **Node.js** (one thread runs user code and the loop; I/O completion and scheduling advance work without blocking that thread on I/O wait), and **resume** suspended continuations when tasks complete.

**Delivery scope:** **Reference VM and JVM backend** implement the same observable behavior in one story—no deferred “JVM later.” **Stdlib:** every API that is **async-shaped or documented as non-blocking** must be implemented **non-blocking** on the main thread, not only a single read primitive; include an **audit** of impacted code and update all call sites and runtimes accordingly. **Errors:** async operations surface failures via **`Task` carrying `Result<Success, ErrorAdt>`** (or equivalent), with **errors as a named ADT** per domain—not ad-hoc sentinels such as empty-string errors where this story defines the new contract. **CLI:** **`kestrel run`** uses **`--exit-wait` by default** (keep the process alive until the event loop is idle). **`--exit-no-wait`** opts out: exit without waiting for pending async work (exact tie to `main` return documented in **Notes** / `09-tools`). Users may pass **`--exit-wait` explicitly** for clarity; it is the default when neither flag is given. This story closes the gap between today’s placeholder behavior and `05-runtime-model` §6 and `04-bytecode-isa` for AWAIT.

**Audit boundary:** The stdlib/runtime **audit** covers only **what is already implemented** today. **HTTP** and other networking surfaces belong to sequence **56** and are **out of scope** for this audit (though **56** builds on the loop delivered here).

## Decisions (pre-planning)

| Topic | Decision |
|-------|----------|
| Runtimes | **VM + JVM parity** in the same story. |
| Stdlib / I/O | **All implemented** APIs that are non-blocking by contract must be **actually non-blocking**; **audit** only **in-tree / shipped** stdlib and primitives—**HTTP and unimplemented spec stubs are deferred to 56**. |
| Task errors | **`Task<X>`** with **`X = Result<A, E>`** where **`E` is an enumerated ADT** for that operation/domain; spec and stdlib signatures updated as needed. |
| CLI / process lifetime | **Default = `--exit-wait`:** run until the **event loop is idle**. **`--exit-no-wait`:** exit without waiting for idle (document in `09-tools` and CLI help). |
| AWAIT + exceptions | **In scope:** AWAIT inside **`try`/`catch`** with **deterministic** interaction with exception unwind tables (VM and JVM). |
| Tests | **No reliance on implementation-defined completion order.** The **same** tests must pass on **both** VM and JVM (shared harness or identical scenarios). |

## Current State

- **AWAIT opcode:** If the TASK is completed, push the result. If pending, push **unit** (incorrect for real async; spec expects frame suspension).
- **`readFileAsync` / async-shaped stdlib:** May complete synchronously; no general **non-blocking** I/O path tied to an event loop. Some APIs may use **empty string** or other ad-hoc error channels today—this story moves toward **Result + error ADT** where async work is defined.
- **No event loop** in the reference VM: no multiplexing, no queue of runnable continuations, no “turn” that drains I/O completions and resumes frames.
- **Compiler:** Correctly emits AWAIT for `await expr` inside async functions; async context and typing are largely in place; may need extension for **Result-typed** task completions and new error ADTs.
- **JVM backend:** Must gain **matching** suspend/resume (or lowering) in lockstep with the VM—same semantics as acceptance and shared tests require.

## Relationship to other stories

- **Deferred until** language/VM test and core correctness work are in good shape; sequence **13** (VM/language test story) is the anchor for “tests green before large VM churn.”
- **Enables** sequence **56** (HTTP server): handlers return `Task<Response>`; without a real loop and suspension, server-style concurrency is not credible. **HTTP is not audited or implemented in 55**—only the loop and **existing** async APIs.
- **Dependencies (risk reduction):** sequences **12**–**15** (VM stack guard, VM integration tests, overflow/divzero tests) before landing large VM changes.
- **Spec / stdlib churn:** This story supersedes the old “reference VM may complete `readText` synchronously” escape hatch where it conflicts with **non-blocking** and **Result/ErrorAdt** requirements.

## Goals

1. **Correct AWAIT:** When AWAIT pops a TASK that is still suspended, **save** the running frame (PC, locals, operand stack / stack discipline per VM layout) and **transfer control** to the scheduler/event loop instead of pushing a dummy value.
2. **Node-like event loop (single-threaded):** One thread executes Kestrel frames; it never **blocks waiting on I/O** on that thread’s critical path for APIs that are specified as non-blocking. I/O is registered with the OS or a helper mechanism; when work completes, the loop **marks tasks complete** and **schedules resumption** of awaiting frames.
3. **Stdlib parity with contracts:** After an **audit of implemented APIs only**, every in-scope async/non-blocking stdlib entry point uses **real suspension** and **non-blocking** integration, not synchronous completion on the main thread (**HTTP → 56**).
4. **Task errors as Result + ADT:** Completed tasks carry **`Result<Success, ErrorAdt>`** (or equivalent surface type) so failures are **typed and enumerable**; align compiler, VM, JVM, and docs.
5. **Multi-task concurrency:** Multiple TASKs may be pending; the loop progresses them and resumes the correct frames without data races on VM state (still single-threaded from the language’s point of view).
6. **JVM parity:** JVM runtime and tests exhibit the **same** behavior as the reference VM for the same programs, especially async I/O and CLI loop lifetime modes.
7. **CLI process model:** Default **`--exit-wait`** (run-until-idle); **`--exit-no-wait`** for eager exit; documented in `09-tools` and CLI help.
8. **Exceptions + AWAIT:** AWAIT inside `try`/`catch` behaves **deterministically**, with documented unwind semantics; covered by VM and JVM tests.
9. **Portable tests:** Async concurrency tests **do not** assert completion **order**; they **do** run unchanged (or via one shared source) on **VM and JVM**.
10. **Foundation for later work:** Timers, HTTP (**56**), and further I/O plug into the same loop model.

## Acceptance Criteria

- [ ] **Frame suspension:** On AWAIT, if the TASK is not completed, persist the current frame state and return to the scheduler; do not push a bogus value in place of the awaited result.
- [ ] **Resumption:** When a TASK becomes completed, any frame suspended awaiting it is resumed and receives the **typed** result on the stack (**`Result`** success or failure as specified).
- [ ] **Single-threaded loop:** Reference VM uses one thread for bytecode and the loop’s turn logic; no parallel execution of two Kestrel frames at once. JVM matches for language-visible behavior.
- [ ] **Non-blocking stdlib (implemented surface only):** Audit complete for **shipped** async/non-blocking APIs; each uses the event loop / background completion path on **VM and JVM**. **HTTP / unimplemented spec-only APIs** excluded (**56**).
- [ ] **Result + error ADTs:** Async stdlib operations exposed as `Task<…>` use **`Result<_, ErrorAdt>`** (or documented equivalent) with **enumerated** error types; legacy ad-hoc error channels removed or deprecated per spec.
- [ ] **Multiple concurrent tasks:** At least two independent async operations can be in flight; tests prove correctness **without** asserting **which** completes first.
- [ ] **E2E / integration:** Scenario(s) with concurrent async work (e.g. two reads) whose assertions depend only on **final aggregated outcomes** (or explicit synchronization **in Kestrel**, not on runtime ordering), runnable on **both** VM and JVM.
- [ ] **CLI:** **`--exit-wait`** is the default (run until event loop idle); **`--exit-no-wait`** implements the override; behavior documented in **`09-tools`** and **`kestrel run --help`**.
- [ ] **AWAIT in try/catch:** Specified, implemented on **VM and JVM**, and tested (unwind + resume correctness).
- [ ] **Specs updated** (`01`, `02`, `04`, `05`, `06`, `08`, `09-tools` as needed)—no contradiction with non-blocking guarantees, Result errors, or CLI lifetime.
- [ ] **Regression safety:** Existing tests and conformance updated for new error and async shapes; shared VM/JVM suites stay green.

## Spec References

- `docs/specs/01-language.md` §5 (Async and Task model)
- `docs/specs/04-bytecode-isa.md` §1.9 (AWAIT: suspend when task not complete)
- `docs/specs/05-runtime-model.md` §6 (TASK suspended vs completed; event-loop-driven I/O; single-threaded frame execution)
- `docs/specs/02-stdlib.md` (async APIs and filesystem **implemented in 55**; HTTP work stays with **56**)
- `docs/specs/06-typesystem.md` (`Task`, `Result`, ADTs)
- `docs/specs/08-tests.md` (async/Task testing expectations; VM+JVM parity)
- `docs/specs/09-tools.md` (CLI: `kestrel run`, loop lifetime, flags)

## Risks / Notes

### Event loop shape (Node.js analogy)

- **Single thread:** All `async`/`await` continuations and synchronous user code run on that thread, interleaved—not in parallel.
- **Blocking calls:** Synchronous/blocking primitives on the main thread are **bugs** for any API specified as non-blocking; the audit should catch them.
- **Scheduling order:** Relative order of **unrelated** task completions may remain **implementation-defined** in the spec, but **tests must not depend on it**—use only outcomes that hold for **any** valid schedule, or use **in-program** synchronization if order must be observed.

### Task errors and migration

- Moving from **empty string** (or similar) to **`Result<_, ErrorAdt>`** is a **breaking** surface change for some stdlib calls; list migration notes, conformance updates, and changelog expectations in **Notes** or project changelog when implementing.

### VM, bytecode, and exceptions

- Suspension must capture **everything** required to resume safely, including **open try regions** when AWAIT appears inside **`try`**. Interaction with **THROW / END_TRY** and JVM lowering is high risk—verify against compiler unwind metadata.

### JVM parity

- Same **CLI modes**, same **observable async behavior**, same **shared tests**. Any use of platform-specific schedulers must be hidden behind a **common semantic contract**.

### Audit scope

- The audit covers **stdlib**, **runtime primitives**, **compiler lowering** if needed, **scripts/CLI** entry, and **tests** that assumed synchronous completion or old error shapes—**limited to code paths that exist today**. **Do not** expand scope to HTTP client/server or other **56** work; the spec may still mention HTTP, but **55** updates only what is already implemented unless a doc fix is needed for consistency.

## Impact analysis

| Area | Files / subsystems (indicative) | Change | Risk |
|------|----------------------------------|--------|------|
| **VM (Zig)** | `vm/src/exec.zig` (AWAIT, interpreter loop), `vm/src/primitives.zig` (`readFileAsync`, TASK layout), `vm/src/gc.zig` (TASK tracing), new scheduler / I/O wait module | Introduce **idle** definition, **ready queue**, **suspended-frame** storage; AWAIT suspends instead of pushing unit; non-blocking file read completion path; possibly thread-pool or async OS API **only** for I/O completion callbacks onto main loop | **High**: re-entrancy, GC roots for suspended frames, try/unwind state |
| **Bytecode / ISA** | `docs/specs/04-bytecode-isa.md`; possibly `compiler/src/bytecode/` if new ops (prefer **no** new user opcodes unless unavoidable) | Document actual AWAIT behavior; align disasm if TASK layout changes | Medium |
| **Compiler (TS)** | `compiler/src/typecheck/check.ts` (`__read_file_async`, `Task<Result<…>>`), `compiler/src/codegen/codegen.ts`, `compiler/src/jvm-codegen/codegen.ts`, `stdlib/kestrel/fs.ks`, stdlib tests | New **Result + error ADT** types for fs async API; primitive name/signature updates; any closure/async edge cases for suspended frames | Medium |
| **JVM runtime** | `runtime/jvm/.../KRuntime.java` (and interpreter loop classes if separate) | **Mirror VM**: suspended tasks, AWAIT, event pump integration, non-blocking read | **High**: parity bugs |
| **CLI** | `scripts/kestrel` (`cmd_run` / argument parsing), possibly `compiler` CLI if run is delegated | Parse **`--exit-wait`** (default) and **`--exit-no-wait`**; reject **both** with a clear error; plumb into VM and JVM launch paths | Low–medium |
| **Tests** | `tests/unit/*.test.ks`, `stdlib/kestrel/fs.test.ks`, `tests/conformance/runtime/valid/async_await.ks`, Vitest async/typecheck tests, E2E, `./scripts/kestrel test-both` | Update expectations for **Result**; add concurrent async scenarios **order-agnostic**; ensure **same** sources run on VM and JVM | Medium |
| **Docs** | `docs/specs/01`, `02`, `05`, `06`, `08`, `09-tools`; `AGENTS.md` if verification commands change | Non-blocking guarantees, CLI flags, error ADTs, test parity | Low |

**Rollback:** Feature-flagging a full event loop is difficult; prefer incremental commits behind tests. JVM and VM should move in lockstep to avoid a long window where only one backend passes shared async tests.

## Tasks

- [ ] **Audit (inventory):** List every **implemented** `Task<…>` / async primitive and stdlib re-export (`stdlib/kestrel/fs.ks`, `__read_file_async`, JVM `KRuntime.readFileAsync`, VM `readFileAsync`); record sync/blocking call sites. Exclude HTTP / spec-only stubs (**56**).
- [ ] **Spec-first pass:** Update `05-runtime-model` §6 and `04` AWAIT text for suspension, idle process, and (if needed) TASK object layout; draft `02` **readText** / fs errors as **`Task<Result<String, FsReadError>>`** (or chosen ADT names); align `06` and `01` §5 for Task + Result composition.
- [ ] **VM: TASK state machine:** Extend TASK representation for **pending** vs **completed** with optional **waiter list** / back-pointer to suspended frame(s); ensure **GC** traces suspended continuations and pending I/O handles safely.
- [ ] **VM: Scheduler / loop:** Implement a **run-until** driver: execute bytecode until AWAIT suspend or halt; **poll/wait** for I/O (or integrate Zig/async or platform non-blocking read) without blocking the **frame-execution** thread on read completion; **idle** = no runnable frames and no pending external work (define precisely in spec).
- [ ] **VM: AWAIT:** On pending TASK, **save frame** (PC, stack, locals, **try stack / handler chain**); enqueue resumption when TASK completes; remove “push unit” placeholder.
- [ ] **VM: `readFileAsync`:** Start **non-blocking** read (or worker completion) that completes TASK on the loop; main thread does not block in `read` syscall during frame execution.
- [ ] **VM: try/catch + AWAIT:** Prove correct behavior for AWAIT inside **try** (resume inside try, exceptions from completed task, interaction with END_TRY); add focused Zig tests or harness programs.
- [ ] **Compiler / stdlib:** Change **`kestrel:fs`** `readText` and primitive typing to **`Task<Result<String, E>>`**; introduce **error ADT** in stdlib or builtins; update **`__read_file_async`** binding in typecheck and both codegens.
- [ ] **JVM:** Implement matching **TASK**, **AWAIT** suspension/resume, and **readFileAsync** non-blocking behavior; align **KRuntime** with new Result shape.
- [ ] **CLI:** Implement **`--exit-wait`** (default) and **`--exit-no-wait`** in `scripts/kestrel`; **error** if both supplied; document semantics in `09-tools`.
- [ ] **CLI wiring:** Ensure VM and JVM **run** paths honor exit mode (wait for idle vs exit when entry completes—per **Notes**).
- [ ] **Portable tests:** Add or update **Kestrel** tests for concurrent async reads with **order-independent** assertions; run via **`./scripts/kestrel test`** / **`test-both`** so **VM and JVM** execute the **same** files.
- [ ] **Conformance / Vitest:** Update `tests/conformance/runtime/valid/async_await.ks` and any typecheck conformance for new **`Result`** types; fix `compiler` unit/integration tests for async/fs.
- [ ] **E2E:** Add scenario under `tests/e2e/scenarios/positive/` (or extend existing) for concurrent async file operations, **no ordering assertions**.
- [ ] **Disasm / debug:** If TASK layout or new runtime hooks affect bytecode metadata, update `compiler/disasm.ts` or debug docs only if needed.
- [ ] **Verification:** `cd compiler && npm run build && npm test`; `cd vm && zig build test`; `./scripts/kestrel test`; `./scripts/kestrel test-both` on affected async tests; `./scripts/run-e2e.sh` if E2E touched.

## Tests to add

| Layer | Path / mechanism | Intent |
|-------|------------------|--------|
| **Zig** | `vm` tests registered in `vm/src/main.zig` (or module tests) | TASK pending/completed transitions; AWAIT suspend/resume **without** full stdlib if feasible; try/catch + AWAIT minimal bytecode fixture |
| **Vitest** | `compiler/test/unit/typecheck/`, `compiler/test/integration/` | `readText` / primitive type **`Task<Result<…>>`**; await + Result unwrap patterns; regressions for async context |
| **Conformance** | `tests/conformance/runtime/valid/async_await.ks`, new `tests/conformance/typecheck/` cases if needed | Language + runtime shapes for async + Result |
| **Kestrel unit** | `tests/unit/*.test.ks`, `stdlib/kestrel/fs.test.ks` | **Result** success/failure paths; **no completion-order** dependence |
| **Dual backend** | `./scripts/kestrel test-both` (or documented equivalent) with **shared** `.ks` sources | **Identical** async behavior on **VM and JVM** |
| **E2E** | `tests/e2e/scenarios/positive/*.ks` + `.expected` | Concurrent async I/O; aggregate assertions only |
| **Manual / smoke** | `scripts/jvm-smoke.mjs` or extend if present | Quick JVM smoke after AWAIT changes |

## Documentation and specs to update

- [ ] `docs/specs/01-language.md` §5 — Task + await; interaction with **Result**-carrying tasks if user-visible.
- [ ] `docs/specs/02-stdlib.md` — **Filesystem** / `readText`: **non-blocking**, **`Task<Result<String, ErrorAdt>>`**, remove or narrow “may complete synchronously” for reference VM where 55 applies.
- [ ] `docs/specs/04-bytecode-isa.md` — AWAIT suspend/resume; reference **05** for idle/process model.
- [ ] `docs/specs/05-runtime-model.md` §6 — Event loop, **idle**, single-threaded execution, TASK lifecycle, optional background I/O thread signaling.
- [ ] `docs/specs/06-typesystem.md` — Typing **`Task<Result<A,E>>`** and error ADT exports if new.
- [ ] `docs/specs/08-tests.md` — Async testing, **VM+JVM parity**, **no scheduler-order** dependence in conformance/unit tests.
- [ ] `docs/specs/09-tools.md` — **`kestrel run`**: **`--exit-wait`** (default), **`--exit-no-wait`**, mutual exclusion rule.
- [ ] `AGENTS.md` — Only if verification commands or story-specific suites change materially.

## Notes

- **`--exit-no-wait` semantics (planning default):** Exit when the **program entry** returns control to the host **without** draining the event loop (pending TASKs may remain incomplete or be dropped—pick one and document; prefer **explicit process exit code** and stderr warning if work was abandoned). **`--exit-wait`:** after entry returns, keep driving the loop until **idle** (no runnable frames, no registered pending I/O for in-flight tasks—exact definition in `05`).
- **Both flags:** **Reject** with a diagnostic and non-zero exit (simplest, matches user recommendation in story draft).
- **Timers:** Out of scope unless needed to unblock I/O testing; if deferred, note follow-up for **56** / later story.
- **Migration:** List every breaking change to `Fs.readText` consumers in stdlib tests and conformance; consider a short **changelog** entry in repo root or `docs/` if the project maintains one.
