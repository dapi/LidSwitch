---
title: LidSwitch UI Reference Index
doc_kind: engineering
doc_function: index
purpose: Curated map to the existing native menu-bar UI implementation.
derived_from:
  - ../../dna/governance.md
  - ../frontend.md
status: active
audience: humans_and_agents
canonical_for:
  - project_ui_design_guide_routing
---

# UI Design Guide

LidSwitch has one compact native AppKit surface, so its conventions are owned by
`../frontend.md`. The installed surface templates are retained as archived N/A
records so future template updates cannot silently recreate fake project facts:

- [`public-web.md`](public-web.md) — N/A: no web UI.
- [`admin.md`](admin.md) — N/A: no admin UI.
- [`mobile.md`](mobile.md) — N/A: no mobile app in the shipped scope.
- [`shared-components.md`](shared-components.md) — N/A: no cross-surface UI kit.

Before a UI change inspect:

- `Sources/LidSwitch/main.swift` for status-item actions, menus and feedback;
- `Sources/LidSwitch/StatusIconRenderer.swift` for work/sleep/unknown icons;
- `Sources/LidSwitch/HoverStatusViewController.swift` for hover presentation;
- `QA.md` for the manual UI matrix.

Code remains the implementation source of truth. Feature-specific UI acceptance
belongs to its delivery artifact, not this index.
