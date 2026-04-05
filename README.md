# Kestrel

Kestrel is a statically typed language with Hindley–Milner type inference. You write programs that feel like scripts; the compiler checks them carefully, emits JVM `.class` files, and runs them on the JVM backend. The project is under active development; language details live in [docs/specs/](docs/specs/), and work is tracked in the Kanban under [docs/kanban/](docs/kanban/) (pre-roadmap ideas in [future/](docs/kanban/future/); roadmap in [unplanned/](docs/kanban/unplanned/); see [docs/kanban/README.md](docs/kanban/README.md) for **future** and **unplanned → planned → doing → done**).

## What you need

- **Node.js** 18 or newer (for the compiler)
- **Java 21+** for the JVM runtime and async execution (Project Loom virtual threads)

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

The [samples/](samples/) directory contains standalone programs that showcase the language:

| File | What it shows |
|------|---------------|
| [samples/quicksort.ks](samples/quicksort.ks) | Divide-and-conquer sort with pattern matching on lists |
| [samples/primes.ks](samples/primes.ks) | Sieve of Eratosthenes |
| [samples/mandelbrot.ks](samples/mandelbrot.ks) | Mandelbrot set rendered in the terminal |
| [samples/expr.ks](samples/expr.ks) | Expression parser and evaluator using ADTs |
| [samples/word-count.ks](samples/word-count.ks) | Word-frequency counter with dictionaries and higher-order functions |
| [samples/life.ks](samples/life.ks) | Conway's Game of Life |
| [samples/lambda.ks](samples/lambda.ks) | Lambda calculus parser and reducer |

Run any sample with `./kestrel run samples/<name>.ks`.

## Java interop

Kestrel runs on the JVM and can call any Java class directly. Three mechanisms cover the common cases:

- **`extern fun`** — bind a function name to a JVM static method, instance method, or constructor: `extern fun toUpper(s: String): String = jvm("java.lang.String#toUpperCase()")`
- **`extern type`** — introduce a Kestrel type backed by a JVM class: `extern type StringBuilder = jvm("java.lang.StringBuilder")`
- **`extern import`** — auto-generate bindings for an entire class by reading its public API at compile time: `extern import "java:java.lang.StringBuilder" as SB { }` (optional override block corrects specific signatures)
- **Maven dependencies** — add a JAR to the classpath with a side-effect import: `import "maven:com.google.guava:guava:33.3.1-jre"` — the compiler downloads and caches the artifact; `kestrel run` picks it up automatically.

See the [Java interop section of the guide](docs/guide.md#java-interop) for full examples.

## Command-line tool

The `kestrel` script implements the CLI described in [docs/specs/09-tools.md](docs/specs/09-tools.md):

- **`kestrel run`** — `<script.ks>` and runtime arguments. Compiles if needed, then runs on the JVM. Pass `--refresh` to re-download URL dependencies; `--allow-http` to permit `http://` imports.
- **`kestrel build`** — Builds the compiler; optional script path to compile. `--refresh`, `--allow-http`, and `--status` (print URL cache report without compiling) are also accepted.
- **`kestrel dis`** — Compiles if needed, then prints JVM bytecode disassembly via `javap`.
- **`kestrel test`** — Runs Kestrel unit tests; optional test file paths. `--verbose` prints per-assertion lines; `--summary` prints one line per suite. `--clean`, `--refresh`, and `--allow-http` have the same meaning as for `run` and `build`.

JVM class output is cached under `~/.kestrel/jvm/` unless you set `KESTREL_JVM_CACHE`.

## Repository layout

```
kestrel/
├── kestrel              # CLI wrapper → scripts/kestrel
├── compiler/            # TypeScript: parse, typecheck, emit JVM .class files
├── runtime/jvm/         # Java runtime for the JVM target
├── stdlib/kestrel/      # Standard modules (strings, lists, tests, …)
├── tests/               # Unit, E2E, and conformance tests
├── docs/specs/          # Normative specifications (language, tools, diagnostics, …)
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
