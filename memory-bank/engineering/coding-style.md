---
title: LidSwitch Coding Style
doc_kind: engineering
doc_function: convention
purpose: Swift and shell conventions observed in LidSwitch.
derived_from:
  - ../dna/governance.md
status: active
audience: humans_and_agents
---

# Coding Style

- Follow the existing Swift style: four-space indentation, explicit access
  control, early `guard`, small value types and `final` runtime controllers.
- Keep deterministic policy in `LidSwitchCore`; keep AppKit/IOKit and process
  execution at adapter edges.
- Prefer enums and fixed mappings over free-form privileged arguments.
- Comments explain why, safety boundaries or undocumented platform behavior.
- Shell scripts use zsh with `set -euo pipefail`, quoted paths and explicit
  validation before mutation.
- No formatter or standalone linter is configured; `swift build`, executable
  checks and `git diff --check` are the current formatting/compile guardrails.
- Do not refactor unrelated code while delivering a focused issue.
