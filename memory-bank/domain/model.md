---
title: LidSwitch Domain Model
doc_kind: domain
doc_function: canonical
purpose: Ключевые concepts и relationships closed-lid поведения.
derived_from:
  - ../dna/governance.md
  - glossary.md
status: active
audience: humans_and_agents
canonical_for:
  - domain_model
  - domain_concepts
---

# Domain Model

| Concept | Kind | Represents | Relationships |
| --- | --- | --- | --- |
| Closed-lid policy | state/value | продолжение работы, разрешение сна или unknown | влияет на status UI и feedback |
| Lid state | state/value | open, closed или unreadable | переход open → closed запускает feedback |
| Energy mode | value | low, automatic, high или unknown | выбирает forecast profile |
| Battery snapshot | value | источник питания, заряд и forecast source | input прогноза |
| Privileged operation | command enum | разрешённое системное изменение | исполняется helper/daemon boundary |

MacOS/IOKit владеет фактическим lid и sleep state. LidSwitch читает эти факты,
показывает их и запрашивает изменение через узкую privileged boundary; UI state
не является самостоятельным source of truth.
