# VM interpreter vs JVM JIT: performance gap (investigation)

## Kind

Investigation / idea — not on the numbered roadmap. Possible future story once goals and acceptance are defined.

## Observation

Running the same program (e.g. `mandelbrot.ks`) on **`./kestrel run`** (Zig stack VM, bytecode interpreter in `vm/src/exec.zig`) vs **`./kestrel run --target jvm`** (HotSpot) shows **materially different wall-clock** on compute-heavy workloads. In one informal run on a laptop, JVM finished in roughly **half** the total time of the VM path; compile times in the log were similar, so the gap is dominated by **execution**, not compilation.

This is **not** a correctness divergence: both backends implement the same language semantics for that program. The surprise is only if one expects “same bytecode shape → same speed”; the **engines** are very different.

## Why the backends diverge

1. **Kestrel VM** — A **single interpreter loop** dispatches `.kbc` opcodes (`while (pc < code.len)` + per-opcode handling). Every inner-loop iteration pays interpreter overhead (dispatch, stack/locals traffic). There is **no JIT** today.
2. **JVM** — **HotSpot** JIT-compiles hot methods and loops to **native code**. Mandelbrot-style nested numeric loops are ideal JIT food: the hot region becomes mostly register/machine code after warmup.

So head-to-head **language** parity does not imply head-to-head **peak numeric** performance. Benchmarks that are call-heavy, allocation-heavy, or very short can look closer because fixed costs dominate; **tight numeric kernels** widen the gap.

## Possible optimisation directions (VM-focused)

These are **options to explore**, not commitments. Any serious effort should start with **reproducible benchmarks** (same machine, ReleaseSafe VM, warm vs cold JVM, separating compile vs run).

| Direction | Notes |
|-----------|--------|
| **Tiered / tracing JIT for `.kbc`** | Largest potential win on hot loops; high engineering cost; interacts with GC and debug. |
| **Superinstructions or fused opcodes** | Reduce dispatch and stack traffic in common sequences (e.g. arithmetic + local load/store). |
| **Fast paths for primitives** | Unboxed int/float fast paths in the interpreter (or specialized opcodes) where type analysis or runtime guards allow. |
| **Computed goto / threaded interpreter** | Speed up dispatch in Zig without a full JIT. |
| **Benchmark harness** | Stable scripts + reporting so regressions and wins are measurable (`test-both` style extensions, dedicated micro/macro benches). |

## JVM backend

HotSpot already optimizes the emitted Java bytecode aggressively. Further JVM-side work is more about **correctness**, **startup**, or **smaller bytecode** than matching the VM on raw loops. Cross-backend **fair comparison** docs could still help set expectations.

## Open questions

- What **target** should the VM aim for (e.g. “within X× of JVM on mandelbrot” vs “good enough for scripting”)?
- Is a **small JIT** or **specialized numeric tier** enough, or is interpreter tuning the right first step?
- How much should **spec / user docs** explain “VM vs JVM performance characteristics”?

## Promotion

When this becomes actionable, move to **`docs/kanban/unplanned/NN-<slug>.md`**, assign the next free global **`NN`**, add **Tier**, and fill standard **unplanned** sections (Summary, Current State, Goals, Acceptance criteria, Spec references, Risks / notes).
