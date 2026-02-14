#!/usr/bin/env bash
# Run compiler tests, VM tests, then E2E. Exit non-zero if any step fails.
# Each layer can also be run alone: cd compiler && npm test, cd vm && zig build test, ./scripts/run-e2e.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== Compiler tests =="
cd compiler && npm test && cd ..

echo "== VM tests =="
cd vm && zig build test 2>&1 && cd .. || exit 1
echo "VM tests passed."

echo "== E2E =="
"$ROOT/scripts/run-e2e.sh"

echo "== All passed =="
