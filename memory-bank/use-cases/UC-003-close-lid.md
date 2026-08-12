---
title: "UC-003: Close The Mac Lid"
doc_kind: use_case
doc_function: canonical
purpose: Фиксирует наблюдаемый пользовательский сценарий закрытия крышки при выбранной политике LidSwitch.
derived_from:
  - ../flows/use-case.md
  - ../product/context.md
  - ../domain/rules.md
  - ../domain/states.md
status: active
audience: humans_and_agents
must_not_define:
  - implementation_sequence
  - architecture_decision
  - feature_level_test_matrix
---

# UC-003: Close The Mac Lid

## Goal

Пользователь закрывает крышку и по звуку понимает, продолжит ли Mac работать или
заснёт; фактический outcome соответствует выбранной политике.

## Primary Actor

Пользователь LidSwitch на MacBook.

## Trigger

Подтверждённый переход крышки из открытого состояния в закрытое.

## Preconditions

- LidSwitch работает и знает выбранную политику `work` или `sleep`.
- Управление закрытием крышки готово; неизвестное состояние не выдаётся за
  подтверждённую политику.

## Main Flow

1. Пользователь закрывает крышку.
2. LidSwitch воспроизводит один звук, соответствующий выбранной политике.
3. При `work` Mac продолжает работать; при `sleep` Mac засыпает после звука.

## Alternate Flows / Exceptions

- `ALT-01`: При mute/нулевой громкости outcome сохраняется без слышимого звука.
- `EX-01`: При потере управления LidSwitch возвращает Mac к безопасному пути
  системного сна; закрытый Mac не остаётся бессрочно бодрствовать.
- `EX-02`: При unknown lid/policy LidSwitch не воспроизводит вводящий в
  заблуждение outcome sound.

## Postconditions

- Успех: пользовательский policy и фактический closed-lid outcome совпадают.
- Failure: privileged wake не остаётся без живого управляющего процесса.

## Business Rules

- `BR-01`: Один open-to-closed transition даёт не более одного outcome sound.
- `BR-02`: Sleep sound завершается до запроса сна.
- `BR-03`: System volume/mute остаются авторитетными.

## Traceability

| Upstream / Downstream | References |
| --- | --- |
| PRD | `none` |
| Features | `FT-003` |
| ADR | `ADR-001` |
| Runbooks / Ops | `QA.md` |
