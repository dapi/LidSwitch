---
title: LidSwitch Domain Context Map
doc_kind: domain
doc_function: canonical
purpose: Language ownership между macOS power state, LidSwitch policy и feedback.
derived_from:
  - ../dna/governance.md
  - glossary.md
  - model.md
status: active
audience: humans_and_agents
canonical_for:
  - bounded_contexts
  - domain_context_map
---

# Domain Context Map

| Context | Owns | Upstream | Downstream | Must not know |
| --- | --- | --- | --- | --- |
| macOS power state | actual lid, battery, sleep and energy values | hardware/macOS | observation adapter | LidSwitch UI assumptions |
| LidSwitch policy | interpretation, forecast and safe mutation intent | macOS power state | UI feedback | arbitrary root commands |
| User feedback | icon, menu, popover and sound presentation | LidSwitch policy | user | undocumented IOKit details |

Technical module mapping lives in `../engineering/architecture.md`. There is no
server-side bounded context or remote integration in the shipped desktop app.
