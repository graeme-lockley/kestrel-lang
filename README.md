# Kestrel

A statically typed, scripting and server-oriented programming language with Hindley–Milner type inference, structural records, algebraic data types, and async/await. Kestrel compiles to bytecode (`.kbc`) and runs on a stack-based VM.

---

## The language

Kestrel is designed for predictable semantics, mechanical simplicity, and strong static typing. It is a good fit for scripts, servers, and tooling where clarity and type safety matter.

**Highlights:**

- **Type inference** — Hindley–Milner with row polymorphism for records
- **Structural records** — Named fields, row extension (`{ ...r, x = v }`), optional `mut` fields
- **Algebraic data types** — Sum types, pattern matching, exhaustiveness checking
- **Union and intersection types** — `A | B`, `A & B`, with `is` narrowing
- **Exceptions** — Declare, throw, and catch with pattern matching; stack traces via stdlib
- **Async/await** — `Task<T>`, `async fun`, `await`; non-blocking, event-loop-friendly
- **Pipeline** — `x |> f` means `f(x)`; `x |> f(y)` means `f(x, y)`
- **No member calls** — No `x.f(y)`; use `f(x)` and `x.field` instead

Source files use the `.ks` extension. One file is one module; modules import and export via a deterministic resolution system (paths, URLs, and standard library names like `kestrel:string`).

**Example (conceptual):**

```text
import { length } from "kestrel:string"
import { print } from "kestrel:stack"

fun greet(name: String): String = "Hello, ${name}!"

val msg = greet("Kestrel")
print(msg)
```

---

## Implementation

The specification targets a split implementation:

| Component | Technology | Role |
|-----------|------------|------|
| **Compiler** | TypeScript | Parsing, type checking, and emission of `.kbc` bytecode |
| **VM** | Zig | Load and execute `.kbc`; stack-based interpreter, GC, async runtime |

The compiler and VM are specified so that any conforming implementation can produce and consume the same bytecode. This repository may contain or reference the reference compiler and VM; see the project layout and build instructions in the repo for current status.

---

## Specifications

The behaviour of the language, bytecode, and runtime is defined in a set of spec documents under **`docs/specs/`**. They are intended to be enough for an independent implementor.

| Spec | Description |
|------|--------------|
| [01 – Core Language](docs/specs/01-language.md) | Lexical structure, grammar (EBNF), expressions, blocks, types, exceptions, async. Defines syntax and surface semantics. |
| [02 – Standard Library](docs/specs/02-stdlib.md) | Contract for stdlib modules: `kestrel:string`, `kestrel:stack`, `kestrel:http`, `kestrel:json`, `kestrel:fs`. Library types: Option, Result, List, Value. |
| [03 – Bytecode Format](docs/specs/03-bytecode-format.md) | `.kbc` file layout: header, string table, constant pool, function/type table, code section, debug section, shape table, ADT table. Endianness and alignment. |
| [04 – Bytecode ISA](docs/specs/04-bytecode-isa.md) | Instruction set: opcodes, operands, MATCH layout. Stack-based execution, calling convention, mapping from language constructs. |
| [05 – Runtime Model](docs/specs/05-runtime-model.md) | Tagged values (64-bit, 3-bit tag), heap object kinds (FLOAT, STRING, RECORD, ADT, TASK, …), GC, exceptions, async runtime. |
| [06 – Type System](docs/specs/06-typesystem.md) | Type grammar, row polymorphism, Hindley–Milner inference, unification, match exhaustiveness, async/catch typing. |
| [07 – Module System](docs/specs/07-modules.md) | Imports and exports, module specifiers, resolution (stdlib, URL, path), export set, lockfile, bytecode import table. |
| [08 – Tests](docs/specs/08-tests.md) | Conformance scope, test categories (parser, type checker, bytecode, runtime, modules, stdlib), golden tests, CI. |

**Reading order** for implementors: **01** (language) and **06** (types) for the front end; **03** and **04** for the bytecode and VM; **05** for the runtime model; **02** and **07** for stdlib and modules; **08** for validation.

There is also a single-document language overview at the repo root: **`Kestrel_v1_Language_Specification.md`** (may overlap with or predate the split specs).

---

## License and status

See the repository for license and current implementation status. The specs in `docs/specs/` are version 1.0 and are stable for implementors.
