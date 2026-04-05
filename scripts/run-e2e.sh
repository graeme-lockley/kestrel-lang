#!/usr/bin/env bash
# E2E tests: negative and positive scenarios.
# Negative (tests/e2e/scenarios/negative/*.ks): must fail (compile or runtime).
# Positive (tests/e2e/scenarios/positive/*.ks): must compile, run with exit 0, stdout matches *.expected.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="$ROOT/compiler"
NEGATIVE="$ROOT/tests/e2e/scenarios/negative"
POSITIVE="$ROOT/tests/e2e/scenarios/positive"

if ! command -v node &>/dev/null; then
  echo "run-e2e: node not found" >&2
  exit 1
fi
if ! command -v java &>/dev/null; then
  echo "run-e2e: java not found" >&2
  exit 1
fi
if ! command -v javac &>/dev/null; then
  echo "run-e2e: javac not found" >&2
  exit 1
fi

# Build compiler and JVM runtime once
cd "$COMPILER" && npm run build >/dev/null 2>&1 && cd "$ROOT" || { echo "Compiler build failed" >&2; exit 1; }
(cd "$ROOT/runtime/jvm" && ./build.sh >/dev/null 2>&1) || { echo "JVM runtime build failed" >&2; exit 1; }

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
  mkdir -p "$out_dir"

  expect_stack_stderr=false
  if grep -qE '^//.*E2E_EXPECT_STACK_TRACE' "$f"; then
    expect_stack_stderr=true
  fi

  out_stderr="$out_dir/$name.stderr"
  out_stdout="$out_dir/$name.stdout"
  exit_code=0
  "$ROOT/scripts/kestrel" run "$f" >"$out_stdout" 2>"$out_stderr" || exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    echo "  $name.ks OK (non-zero exit $exit_code as expected)"
    if [ "$expect_stack_stderr" = true ]; then
      if grep -q "kestrel: JVM compile failed for" "$out_stderr"; then
        # Negative scenarios are satisfied by compile-time or runtime failure.
        continue
      fi
      ok_st=0
      if grep -q "Uncaught exception" "$out_stderr" && grep -Eq '^[[:space:]]+at | at ' "$out_stderr"; then
        ok_st=1
      elif grep -q "Operand stack overflow" "$out_stderr" && grep -Eq '^[[:space:]]+at | at ' "$out_stderr"; then
        ok_st=1
      elif grep -q "stack overflow (exceeded" "$out_stderr"; then
        ok_st=1
      elif grep -q "VerifyError" "$out_stderr"; then
        ok_st=1
      fi
      if [ "$ok_st" -ne 1 ]; then
        echo "E2E negative $name: expected stderr diagnostic (uncaught/stack trace or frame limit) per E2E_EXPECT_STACK_TRACE" >&2
        echo "stderr was:" >&2
        cat "$out_stderr" >&2
        exit 1
      fi
    fi
  else
    echo "E2E negative $name: expected compile or runtime failure, but program succeeded" >&2
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
pos_skipped=0
if [ -d "$POSITIVE" ]; then
  for f in "$POSITIVE"/*.ks; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .ks)

    # Skip network-dependent tests if KESTREL_MAVEN_OFFLINE=1
    if [ "${KESTREL_MAVEN_OFFLINE:-}" = "1" ] && grep -q '// E2E_REQUIRE_NETWORK' "$f"; then
      echo "  $name.ks SKIPPED (KESTREL_MAVEN_OFFLINE=1)"
      pos_skipped=$((pos_skipped + 1))
      continue
    fi
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
if [ "$pos_skipped" -gt 0 ]; then
  echo "E2E positive: $pos_skipped scenario(s) skipped (KESTREL_MAVEN_OFFLINE=1)."
fi

# CLI flag smoke checks for S01-05 process exit modes.
sample_run="$POSITIVE/async-await-virtual-threads.ks"
sample_expected="$POSITIVE/async-await-virtual-threads.expected"
if [ -f "$sample_run" ] && [ -f "$sample_expected" ]; then
  out_dir="$ROOT/out/e2e"
  mkdir -p "$out_dir"

  default_stdout="$out_dir/cli_exit_wait_default.stdout"
  wait_stdout="$out_dir/cli_exit_wait_explicit.stdout"
  nowait_stdout="$out_dir/cli_exit_nowait.stdout"
  nowait_stderr="$out_dir/cli_exit_nowait.stderr"
  nowait_probe="$out_dir/cli_exit_nowait_probe.ks"
  conflict_stderr="$out_dir/cli_exit_wait_conflict.stderr"
  help_stdout="$out_dir/cli_exit_help.stdout"

  if ! (cd "$ROOT" && ./scripts/kestrel run "$sample_run" >"$default_stdout" 2>/dev/null); then
    echo "E2E CLI: default run failed for exit-wait smoke check" >&2
    exit 1
  fi
  if ! diff -q "$sample_expected" "$default_stdout" >/dev/null 2>&1; then
    echo "E2E CLI: default run output mismatch for exit-wait smoke check" >&2
    diff "$sample_expected" "$default_stdout" >&2 || true
    exit 1
  fi

  if ! (cd "$ROOT" && ./scripts/kestrel run --exit-wait "$sample_run" >"$wait_stdout" 2>/dev/null); then
    echo "E2E CLI: --exit-wait run failed" >&2
    exit 1
  fi
  if ! diff -q "$sample_expected" "$wait_stdout" >/dev/null 2>&1; then
    echo "E2E CLI: --exit-wait output mismatch" >&2
    diff "$sample_expected" "$wait_stdout" >&2 || true
    exit 1
  fi

  if (cd "$ROOT" && ./scripts/kestrel run --exit-wait --exit-no-wait "$sample_run" >/dev/null 2>"$conflict_stderr"); then
    echo "E2E CLI: expected conflicting exit flags to fail" >&2
    exit 1
  fi
  if ! grep -q "mutually exclusive" "$conflict_stderr"; then
    echo "E2E CLI: conflicting exit flags did not print expected error" >&2
    cat "$conflict_stderr" >&2
    exit 1
  fi

  cat >"$nowait_probe" <<'EOF'
import * as Process from "kestrel:sys/process"

async fun linger(): Task<Unit> = {
  val _ = await Process.runProcess("sh", ["-c", "sleep 2"]);
  println("late");
  ()
}

linger()
println("main")
EOF

  if ! (cd "$ROOT" && ./scripts/kestrel run --exit-no-wait "$nowait_probe" >"$nowait_stdout" 2>"$nowait_stderr"); then
    echo "E2E CLI: --exit-no-wait run failed" >&2
    cat "$nowait_stderr" >&2
    exit 1
  fi
  if ! grep -q "^main$" "$nowait_stdout"; then
    echo "E2E CLI: --exit-no-wait did not print main marker" >&2
    cat "$nowait_stdout" >&2
    exit 1
  fi
  if grep -q "^late$" "$nowait_stdout"; then
    echo "E2E CLI: --exit-no-wait unexpectedly waited for async completion" >&2
    cat "$nowait_stdout" >&2
    exit 1
  fi

  if ! (cd "$ROOT" && ./scripts/kestrel run --help >"$help_stdout"); then
    echo "E2E CLI: kestrel run --help failed" >&2
    exit 1
  fi
  if ! grep -q -- "--exit-wait" "$help_stdout" || ! grep -q -- "--exit-no-wait" "$help_stdout"; then
    echo "E2E CLI: kestrel run --help missing exit mode flags" >&2
    cat "$help_stdout" >&2
    exit 1
  fi

  echo "E2E CLI: exit mode flag checks passed."
fi
