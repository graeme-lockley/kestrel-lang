# Contributing to Kestrel

Thank you for your interest in Kestrel. This project welcomes contributions that align with its goals: a small, clear language with solid types and honest documentation.

Please read the [Code of Conduct](CODE_OF_CONDUCT.md) before participating.

## Prerequisites

| Tool | Version | Used for |
|------|---------|----------|
| [Node.js](https://nodejs.org/) | 18 or newer | Compiler (TypeScript), tests |
| [Zig](https://ziglang.org/) | Current stable | Bytecode VM, build and tests |
| [Java](https://adoptium.net/) JDK | 11 or newer | Optional: JVM backend (`--target jvm`) |

The compiler declares `engines.node` in [compiler/package.json](compiler/package.json). The JVM runtime is built with `-source 11 -target 11` in [runtime/jvm/build.sh](runtime/jvm/build.sh).

## Getting started

Clone the repository and install compiler dependencies:

```bash
cd compiler
npm install
npm run build
```

Build the VM:

```bash
cd ../vm
zig build
```

From the repository root you can use the CLI:

```bash
./kestrel run path/to/script.ks
```

You can add the repo to your `PATH` or symlink `./kestrel` so the toolchain resolves correctly from anywhere (see [README.md](README.md)).

## Running tests

**Full suite** (recommended before opening a PR):

```bash
./scripts/test-all.sh
```

This runs, in order:

1. Compiler unit and integration tests — `cd compiler && npm test`
2. VM tests — `cd vm && zig build test`
3. End-to-end scenarios — `./scripts/run-e2e.sh`
4. Kestrel-language unit tests — `./scripts/kestrel test`

You can run each layer alone when iterating:

```bash
cd compiler && npm test
cd vm && zig build test
./scripts/run-e2e.sh
./scripts/kestrel test
```

**JVM target** (optional local check):

```bash
cd runtime/jvm && ./build.sh
./scripts/kestrel test --target jvm
```

## Code and documentation expectations

- Follow existing style in the compiler (TypeScript, strict mode) and VM (Zig). Conventions for agents and humans are summarized in [AGENTS.md](AGENTS.md).
- Language behaviour and public APIs should match the specs in [docs/specs/](docs/specs/). If you change behaviour, update the relevant spec in the same change.
- Add or extend Kestrel tests under [tests/unit/](tests/unit/) for language or stdlib behaviour. Run `./scripts/kestrel test` to verify.

## Commit messages

Kestrel follows the [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) specification.

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**Types:**

| Type | When to use |
|------|-------------|
| `feat` | New language feature or compiler capability |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `refactor` | Code change that is neither a fix nor a feature |
| `test` | Adding or updating tests |
| `chore` | Maintenance tasks (dependency updates, tooling) |
| `ci` | CI/CD configuration |
| `perf` | Performance improvement |
| `style` | Formatting changes with no logic impact |

**Scopes** (optional, in parentheses): `parser`, `typecheck`, `codegen`, `jvm`, `stdlib`, `cli`, `vm`, `e2e`.

**Breaking changes** — append `!` after the type/scope and/or add a `BREAKING CHANGE:` footer:

```
feat(parser)!: remove support for legacy syntax

BREAKING CHANGE: the `=>` arrow form is no longer accepted; use `->` instead.
```

**Examples:**

```
feat(typecheck): infer return type of recursive functions
fix(codegen): emit correct opcode for nested let bindings
docs: update spec for match expressions
test(stdlib): add coverage for List.map edge cases
chore: bump vitest to 2.x
```

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Make focused changes using [Conventional Commits](#commit-messages) for all commit messages.
3. Ensure `./scripts/test-all.sh` passes (and JVM tests if you touch the JVM backend).
4. Open a pull request describing the problem, the solution, and any spec or test updates.

## Where to look next

- **Language and bytecode design:** [docs/specs/](docs/specs/) (numbered specs 01–09).
- **Kanban / planned work:** investigations and ideas in [docs/kanban/future/](docs/kanban/future/) (`slug.md`, no numeric prefix); prioritized roadmap in [docs/kanban/unplanned/](docs/kanban/unplanned/) (`NN-slug.md`); stories move through **planned**, **doing**, and **done** per [docs/kanban/README.md](docs/kanban/README.md).
- **Security issues:** do not file them as public issues; see [SECURITY.md](SECURITY.md).

Questions and small fixes are welcome via issues and pull requests. Thank you for helping improve Kestrel.
