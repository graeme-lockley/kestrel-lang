#!/usr/bin/env bash
# E2E tests: negative and positive scenarios.
# Negative (tests/e2e/scenarios/negative/*.ks): must fail (compile or runtime).
# Positive (tests/e2e/scenarios/positive/*.ks): must compile, run with exit 0, stdout matches *.expected.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="$ROOT/compiler"
VM="$ROOT/vm"
NEGATIVE="$ROOT/tests/e2e/scenarios/negative"
POSITIVE="$ROOT/tests/e2e/scenarios/positive"

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

# Positive tests: compile, run (exit 0), stdout must match .expected
pos_count=0
if [ -d "$POSITIVE" ]; then
  for f in "$POSITIVE"/*.ks; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .ks)
    expected="$POSITIVE/$name.expected"
    if [ ! -f "$expected" ]; then
      echo "E2E positive: $name.ks has no $name.expected" >&2
      exit 1
    fi
    out_dir="$ROOT/out/e2e"
    stdout_file="$out_dir/positive_${name}.stdout"
    stderr_file="$out_dir/positive_${name}.stderr"
    mkdir -p "$out_dir"
    if ! (cd "$ROOT" && ./scripts/kestrel run "$f" >"$stdout_file" 2>"$stderr_file"); then
      echo "E2E positive $name: compile or run failed" >&2
      cat "$stderr_file" >&2
      exit 1
    fi
    if ! diff -q "$expected" "$stdout_file" >/dev/null 2>&1; then
      echo "E2E positive $name: stdout does not match $name.expected" >&2
      diff "$expected" "$stdout_file" >&2 || true
      exit 1
    fi
    pos_count=$((pos_count + 1))
    echo "  $name.ks OK (stdout matches .expected)"
  done
fi
if [ "$pos_count" -gt 0 ]; then
  echo "E2E positive: $pos_count scenario(s) passed."
fi
