# CLAUDE.md

@AGENTS.md

## Claude-specific notes

- Talk to the owner in Egyptian Arabic; keep code, commits and identifiers in English.
- Before a large UI change, list the test files that reference the widgets you touch
  (`grep -rln "<WidgetName>\|<key>" test/`) and update them in the same change.
- When you cannot run Flutter locally, say so plainly and rely on the CI result — never claim a
  build or test passed without seeing it.
- Prefer small, reviewable commits: one plan item per commit, message in English.
