# Import resolution and multi-module compilation

## Description

The compiler emits import specifiers in the bytecode import table but does **not** resolve them to source files or compiled modules. Specifiers like `kestrel:string` or `./other.ks` are not resolved; the compiler compiles a single source file only.

Per spec 07 and IMPLEMENTATION_PLAN Phase 3.4: resolve stdlib (`kestrel:string`, etc.) to stdlib source path; resolve path imports to .ks files; compile dependencies; support multi-file scenarios.

## Acceptance Criteria

- [ ] Resolve `kestrel:string`, `kestrel:stack`, `kestrel:http`, `kestrel:json`, `kestrel:fs` to stdlib source (e.g. `stdlib/kestrel/string.ks`)
- [ ] Resolve relative/absolute path imports to .ks files
- [ ] Compile imported modules to .kbc (or use pre-compiled)
- [ ] Emit correct import table with resolved specifiers
- [ ] E2E: two-module program (user imports from local .ks) compiles and runs
