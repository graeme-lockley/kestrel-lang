#!/usr/bin/env bash
# Run compiler tests, VM tests, then E2E. Exit non-zero if any step fails.
# Each layer can also be run alone: cd compiler && npm test, cd vm && zig build test, ./scripts/run-e2e.sh, ./scripts/kestrel test
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== Compiler tests =="
(cd compiler && npm test)

echo "== VM tests =="
(cd vm && zig build test --verbose 2>&1)
echo "VM tests passed."

echo "== E2E =="
"$ROOT/scripts/run-e2e.sh"

echo "== Kestrel unit vm tests =="
"$ROOT/scripts/kestrel" test || exit 1

echo "== Kestrel unit jvm tests =="
"$ROOT/scripts/kestrel" test --target jvm || exit 1

echo "== All passed =="
