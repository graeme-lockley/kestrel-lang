#!/usr/bin/env bash
# check-epic.sh — validate a Kestrel kanban epic's closure preconditions.
#
# Usage: scripts/check-epic.sh <epic-id>
#   <epic-id> is EXX (e.g. E01).
#
# Exit codes:
#   0  epic is ready to close (or already closed)
#   1  validation failure (member story not done, criteria unticked, etc.)
#   2  usage error or epic not found
#
# This script is the source-of-truth gate referenced by skills
# (.github/skills/finish-epic). Skill prose may describe the same checks
# for human readers, but only this script's exit code is authoritative.

set -u
shopt -s nullglob

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <epic-id>" >&2
  exit 2
fi

EPIC_ID="$1"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KANBAN="$REPO_ROOT/docs/kanban"

# --- Resolve epic file --------------------------------------------------------

declare -a found=()
for phase in unplanned done; do
  for f in "$KANBAN/epics/$phase/$EPIC_ID-"*.md; do
    found+=("$phase|$f")
  done
done

if [[ ${#found[@]} -eq 0 ]]; then
  echo "FAIL: no epic file found for id '$EPIC_ID' in docs/kanban/epics/{unplanned,done}/" >&2
  exit 2
fi
if [[ ${#found[@]} -gt 1 ]]; then
  echo "FAIL: epic id '$EPIC_ID' resolves to multiple files:" >&2
  for entry in "${found[@]}"; do echo "  $entry" >&2; done
  exit 1
fi

EPIC_PHASE="${found[0]%%|*}"
EPIC_FILE="${found[0]##*|}"
REL="${EPIC_FILE#$REPO_ROOT/}"

echo "Epic   : $EPIC_ID"
echo "Phase  : $EPIC_PHASE"
echo "File   : $REL"
echo "----"

errors=0
warn=0

err()  { echo "  ERROR: $*"; errors=$((errors+1)); }
warn() { echo "  WARN : $*"; warn=$((warn+1)); }
ok()   { echo "  ok   : $*"; }

# --- If already in done/, just report ----------------------------------------

if [[ "$EPIC_PHASE" == "done" ]]; then
  echo "Epic is already in epics/done/. Nothing to validate."
  echo "PASS (0 warnings)"
  exit 0
fi

# --- Required sections -------------------------------------------------------

required=( "Status" "Summary" "Stories" "Dependencies" "Epic Completion Criteria" )
for s in "${required[@]}"; do
  if grep -qE "^## ${s}([: ]|\$)" "$EPIC_FILE"; then
    ok "section '## $s' present"
  else
    err "section '## $s' missing"
  fi
done

echo "----"

# --- Extract member story ids from the Stories section ----------------------

# Match S##-## ids in the Stories section.
declare -a story_ids=()
while IFS= read -r id; do
  story_ids+=("$id")
done < <(awk '
  /^## / { if ($0 ~ /^## Stories(:|$| )/) { in_section=1; next } else if (in_section) { exit } }
  in_section { print }
' "$EPIC_FILE" | grep -oE 'S[0-9]+-[0-9]+' | sort -u)

if [[ ${#story_ids[@]} -eq 0 ]]; then
  err "no S##-## story ids found in '## Stories' section"
else
  ok "found ${#story_ids[@]} member story id(s)"
fi

# --- Verify every member story is in done/ and passes check-story.sh --------

for id in "${story_ids[@]}"; do
  # Locate the story across phases.
  declare -a sfound=()
  for sphase in unplanned planned doing done; do
    for f in "$KANBAN/$sphase/$id-"*.md; do
      sfound+=("$sphase|$f")
    done
  done
  if [[ ${#sfound[@]} -eq 0 ]]; then
    err "story $id: not found in any kanban folder"
    continue
  fi
  if [[ ${#sfound[@]} -gt 1 ]]; then
    err "story $id: resolves to multiple files"
    continue
  fi
  sphase="${sfound[0]%%|*}"
  if [[ "$sphase" != "done" ]]; then
    err "story $id: in '$sphase/', must be in 'done/' before epic can close"
    continue
  fi
  # Run check-story.sh quietly; surface only its exit code.
  if "$REPO_ROOT/scripts/check-story.sh" "$id" >/dev/null 2>&1; then
    ok "story $id: done and check-story passes"
  else
    err "story $id: in done/ but check-story.sh failed (run it directly to see details)"
  fi
done

echo "----"

# --- Unchecked epic completion criteria --------------------------------------

unchecked=$(awk '
  /^## / { if ($0 ~ /^## Epic Completion Criteria(:|$)/) { in_section=1; next } else if (in_section) { exit } }
  in_section && /^- \[ \]/ { count++ }
  END { print count + 0 }
' "$EPIC_FILE")

if [[ "$unchecked" -gt 0 ]]; then
  err "$unchecked unchecked '- [ ]' in '## Epic Completion Criteria'"
else
  ok "no unchecked boxes in '## Epic Completion Criteria'"
fi

# --- Status line --------------------------------------------------------------

status_line=$(awk '
  /^## / { if ($0 ~ /^## Status(:|$)/) { in_section=1; next } else if (in_section) { exit } }
  in_section && NF { print; exit }
' "$EPIC_FILE")

if [[ "$status_line" == "Done" ]]; then
  ok "Status: Done"
else
  warn "Status is '$status_line' (will need to be 'Done' before move to epics/done/)"
fi

# --- Summary ------------------------------------------------------------------

echo "----"
if [[ "$errors" -eq 0 ]]; then
  echo "PASS ($warn warning$( [[ $warn -eq 1 ]] || echo s )) — epic is ready to close"
  exit 0
else
  echo "FAIL ($errors error$( [[ $errors -eq 1 ]] || echo s ), $warn warning$( [[ $warn -eq 1 ]] || echo s ))"
  exit 1
fi
