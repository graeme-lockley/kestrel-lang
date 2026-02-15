# Import resolution and multi-module compilation

## Description

The compiler emits import specifiers in the bytecode import table but does **not** resolve them to source files or compiled modules. Specifiers like `kestrel:string` or `./other.ks` are not resolved; the compiler compiles a single source file only.

Per spec 07 and IMPLEMENTATION_PLAN Phase 3.4: resolve stdlib (`kestrel:string`, etc.) to stdlib source path; resolve path imports to .ks files; compile dependencies; support multi-file scenarios.

## Acceptance Criteria

- [x] Resolve `kestrel:string`, `kestrel:stack`, `kestrel:http`, `kestrel:json`, `kestrel:fs` to stdlib source (e.g. `stdlib/kestrel/string.ks`)
- [x] Resolve relative/absolute path imports to .ks files
- [x] Compile imported modules to .kbc (or use pre-compiled)
- [x] Emit correct import table with resolved specifiers
- [x] E2E: two-module program (user imports from local .ks) compiles and runs

## Tasks

- [x] Add import resolution (stdlib + path) module
- [x] Implement multi-module compile with dependency bundling
- [x] Integrate resolution into compiler/CLI pipeline
- [x] Add typecheck/codegen support for imported names
- [x] Add E2E two-module scenario
