# Agent Guidelines for Kestrel

**Generated:** 2026-03-07
**Commit:** 745543c
**Branch:** main

This file provides guidance for agentic coding agents working on the Kestrel project.

## Project Overview

Kestrel is a statically typed programming language with Hindley-Milner type inference. It consists of:
- **Compiler**: TypeScript in `compiler/`
- **VM**: Zig in `vm/`
- **CLI**: Bash scripts in `scripts/`

---

## Build, Test, and Lint Commands

### Compiler (TypeScript)

```bash
cd compiler

# Install dependencies
npm install

# Build the compiler (outputs to dist/)
npm run build

# Run all tests
npm test

# Run tests in watch mode
npm run test:watch

# Run a single test file
npm test -- --run <test-file>
# Example: npm test -- --run test/unit/lexer.test.ts
```

### VM (Zig)

```bash
cd vm

# Build the VM
zig build

# Build with optimizations
zig build -Doptimize=ReleaseSafe

# Run VM tests (uses build.zig; registers tests via src/main.zig)
zig build test
```

### End-to-End Tests

Layout: `tests/e2e/scenarios/negative/*.ks` (must fail at compile or VM with non-zero exit; see `tests/e2e/scenarios/negative/README.md`) and `tests/e2e/scenarios/positive/*.ks` (stdout compared to `*.expected`). `./scripts/test-all.sh` runs `./scripts/run-e2e.sh` after compiler and VM tests.

```bash
# Run E2E tests (from project root)
./scripts/run-e2e.sh
```

### Using the Kestrel CLI

```bash
# Run a Kestrel script
./kestrel run <script.ks> [args...]

# Disassemble bytecode
./kestrel dis <script.ks>

# Build compiler and VM (optionally compile a script)
./kestrel build [script.ks]

# Run Kestrel test suite
./kestrel test [files...]

# Run unit tests on VM and JVM with wall-clock and harness timing comparison
./kestrel test-both [files...]
```

---

## Code Style Guidelines

### General

- **Language**: TypeScript for the compiler, Zig for the VM
- **Strict mode**: Always enabled in TypeScript (`tsconfig.json` has `"strict": true`)
- **Module system**: ES modules (`.js` extensions in imports)

### TypeScript Conventions

#### Imports

- Use explicit `.js` extensions for all local imports: `import { foo } from './foo.js';`
- Group imports: standard library first, then external, then local
- Use `import type` for type-only imports

```typescript
import { readFileSync } from 'fs';
import type { Token, Span } from './types.js';
import { tokenize } from './lexer/index.js';
```

#### Naming

- **Variables/functions**: camelCase (`tokenize`, `parseProgram`)
- **Classes**: PascalCase (`Parser`, `ParseError`)
- **Interfaces**: PascalCase, often with descriptive names (`CompileOptions`)
- **Types**: PascalCase (`Diagnostic`, `SourceLocation`)
- **Constants**: PascalCase for exported constants, camelCase for local

#### Functions

- Use function declarations for exported functions
- Use private class methods for internal parsing/analysis
- Keep functions focused and small (under 50 lines when possible)

#### Types

- Prefer explicit return types for exported functions
- Use `interface` for public APIs, type aliases for unions/primitives
- Use `unknown` instead of `any`; use type assertions sparingly

```typescript
export function compile(source: string, opts?: CompileOptions): 
  { ok: true; ast: Program } | { ok: false; diagnostics: Diagnostic[] }
```

#### Error Handling

- Use custom error classes for parsing errors (e.g., `ParseError`)
- Use result types (`{ ok: true; ... } | { ok: false; ... }`) for operations that can fail
- Provide meaningful error messages with location info when possible

```typescript
export class ParseError extends Error {
  constructor(
    message: string,
    public offset: number,
    public line: number,
    public column: number
  ) {
    super(message);
    this.name = 'ParseError';
  }
}
```

#### Testing (Vitest)

- Tests go in `compiler/test/unit/` and `compiler/test/integration/`
- **Conformance corpora** (`.ks` files under `tests/conformance/`): **parse** (`parse/` — `parse-conformance.test.ts`), **typecheck** (`typecheck/` — `typecheck-conformance.test.ts`), **runtime VM** (`runtime/valid/` — `runtime-conformance.test.ts`). All are run by **`cd compiler && npm test`**. See [tests/conformance/typecheck/README.md](tests/conformance/typecheck/README.md) (links to parse/runtime READMEs) for layout, `// EXPECT:` on invalid cases, and in-file `println` + `//` stdout goldens for runtime.
- Use `describe` blocks for grouping related tests
- Use `it` or `test` for individual test cases
- Use `expect` with matchers

```typescript
import { describe, it, expect } from 'vitest';
import { tokenize } from '../../src/lexer/index.js';

describe('tokenize', () => {
  it('returns eof for empty source', () => {
    const tokens = tokenize('');
    expect(tokens.length).toBe(1);
  });
});
```

### Code Organization

- Each module should have an `index.ts` that re-exports the public API
- Use barrel files for cleaner imports: `import { tokenize } from './lexer/index.js';`
- Keep related code together (e.g., types near their consumers)

---

## Quality Standards

### Tests are Mandatory
- **All Kestrel changes must update unit tests** in `tests/unit/*.test.ks`
- Run tests with: `./scripts/kestrel test`
- New features should include test cases in the appropriate test file
- Bug fixes should include regression tests

### Specs are Mandatory
- **All Kestrel changes must review and update relevant specs** in `docs/specs/`
- Before implementing: check if the feature is documented in specs
- After implementing: update the spec to reflect the new behavior
- Specs should be accurate at all times - they are the source of truth

### Change Checklist
Before marking a task complete:
- [ ] Unit tests pass (`./scripts/kestrel test`)
- [ ] Compiler tests pass (`cd compiler && npm test`)
- [ ] VM tests pass (`cd vm && zig build test`)
- [ ] Relevant specs updated (if applicable)

---

## Kanban Workflow (from Cursor rules)

Stories live in `docs/kanban/` with folders: **unplanned**, **planned**, **doing**, **done**.

The **prioritized roadmap** is in **`docs/kanban/unplanned/`**, named `NN-slug.md`; **`NN` is globally unique** (current queue **50–67**, lower = higher priority). See `docs/kanban/README.md` for the tier table, entry/exit criteria, and templates. The same file is **moved** between folders as work progresses. **`docs/kanban/backlog/`** is **deprecated**; use **`planned/`** instead.

### Workflow

1. **unplanned** — High-level feature stories on the ordered roadmap (summary, state, relationships, **goals**, acceptance, spec refs, **risks / notes**).
2. **planned** — Scoped but not yet built: adds impact analysis, **Tasks**, tests to add, docs/specs to update, optional **Notes**.
3. **doing** — Active implementation; tick tasks; add **Build notes** as needed.
4. **done** — All tasks ticked, acceptance satisfied, and **required tests passing**.

### When promoting a story

- **unplanned → planned** — Meet unplanned exit criteria in `docs/kanban/README.md`; move the file to `docs/kanban/planned/`.
- **planned → doing** — Meet planned exit criteria (tasks and test/doc lists complete); move to `docs/kanban/doing/`.
- **doing → done** — Meet doing exit criteria; run verification commands; move to `docs/kanban/done/`.

### When implementing (in `doing/`)

1. Tick tasks as you complete them: `- [x] Task 1`.
2. Add tasks if scope discovers new work; finish them before closing.
3. Append dated lines under **Build notes** when decisions or surprises matter for the record.

### When completing a story

1. Ensure all tasks are ticked and acceptance criteria are met.
2. Confirm tests pass (`npm test`, `./scripts/kestrel test`, `zig build test`, and any story-specific suites).
3. Move the story from `docs/kanban/doing/` to `docs/kanban/done/`.

---

## Key Files and Locations

- **Compiler entry**: `compiler/src/index.ts`
- **Parser**: `compiler/src/parser/parse.ts`
- **Type checker**: `compiler/src/typecheck/check.ts`
- **Code generator**: `compiler/src/codegen/codegen.ts`
- **Diagnostics**: `compiler/src/diagnostics/reporter.ts`
- **CLI**: `scripts/kestrel`
- **Specs**: `docs/specs/` (01-language, 09-tools, etc.)
- **Kestrel tests**: `tests/e2e/`, `tests/conformance/`
- **Kanban**: `docs/kanban/README.md` (phases and gates); skills `.cursor/skills/kestrel-kanban-story-create/`, `kestrel-kanban-story-migrate/`; subagents `.cursor/agents/kanban-*.md`

---

## Common Patterns

### Returning Diagnostics

```typescript
if (!tc.ok) {
  return { ok: false, diagnostics: tc.diagnostics };
}
return { ok: true, ast };
```

### Adding a New Compiler Pass

1. Add the pass in `compiler/src/<module>/`
2. Export from `compiler/src/<module>/index.ts`
3. Import and use in `compiler/src/index.ts`
4. Add tests in `compiler/test/`

### Running a Specific Test

```bash
cd compiler
npm test -- --run test/unit/lexer.test.ts
```
