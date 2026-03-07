# VM Source

**Parent:** `/AGENTS.md`

## Structure

```
vm/src/
├── main.zig        # Entry point, CLI
├── exec.zig        # Interpreter loop (41KB - core)
├── load.zig        # .kbc bytecode loader
├── gc.zig          # Mark-sweep garbage collector
├── value.zig       # Tagged value representation
└── primitives.zig  # Built-in functions (print, etc.)
```

## Execution Flow

1. `main.zig` → Parse args, load .kbc
2. `load.zig` → Deserialize bytecode → `LoadedProgram`
3. `exec.zig` → Run interpreter loop → Execute instructions

## Component Responsibilities

| File | Purpose |
|------|---------|
| `main.zig` | CLI entry, argument parsing |
| `exec.zig` | Virtual machine, instruction dispatch |
| `load.zig` | Bytecode parsing, validation |
| `gc.zig` | Mark-sweep GC with root tracking |
| `value.zig` | 64-bit tagged values (3-bit tag + payload) |
| `primitives.zig` | Built-in functions (print, etc.) |

## Bytecode Format

`.kbc` files contain:
- Magic number + version
- Function count + functions
- Each function: locals, upvalues, instructions

## Build

```bash
zig build          # Debug build
zig build -Doptimize=ReleaseSafe  # Optimized
zig test           # Run VM tests
```

## Notes

- 6 Zig source files
- `exec.zig` is the core (~41KB)
- Uses tagged 64-bit values (3-bit tag for type discrimination)
- Mark-sweep GC with stack root scanning
