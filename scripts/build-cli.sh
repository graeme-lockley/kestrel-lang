#!/usr/bin/env bash
# Drive planned kanban stories through review → implementation → verification → commit/push
# using the Cursor Agent CLI (non-interactive).
#
# Only processes files in docs/kanban/planned/ (build-ready planning gate). Stories must be
# promoted from unplanned per docs/kanban/README.md before this script will pick them up.
#
# Environment:
#   CURSOR_CLI   — Agent binary (default: cursor-agent). Must support the flags used below.
#   REPO_ROOT    — Workspace root (default: parent of scripts/)
#
# Agent invocation uses --sandbox disabled, --force, and --approve-mcps so headless runs can
# use filesystem tools (including delete), shell, MCP servers, and other actions without
# sandbox blocks or extra prompts.
# Only run this script on workspaces you trust.
#
# Prerequisites: cursor-agent (or agent) on PATH, logged in; git remote for push.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

: "${CURSOR_CLI:=cursor-agent}"
MAX_STEP2_ATTEMPTS=5
PLANNED_DIR="$REPO_ROOT/docs/kanban/planned"
DONE_DIR="$REPO_ROOT/docs/kanban/done"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

log_stage() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "STAGE: $*"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

log_step() {
  echo ""
  echo "── STEP $* ──"
}

# Run Cursor Agent CLI with a single prompt (non-interactive, trusted workspace, sandbox off).
# Prints the prompt and merges agent stdout/stderr so the run is visible in the terminal.
run_cursor_cli() {
  local prompt=$1
  if ! command -v "$CURSOR_CLI" >/dev/null 2>&1; then
    die "CURSOR_CLI='$CURSOR_CLI' not found on PATH. Install Cursor Agent CLI or set CURSOR_CLI."
  fi
  echo ""
  echo "================================================================================"
  echo "Submitted prompt"
  echo "================================================================================"
  printf '%s\n' "$prompt"
  echo ""
  echo "================================================================================"
  echo "Agent output ($CURSOR_CLI)"
  echo "================================================================================"
  set +e
  "$CURSOR_CLI" -p --trust --sandbox disabled --force --approve-mcps --workspace "$REPO_ROOT" "$prompt" 2>&1
  local ec=$?
  set -e
  echo "================================================================================"
  echo "End agent output (exit $ec)"
  echo "================================================================================"
  return "$ec"
}

story_basename() {
  basename "$1"
}

story_slug_for_prompts() {
  # e.g. 11-namespace-constructor-access.md → human-friendly id for prompts
  local base
  base="$(basename "$1" .md)"
  echo "$base"
}

is_story_in_done() {
  local name
  name="$(story_basename "$1")"
  [[ -f "$DONE_DIR/$name" ]]
}

# Each step must use "|| return 1": this function is invoked as "if ! run_full_test_suite",
# and bash disables errexit during that evaluation, so a bare failing subshell would not stop
# the function and "Full test suite passed." could print anyway.
run_full_test_suite() {
  echo "Running full test suite (compiler build + tests, VM, E2E, Kestrel harness)…"
  (cd "$REPO_ROOT/compiler" && npm run build && npm test) || return 1
  (cd "$REPO_ROOT/vm" && zig build test --verbose 2>&1) || return 1
  "$REPO_ROOT/scripts/run-e2e.sh" || return 1
  "$REPO_ROOT/scripts/kestrel" test || return 1
  "$REPO_ROOT/scripts/kestrel" test --target jvm || return 1
  echo "Full test suite passed."
}

process_one_story() {
  local story_path=$1
  local index=$2
  local total=$3
  local base_name slug

  base_name="$(story_basename "$story_path")"
  slug="$(story_slug_for_prompts "$story_path")"

  log_stage "Story $index/$total — $base_name"

  local p1 p2 p3 p6
  p1="please review the planned story docs/kanban/planned/${base_name} in great detail and ensure that it is accurate and complete for implementation. Specifically, make sure that all docs that need to be updated are listed (Documentation and specs to update) and reflected in acceptance criteria where appropriate, and that Tests to add covers an exhaustive set of unit/integration checks. Follow docs/kanban/README.md planned exit criteria before moving the story to docs/kanban/doing/."

  p3="please verify that the feature ${slug} is complete and all tests pass"

  p6="please commit the change for feature ${slug}"

  log_step "1/7 — Review story via Cursor Agent ($base_name)"
  run_cursor_cli "$p1"

  local attempt=1
  local failure_context=""

  while (( attempt <= MAX_STEP2_ATTEMPTS )); do
    log_step "2/7 — Feature delivery (Kestrel feature delivery skill) — attempt $attempt/$MAX_STEP2_ATTEMPTS ($base_name)"
    p2="use the Kestrel feature delivery skill on story ${base_name}. The story file starts in docs/kanban/planned/${base_name}; move it to docs/kanban/doing/ per kestrel-kanban-story-migrate before coding. Complete: meet acceptance criteria, all tests run and pass, move the file to docs/kanban/done/${base_name}.${failure_context}"
    run_cursor_cli "$p2" || die "Cursor Agent exited non-zero on feature delivery (attempt $attempt)."

    log_step "3/7 — Verification via Cursor Agent ($base_name)"
    local verify_ok=0
    run_cursor_cli "${p3}${failure_context}" || verify_ok=$?

    if (( verify_ok != 0 )); then
      echo "Verification (step 3) did not succeed (exit $verify_ok)."
      if (( attempt >= MAX_STEP2_ATTEMPTS )); then
        die "Exceeded $MAX_STEP2_ATTEMPTS attempts at step 2 (feature delivery loop). Last failure: verification step did not complete."
      fi
      failure_context+=$'\n\n'"IMPORTANT: A previous run did not pass verification (step 3). The verification step was not completed successfully. Address this, then complete the story and ensure verification passes."
      ((++attempt))
      continue
    fi

    log_step "4/7 — Check story file is in docs/kanban/done/"
    if ! is_story_in_done "$story_path"; then
      echo "Story $base_name is not present under $DONE_DIR/"
      if (( attempt >= MAX_STEP2_ATTEMPTS )); then
        die "Exceeded $MAX_STEP2_ATTEMPTS attempts at step 2. Last failure: story not moved to done folder."
      fi
      failure_context+=$'\n\n'"IMPORTANT: The story file was not found in docs/kanban/done/. If the work is complete, the story must be moved into the done folder (see kanban workflow)."
      ((++attempt))
      continue
    fi

    log_step "5/7 — Manual full test suite"
    local test_log
    test_log="$(mktemp)"
    if ! run_full_test_suite >"$test_log" 2>&1; then
      echo "Test suite failed. Tail of log:"
      tail -n 80 "$test_log" || true
      local snippet
      snippet="$(tail -n 40 "$test_log" 2>/dev/null | sed 's/^/  /' || true)"
      rm -f "$test_log"
      if (( attempt >= MAX_STEP2_ATTEMPTS )); then
        die "Exceeded $MAX_STEP2_ATTEMPTS attempts at step 2. Last failure: manual test suite failed."
      fi
      failure_context+=$'\n\n'"IMPORTANT: The manual test suite failed after the agent reported completion. Fix the failures below and get the story fully complete; all tests must pass."$'\n'"--- test output (tail) ---"$'\n'"$snippet"
      ((++attempt))
      continue
    fi
    rm -f "$test_log"

    echo "Story $base_name: verification, done folder, and tests OK (after $attempt attempt(s) of the delivery loop)."
    break
  done

  if (( attempt > MAX_STEP2_ATTEMPTS )); then
    die "Internal error: exited delivery loop without success for $base_name"
  fi

  log_step "6/7 — Request commit via Cursor Agent ($base_name)"
  run_cursor_cli "$p6"

  log_step "7/7 — git push"
  git push

  echo "Completed story $base_name (committed and pushed)."
}

main() {
  log_stage "Discover planned stories"
  local -a stories=()
  if [[ ! -d "$PLANNED_DIR" ]]; then
    die "Missing directory: $PLANNED_DIR"
  fi
  shopt -s nullglob
  local -a raw=("$PLANNED_DIR"/*.md)
  shopt -u nullglob
  local f line
  local -a story_files=()
  for f in "${raw[@]}"; do
    [[ "$(basename "$f")" == "README.md" ]] && continue
    story_files+=("$f")
  done
  if ((${#story_files[@]} > 0)); then
    while IFS= read -r line; do
      [[ -n "$line" ]] && stories+=("$line")
    done < <(printf '%s\n' "${story_files[@]}" | sort)
  fi

  if ((${#stories[@]} == 0)); then
    echo "No planned stories in $PLANNED_DIR — nothing to do."
    exit 0
  fi

  echo "Found ${#stories[@]} planned story/stories (sorted by filename)."
  local i=1
  for f in "${stories[@]}"; do
    process_one_story "$f" "$i" "${#stories[@]}"
    i=$((i + 1))
  done

  log_stage "All listed planned stories processed"
  echo "Done."
}

main "$@"
