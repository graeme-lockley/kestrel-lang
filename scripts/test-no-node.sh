#!/usr/bin/env bash
# Validate that kestrel test passes without the TypeScript compiler directory.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

COMPILER_DIR="$ROOT/compiler"
DISABLED_DIR="$ROOT/compiler_DISABLED"
renamed=0

restore_compiler() {
  if [ "$renamed" -eq 1 ] && [ -d "$DISABLED_DIR" ] && [ ! -d "$COMPILER_DIR" ]; then
    mv "$DISABLED_DIR" "$COMPILER_DIR"
  fi
}

trap restore_compiler EXIT INT TERM

if [ ! -d "$COMPILER_DIR" ]; then
  echo "test-no-node: missing compiler/ directory" >&2
  exit 1
fi

if [ -e "$DISABLED_DIR" ]; then
  echo "test-no-node: compiler_DISABLED already exists; refusing to continue" >&2
  exit 1
fi

mv "$COMPILER_DIR" "$DISABLED_DIR"
renamed=1

./scripts/kestrel test

echo "test-no-node: PASS (kestrel test succeeded with compiler/ unavailable)"
