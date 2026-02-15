# VM: Module loading and cross-module linking

## Description

The VM loads a single .kbc file and runs it. It does not load imported modules (e.g. stdlib .kbc) or resolve cross-module CALL targets. Programs that `import { length } from "kestrel:string"` will fail at runtime when calling `length`.

Per IMPLEMENTATION_PLAN Phase 5.8: when loading a module that imports `kestrel:string`, resolve to stdlib .kbc, load it, and link CALL targets.

## Acceptance Criteria

- [ ] VM resolves stdlib specifiers (`kestrel:string`, etc.) to stdlib .kbc path
- [ ] Load imported modules recursively (or from known stdlib path)
- [ ] Link CALL targets: function table index → actual code address across modules
- [ ] E2E: user program that imports and calls stdlib function runs correctly
