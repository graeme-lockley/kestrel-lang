# Async/Await: Real Suspension and Event Loop

## Sequence: 59
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: 22

## Summary

The current AWAIT implementation only handles **completed** tasks (synchronous returns). If a task is pending, the VM pushes **unit** instead of suspending the caller—so `await` does not actually yield. For real async (file I/O, HTTP, timers), the runtime must **suspend the current frame** when AWAIT sees a suspended TASK, drive work from a **single-threaded event loop** in the spirit of **Node.js** (one thread runs user code and the loop; I/O completion and scheduling advance work without blocking that thread on I/O wait), and **resume** suspended continuations when tasks complete.

**Delivery scope:** **JVM backend** implements the correct async observable behavior. **Stdlib:** every API that is **async-shaped or documented as non-blocking** must be implemented **non-blocking** on the main thread, not only a single read primitive; include an **audit** of impacted code and update all call sites and runtimes accordingly. **Errors:** async operations surface failures via **`Task` carrying `Result<Success, ErrorAdt>`** (or equivalent), with **errors as a named ADT** per domain—not ad-hoc sentinels such as empty-string errors where this story defines the new contract. **CLI:** **`kestrel run`** uses **`--exit-wait` by default** (keep the process alive until the event loop is idle). **`--exit-no-wait`** opts out: exit without waiting for pending async work (exact tie to `main` return documented in **Notes** / `09-tools`). Users may pass **`--exit-wait` explicitly** for clarity; it is the default when neither flag is given. This story closes the gap between today’s placeholder behavior and `05-runtime-model` §6 and `04-bytecode-isa` for AWAIT.

**Audit boundary:** The stdlib/runtime **audit** covers only **what is already implemented** today. **HTTP** and other networking surfaces belong to sequence **60** and are **out of scope** for this audit (though **60** builds on the loop delivered here).

## Decisions (pre-planning)

| Topic | Decision |
|-------|----------|
| Runtimes | **JVM** backend. |
| Stdlib / I/O | **All implemented** APIs that are non-blocking by contract must be **actually non-blocking**; **audit** only **in-tree / shipped** stdlib and primitives—**HTTP and unimplemented spec stubs are deferred to 56**. |
| Task errors | **`Task<X>`** with **`X = Result<A, E>`** where **`E` is an enumerated ADT** for that operation/domain; spec and stdlib signatures updated as needed. |
| CLI / process lifetime | **Default = `--exit-wait`:** run until the **event loop is idle**. **`--exit-no-wait`:** exit without waiting for idle (document in `09-tools` and CLI help). |
| AWAIT + exceptions | **In scope:** AWAIT inside **`try`/`catch`** with **deterministic** interaction with exception unwind tables (JVM). |
| Tests | **No reliance on implementation-defined completion order.** The **same** tests must pass on the JVM (shared harness or identical scenarios). |

## Current State

- **AWAIT opcode:** If the TASK is completed, push the result. If pending, push **unit** (incorrect for real async; spec expects frame suspension).
- **`readFileAsync` / async-shaped stdlib:** May complete synchronously; no general **non-blocking** I/O path tied to an event loop. Some APIs may use **empty string** or other ad-hoc error channels today—this story moves toward **Result + error ADT** where async work is defined.
- **No event loop** in the JVM runtime: no multiplexing, no queue of runnable continuations, no “turn” that drains I/O completions and resumes frames.
- **Compiler:** Correctly emits AWAIT for `await expr` inside async functions; async context and typing are largely in place; may need extension for **Result-typed** task completions and new error ADTs.
- **JVM backend:** Must gain suspend/resume (or lowering) for AWAIT semantics.

## Relationship to other stories

- **Deferred until** language/runtime test and core correctness work are in good shape; sequence **13** (language test story) is the anchor for “tests green before large runtime churn.”
- **Enables** sequence **60** (HTTP server): handlers return `Task<Response>`; without a real loop and suspension, server-style concurrency is not credible. **HTTP is not audited or implemented in 59**—only the loop and **existing** async APIs.
- **Spec / stdlib churn:** This story supersedes the old “reference VM may complete `readText` synchronously” escape hatch where it conflicts with **non-blocking** and **Result/ErrorAdt** requirements.

## Goals

1. **Correct AWAIT:** When AWAIT pops a TASK that is still suspended, **save** the running frame (PC, locals, operand stack / stack discipline per VM layout) and **transfer control** to the scheduler/event loop instead of pushing a dummy value.
2. **Node-like event loop (single-threaded):** One thread executes Kestrel frames; it never **blocks waiting on I/O** on that thread’s critical path for APIs that are specified as non-blocking. I/O is registered with the OS or a helper mechanism; when work completes, the loop **marks tasks complete** and **schedules resumption** of awaiting frames.
3. **Stdlib parity with contracts:** After an **audit of implemented APIs only**, every in-scope async/non-blocking stdlib entry point uses **real suspension** and **non-blocking** integration, not synchronous completion on the main thread (**HTTP → 56**).
4. **Task errors as Result + ADT:** Completed tasks carry **`Result<Success, ErrorAdt>`** (or equivalent surface type) so failures are **typed and enumerable**; align compiler, JVM, and docs.
5. **Multi-task concurrency:** Multiple TASKs may be pending; the loop progresses them and resumes the correct frames without data races on VM state (still single-threaded from the language’s point of view).
6. **JVM runtime behavior:** JVM runtime exhibits the correct behavior for async programs, especially async I/O and CLI loop lifetime modes.
7. **CLI process model:** Default **`--exit-wait`** (run-until-idle); **`--exit-no-wait`** for eager exit; documented in `09-tools` and CLI help.
8. **Exceptions + AWAIT:** AWAIT inside `try`/`catch` behaves **deterministically**, with documented unwind semantics; covered by JVM tests.
9. **Portable tests:** Async concurrency tests **do not** assert completion **order**; they **do** run unchanged on the **JVM**.
10. **Foundation for later work:** Timers, HTTP (**60**), and further I/O plug into the same loop model.

## Acceptance Criteria

- [ ] **Frame suspension:** On AWAIT, if the TASK is not completed, persist the current frame state and return to the scheduler; do not push a bogus value in place of the awaited result.
- [ ] **Resumption:** When a TASK becomes completed, any frame suspended awaiting it is resumed and receives the **typed** result on the stack (**`Result`** success or failure as specified).
- [ ] **Single-threaded loop:** JVM runtime uses one thread for Kestrel frames and the loop’s turn logic; no parallel execution of two Kestrel frames at once.
- [ ] **Non-blocking stdlib (implemented surface only):** Audit complete for **shipped** async/non-blocking APIs; each uses the event loop / background completion path on the **JVM**. **HTTP / unimplemented spec-only APIs** excluded (**60**).
- [ ] **Result + error ADTs:** Async stdlib operations exposed as `Task<…>` use **`Result<_, ErrorAdt>`** (or documented equivalent) with **enumerated** error types; legacy ad-hoc error channels removed or deprecated per spec.
- [ ] **Multiple concurrent tasks:** At least two independent async operations can be in flight; tests prove correctness **without** asserting **which** completes first.
- [ ] **E2E / integration:** Scenario(s) with concurrent async work (e.g. two reads) whose assertions depend only on **final aggregated outcomes** (or explicit synchronization **in Kestrel**, not on runtime ordering), runnable on the **JVM**.
- [ ] **CLI:** **`--exit-wait`** is the default (run until event loop idle); **`--exit-no-wait`** implements the override; behavior documented in **`09-tools`** and **`kestrel run --help`**.
- [ ] **AWAIT in try/catch:** Specified, implemented on the **JVM**, and tested (unwind + resume correctness).
- [ ] **Specs updated** (`01`, `02`, `04`, `05`, `06`, `08`, `09-tools` as needed)—no contradiction with non-blocking guarantees, Result errors, or CLI lifetime.
- [ ] **Regression safety:** Existing tests and conformance updated for new error and async shapes; JVM suites stay green.

## Spec References

- `docs/specs/01-language.md` §5 (Async and Task model)
- `docs/specs/04-bytecode-isa.md` §1.9 (AWAIT: suspend when task not complete)
- `docs/specs/05-runtime-model.md` §6 (TASK suspended vs completed; event-loop-driven I/O; single-threaded frame execution)
- `docs/specs/02-stdlib.md` (async APIs and filesystem **implemented in 59**; HTTP work stays with **60**)
- `docs/specs/06-typesystem.md` (`Task`, `Result`, ADTs)
- `docs/specs/08-tests.md` (async/Task testing expectations; JVM runtime behavior)
- `docs/specs/09-tools.md` (CLI: `kestrel run`, loop lifetime, flags)

## Risks / Notes

### Event loop shape (Node.js analogy)

- **Single thread:** All `async`/`await` continuations and synchronous user code run on that thread, interleaved—not in parallel.
- **Blocking calls:** Synchronous/blocking primitives on the main thread are **bugs** for any API specified as non-blocking; the audit should catch them.
- **Scheduling order:** Relative order of **unrelated** task completions may remain **implementation-defined** in the spec, but **tests must not depend on it**—use only outcomes that hold for **any** valid schedule, or use **in-program** synchronization if order must be observed.

### Task errors and migration

- Moving from **empty string** (or similar) to **`Result<_, ErrorAdt>`** is a **breaking** surface change for some stdlib calls; list migration notes, conformance updates, and changelog expectations in **Notes** or project changelog when implementing.

### JVM, bytecode, and exceptions

- Suspension must capture **everything** required to resume safely, including **open try regions** when AWAIT appears inside **`try`**. Interaction with **THROW / END_TRY** and JVM lowering is high risk—verify against compiler unwind metadata.


### Audit scope

- The audit covers **stdlib**, **JVM runtime primitives**, **compiler lowering** if needed, **scripts/CLI** entry, and **tests** that assumed synchronous completion or old error shapes—**limited to code paths that exist today**. **Do not** expand scope to HTTP client/server or other **60** work; the spec may still mention HTTP, but **59** updates only what is already implemented unless a doc fix is needed for consistency.

## Impact analysis

| Area | Files / subsystems (indicative) | Change | Risk |
|------|----------------------------------|--------|------|
| **Bytecode / ISA** | `docs/specs/04-bytecode-isa.md`; possibly `compiler/src/bytecode/` if new ops (prefer **no** new user opcodes unless unavoidable) | Document actual AWAIT behavior; align disasm if TASK layout changes | Medium |
| **Compiler (TS)** | `compiler/src/typecheck/check.ts` (`__read_file_async`, `Task<Result<…>>`), `compiler/src/codegen/codegen.ts`, `compiler/src/jvm-codegen/codegen.ts`, `stdlib/kestrel/fs.ks`, stdlib tests | New **Result + error ADT** types for fs async API; primitive name/signature updates; any closure/async edge cases for suspended frames | Medium |
| **JVM runtime** | `runtime/jvm/.../KRuntime.java` (and interpreter loop classes if separate) | Suspended tasks, AWAIT, event pump integration, non-blocking read | **High**: suspension, try/unwind state |
| **CLI** | `scripts/kestrel` (`cmd_run` / argument parsing), possibly `compiler` CLI if run is delegated | Parse **`--exit-wait`** (default) and **`--exit-no-wait`**; reject **both** with a clear error; plumb into JVM launch path | Low–medium |
| **Tests** | `tests/unit/*.test.ks`, `stdlib/kestrel/fs.test.ks`, `tests/conformance/runtime/valid/async_await.ks`, Vitest async/typecheck tests, E2E | Update expectations for **Result**; add concurrent async scenarios **order-agnostic** | Medium |
| **Docs** | `docs/specs/01`, `02`, `05`, `06`, `08`, `09-tools`; `AGENTS.md` if verification commands change | Non-blocking guarantees, CLI flags, error ADTs, test parity | Low |

**Rollback:** Feature-flagging a full event loop is difficult; prefer incremental commits behind tests.

## Tasks

- [ ] **Audit (inventory):** List every **implemented** `Task<…>` / async primitive and stdlib re-export (`stdlib/kestrel/fs.ks`, `__read_file_async`, JVM `KRuntime.readFileAsync`); record sync/blocking call sites. Exclude HTTP / spec-only stubs (**60**).
- [ ] **Spec-first pass:** Update `05-runtime-model` §6 and `04` AWAIT text for suspension, idle process, and (if needed) TASK object layout; draft `02` **readText** / fs errors as **`Task<Result<String, FsReadError>>`** (or chosen ADT names); align `06` and `01` §5 for Task + Result composition.
- [ ] **Compiler / stdlib:** Change **`kestrel:fs`** `readText` and primitive typing to **`Task<Result<String, E>>`**; introduce **error ADT** in stdlib or builtins; update **`__read_file_async`** binding in typecheck and both codegens.
- [ ] **JVM:** Implement **TASK**, **AWAIT** suspension/resume, and **readFileAsync** non-blocking behavior; align **KRuntime** with new Result shape.
- [ ] **CLI:** Implement **`--exit-wait`** (default) and **`--exit-no-wait`** in `scripts/kestrel`; **error** if both supplied; document semantics in `09-tools`.
- [ ] **CLI wiring:** Ensure the JVM **run** path honors exit mode (wait for idle vs exit when entry completes—per **Notes**).
- [ ] **Portable tests:** Add or update **Kestrel** tests for concurrent async reads with **order-independent** assertions; run via **`./scripts/kestrel test`** on the **JVM**.
- [ ] **Conformance / Vitest:** Update `tests/conformance/runtime/valid/async_await.ks` and any typecheck conformance for new **`Result`** types; fix `compiler` unit/integration tests for async/fs.
- [ ] **E2E:** Add scenario under `tests/e2e/scenarios/positive/` (or extend existing) for concurrent async file operations, **no ordering assertions**.
- [ ] **Disasm / debug:** If TASK layout or new runtime hooks affect bytecode metadata, update `compiler/disasm.ts` or debug docs only if needed.
- [ ] **Verification:** `cd compiler && npm run build && npm test`; `./scripts/kestrel test`; `./scripts/run-e2e.sh` if E2E touched.

## Tests to add

| Layer | Path / mechanism | Intent |
|-------|------------------|--------|
| **Vitest** | `compiler/test/unit/typecheck/`, `compiler/test/integration/` | `readText` / primitive type **`Task<Result<…>>`**; await + Result unwrap patterns; regressions for async context |
| **Conformance** | `tests/conformance/runtime/valid/async_await.ks`, new `tests/conformance/typecheck/` cases if needed | Language + runtime shapes for async + Result |
| **Kestrel unit** | `tests/unit/*.test.ks`, `stdlib/kestrel/fs.test.ks` | **Result** success/failure paths; **no completion-order** dependence |
| **JVM** | `./scripts/kestrel test` | Async behavior on the **JVM** |
| **E2E** | `tests/e2e/scenarios/positive/*.ks` + `.expected` | Concurrent async I/O; aggregate assertions only |
| **Manual / smoke** | `scripts/jvm-smoke.mjs` or extend if present | Quick JVM smoke after AWAIT changes |

## Documentation and specs to update

- [ ] `docs/specs/01-language.md` §5 — Task + await; interaction with **Result**-carrying tasks if user-visible.
- [ ] `docs/specs/02-stdlib.md` — **Filesystem** / `readText`: **non-blocking**, **`Task<Result<String, ErrorAdt>>`**, remove or narrow “may complete synchronously” where 55 applies.
- [ ] `docs/specs/04-bytecode-isa.md` — AWAIT suspend/resume; reference **05** for idle/process model.
- [ ] `docs/specs/05-runtime-model.md` §6 — Event loop, **idle**, single-threaded execution, TASK lifecycle, optional background I/O thread signaling.
- [ ] `docs/specs/06-typesystem.md` — Typing **`Task<Result<A,E>>`** and error ADT exports if new.
- [ ] `docs/specs/08-tests.md` — Async testing, **JVM runtime behavior**, **no scheduler-order** dependence in conformance/unit tests.
- [ ] `docs/specs/09-tools.md` — **`kestrel run`**: **`--exit-wait`** (default), **`--exit-no-wait`**, mutual exclusion rule.

## Notes

- **`--exit-no-wait` semantics (planning default):** Exit when the **program entry** returns control to the host **without** draining the event loop (pending TASKs may remain incomplete or be dropped—pick one and document; prefer **explicit process exit code** and stderr warning if work was abandoned). **`--exit-wait`:** after entry returns, keep driving the loop until **idle** (no runnable frames, no registered pending I/O for in-flight tasks—exact definition in `05`).
- **Both flags:** **Reject** with a diagnostic and non-zero exit (simplest, matches user recommendation in story draft).
- **Timers:** Out of scope unless needed to unblock I/O testing; if deferred, note follow-up for **60** / later story.
- **Migration:** List every breaking change to `Fs.readText` consumers in stdlib tests and conformance; consider a short **changelog** entry in repo root or `docs/` if the project maintains one.
