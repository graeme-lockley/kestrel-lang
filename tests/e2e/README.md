# E2E scenarios

Each `.ks` file in `scenarios/` is compiled, run on the VM, and its stdout is checked.

## Expected output in the scenario file

Put the expected value **below each `print(...)`** as a comment:

- Use `// <value>` for the line(s) that should match the output of that print.
- For multi-line output (e.g. a string with `\n`), use one `//` line per output line.
- A bare `//` means one blank line of output.

Example:

```ks
print(42)
// 42
print("Hello\nWorld")
// Hello
// World
print("")
//
```

When the test runs, the runner collects all such comment lines (in order, with the `// ` prefix removed) and compares them to the actual stdout. This keeps the test and its expected output in one file. E2E tests use only this comment mechanism; there is no separate `expected/` directory.
