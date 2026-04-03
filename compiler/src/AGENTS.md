# Compiler Source Modules

**Parent:** `/AGENTS.md`

## Structure

```
compiler/src/
├── index.ts          # Entry point, orchestrates passes
├── bundle.ts         # Bundles multiple source files
├── resolve.ts        # Module resolution
├── compile-file-jvm.ts # Multi-module JVM compilation
├── lexer/            # Tokenization
├── parser/           # AST generation
├── typecheck/        # Hindley-Milner type inference
├── jvm-codegen/      # JVM .class generation
├── types/            # Type system primitives
├── ast/              # AST node definitions
└── diagnostics/      # Error reporting
```

## Pass Order

1. **Lex** → Token stream
2. **Parse** → AST
3. **Typecheck** → Annotated AST + diagnostics
4. **JVM Codegen** → `.class` bytes

## Module Responsibilities

| Module | Purpose |
|--------|---------|
| `index.ts` | Pipeline: lex → parse → typecheck → codegen |
| `lexer/` | `tokenize(source): Token[]` |
| `parser/` | `parse(tokens): Program` |
| `typecheck/` | `typecheck(ast): { ok, type, diagnostics }` |
| `jvm-codegen/` | `jvmCodegen(ast): JvmCodegenResult` |
| `types/` | TypeExpr, TypeVar, unify, generalize |
| `ast/` | Node types (Program, Expr, Decl, etc.) |
| `diagnostics/` | Diagnostic, SourceLocation, reporter |

## Key Exports

```typescript
// compiler/src/index.ts
export function compile(source: string, opts?: CompileOptions): 
  { ok: true; ast: Program } | { ok: false; diagnostics: Diagnostic[] }
```

## Conventions

- Result types: `{ ok: true; ... } | { ok: false; ... }`
- Each module has `index.ts` barrel export
- Import paths: `./lexer/index.js` (explicit .js)
- Root-level files: compilation orchestration

## Notes

- 28 TypeScript files total
- Each pass is independent, testable in isolation
- Type errors flow through `diagnostics` module
