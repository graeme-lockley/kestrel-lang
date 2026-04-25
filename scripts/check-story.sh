#!/usr/bin/env bash
# check-story.sh — validate a Kestrel kanban story's shape vs. its current phase.
#
# Usage: scripts/check-story.sh <story-id>
#   <story-id> is either S##-## (modern) or NN (legacy).
#
# Exit codes:
#   0  story is valid for its current phase
#   1  validation failure (sections missing, unticked boxes, etc.)
#   2  usage error or story not found
#
# Resolution:
#   Searches docs/kanban/{unplanned,planned,doing,done}/ for a file whose
#   basename starts with the given id followed by '-'.
#
# This script is the source-of-truth gate referenced by skills
# (.github/skills/build-story, plan-story, finish-epic). Skill prose may
# describe the same checks for human readers, but only this script's
# exit code is authoritative.

set -u
shopt -s nullglob

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <story-id>" >&2
  exit 2
fi

STORY_ID="$1"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KANBAN="$REPO_ROOT/docs/kanban"

# --- Resolve the story file ---------------------------------------------------

declare -a found=()
for phase in unplanned planned doing done; do
  for f in "$KANBAN/$phase/$STORY_ID-"*.md; do
    found+=("$phase|$f")
  done
done

if [[ ${#found[@]} -eq 0 ]]; then
  echo "FAIL: no story file found for id '$STORY_ID' in docs/kanban/{unplanned,planned,doing,done}/" >&2
  exit 2
fi
if [[ ${#found[@]} -gt 1 ]]; then
  echo "FAIL: story id '$STORY_ID' resolves to multiple files:" >&2
  for entry in "${found[@]}"; do echo "  $entry" >&2; done
  exit 1
fi

PHASE="${found[0]%%|*}"
FILE="${found[0]##*|}"
REL="${FILE#$REPO_ROOT/}"

echo "Story  : $STORY_ID"
echo "Phase  : $PHASE"
echo "File   : $REL"
echo "----"

# --- Helpers ------------------------------------------------------------------

errors=0
warn=0

err()  { echo "  ERROR: $*"; errors=$((errors+1)); }
warn() { echo "  WARN : $*"; warn=$((warn+1)); }
ok()   { echo "  ok   : $*"; }

has_section() {
  grep -qE "^## $(printf '%s' "$1" | sed 's/[][\\.*^$/]/\\&/g')([: ]|\$)" "$FILE"
}

count_unchecked_in_section() {
  # Print the count of '- [ ]' lines inside the section named by $1, stopping
  # at the next H2 or EOF.
  local section="$1"
  awk -v section="$section" '
    BEGIN { in_section = 0 }
    /^## / {
      if ($0 ~ "^## " section "(:|$)") { in_section = 1; next }
      else if (in_section) { exit }
    }
    in_section && /^- \[ \]/ { count++ }
    END { print count + 0 }
  ' "$FILE"
}

# --- Determine if this is a modern (S##-##) or legacy story -------------------

if [[ "$STORY_ID" =~ ^S[0-9]+-[0-9]+$ ]]; then
  KIND="modern"
else
  KIND="legacy"
fi
echo "Kind   : $KIND"
echo "----"

# --- Required sections per phase ---------------------------------------------

required_unplanned=(
  "Sequence" "Tier" "Former ID" "Epic" "Summary" "Current State"
  "Relationship to other stories" "Goals" "Acceptance Criteria"
  "Spec References" "Risks / Notes"
)
required_planned_extra=(
  "Impact analysis" "Tasks" "Tests to add"
  "Documentation and specs to update"
)
required_doing_extra=( "Build notes" )
# done has same required sections as doing.

check_sections() {
  # Usage: check_sections "<label>" "<section>" "<section>" ...
  local label="$1"; shift
  local s
  for s in "$@"; do
    if has_section "$s"; then
      ok "section '## $s' present"
    else
      if [[ "$KIND" == "legacy" ]]; then
        warn "section '## $s' missing ($label) — legacy story, not enforced"
      else
        err "section '## $s' missing ($label)"
      fi
    fi
  done
}

case "$PHASE" in
  unplanned)
    check_sections "unplanned" "${required_unplanned[@]}"
    ;;
  planned)
    check_sections "unplanned" "${required_unplanned[@]}"
    check_sections "planned" "${required_planned_extra[@]}"
    ;;
  doing)
    check_sections "unplanned" "${required_unplanned[@]}"
    check_sections "planned" "${required_planned_extra[@]}"
    check_sections "doing" "${required_doing_extra[@]}"
    ;;
  done)
    check_sections "unplanned" "${required_unplanned[@]}"
    check_sections "planned" "${required_planned_extra[@]}"
    check_sections "doing" "${required_doing_extra[@]}"
    ;;
esac

echo "----"

# --- Unchecked boxes in done/doing -------------------------------------------

if [[ "$PHASE" == "done" || "$PHASE" == "doing" ]]; then
  for sec in "Tasks" "Documentation and specs to update" "Acceptance Criteria"; do
    if has_section "$sec"; then
      n=$(count_unchecked_in_section "$sec")
      if [[ "$n" -gt 0 ]]; then
        if [[ "$KIND" == "legacy" && "$PHASE" == "done" ]]; then
          warn "$n unchecked box(es) in '## $sec' — legacy story, not enforced"
        else
          err "$n unchecked '- [ ]' in '## $sec' (must be ticked at $PHASE)"
        fi
      else
        ok "no unchecked boxes in '## $sec'"
      fi
    fi
  done
fi

# --- Sequence matches filename (modern stories) ------------------------------

if [[ "$KIND" == "modern" ]]; then
  if grep -qE "^## Sequence: $STORY_ID\$" "$FILE"; then
    ok "## Sequence matches filename"
  else
    err "## Sequence: line missing or does not match filename id '$STORY_ID'"
  fi
fi

# --- Epic link resolves -------------------------------------------------------

if has_section "Epic"; then
  # Look for a markdown link to an epic file in the Epic section.
  epic_link=$(awk '
    /^## / { if ($0 ~ /^## Epic(:|$)/) { in_section=1; next } else if (in_section) { exit } }
    in_section { print }
  ' "$FILE" | grep -oE '\(\.\./epics/(unplanned|done)/E[0-9]+-[^)]+\.md\)' | head -1 | tr -d '()')
  if [[ -n "$epic_link" ]]; then
    # Resolve relative to the kanban folder containing the story.
    story_dir="$(dirname "$FILE")"
    target="$(cd "$story_dir" && cd "$(dirname "$epic_link")" 2>/dev/null && pwd)/$(basename "$epic_link")"
    if [[ -f "$target" ]]; then
      ok "Epic link resolves: $(basename "$target")"
    else
      err "Epic link does not resolve: $epic_link"
    fi
  else
    if [[ "$KIND" == "legacy" ]]; then
      warn "no Epic link found — legacy story, not enforced"
    else
      err "no Epic link found in '## Epic' section"
    fi
  fi
fi

# --- Summary ------------------------------------------------------------------

echo "----"
if [[ "$errors" -eq 0 ]]; then
  echo "PASS ($warn warning$( [[ $warn -eq 1 ]] || echo s ))"
  exit 0
else
  echo "FAIL ($errors error$( [[ $errors -eq 1 ]] || echo s ), $warn warning$( [[ $warn -eq 1 ]] || echo s ))"
  exit 1
fi
