---
title: "ADR-001: Delegate Managed Lid Sleep To A Fail-Safe Daemon"
doc_kind: adr
doc_function: canonical
purpose: Фиксирует владельца controlled lid-close sequencing, lease semantics и fail-safe возврат к системному сну.
derived_from:
  - ../features/FT-003/brief.md
  - ../engineering/architecture.md
status: active
decision_status: accepted
date: 2026-08-12
decision_makers:
  - Danil Pismenny
consulted: []
informed: []
audience: humans_and_agents
must_not_define:
  - current_system_state
  - implementation_plan
---

# ADR-001: Delegate Managed Lid Sleep To A Fail-Safe Daemon

## Контекст

FT-003 должна гарантировать, что при закрытии крышки пользователь слышит разные
звуки для `work` и `sleep`. В режиме `sleep` звук должен завершиться до начала
сна, после чего LidSwitch сам запрашивает сон.

Нативный lid-close sleep начинается вскоре после clamshell notification, а
публичные power assertions не отменяют этот вид сна. Значит, гарантированная
последовательность требует временно держать `disablesleep=1`. App-only ownership
небезопасен: crash или kill приложения может оставить закрытый Mac работающим и
нагревающимся в сумке. Нужен владелец privileged state, который переживает app
и при потере управления возвращает систему в безопасный режим.

## Границы решения

- Решение действует для lid policy, clamshell events, app-daemon XPC и явного
  system sleep в LidSwitch.
- Energy modes остаются в существующем helper boundary.
- Distribution approval, notarization и hardware acceptance не принимаются
  этим ADR; они остаются delivery/ops gates.

## Драйверы решения

1. Закрытый Mac не должен оставаться бодрствовать после потери app или XPC.
2. В healthy path daemon не должен отдавать lid-close sleep macOS до завершения
   звука.
3. Решение должно быть детерминированно тестируемым без физического закрытия
   крышки.
4. Privileged interface должен оставаться перечисленным и узким, без
   произвольных shell arguments.
5. Миграция должна использовать уже встроенный Service Management daemon.

## Рассмотренные варианты

| Вариант | Плюсы | Минусы | Итог |
| --- | --- | --- | --- |
| Нативный сон и best-effort звук | Нет нового privileged lifecycle; простая реализация | Нельзя гарантировать завершение звука; не выполняет REQ-06 | Отклонён |
| App держит `disablesleep=1` и сама вызывает сон | Меньше XPC protocol; app знает playback state | App crash может навсегда оставить закрытый Mac бодрствовать | Отклонён |
| Service Management daemon владеет краткой lease и deadline | Fail-safe переживает app; privileged state и lid events у одного owner; подходит существующий daemon | Нужны persistent XPC, heartbeat, timers и hardware gate | Принят |
| Отдельный новый watchdog/helper | Можно изолировать только lid workflow | Ещё один deployable, approval/update lifecycle и trust boundary без дополнительной пользы | Отклонён |

## Решение

Использовать существующий root `LidSwitchDaemon` как единственного runtime owner
managed lid policy:

- app хранит пользовательский desired policy (`work` или `sleep`) и открывает
  authenticated persistent XPC connection;
- daemon выдаёт in-memory lease только живому authenticated app, включает
  `disablesleep=1` и требует heartbeat;
- daemon наблюдает подтверждённый `open -> closed` transition;
- для `work` daemon уведомляет app, но не запрашивает сон;
- для `sleep` daemon уведомляет app и запускает короткий deadline; app
  проигрывает sleep sound и подтверждает завершение с daemon-generated event ID;
- при корректном acknowledgement daemon сначала возвращает `disablesleep=0`,
  затем вызывает системный sleep;
- при deadline, invalidation, heartbeat expiry или daemon startup без lease
  daemon возвращает `disablesleep=0`; если крышка закрыта или pending sleep уже
  начат, daemon также запрашивает system sleep;
- lease, acknowledgement и heartbeat принимаются только от текущего
  authenticated connection; daemon не принимает команды или пути shell от app;
- после wake app создаёт новую lease. Daemon не сохраняет lease или
  `disablesleep=1` на диск.

Таким образом LidSwitch владеет последовательностью только пока обе стороны
healthy. При control failure ownership безопасно возвращается macOS.

## Последствия

### Положительные

- Звук и сон имеют явный order, а не timing race с нативным lid sleep.
- Crash app не оставляет бессрочный privileged wake state.
- Pure state machine может проверить duplicates, stale acknowledgements,
  deadline и lease loss без IOKit/AppKit.
- XPC boundary остаётся capability-based и не допускает произвольных команд.

### Отрицательные

- Работа требует одобрения Service Management daemon пользователем.
- App и daemon получают heartbeat/timer/reconnect lifecycle и больше failure
  branches.
- Crash daemon в режиме `work` безопасно деградирует к нативному сну и может
  прервать ожидаемую фоновую работу.
- Недокументированный `pmset disablesleep` остаётся compatibility risk и требует
  проверки на поддерживаемом MacBook.

### Нейтральные / организационные

- Existing M2 spike перестаёт быть экспериментальным check-version-only
  surface и становится production runtime boundary.
- Living domain/runtime facts переходят в domain docs, engineering architecture
  и FT-003 contract; ADR хранит только выбор и rationale.

## Риски и mitigation

| Риск | Mitigation |
| --- | --- |
| App завис, но XPC connection не оборвался | Heartbeat expiry снимает lease |
| Sound callback не приходит | Bounded feedback deadline инициирует fail-safe sleep |
| Late/stale acknowledgement | Event ID + current-connection ownership; stale ack ignored |
| `IOPMSleepSystem` fails | Сначала restore `disablesleep=0`, чтобы native lid sleep снова был доступен |
| Daemon dies while owning wake | launchd restart starts by restoring `disablesleep=0`; no persistent lease |
| Mixed app/daemon versions | Exact protocol version handshake; incompatible peer does not receive lease |

## Confirmation

- Owner: implementing agent records automated outputs in FT-003 evidence.
- Pure state-machine checks cover activation, work close, sleep ack, feedback
  deadline, lease expiry, stale ack, duplicate lid events and wake reactivation.
- XPC protocol checks verify the exact enumerated method/callback surface,
  code-signing requirements and no arbitrary argument operation.
- Repository build and existing M2 verification remain green.
- Danil performs the FT-003 `QA.md` hardware matrix: both sounds, mute, explicit
  post-sound sleep, app kill, XPC loss and daemon restart with lid closed.
- The implementation plan and issue/PR retain links to those evidence records.

## Условия пересмотра

- macOS provides a supported API that delays only lid sleep until feedback ends;
- `disablesleep` or clamshell notifications stop working on supported macOS;
- Service Management lifecycle cannot satisfy the hardware failure matrix;
- product policy changes from fail-safe sleep to persistent unattended work.

## Follow-up

- `memory-bank/features/FT-003/design.md` owns target architecture and failures.
- `memory-bank/features/FT-003/contracts/managed-lid-control.md` owns XPC and
  lease contract.
- `memory-bank/domain/{states,rules,events}.md` owns living semantics.
- `memory-bank/engineering/architecture.md` owns module/runtime boundaries.
- FT-003 implementation and QA provide confirmation evidence.

## Связанные ссылки

- [FT-003 brief](../features/FT-003/brief.md)
- [GitHub issue #3](https://github.com/dapi/LidSwitch/issues/3)
- [Apple `IOPMSleepSystem`](https://developer.apple.com/documentation/iokit/1557121-iopmsleepsystem)
