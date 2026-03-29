# Async/Await: Real Suspension and Event Loop

## Sequence: 55
## Tier: 7 — Deferred (large / dependency-heavy)
## Former ID: 22

## Summary

The current AWAIT implementation only handles **completed** tasks (synchronous returns). If a task is pending, the VM pushes **unit** instead of suspending the caller—so `await` does not actually yield. For real async (file I/O, HTTP, timers), the runtime must **suspend the current frame** when AWAIT sees a suspended TASK, drive work from a **single-threaded event loop** in the spirit of **Node.js** (one thread runs user code and the loop; I/O completion and scheduling advance work without blocking that thread on I/O wait), and **resume** suspended continuations when tasks complete.

**Delivery scope:** **Reference VM and JVM backend** implement the same observable behavior in one story—no deferred “JVM later.” **Stdlib:** every API that is **async-shaped or documented as non-blocking** must be implemented **non-blocking** on the main thread, not only a single read primitive; include an **audit** of impacted code and update all call sites and runtimes accordingly. **Errors:** async operations surface failures via **`Task` carrying `Result<Success, ErrorAdt>`** (or equivalent), with **errors as a named ADT** per domain—not ad-hoc sentinels such as empty-string errors where this story defines the new contract. **CLI:** **`kestrel run`** uses **`--exit-wait` by default** (keep the process alive until the event loop is idle). **`--exit-no-wait`** opts out: exit without waiting for pending async work (exact tie to `main` return documented in **planned** / `09-tools`). Users may pass **`--exit-wait` explicitly** for clarity; it is the default when neither flag is given. This story closes the gap between today’s placeholder behavior and `05-runtime-model` §6 and `04-bytecode-isa` for AWAIT.

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
- **Dependencies (risk reduction):** sequences **12**–**15** (VM stack guard, VM integration tests, overflow/divzero tests) before landing large VM/runtime changes.
- **Spec / stdlib churn:** This story supersedes the old “reference VM may complete `readText` synchronously” escape hatch where it conflicts with **non-blocking** and **Result/ErrorAdt** requirements; **planned** lists every spec and module to touch.

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

- Moving from **empty string** (or similar) to **`Result<_, ErrorAdt>`** is a **breaking** surface change for some stdlib calls; **planned** should list migration notes, conformance updates, and version/changelog expectations if applicable.

### VM, bytecode, and exceptions

- Suspension must capture **everything** required to resume safely, including **open try regions** when AWAIT appears inside **`try`**. Enumerate interaction with **THROW / END_TRY** and JVM lowering in **planned** impact analysis.

### JVM parity

- Same **CLI modes**, same **observable async behavior**, same **shared tests**. Any use of platform-specific schedulers must be hidden behind a **common semantic contract**.

### Audit scope

- The audit covers **stdlib**, **runtime primitives**, **compiler lowering** if needed, **scripts/CLI** entry, and **tests** that assumed synchronous completion or old error shapes—**limited to code paths that exist today**. **Do not** expand scope to HTTP client/server or other **56** work; the spec may still mention HTTP, but **55** updates only what is already implemented unless a doc fix is needed for consistency.

### Open questions for **planned** (implementation detail)

- Precise semantics of **`--exit-no-wait`** vs `main` return and pending TASKs (edge cases); behavior if **both** `--exit-wait` and `--exit-no-wait` are passed (recommend: reject with diagnostic or define precedence).
- Internal scheduler API (ready queue, I/O registration hook).
- Whether **timers** ship in this story or only I/O hooks (**56** may assume timer follow-up if deferred).

Planning gate: add **Impact analysis**, **Tasks**, **Tests to add**, and **Documentation and specs to update** when promoting this file to `docs/kanban/planned/`.
