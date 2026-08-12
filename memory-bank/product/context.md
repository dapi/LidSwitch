---
title: LidSwitch Product Context
doc_kind: product
doc_function: canonical
purpose: Каноничный общий контекст продукта LidSwitch, его workflows, outcomes и ограничения.
derived_from:
  - ../dna/governance.md
status: active
audience: humans_and_agents
canonical_for:
  - project_product_context
  - product_problem_space
  - top_level_outcomes
---

# LidSwitch Product Context

LidSwitch — небольшое нативное menu-bar приложение для владельцев MacBook с
Apple silicon. Оно показывает и переключает реальное системное поведение при
закрытии крышки: продолжить работу или разрешить обычный сон. Дополнительно оно
показывает прогноз активной работы от батареи и управляет режимом энергии.

Главная ценность — быстро понять и изменить потенциально опасное для батареи и
температуры поведение без командной строки и без повторного запроса пароля.

## Core Workflows

- `WF-01`: увидеть в menu bar текущий исход закрытия крышки.
- `WF-02`: левым кликом переключить closed-lid policy и получить подтверждение.
- `WF-03`: правым кликом открыть подробный статус, прогноз, energy mode и helper lifecycle.
- `WF-04`: безопасно собрать, проверить и выпустить подписанный macOS app bundle.

## Top-Level Outcomes

- UI совпадает со значением, прочитанным из macOS, и не показывает ложный успех.
- Переключение после корректной установки helper не требует повторной авторизации.
- Пользователь явно различает режим продолжения работы, сна и неизвестное состояние.

Числовые product metrics и instrumentation отсутствуют; canonical quality
signals пока заданы automated и manual checks в `QA.md`.

## Product Constraints

- Поддерживаются MacBook с Apple silicon и macOS 15+.
- Работа с закрытой крышкой может расходовать батарею и выделять тепло; продукт
  обязан сохранять явное safety messaging.
- UI должен отражать read-back macOS, а не отдельную сохранённую догадку.
- Direct distribution остаётся текущим путём; Mac App Store compatibility не
  подтверждена из-за privileged и undocumented power-management contracts.

## Source Documents

- `README.md` и `README.ru.md` — публичный продуктовый контракт.
- `QA.md` — проверяемые runtime expectations и safety matrix.
- `docs/discovery/fpf-decision-record.md` — ратифицированное направление.
