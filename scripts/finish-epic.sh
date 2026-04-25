#!/usr/bin/env bash
# finish-epic.sh — mechanical epic closure: gate → tests → update → move → commit.
#
# Usage: scripts/finish-epic.sh <epic-id>
#   <epic-id> is EXX (e.g. E16).
#
# Exit codes:
#   0  epic successfully closed and committed
#   1  gate or test failure — epic file restored to original state, no commit made
#   2  usage error or epic not found
#
# Sequence (non-skippable):
#   1. Locate epic file (must be in epics/unplanned/).
#   2. Set ## Status to Done in the epic file.
#   3. Pre-flight gate: scripts/check-epic.sh must exit 0.
#   4. Test suites (Epic close trigger — all four required).
#   5. Move epic file to epics/done/.
#   6. Update story epic links (unplanned → done).
#   7. Postcondition gate: scripts/check-epic.sh must exit 0.
#   8. Commit with deterministic message.

set -uo pipefail

EPIC_ID="${1:-}"
if [[ -z "$EPIC_ID" ]]; then
  echo "usage: $0 <epic-id>" >&2
  exit 2
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KANBAN="$REPO_ROOT/docs/kanban"

step() { echo ""; echo "=== Step $1: $2 ==="; }
ok()   { echo "  ok : $*"; }
fail() { echo "  FAIL: $*" >&2; }

echo "finish-epic: $EPIC_ID"
echo "$(date '+%Y-%m-%d %H:%M:%S')"

# ---------------------------------------------------------------------------
# Step 1. Locate epic file
# ---------------------------------------------------------------------------
step 1 "Locate epic file"

shopt -s nullglob
declare -a found=()
for phase in unplanned done; do
  for f in "$KANBAN/epics/$phase/$EPIC_ID-"*.md; do
    found+=("$phase|$f")
  done
done

if [[ ${#found[@]} -eq 0 ]]; then
  fail "no epic file found for id '$EPIC_ID' in docs/kanban/epics/{unplanned,done}/"
  exit 2
fi
if [[ ${#found[@]} -gt 1 ]]; then
  fail "epic id '$EPIC_ID' resolves to multiple files:"
  for entry in "${found[@]}"; do echo "    $entry" >&2; done
  exit 1
fi

EPIC_PHASE="${found[0]%%|*}"
EPIC_FILE="${found[0]##*|}"
EPIC_BASENAME="$(basename "$EPIC_FILE")"
EPIC_SLUG="${EPIC_BASENAME%.md}"

ok "${EPIC_FILE#$REPO_ROOT/}"
ok "Phase: $EPIC_PHASE"

if [[ "$EPIC_PHASE" == "done" ]]; then
  ok "Epic is already in epics/done/. Nothing to do."
  exit 0
fi

# Save a backup so we can restore on failure.
EPIC_BACKUP="$EPIC_FILE.finish-epic-backup"
cp "$EPIC_FILE" "$EPIC_BACKUP"

restore_and_fail() {
  echo ""
  fail "$1"
  if [[ -f "$EPIC_BACKUP" ]]; then
    cp "$EPIC_BACKUP" "$EPIC_FILE"
    rm -f "$EPIC_BACKUP"
    echo "  Restored epic file to pre-run state." >&2
  fi
  exit 1
}

# ---------------------------------------------------------------------------
# Step 2. Set Status to Done
# ---------------------------------------------------------------------------
step 2 "Set Status to Done"

python3 - "$EPIC_FILE" <<'PYEOF'
import re, sys
path = sys.argv[1]
txt = open(path).read()
updated = re.sub(r'(?m)(^## Status\n\n?)[^\n#][^\n]*', r'\1Done', txt)
if updated == txt:
    # Status line may be missing content — insert Done after blank line
    updated = re.sub(r'(?m)(^## Status\n)(\n*)(##)', r'\1\nDone\n\n\3', txt)
open(path, 'w').write(updated)
print("  ok : Status set to Done")
PYEOF

if [[ $? -ne 0 ]]; then
  restore_and_fail "failed to update Status in epic file"
fi

# ---------------------------------------------------------------------------
# Step 3. Pre-flight gate
# ---------------------------------------------------------------------------
step 3 "Pre-flight gate: check-epic.sh"

if ! "$REPO_ROOT/scripts/check-epic.sh" "$EPIC_ID"; then
  restore_and_fail "pre-flight gate failed — fix reported errors and re-run"
fi
ok "gate passed"

# ---------------------------------------------------------------------------
# Step 4. Required test suites (Epic close trigger)
# ---------------------------------------------------------------------------
step 4 "Test suites (Epic close — all required)"

echo "  [1/4] compiler build + test"
if ! (cd "$REPO_ROOT/compiler" && npm run build --silent && npm test --silent); then
  restore_and_fail "compiler build/test failed"
fi
ok "[1/4] compiler build + test passed"

echo "  [2/4] kestrel test"
if ! "$REPO_ROOT/scripts/kestrel" test; then
  restore_and_fail "kestrel test failed"
fi
ok "[2/4] kestrel test passed"

echo "  [3/4] JVM runtime build"
if ! (cd "$REPO_ROOT/runtime/jvm" && bash build.sh); then
  restore_and_fail "JVM runtime build failed"
fi
ok "[3/4] JVM runtime build passed"

echo "  [4/4] E2E tests"
if ! "$REPO_ROOT/scripts/run-e2e.sh"; then
  restore_and_fail "E2E tests failed"
fi
ok "[4/4] E2E tests passed"

# ---------------------------------------------------------------------------
# Step 5. Move epic file
# ---------------------------------------------------------------------------
step 5 "Move epic to epics/done/"

DEST_DIR="$KANBAN/epics/done"
DEST_FILE="$DEST_DIR/$EPIC_BASENAME"

if ! mv "$EPIC_FILE" "$DEST_FILE"; then
  restore_and_fail "mv failed"
fi
rm -f "$EPIC_BACKUP"
ok "moved to ${DEST_FILE#$REPO_ROOT/}"

# ---------------------------------------------------------------------------
# Step 6. Update story epic links (unplanned → done)
# ---------------------------------------------------------------------------
step 6 "Update story epic links (unplanned → done)"

updated_count=0
for phase in unplanned planned doing done; do
  for story in "$KANBAN/$phase/"*.md; do
    [[ -f "$story" ]] || continue
    if grep -q "epics/unplanned/$EPIC_BASENAME" "$story" 2>/dev/null; then
      sed -i '' "s|epics/unplanned/${EPIC_BASENAME}|epics/done/${EPIC_BASENAME}|g" "$story"
      ok "updated ${story#$REPO_ROOT/}"
      updated_count=$((updated_count + 1))
    fi
  done
done
ok "$updated_count story link(s) updated"

# ---------------------------------------------------------------------------
# Step 7. Postcondition gate
# ---------------------------------------------------------------------------
step 7 "Postcondition gate: check-epic.sh"

if ! "$REPO_ROOT/scripts/check-epic.sh" "$EPIC_ID"; then
  fail "postcondition gate failed — epic was moved but links may need manual repair"
  exit 1
fi
ok "postcondition gate passed"

# ---------------------------------------------------------------------------
# Step 8. Commit
# ---------------------------------------------------------------------------
step 8 "Commit"

COMMIT_MSG="docs(kanban): close epic $EPIC_ID ${EPIC_SLUG#${EPIC_ID}-}"
(cd "$REPO_ROOT" && git add -A && git commit -m "$COMMIT_MSG")
ok "committed: $COMMIT_MSG"

echo ""
echo "=== finish-epic: $EPIC_ID DONE ==="
