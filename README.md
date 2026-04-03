# Kestrel

Kestrel is a statically typed language with Hindley–Milner type inference. You write programs that feel like scripts; the compiler checks them carefully, emits bytecode (`.kbc`), and runs them on the JVM backend. The project is under active development; language details live in [docs/specs/](docs/specs/), and work is tracked in the Kanban under [docs/kanban/](docs/kanban/) (pre-roadmap ideas in [future/](docs/kanban/future/); roadmap in [unplanned/](docs/kanban/unplanned/); see [docs/kanban/README.md](docs/kanban/README.md) for **future** and **unplanned → planned → doing → done**).

## What you need

- **Node.js** 18 or newer (for the compiler)
- **JDK 11+** for the JVM runtime

## Quick start

Clone the repository, then build the compiler:

```bash
cd compiler && npm install && npm run build
cd ..
```

Create `hello.ks`:

```kestrel
fun fibonacci(n: Int): Int =
  if (n <= 1) n else fibonacci(n - 1) + fibonacci(n - 2)

val result = fibonacci(10)
print(result)
```

Run it (the CLI compiles when inputs or dependencies change):

```bash
./kestrel run hello.ks
# prints 55
```

You can invoke `./kestrel` using an absolute path or a symlink; the script resolves its install location so it does not depend on your current working directory. See [CONTRIBUTING.md](CONTRIBUTING.md) for adding the tool to your `PATH`.

## Learn the language

The **[Introduction to Kestrel](docs/guide.md)** walks through the language from first principles: values, functions, types, pattern matching, error handling, modules, and pipelines — with runnable examples throughout.

For a quick taste:

```kestrel
import { map, filter, sum } from "kestrel:list"

val result =
  [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  |> filter((n) => n % 2 == 0)
  |> map((n) => n * n)
  |> sum
// result is 220
```

More examples appear in [tests/unit/](tests/unit/) and [tests/e2e/scenarios/](tests/e2e/scenarios/).

## Command-line tool

The `kestrel` script implements the CLI described in [docs/specs/09-tools.md](docs/specs/09-tools.md):

- **`kestrel run`** — `<script.ks>` and runtime arguments. Compiles if needed, then runs on the JVM.
- **`kestrel build`** — Builds the compiler; optional script path to compile.
- **`kestrel dis`** — Compiles if needed, then prints bytecode disassembly for a script.
- **`kestrel test`** — Runs Kestrel unit tests; optional test file paths.

Bytecode is cached under `~/.kestrel/kbc/` (layout mirrors absolute source paths). Override with `KESTREL_CACHE`. JVM class output uses `~/.kestrel/jvm/` unless you set `KESTREL_JVM_CACHE`.

## Repository layout

```
kestrel/
├── kestrel              # CLI wrapper → scripts/kestrel
├── compiler/            # TypeScript: parse, typecheck, emit .kbc (and JVM)
├── runtime/jvm/         # Java runtime for the JVM target
├── stdlib/kestrel/      # Standard modules (strings, lists, tests, …)
├── tests/               # Unit, E2E, and conformance tests
├── docs/specs/          # Normative specifications (language, bytecode, tools, …)
└── scripts/             # CLI implementation, E2E runner, full test script
```

## Tests

From the repository root:

```bash
./scripts/test-all.sh
```

runs compiler tests, E2E scenarios, and Kestrel unit tests. See [CONTRIBUTING.md](CONTRIBUTING.md) for running individual layers.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). For security-sensitive reports, use [SECURITY.md](SECURITY.md).

## License

MIT — see [LICENSE](LICENSE).
