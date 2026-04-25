#!/usr/bin/env bash
# lint-skills.sh — lint .github/skills/ for shape, frontmatter, and refs.
#
# Usage: scripts/lint-skills.sh
#
# Exit codes:
#   0  all skills pass
#   1  one or more skills fail
#
# Checks:
#   - Every .github/skills/<name>/SKILL.md exists with required frontmatter
#     keys: name, version, description, outputs, allowed-tools, forbids.
#   - frontmatter `name` matches the folder name.
#   - All referenced templates and shared docs exist.
#   - All referenced exemplar files (examples sections) exist.
#   - All referenced sibling skill names point to a real skill folder.

set -u
shopt -s nullglob

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_DIR="$REPO_ROOT/.github/skills"

errors=0
warn=0

err() { echo "  ERROR ($1): $2"; errors=$((errors+1)); }
ok()  { echo "  ok   ($1): $2"; }

if [[ ! -d "$SKILLS_DIR" ]]; then
  echo "FAIL: $SKILLS_DIR does not exist" >&2
  exit 1
fi

# --- Collect skill folders (exclude underscore-prefixed dirs) ---------------

declare -a skills=()
for d in "$SKILLS_DIR"/*/; do
  name="$(basename "$d")"
  case "$name" in
    _*) continue ;;
  esac
  skills+=("$name")
done

echo "Linting ${#skills[@]} skill(s) in $SKILLS_DIR"
echo "----"

# --- Required frontmatter keys ----------------------------------------------

required_keys=( "name" "version" "description" "outputs" "allowed-tools" "forbids" )

for skill in "${skills[@]}"; do
  file="$SKILLS_DIR/$skill/SKILL.md"
  if [[ ! -f "$file" ]]; then
    err "$skill" "missing SKILL.md"
    continue
  fi

  # Extract frontmatter (between first and second '---').
  fm=$(awk 'BEGIN{n=0} /^---$/{n++; if(n==2) exit; next} n==1 {print}' "$file")
  if [[ -z "$fm" ]]; then
    err "$skill" "no YAML frontmatter found"
    continue
  fi

  # Required keys.
  for k in "${required_keys[@]}"; do
    if echo "$fm" | grep -qE "^${k}:"; then
      :
    else
      err "$skill" "frontmatter missing key '$k'"
    fi
  done

  # name matches folder.
  fm_name=$(echo "$fm" | awk -F': *' '/^name:/{print $2; exit}')
  if [[ "$fm_name" != "$skill" ]]; then
    err "$skill" "frontmatter name '$fm_name' != folder '$skill'"
  fi

  # Reference checks: extract markdown links to .md and .ks files
  # (excluding external URLs and anchors-only).
  while IFS= read -r ref; do
    # Skip external / anchor / empty / placeholders.
    case "$ref" in
      http*|"#"*|"") continue ;;
      *"##"*|*"<"*) continue ;;  # template placeholders like S##-##-slug.md
    esac
    # Strip anchor.
    target="${ref%%#*}"
    [[ -z "$target" ]] && continue
    skill_dir="$(dirname "$file")"
    # Try (1) relative to skill dir, (2) relative to repo root, (3) absolute.
    if [[ "$target" = /* ]]; then
      candidates=( "$REPO_ROOT$target" )
    else
      candidates=( "$skill_dir/$target" "$REPO_ROOT/$target" )
    fi
    found=""
    for c in "${candidates[@]}"; do
      if [[ -e "$c" ]]; then found="$c"; break; fi
    done
    if [[ -z "$found" ]]; then
      err "$skill" "broken link: $ref"
    fi
  done < <(grep -oE '\]\([^)]+\)' "$file" | sed 's/^](//' | sed 's/)$//' | grep -E '\.(md|ks|sh|yml|yaml)([#?]|$)' || true)

  # Cross-skill name references (bold form **skill-name**).
  while IFS= read -r ref_skill; do
    if [[ ! -d "$SKILLS_DIR/$ref_skill" ]]; then
      err "$skill" "references unknown skill: **$ref_skill**"
    fi
  done < <(grep -oE '\*\*[a-z][a-z0-9-]+\*\*' "$file" | tr -d '*' | sort -u | grep -E '^(epic-create|story-create|plan-epic|plan-story|build-story|build-epic|finish-epic|kestrel-stdlib-doc)$' || true)

  ok "$skill" "frontmatter keys present, name matches, links resolve"
done

echo "----"

# --- Lint shared assets exist -------------------------------------------------

for asset in _glossary.md _templates/README.md _shared/verify.md _shared/failure-protocol.md _shared/conventions.md README.md; do
  if [[ -f "$SKILLS_DIR/$asset" ]]; then
    ok "shared" "$asset exists"
  else
    err "shared" "missing $asset"
  fi
done

# --- Verify check-* scripts are executable -----------------------------------

for script in check-story.sh check-epic.sh finish-epic.sh; do
  path="$REPO_ROOT/scripts/$script"
  if [[ -x "$path" ]]; then
    ok "scripts" "$script exists and is executable"
  else
    err "scripts" "$script missing or not executable"
  fi
done

echo "----"
if [[ "$errors" -eq 0 ]]; then
  echo "PASS"
  exit 0
else
  echo "FAIL ($errors error$( [[ $errors -eq 1 ]] || echo s ))"
  exit 1
fi
