# Failure protocol

What to do when a step in **plan-story**, **build-story**, **build-epic**,
or **finish-epic** does not succeed. The protocol is deliberately
conservative: the agent halts and surfaces the problem rather than
inventing a workaround.

## General rule

**Halt at the first failure. Report. Do not advance the phase. Do not
commit a partial state.**

## Specific failure modes

### 1. Test suite failure

A required suite from [`verify.md`](verify.md) returns non-zero.

- **Halt** the current step.
- **Paste the failing output verbatim** (last 50 lines minimum) so the
  author can see the actual error.
- **Do not** move the story to `done/` or the epic to `epics/done/`.
- **Do not** commit. Implementation changes may stay in the working
  tree; the author decides whether to discard or retry.
- If the failure looks unrelated to the current change, say so but
  still halt.

### 2. Scope explosion

While building, more than **3 new tasks** are discovered beyond the
planned set.

- Append a **Build note** describing what was discovered and why it
  blocks the planned scope.
- **Stop work** and ask the author whether to:
  - extend this story (add the new tasks), or
  - file a follow-up story and revert the in-progress changes.
- Never silently grow scope beyond the threshold.

### 3. Spec contradiction

The implementation requirement contradicts a `docs/specs/` file, or two
specs contradict each other.

- **Halt**.
- Cite both sources (file + section).
- Ask the author which is authoritative.
- **Never** silently choose. Spec drift left in place becomes the next
  bug.

### 4. Unexpected uncommitted changes

At the start of any skill, the working tree contains modifications
unrelated to the story.

- **Halt** before doing any work.
- Report the dirty paths.
- Ask the author to commit or stash them first.

### 5. Phase/folder mismatch

A story file is found in an unexpected folder (e.g. story id implies
`done/` but file is in `doing/`), or its `## Sequence:` does not match
the filename.

- **Halt**.
- Report the discrepancy with the resolved path.
- Do not auto-correct. The agent cannot reliably know which side is
  authoritative.

### 6. Missing required section

A story or epic file is missing a load-bearing section (see
[`../_glossary.md`](../_glossary.md) and the templates).

- If the skill's job is to **create** that section (e.g. **plan-story**
  adding `## Tasks`), proceed.
- Otherwise **halt** and ask the author whether to use **plan-story**
  or **story-create** to repair the file first.

### 7. Verification script non-zero

`scripts/check-story.sh` or `scripts/check-epic.sh` returns non-zero.

- **Halt**.
- Treat the script's output as authoritative; do not override.
- Fix the underlying cause (tick boxes, add sections, move file) and
  re-run. Never edit the script's output to bypass it.

## Forbidden recoveries

- `git push --force`
- `git reset --hard` to discard the failure
- `git commit --amend` on commits that exist on a remote branch
- `git rebase` mid-story to "tidy" history
- Removing tests to make a suite green
- Editing `.expected` E2E files without inspecting the actual diff

If any of these seems necessary, the answer is to halt and ask the
author, not to proceed.
