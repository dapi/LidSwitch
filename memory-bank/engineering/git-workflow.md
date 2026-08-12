---
title: LidSwitch Git Workflow
doc_kind: engineering
doc_function: convention
purpose: Branch, commit, pull request and release safety conventions for LidSwitch.
derived_from:
  - ../dna/governance.md
status: active
audience: humans_and_agents
---

# Git Workflow

- Default branch: `main`.
- Work on a focused `agent/<topic>` branch; preserve unrelated user changes.
- Commits use concise present-tense messages and keep generated `.build/` and
  `dist/` artifacts untracked.
- Before PR, run the relevant local checks from `testing-policy.md`, inspect the
  complete diff, and record manual hardware gaps.
- PR body links the issue and lists behavior, tests, risks and manual checks.
- Creating a PR is allowed for an explicitly requested repository change;
  merge, release and live privileged operations require explicit approval.
