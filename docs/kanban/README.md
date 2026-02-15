# Kanban Board

Stories flow through: **unplanned** → **backlog** → **doing** → **done**.

| Folder      | Purpose |
|-------------|---------|
| **unplanned** | Stories for refinement. Human moves to backlog when ready. |
| **backlog**   | Ready for work. Agent picks up from here. |
| **doing**     | Active work. Agent moves story here when starting; adds tasks and ticks them off. |
| **done**      | Completed. Agent moves story here when finished. |

The agent is instructed (via Cursor rules) to follow this workflow. See `.cursor/rules/kanban-workflow.mdc`.
