# Compiler Source Modules

**Parent:** `/AGENTS.md`

## Structure

```
compiler/src/
├── index.ts          # Entry point, orchestrates passes
├── bundle.ts         # Bundles multiple source files
├── resolve.ts        # Module resolution
├── types-file.ts     # Type inference for files
├── compile-file.ts   # Single file compilation
├── lexer/            # Tokenization
├── parser/           # AST generation
├── typecheck/        # Hindley-Milner type inference
├── codegen/          # Bytecode emission
├── bytecode/         # .kbc format definitions
├── types/            # Type system primitives
├── ast/              # AST node definitions
└── diagnostics/      # Error reporting
```

## Pass Order

1. **Lex** → Token stream
2. **Parse** → AST
3. **Typecheck** → Annotated AST + diagnostics
4. **Codegen** → Bytecode

## Module Responsibilities

| Module | Purpose |
|--------|---------|
| `index.ts` | Pipeline: lex → parse → typecheck → codegen |
| `lexer/` | `tokenize(source): Token[]` |
| `parser/` | `parse(tokens): Program` |
| `typecheck/` | `typecheck(ast): { ok, type, diagnostics }` |
| `codegen/` | `codegen(ast): BytecodeFunction[]` |
| `bytecode/` | Instruction set, .kbc serialization |
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
