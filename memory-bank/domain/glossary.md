---
title: LidSwitch Domain Glossary
doc_kind: domain
doc_function: canonical
purpose: Каноничный язык поведения крышки и питания в LidSwitch.
derived_from:
  - ../dna/governance.md
status: active
audience: humans_and_agents
canonical_for:
  - ubiquitous_language
  - domain_terms
---

# Domain Glossary

| Term | Meaning | Do not confuse with |
| --- | --- | --- |
| Closed-lid work | Mac продолжает выполнять задачи после закрытия крышки, потому что system sleep disabled | Обычный внешний-display clamshell workflow |
| Allow sleep | LidSwitch не запрещает системный сон при закрытии крышки | Гарантия мгновенного сна при любых внешних условиях |
| Closed-lid policy | Текущий read-back `SleepDisabled`: work, sleep или unknown | Сохранённая UI preference |
| Lid transition | Наблюдаемый переход крышки open → closed или closed → open | Sleep/wake notification |
| Forecast | Оценка активного времени от батареи с закрытой крышкой | Обещание точной автономности |
| Energy mode | Low Power, Automatic или High Power, прочитанный/установленный через `pmset` | Closed-lid policy |
| Helper | Привилегированный executable с фиксированным allowlist операций | Произвольный root shell |

Canonical language sources: `README.md`, `README.ru.md`, `QA.md` и текущий UI.
