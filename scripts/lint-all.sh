#!/usr/bin/env bash
# Run all linting checks. Exit non-zero if any step fails.
# Each layer can also be run alone:
#   cd compiler && npx tsc --noEmit
#   ./scripts/lint-skills.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== Compiler type-check =="
(cd compiler && npx tsc --noEmit)

echo "== Skills lint =="
"$ROOT/scripts/lint-skills.sh"

echo "== All lint checks passed =="
