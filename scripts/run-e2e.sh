#!/usr/bin/env bash
# E2E negative tests only: each tests/e2e/scenarios/negative/*.ks must fail (compile or runtime).
# For each file: try compile; if compile fails, pass. If compile succeeds, run and require exit != 0.
# Positive behaviour is covered by Kestrel unit tests (tests/unit/*.test.ks).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="$ROOT/compiler"
VM="$ROOT/vm"
NEGATIVE="$ROOT/tests/e2e/scenarios/negative"

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
  arg="$1"
  if [ -f "$arg" ]; then
    files=("$arg")
  elif [ -f "$NEGATIVE/$arg" ]; then
    files=("$NEGATIVE/$arg")
  elif [ -f "$NEGATIVE/${arg%.ks}.ks" ]; then
    files=("$NEGATIVE/${arg%.ks}.ks")
  else
    echo "run-e2e: file not found: $arg" >&2
    exit 1
  fi
else
  if [ -d "$NEGATIVE" ]; then
    files=("$NEGATIVE"/*.ks)
  else
    files=()
  fi
fi

for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  count=$((count + 1))
  name=$(basename "$f" .ks)
  out_dir="$ROOT/out/e2e"
  kbc="$out_dir/$name.kbc"
  mkdir -p "$out_dir"

  if ! node "$COMPILER/dist/cli.js" "$f" -o "$kbc" 2>/dev/null; then
    # Expected: compile failed
    echo "  $name.ks OK (compile failed as expected)"
    continue
  fi

  if [ ! -f "$kbc" ]; then
    echo "E2E $name: expected compile to fail" >&2
    exit 1
  fi

  out_stderr="$out_dir/$name.stderr"
  exit_code=0
  "$ROOT/vm/zig-out/bin/kestrel" "$kbc" 2>"$out_stderr" || exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    echo "  $name.ks OK (runtime exit $exit_code as expected)"
    if [ "$name" = "uncaught_exception" ]; then
      if ! grep -q "Uncaught exception" "$out_stderr" || ! grep -q " at " "$out_stderr"; then
        echo "E2E $name: expected stack trace with file:line in stderr" >&2
        echo "stderr was:" >&2
        cat "$out_stderr" >&2
        exit 1
      fi
    fi
  else
    echo "E2E $name: expected compile or runtime failure, but program succeeded" >&2
    exit 1
  fi
done

if [ "$count" -eq 0 ]; then
  echo "E2E: no negative scenarios (add .ks files to tests/e2e/scenarios/negative/)"
else
  echo "E2E negative: $count scenario(s) passed."
fi
