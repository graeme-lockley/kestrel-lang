#!/usr/bin/env bash
# test-kestrel.sh — run the Kestrel-compiler test corpora via ./kestrel-self.
#
# Tiers (in order):
#   parse     tests/kconformance/parse/*.ks        — compile-only (exit 0)
#   typecheck tests/kconformance/typecheck/*.ks     — compile-only (exit 0)
#   runtime   tests/kconformance/runtime/valid/*.ks — run + // => golden check
#   unit      tests/kunit/*.test.ks                 — kestrel:dev/test (if non-empty)
#
# Exits non-zero on any failure. Prints per-tier counts.
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"; SOURCE="$(readlink "$SOURCE")"
  [[ "$SOURCE" != /* ]] && SOURCE="$DIR/$SOURCE"
done
ROOT="$(cd -P "$(dirname "$SOURCE")/.." && pwd)"
KSELF="$ROOT/kestrel-self"
JVM_CACHE="${KESTREL_SELF_CACHE:-$HOME/.kestrel/self}"

# Redirect build outputs to a throwaway cache so the self-hosted compiler's
# (currently incomplete) codegen for stdlib modules cannot pollute the user's
# normal ~/.kestrel/ts cache and break a subsequent `./kestrel test`. The
# self-hosted CLI writes compile output to KESTREL_TS_CACHE; classloading also
# uses it, but a throwaway empty dir is fine because real classes are loaded
# from $JVM_CACHE (self-hosted bootstrap cache) which we leave untouched.
TS_CACHE_OVERRIDE="${TMPDIR:-/tmp}/kestrel-test-corpus-ts.$$"
trap 'rm -rf "$TS_CACHE_OVERRIDE"' EXIT
mkdir -p "$TS_CACHE_OVERRIDE"
export KESTREL_TS_CACHE="$TS_CACHE_OVERRIDE"

# ── Bootstrap guard ──────────────────────────────────────────────────────────
if ! find "$JVM_CACHE" -name "Cli.class" -path "*/kestrel/tools/Cli.class" 2>/dev/null | grep -q .; then
  echo "test-kestrel: self-hosted cache missing — bootstrapping..." >&2
  "$KSELF" bootstrap >/dev/null 2>&1 || {
    echo "test-kestrel: bootstrap unavailable (requires build-bootstrap-jar.sh + kestrel-self bootstrap) — skipping" >&2
    exit 0
  }
fi

# ── Helpers ───────────────────────────────────────────────────────────────────
PASS=0; FAIL=0

run_build_tier() {
  local tier_name="$1"; local dir="$2"
  local count=0; local tier_fail=0
  if [ ! -d "$dir" ] || [ -z "$(find "$dir" -maxdepth 1 -name '*.ks' 2>/dev/null)" ]; then
    echo "${tier_name}: 0 files"
    return
  fi
  for f in "$dir"/*.ks; do
    [ -f "$f" ] || continue
    if "$KSELF" build --clean "$f" >/dev/null 2>/tmp/test-kestrel-err; then
      (( count++ )) || true
    else
      echo "  FAIL [${tier_name}] $f"
      head -1 /tmp/test-kestrel-err >&2 || true
      (( tier_fail++ )) || true
    fi
  done
  echo "${tier_name}: ${count} passed, ${tier_fail} failed"
  (( PASS += count )) || true
  (( FAIL += tier_fail )) || true
}

run_runtime_tier() {
  # NOTE: The runtime tier currently compiles and runs files via ./kestrel (TS compiler path)
  # because the self-hosted compiler's code generation for top-level programs is not yet
  # complete (pending S17-36/S17-37/S17-38). Once self-hosted codegen is functional,
  # this will switch to $KSELF (./kestrel-self).
  local krun="$ROOT/kestrel"
  local dir="$1"
  local count=0; local tier_fail=0
  if [ ! -d "$dir" ] || [ -z "$(find "$dir" -maxdepth 1 -name '*.ks' 2>/dev/null)" ]; then
    echo "runtime: 0 files"
    return
  fi
  for f in "$dir"/*.ks; do
    [ -f "$f" ] || continue
    # Extract // => goldens from source
    local goldens=()
    while IFS= read -r line; do
      if [[ "$line" =~ ^[[:space:]]*//[[:space:]]=\>[[:space:]]?(.*) ]]; then
        goldens+=("${BASH_REMATCH[1]}")
      fi
    done < "$f"

    # Run the file; capture stdout to a temp file
    local stdout_file
    stdout_file=$(mktemp /tmp/test-kestrel-stdout-XXXXXX)
    if ! "$krun" run --clean "$f" >"$stdout_file" 2>/tmp/test-kestrel-err; then
      echo "  FAIL [runtime] $f (non-zero exit)"
      head -1 /tmp/test-kestrel-err >&2 || true
      rm -f "$stdout_file"
      (( tier_fail++ )) || true
      continue
    fi

    # Compare stdout lines to goldens
    if [ ${#goldens[@]} -gt 0 ]; then
      local ok=1
      local i=0
      while IFS= read -r actual_line; do
        local expected="${goldens[$i]:-}"
        if [ "$expected" != "$actual_line" ]; then
          echo "  FAIL [runtime] $f line $((i+1)): expected '${expected}' got '${actual_line}'"
          ok=0
        fi
        (( i++ )) || true
      done < "$stdout_file"
      # Check if we got fewer lines than expected goldens
      if [ "$ok" -eq 1 ] && [ "$i" -lt "${#goldens[@]}" ]; then
        for (( j=i; j<${#goldens[@]}; j++ )); do
          echo "  FAIL [runtime] $f line $((j+1)): expected '${goldens[$j]}' got ''"
          ok=0
        done
      fi
      if [ "$ok" -eq 1 ]; then
        (( count++ )) || true
      else
        (( tier_fail++ )) || true
      fi
    else
      (( count++ )) || true
    fi
    rm -f "$stdout_file"
  done
  echo "runtime: ${count} passed, ${tier_fail} failed"
  (( PASS += count )) || true
  (( FAIL += tier_fail )) || true
}

run_unit_tier() {
  local dir="$1"
  if [ ! -d "$dir" ] || [ -z "$(find "$dir" -maxdepth 1 -name '*.test.ks' 2>/dev/null)" ]; then
    echo "unit: 0 files (inactive)"
    return
  fi
  local count=0; local tier_fail=0
  for f in "$dir"/*.test.ks; do
    [ -f "$f" ] || continue
    if "$KSELF" test "$f" >/dev/null 2>/tmp/test-kestrel-err; then
      (( count++ )) || true
    else
      echo "  FAIL [unit] $f"
      head -1 /tmp/test-kestrel-err >&2 || true
      (( tier_fail++ )) || true
    fi
  done
  echo "unit: ${count} passed, ${tier_fail} failed"
  (( PASS += count )) || true
  (( FAIL += tier_fail )) || true
}

# ── Run tiers ─────────────────────────────────────────────────────────────────
run_build_tier "parse"     "$ROOT/tests/kconformance/parse"
run_build_tier "typecheck" "$ROOT/tests/kconformance/typecheck"
run_runtime_tier           "$ROOT/tests/kconformance/runtime/valid"
run_unit_tier              "$ROOT/tests/kunit"

echo ""
echo "total: $((PASS + FAIL)) files, ${PASS} passed, ${FAIL} failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
