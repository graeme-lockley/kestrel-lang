# Skill frontmatter template

Used by every `SKILL.md`. Standardised in Stage 6.

```yaml
---
name: <kebab-case-skill-name>
version: 1.0.0
description: >-
  One- or two-sentence description suitable for skill routing. Should
  state what the skill does, when to use it, and any required inputs.
inputs:
  - <name>: <description, e.g. "epic id (EXX)">
outputs:
  - <effect, e.g. "creates docs/kanban/epics/unplanned/EXX-slug.md">
allowed-tools: [read_file, replace_string_in_file, multi_replace_string_in_file, run_in_terminal, manage_todo_list]
forbids: ["git push", "git push --force", "git reset --hard"]
---
```

## Field reference

| Field | Required | Notes |
|-------|----------|-------|
| `name` | yes | Must equal the folder name. |
| `version` | yes | Semver. Bump on substantive changes. |
| `description` | yes | Used by Copilot to decide when to load the skill. |
| `inputs` | no | Omit if the skill takes none. |
| `outputs` | yes | Side effects: files created/moved/edited, commits, etc. |
| `allowed-tools` | yes | Declarative; lint-checked. |
| `forbids` | yes | Declarative; lint-checked. |

## Allowed-tools by skill kind

| Kind | Typical allow-list |
|------|-----|
| Authoring (epic-create, story-create) | `read_file`, `create_file`, `replace_string_in_file`, `manage_todo_list` |
| Planning (plan-epic, plan-story) | + `grep_search`, `file_search`, `semantic_search` |
| Building (build-story, build-epic) | + `run_in_terminal`, `multi_replace_string_in_file` |
| Verification (finish-epic) | + `run_in_terminal` (read-mostly), no commits without an explicit step |
| Standalone (kestrel-stdlib-doc) | `read_file`, `replace_string_in_file`, `grep_search` |

## Forbids defaults

Always forbid: `git push`, `git push --force`, `git reset --hard`,
`rm -rf`. Skills that must never modify history additionally forbid:
`git rebase`, `git commit --amend`.
