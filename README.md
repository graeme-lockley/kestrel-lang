# Kestrel

A statically typed, scripting and server-oriented programming language with Hindley–Milner type inference, structural records, algebraic data types, and async/await. Kestrel compiles to bytecode (`.kbc`) and runs on a stack-based VM.

**Current Status:** Core language features are implemented and working. The compiler (TypeScript) and VM (Zig) are functional with 22 end-to-end tests passing.

---

## Quick Start

### Build

```bash
# Build the compiler
cd compiler
npm install
npm run build

# Build the VM
cd ../vm
zig build

# Run tests
cd ..
./scripts/run-e2e.sh
```

### Hello World

Create `hello.ks`:
```kestrel
fun fibonacci(n: Int): Int =
  if (n <= 1) n else fibonacci(n - 1) + fibonacci(n - 2)

val result = fibonacci(10)
val _ = print(result)
```

Compile and run:
```bash
node compiler/dist/cli.js hello.ks -o hello.kbc
./vm/zig-out/bin/kestrel hello.kbc
# Output: 55
```

---

## Language Features

### ✅ Implemented

- **Type inference** — Hindley–Milner type system with let-polymorphism
- **Functions** — First-class functions, recursion, higher-order functions
- **Algebraic data types** — Lists with pattern matching
- **Records and tuples** — Structural records with named fields
- **Control flow** — if-else, match expressions with exhaustiveness checking
- **Exceptions** — try-catch-throw with proper unwinding
- **Arithmetic** — Integer operations: +, -, *, /, %, **
- **Comparisons** — ==, !=, <, <=, >, >=
- **Boolean logic** — Short-circuit && and ||
- **Garbage collection** — Mark-sweep GC with automatic collection
- **Async infrastructure** — TASK objects and AWAIT instruction
- **I/O** — `print()` builtin for stdout

### 🚧 In Progress

- **Row polymorphism** — Advanced record type features
- **Module system** — Import/export (infrastructure ready)
- **Standard library** — Additional primitives needed
- **String interpolation** — Parser support needed

---

## Examples

### Recursion
```kestrel
fun factorial(n: Int): Int =
  if (n == 0) 1 else n * factorial(n - 1)

val result = factorial(5)
val _ = print(result)  // 120
```

### Lists
```kestrel
val numbers = [1, 2, 3, 4, 5]
val empty = []
val cons = 42 :: numbers
```

### Pattern Matching
```kestrel
fun check(b: Bool): Int = match (b) {
  _ => 42
}
```

### Records
```kestrel
val person = { name: "Alice", age: 30 }
val name = person.name
val age = person.age
```

More examples in `tests/e2e/scenarios/`

---

## Implementation Status

### Compiler (TypeScript)
- ✅ **Lexer** — Full lexical analysis
- ✅ **Parser** — AST generation for all expression forms
- ✅ **Type checker** — Hindley-Milner inference with unification
  - ✅ Let-polymorphism with generalization/instantiation
  - ✅ Match exhaustiveness checking
  - ✅ Async context validation
  - ⏳ Row polymorphism (planned)
- ✅ **Code generator** — Complete bytecode emission
  - ✅ Functions, locals, arithmetic, control flow
  - ✅ Records, ADTs, pattern matching
  - ✅ Exception handling (try-catch-throw)
  - ✅ Async/await infrastructure
- ⏳ **Module resolution** (planned)

### VM (Zig)
- ✅ **Bytecode loader** — .kbc file parsing
- ✅ **Execution engine** — Stack-based interpreter
  - ✅ All core instructions (32 opcodes)
  - ✅ Function calls with proper frame management
  - ✅ Pattern matching with jump tables
- ✅ **Memory management**
  - ✅ Tagged 64-bit values (3-bit tag + 61-bit payload)
  - ✅ Heap allocation for records, ADTs, tasks
  - ✅ Mark-sweep garbage collector
- ✅ **Exception handling** — Stack unwinding with handlers
- ✅ **Async support** — TASK objects, AWAIT instruction
- ✅ **Primitives** — `print()` for stdout

### Test Coverage
- ✅ **22 E2E tests** — Full compile-and-run scenarios
- ✅ **29 Compiler tests** — Unit and integration tests
- ✅ **25 Conformance tests** — Type checker validation

---

## Architecture

```
kestrel/
├── compiler/          # TypeScript compiler
│   ├── src/
│   │   ├── lexer/    # Tokenization
│   │   ├── parser/   # AST generation
│   │   ├── typecheck/# Type inference
│   │   ├── codegen/  # Bytecode emission
│   │   └── bytecode/ # .kbc format
│   └── test/         # Unit & integration tests
├── vm/               # Zig virtual machine
│   ├── src/
│   │   ├── main.zig  # Entry point
│   │   ├── load.zig  # Bytecode loader
│   │   ├── exec.zig  # Interpreter loop
│   │   ├── value.zig # Tagged values
│   │   ├── gc.zig    # Garbage collector
│   │   └── primitives.zig # VM primitives
│   └── test/         # VM tests
├── tests/            # Cross-cutting tests
│   ├── e2e/         # End-to-end scenarios
│   └── conformance/ # Type system tests
├── docs/            # Specifications
└── scripts/         # Build & test scripts
```

---

## Roadmap

### Phase 1: Core Language ✅
- [x] Lexer and parser
- [x] Type inference (Hindley-Milner)
- [x] Code generation
- [x] VM with GC and exceptions
- [x] Basic primitives

### Phase 2: Advanced Features 🚧
- [ ] Row polymorphism for records
- [ ] Module system (import/export)
- [ ] String operations
- [ ] More pattern matching features

### Phase 3: Standard Library 📋
- [ ] kestrel:string
- [ ] kestrel:stack
- [ ] kestrel:json
- [ ] kestrel:fs
- [ ] kestrel:http

### Phase 4: Tooling 📋
- [ ] Better error messages
- [ ] Debugger support
- [ ] Language server protocol
- [ ] Package manager

---

## Documentation

### Specifications

Comprehensive language specifications are in `docs/`:

- **`Kestrel_v1_Language_Specification.md`** — Complete language reference
- **`IMPLEMENTATION_PLAN.md`** — Implementation strategy and progress

The specifications define:
- Language syntax and semantics
- Type system rules
- Bytecode format (.kbc)
- Instruction set architecture
- Runtime value model
- Standard library contracts

---

## Contributing

The core language implementation is functional. Contributions welcome for:

1. **Standard library primitives** — I/O, strings, JSON, HTTP
2. **Module system** — Import/export resolution
3. **Error messages** — Better diagnostics
4. **Examples** — More demonstration programs
5. **Documentation** — Tutorials and guides

See `IMPLEMENTATION_PLAN.md` for detailed status and next steps.

---

## License

See the repository for license information.
