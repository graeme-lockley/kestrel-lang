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

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Make focused changes with clear commit messages.
3. Ensure `./scripts/test-all.sh` passes (and JVM tests if you touch the JVM backend).
4. Open a pull request describing the problem, the solution, and any spec or test updates.

## Where to look next

- **Language and bytecode design:** [docs/specs/](docs/specs/) (numbered specs 01–09).
- **Planned work:** [docs/kanban/unplanned/](docs/kanban/unplanned/) (sequence-ordered); overview in [docs/kanban/README.md](docs/kanban/README.md).
- **Security issues:** do not file them as public issues; see [SECURITY.md](SECURITY.md).

Questions and small fixes are welcome via issues and pull requests. Thank you for helping improve Kestrel.
