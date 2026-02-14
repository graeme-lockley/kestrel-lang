#!/usr/bin/env bash
# For each tests/e2e/scenarios/*.ks: compile to .kbc, run VM, diff stdout/stderr/exit to tests/e2e/expected/.
# No-op if no scenarios exist. Exit non-zero on first failure.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="$ROOT/compiler"
VM="$ROOT/vm"
SCENARIOS="$ROOT/tests/e2e/scenarios"
EXPECTED="$ROOT/tests/e2e/expected"

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
    if [ -f "$EXPECTED/$name.stdout" ]; then
      diff -u "$EXPECTED/$name.stdout" "$out_stdout" || { echo "E2E $name: stdout mismatch" >&2; exit 1; }
    fi
    if [ -f "$EXPECTED/$name.stderr" ]; then
      diff -u "$EXPECTED/$name.stderr" "$out_stderr" || { echo "E2E $name: stderr mismatch" >&2; exit 1; }
    fi
    if [ -f "$EXPECTED/$name.exit" ]; then
      diff -u "$EXPECTED/$name.exit" "$ROOT/out/e2e/$name.exit" || { echo "E2E $name: exit code mismatch" >&2; exit 1; }
    fi
  fi
  echo "  $name.ks OK"
done

if [ "$count" -eq 0 ]; then
  echo "E2E: no scenarios (add .ks files to tests/e2e/scenarios/)"
else
  echo "E2E: $count scenario(s) passed."
fi
