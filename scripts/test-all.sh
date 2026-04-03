#!/usr/bin/env bash
# Run compiler tests, E2E, then Kestrel JVM unit tests. Exit non-zero if any step fails.
# Each layer can also be run alone: cd compiler && npm test, ./scripts/run-e2e.sh, ./scripts/kestrel test
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== Compiler tests =="
(cd compiler && npm test)

echo "== E2E =="
"$ROOT/scripts/run-e2e.sh"

echo "== Kestrel unit tests (JVM) =="
"$ROOT/scripts/kestrel" test || exit 1

echo "== All passed =="
