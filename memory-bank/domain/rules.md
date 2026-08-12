---
title: LidSwitch Domain Rules
doc_kind: domain
doc_function: canonical
purpose: Инварианты closed-lid state, feedback и privileged operations.
derived_from:
  - ../dna/governance.md
  - model.md
status: active
audience: humans_and_agents
canonical_for:
  - domain_rules
  - domain_invariants
---

# Domain Rules

| Rule | Invariant | Source |
| --- | --- | --- |
| `DR-01` | Пользовательское состояние следует read-back macOS, а не optimistic guess | `README.md`, `QA.md` |
| `DR-02` | Unknown state не подтверждается как work или sleep | `README.md`, issue #3 |
| `DR-03` | Одна пользовательская/физическая transition даёт не более одного feedback signal каждого типа | `QA.md`, issue #3 |
| `DR-04` | Приложение не обходит системную громкость или mute | issue #3 |
| `DR-05` | Privileged boundary принимает только перечисленные операции без произвольных аргументов | helper code и core checks |
| `DR-06` | Closed-lid work сопровождается safety warning о батарее и тепле | `README.md` |
| `DR-07` | При valid managed policy автоматический lid sleep удерживается до outcome; sleep policy завершает звук до explicit sleep, кроме bounded fail-safe timeout | issue #3, ADR-001 |
| `DR-08` | Privileged wake существует только под живой authenticated lease; loss/restart возвращает native sleep и не сохраняет lease на диск | ADR-001 |
| `DR-09` | Desired closed-lid policy и raw `SleepDisabled` не взаимозаменяемы; UI подтверждает только effective managed policy | ADR-001 |

Изменение этих shared rules требует обновить этот owner до или вместе с
delivery artifact.
