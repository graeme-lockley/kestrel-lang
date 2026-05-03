---
name: verify-story
version: 1.0.0
description: >-
  Verifies a completed Kestrel kanban story by auditing every acceptance
  criterion against the actual codebase, checking that all task and
  documentation checkboxes are ticked, and confirming the required test suites
  pass. Reports a pass/fail verdict with per-criterion evidence. Does not move
  files or create commits — verification only.
inputs:
  - story_id: "story identifier (S##-##)"
outputs:
  - "pass/fail verdict with per-criterion evidence"
  - "list of any unmet criteria, unticked tasks, or failing test suites"
allowed-tools: [read_file, list_dir, file_search, grep_search, semantic_search, run_in_terminal, manage_todo_list]
forbids: ["git push", "git push --force", "git reset --hard", "git commit --amend", "git rebase", "rm -rf", "replace_string_in_file", "multi_replace_string_in_file", "create_file"]
---

# Kestrel kanban — verify a story

Canonical rules: **[docs/kanban/README.md](docs/kanban/README.md)**. This
skill performs a read-only audit of a story that is believed to be complete.
It does **not** fix issues — fixing belongs to **build-story**.

When anything goes wrong at any step, follow
[`_shared/failure-protocol.md`](../_shared/failure-protocol.md).

## Inputs

- **story_id** — the story identifier (e.g. `S17-21`).

## Outputs / Side effects

- A structured verdict: **PASS** or **FAIL**.
- A per-criterion evidence table showing what was checked and what was found.
- A list of blocking issues if the verdict is FAIL.
- **No file edits. No commits. No phase transitions.**

---

## §A. Locate the story

Search `docs/kanban/` for the story file:

```
docs/kanban/{done,doing,planned,unplanned}/S##-##-*.md
```

Read the file in full. Note:

- Current phase (which folder it is in).
- Every `## Acceptance Criteria` checkbox.
- Every `## Tasks` checkbox.
- Every `## Documentation and specs to update` checkbox.
- The `## Spec References` list.
- The `## Build notes` section (if present).

---

## §B. Check structural completeness

Verify the story contains the sections required for its current phase.
Use `scripts/check-story.sh S##-##` as the authoritative gate:

```bash
./scripts/check-story.sh S##-##
```

If the script exits non-zero, record each reported failure as a blocking
issue. Do **not** skip this step.

Expected output for a story ready for `done/`:

```
PASS (0 warnings)
```

---

## §C. Check checkboxes

For each section below, confirm **every** checkbox is `[x]`. Record any
`[ ]` as a blocking issue with its section name and verbatim text.

| Section | Must be fully ticked |
|---------|---------------------|
| `## Tasks` | Yes |
| `## Documentation and specs to update` | Yes |
| `## Acceptance Criteria` | Yes |

---

## §D. Verify each acceptance criterion against the codebase

For every criterion listed under `## Acceptance Criteria`:

1. **Identify the artefact** — determine what file, function, test, or
   behaviour the criterion refers to.
2. **Locate the evidence** — search the codebase for the relevant code,
   test assertion, conformance file, or spec text. Use `grep_search`,
   `file_search`, `read_file`, or `run_in_terminal` as needed.
3. **Assess** — decide whether the evidence satisfies the criterion:
   - `MET` — artefact exists and matches the criterion.
   - `UNMET` — artefact is absent, incorrect, or incomplete.
   - `PARTIAL` — artefact exists but only partially satisfies the criterion.
4. **Record** — add a row to the evidence table (see §F).

Be conservative: if evidence is ambiguous, mark `PARTIAL` and explain.

---

## §E. Run the test suites

Run the suites required by the **Any story** triggers in
[`_shared/verify.md`](../_shared/verify.md):

```bash
cd compiler && npm test
```

```bash
./scripts/kestrel test
```

If either suite exits non-zero, record the failure verbatim (last 50 lines)
and mark the verdict FAIL. Do **not** suppress or truncate failures.

If the story touched `runtime/jvm/src/**`, also run:

```bash
cd runtime/jvm && bash build.sh
```

If the story introduced or modified E2E scenarios, also run:

```bash
./scripts/run-e2e.sh
```

---

## §F. Produce the verdict

After completing §B–§E, output a structured summary:

### Verdict: PASS

All of the following are true:

- `scripts/check-story.sh` exits 0.
- Every `## Tasks`, `## Acceptance Criteria`, and
  `## Documentation and specs to update` checkbox is `[x]`.
- Every acceptance criterion is `MET`.
- All required test suites pass.

### Verdict: FAIL

One or more of the above is false. List every blocking issue:

```
FAIL

Blocking issues:
1. <criterion or checkbox> — <what is missing or wrong>
2. ...

Per-criterion evidence:
| Criterion | Status | Evidence / Gap |
|-----------|--------|---------------|
| <text>    | MET    | <where found> |
| <text>    | UNMET  | <what is missing> |
| <text>    | PARTIAL| <what exists vs. what is required> |
```

---

## §G. When the verdict is FAIL

1. Report the full blocking list to the author.
2. **Do not edit any files.**
3. **Do not move the story.**
4. Suggest using **build-story** to address the gaps if the story is in
   `doing/` or `planned/`, or re-opening the story if it is already in
   `done/`.

---

## Related

- Implement a story: skill **build-story**
- Plan a story: skill **plan-story**
- Close an epic: skill **finish-epic**
- Kanban rules: `docs/kanban/README.md`
- Verification matrix: `_shared/verify.md`
