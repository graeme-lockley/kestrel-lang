# Runtime conformance (spec 08 §2.4–2.5, §3.2)

- **valid/** — `.ks` programs that must **compile**, execute on the JVM runtime with **exit code 0**, and produce **stdout** that matches golden lines derived from the source file.

## Golden stdout lines

After each **`println(...)`**, expected output is given on following **`//`** comment lines. The test harness collects `//` lines in source order, skipping documentation-style comments (e.g. lines starting with `Runtime conformance:`, `For now:`, `EXPECT:`, `Parse note:`, etc. — see `compiler/test/integration/helpers/runtime-stdout-goldens.ts`).

Each non-empty stdout line from the VM (after trimming a trailing newline) must equal the corresponding golden line, in order.

## CI execution

These scenarios run under **`cd compiler && npm test`** via `compiler/test/integration/runtime-conformance.test.ts`.

Compilation uses `node compiler/dist/cli.js <file.ks> -o <kbc>` with **`KESTREL_CACHE`** pointing at a per-run temp directory whose layout matches `scripts/kestrel` (`KBC_CACHE` + absolute source directory + basename `.kbc`), so multi-module programs resolve the same way as `kestrel run`.

The JVM runtime is executed via the compiled `.class` files using the `kestrel-runtime.jar` (built in the test `beforeAll`).

**Note:** `./scripts/run-e2e.sh` exercises `tests/e2e/scenarios/*` only; it does **not** run this tree.

See also: [../parse/README.md](../parse/README.md), [../typecheck/README.md](../typecheck/README.md).
