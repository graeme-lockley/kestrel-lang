# Agent Guidelines for Kestrel

**Generated:** 2026-03-07
**Commit:** 745543c
**Branch:** main

This file provides guidance for agentic coding agents working on the Kestrel project.

## Project Overview

Kestrel is a statically typed programming language with Hindley-Milner type inference. It consists of:
- **Compiler**: TypeScript in `compiler/`
- **JVM runtime**: Java in `runtime/jvm/`
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

### End-to-End Tests

Layout: `tests/e2e/scenarios/negative/*.ks` (must fail at compile or runtime with non-zero exit; see `tests/e2e/scenarios/negative/README.md`) and `tests/e2e/scenarios/positive/*.ks` (stdout compared to `*.expected`). `./scripts/test-all.sh` runs `./scripts/run-e2e.sh` after compiler tests.

```bash
# Run E2E tests (from project root)
./scripts/run-e2e.sh
```

### Using the Kestrel CLI

```bash
# Run a Kestrel script
./kestrel run <script.ks> [args...]

# Disassemble bytecode
./kestrel dis [--verbose|--code-only] <script.ks>

# Build compiler (optionally compile a script)
./kestrel build [script.ks]

# Run Kestrel test suite
./kestrel test [files...]
```

---

## Code Style Guidelines

### General

- **Language**: TypeScript for the compiler, Java for the JVM runtime
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
- **Conformance corpora** (`.ks` files under `tests/conformance/`): **parse** (`parse/` — `parse-conformance.test.ts`), **typecheck** (`typecheck/` — `typecheck-conformance.test.ts`), **runtime** (`runtime/valid/` — `runtime-conformance.test.ts`). All are run by **`cd compiler && npm test`**. See [tests/conformance/typecheck/README.md](tests/conformance/typecheck/README.md) (links to parse/runtime READMEs) for layout, `// EXPECT:` on invalid cases, and in-file `println` + `//` stdout goldens for runtime.
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

## Commit Messages

All commits must follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/):

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**Allowed types:** `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`, `perf`, `style`.

**Allowed scopes:** `parser`, `typecheck`, `codegen`, `jvm`, `stdlib`, `cli`, `vm`, `e2e`.

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
- [ ] Relevant specs updated (if applicable)

---

## Kanban Workflow (from Cursor rules)

Stories live in `docs/kanban/` with folders: **future**, **unplanned**, **planned**, **doing**, **done**.
Epics live in `docs/kanban/epics/` with folders: **unplanned** and **done**.

**`future/`** holds pre-roadmap **investigations and ideas** (`slug.md`, **no `S##-##-` prefix**). The **prioritized roadmap** is in **`docs/kanban/unplanned/`**, named **`S##-##-slug.md`** where the first number is the epic id and the second number is story order within that epic. See `docs/kanban/README.md` for the tier table, **future** lifecycle, entry/exit criteria, epic rules, and templates. Roadmap files are **moved** between **unplanned**, **planned**, **doing**, and **done** without renaming the `S##-##` id. **`docs/kanban/backlog/`** is **deprecated**; use **`planned/`** instead.

### Workflow

**Skills for each phase:**

| Phase transition | Skill |
|-----------------|-------|
| Create an epic | `epic-create` |
| Decompose epic into stories | `plan-epic` |
| Capture idea | `story-create` |
| `future/` → `unplanned/` | `story-create` + `kanban-story-migrate` |
| `unplanned/` → `planned/` | **`plan-story`** |
| `planned/` → `doing/` → `done/` | **`build-story`** |
| End-to-end (any phase → done) | **`build-story`** |

1. **future** (optional) — Capture investigations and ideas before they are roadmap items; promote to **unplanned** with a new **`S##-##-slug.md`** when scoped.
2. **unplanned** — High-level feature stories on the ordered roadmap (summary, state, relationships, **goals**, acceptance, spec refs, **risks / notes**).
3. **planned** — Scoped but not yet built: adds impact analysis, **Tasks**, tests to add, docs/specs to update, optional **Notes**. Use **`plan-story`** to produce this content.
4. **doing** — Active implementation; tick tasks; add **Build notes** as needed. Use **`build-story`** to execute.
5. **done** — All tasks ticked, acceptance satisfied, and **required tests passing**.
6. **epics** — Each roadmap story links to one epic in `docs/kanban/epics/unplanned/`; move epic to `docs/kanban/epics/done/` when all member stories are done.

### When promoting a story

- **future → unplanned** — Choose epic id + next story index, rename to **`S##-##-slug.md`**, move to `docs/kanban/unplanned/`, add full unplanned sections per `docs/kanban/README.md`.
- **unplanned → planned** — Use the **`plan-story`** skill: it explores the codebase and specs, adds impact analysis, Tasks, Tests to add, and Docs to update, then moves the file to `docs/kanban/planned/`.
- **planned → doing → done** — Use the **`build-story`** skill: it confirms the plan, implements all tasks, records build notes, verifies tests, and moves the file to `docs/kanban/done/`.
- **epic unplanned → done** — When all member stories are in `docs/kanban/done/`, move epic file from `docs/kanban/epics/unplanned/` to `docs/kanban/epics/done/`.

### When implementing (in `doing/`)

Use the **`build-story`** skill to execute planned work. Key steps:

1. Tick tasks as you complete them: `- [x] Task 1`.
2. Add tasks if scope discovers new work; finish them before closing.
3. Append dated lines under **Build notes** when decisions or surprises matter for the record.

### When completing a story

1. Ensure all tasks are ticked and acceptance criteria are met.
2. Confirm tests pass (`npm test`, `./scripts/kestrel test`, and any story-specific suites).
3. Move the story from `docs/kanban/doing/` to `docs/kanban/done/`.

---

## Key Files and Locations

- **Compiler entry**: `compiler/src/index.ts`
- **Parser**: `compiler/src/parser/parse.ts`
- **Type checker**: `compiler/src/typecheck/check.ts`
- **Code generator**: `compiler/src/jvm-codegen/codegen.ts`
- **Diagnostics**: `compiler/src/diagnostics/reporter.ts`
- **CLI**: `scripts/kestrel`
- **Specs**: `docs/specs/` (01-language, 09-tools, etc.)
- **Kestrel tests**: `tests/e2e/`, `tests/conformance/`
- **Kanban**: `docs/kanban/README.md` (phases and gates); skills `.github/skills/epic-create/`, `story-create/`, `plan-epic/`, `kanban-story-migrate/`, `plan-story/`, `build-story/`; subagents `.cursor/agents/kanban-*.md`

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
