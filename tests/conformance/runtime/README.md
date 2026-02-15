# Runtime conformance tests (spec 08 §2.4, §2.5, §3.2)

VM behaviour verification per [05-runtime-model.md](../../../docs/specs/05-runtime-model.md).

- **valid/** — `.ks` programs that must compile, run on the VM, and produce expected stdout. Expected output is given by `//` comment lines immediately after each `print(...)` (same convention as E2E scenarios).

Scenarios cover:

- **Exception throw/catch** — bytecode that throws and catches; stack unwinding and result.
- **GC stress** — many short-lived allocations; no leaks, no use-after-free.
- **Async/await** — when supported; suspension and resumption.

The test harness runs these via `scripts/run-e2e.sh` (runtime conformance is executed together with E2E scenarios). `scripts/test-all.sh` runs the full suite including runtime conformance.
