#!/usr/bin/env bash
# For each tests/e2e/scenarios/*.ks and tests/conformance/runtime/valid/*.ks: compile to .kbc,
# run VM, then validate stdout. Expected stdout is taken from the scenario file: each line
# that starts with "// " (or "//") immediately after a print(...) is the expected output.
# No-op if no scenarios exist. Exit non-zero on first failure.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="$ROOT/compiler"
VM="$ROOT/vm"
SCENARIOS="$ROOT/tests/e2e/scenarios"
RUNTIME_CONFORMANCE="$ROOT/tests/conformance/runtime/valid"

if ! command -v node &>/dev/null; then
  echo "run-e2e: node not found" >&2
  exit 1
fi
if ! command -v zig &>/dev/null; then
  echo "run-e2e: zig not found" >&2
  exit 1
fi

# Build compiler and VM once
cd "$COMPILER" && npm run build >/dev/null 2>&1 && cd "$ROOT" || { echo "Compiler build failed" >&2; exit 1; }
cd "$VM" && zig build -Doptimize=ReleaseSafe >/dev/null 2>&1 && cd "$ROOT" || { echo "VM build failed" >&2; exit 1; }

count=0
if [ -n "${1:-}" ]; then
  # Run single file: accept "logical_not", "logical_not.ks", or path (e2e or runtime conformance)
  arg="$1"
  if [ -f "$arg" ]; then
    files=("$arg")
  elif [ -f "$SCENARIOS/$arg" ]; then
    files=("$SCENARIOS/$arg")
  elif [ -f "$SCENARIOS/${arg%.ks}.ks" ]; then
    files=("$SCENARIOS/${arg%.ks}.ks")
  elif [ -f "$RUNTIME_CONFORMANCE/$arg" ]; then
    files=("$RUNTIME_CONFORMANCE/$arg")
  elif [ -f "$RUNTIME_CONFORMANCE/${arg%.ks}.ks" ]; then
    files=("$RUNTIME_CONFORMANCE/${arg%.ks}.ks")
  else
    echo "run-e2e: file not found: $arg" >&2
    exit 1
  fi
else
  files=("$SCENARIOS"/*.ks "$RUNTIME_CONFORMANCE"/*.ks)
fi

for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  count=$((count + 1))
  name=$(basename "$f" .ks)
  if [[ "$f" == "$RUNTIME_CONFORMANCE"/* ]]; then
    out_dir="$ROOT/out/runtime-conformance"
    suite="runtime conformance"
  else
    out_dir="$ROOT/out/e2e"
    suite="E2E"
  fi
  kbc="$out_dir/$name.kbc"
  mkdir -p "$out_dir"
  if ! node "$COMPILER/dist/cli.js" "$f" -o "$kbc" 2>/dev/null; then
    echo "$suite: compile failed for $name" >&2
    exit 1
  fi
  if [ -f "$kbc" ]; then
    out_stdout="$out_dir/$name.stdout"
    out_stderr="$out_dir/$name.stderr"
    "$ROOT/vm/zig-out/bin/kestrel" "$kbc" >"$out_stdout" 2>"$out_stderr" || true
    echo "$?" >"$out_dir/$name.exit"
    # Expected stdout from // comments in .ks (below each print)
    expected_stdout=""
    if grep -q 'print(' "$f" && awk '
      /print\(/ { in_expected=1; next }
      in_expected && /^[[:space:]]*\/\/[[:space:]]*/ {
        sub(/^[[:space:]]*\/\/ ?/, ""); print; next
      }
      { in_expected=0 }
    ' "$f" | grep -q .; then
      expected_stdout=$(awk '
        /print\(/ { in_expected=1; next }
        in_expected && /^[[:space:]]*\/\/[[:space:]]*/ {
          sub(/^[[:space:]]*\/\/ ?/, ""); print; next
        }
        { in_expected=0 }
      ' "$f")
    fi
    if [ -n "$expected_stdout" ]; then
      tmp_expected=$(mktemp)
      printf '%s\n' "$expected_stdout" >"$tmp_expected"
      diff -u "$tmp_expected" "$out_stdout" || { rm -f "$tmp_expected"; echo "$suite $name: stdout mismatch" >&2; exit 1; }
      rm -f "$tmp_expected"
    fi
  fi
  echo "  $name.ks OK"
done

if [ "$count" -eq 0 ]; then
  echo "E2E: no scenarios (add .ks files to tests/e2e/scenarios/ or tests/conformance/runtime/valid/)"
else
  echo "E2E + runtime conformance: $count scenario(s) passed."
fi
