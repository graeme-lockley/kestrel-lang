#!/usr/bin/env bash
# For each tests/e2e/scenarios/*.ks: compile to .kbc, run VM, then validate stdout.
# Expected stdout is taken from the scenario file: each line that starts with "// "
# (or "//") immediately after a print(...) is the expected output for that print.
# Multiple consecutive "//" lines after one print are allowed (multi-line output).
# No-op if no scenarios exist. Exit non-zero on first failure.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="$ROOT/compiler"
VM="$ROOT/vm"
SCENARIOS="$ROOT/tests/e2e/scenarios"

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
for f in "$SCENARIOS"/*.ks; do
  [ -f "$f" ] || continue
  count=$((count + 1))
  name=$(basename "$f" .ks)
  kbc="$ROOT/out/e2e/$name.kbc"
  mkdir -p "$(dirname "$kbc")"
  if ! node "$COMPILER/dist/cli.js" "$f" -o "$kbc" 2>/dev/null; then
    echo "E2E: compile failed for $name" >&2
    exit 1
  fi
  if [ -f "$kbc" ]; then
    out_stdout="$ROOT/out/e2e/$name.stdout"
    out_stderr="$ROOT/out/e2e/$name.stderr"
    "$ROOT/vm/zig-out/bin/kestrel" "$kbc" >"$out_stdout" 2>"$out_stderr" || true
    echo "$?" >"$ROOT/out/e2e/$name.exit"
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
      diff -u "$tmp_expected" "$out_stdout" || { rm -f "$tmp_expected"; echo "E2E $name: stdout mismatch" >&2; exit 1; }
      rm -f "$tmp_expected"
    fi
  fi
  echo "  $name.ks OK"
done

if [ "$count" -eq 0 ]; then
  echo "E2E: no scenarios (add .ks files to tests/e2e/scenarios/)"
else
  echo "E2E: $count scenario(s) passed."
fi
