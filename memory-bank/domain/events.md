---
title: LidSwitch Domain Events
doc_kind: domain
doc_function: canonical
purpose: Значимые факты closed-lid workflow без привязки к transport.
derived_from:
  - ../dna/governance.md
  - model.md
  - rules.md
status: active
audience: humans_and_agents
canonical_for:
  - domain_events
  - business_events
---

# Domain Events

| Event | Meaning | Producer | Consumers | Minimal facts |
| --- | --- | --- | --- | --- |
| Lid closed | Подтверждён переход open → closed | daemon macOS observation adapter | managed lid policy and app feedback | previous=open, current=closed, daemon event ID when leased |
| Lid opened | Подтверждён переход closed → open | macOS observation adapter | forecast policy | previous=closed, current=open |
| Closed-lid policy changed | Daemon accepted a new authenticated lease policy | app/daemon boundary | UI and managed lid policy | confirmed desired/effective policy |
| Feedback completed | App завершил outcome sound для текущего close event | app audio adapter | daemon managed sleep policy | event ID |
| Managed control lost | Connection, heartbeat or feedback deadline перестали быть valid | daemon lease controller | fail-safe sleep policy | reason, current lid, pending event if any |
| System woke | Workspace сообщил wake | macOS | forecast and lease lifecycle | occurrence |

Это domain facts, не публичная queue schema; app-daemon transport принадлежит
FT-003 managed-lid contract.
