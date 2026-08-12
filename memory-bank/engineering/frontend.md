---
title: LidSwitch Native UI Engineering
doc_kind: engineering
doc_function: canonical
purpose: AppKit status-item surfaces, interaction rules and localization status.
derived_from:
  - ../dna/governance.md
  - ../product/context.md
status: active
audience: humans_and_agents
---

# Native UI Engineering

The only shipped UI surface is a native AppKit menu-bar application in
`Sources/LidSwitch/`. `ApplicationDelegate` owns status-item actions and menu
state; `StatusIconRenderer` owns icon drawing; `HoverStatusViewController` owns
the hover card.

## Interaction Rules

- Left click toggles closed-lid work; right/Control-click opens the menu.
- Hover appears after 0.35 seconds and must agree with icon/menu state.
- Work, sleep and unknown are distinct UI states; unknown must not be promoted
  to either known outcome.
- UI state follows system read-back and main-thread updates.
- Feedback should respect macOS conventions and user sound settings.

There is no design system or separate frontend bundle. UI strings are currently
embedded in Swift and mixed English/Russian; no localization catalog exists, so
new copy should be minimal and follow the surrounding surface language.

The project-level reference map is `ui-design-guide/README.md`.
