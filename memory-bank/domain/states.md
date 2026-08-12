---
title: LidSwitch Domain States
doc_kind: domain
doc_function: canonical
purpose: Пользовательски значимые состояния и переходы LidSwitch.
derived_from:
  - ../dna/governance.md
  - model.md
  - rules.md
status: active
audience: humans_and_agents
canonical_for:
  - domain_states
  - state_transitions
---

# Domain States

## Closed-Lid Policy

- `work`: пользователь выбрал продолжать работу с закрытой крышкой; valid
  daemon lease удерживает managed sleep inhibition.
- `sleep`: пользователь выбрал сон после outcome sound; valid daemon lease
  временно удерживает sleep до acknowledgement/deadline, затем возвращает native
  sleep и запрашивает системный сон.
- `unknown`: managed daemon/lease или effective policy не подтверждены; нельзя
  заявлять work или sleep.

Raw macOS `SleepDisabled` является implementation state, а не пользовательской
policy: в healthy managed `work` и `sleep` он временно true, а перед actual
sleep и без lease обязан быть false.

## Managed Control State

- `inactive`: valid app lease отсутствует; native sleep разрешён.
- `active(work)` / `active(sleep)`: authenticated app поддерживает lease.
- `pendingSleep(eventID)`: daemon ожидает bounded feedback acknowledgement.
- `failSafe`: lease/connection/deadline потеряны; native sleep восстановлен и
  при закрытой крышке daemon запрашивает sleep.

## Lid State

- `open`, `closed`, `unknown`.
- Значимый transition для issue #3: подтверждённый `open → closed`.
- Initial observation не считается transition. Повторная публикация `closed`
  также не является новой transition.

Sleep/wake — отдельный runtime lifecycle; wake сбрасывает rolling forecast
samples согласно текущей реализации и требует новой managed lease.
