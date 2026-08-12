---
title: LidSwitch Product Vision
doc_kind: product
doc_function: canonical
purpose: Устойчивое направление, experience principles и non-goals LidSwitch.
derived_from:
  - ../dna/governance.md
  - context.md
status: active
audience: humans_and_agents
canonical_for:
  - product_vision
  - product_strategy_principles
---

# Product Vision

LidSwitch должен делать закрытие крышки предсказуемым: пользователь заранее и
в момент действия понимает, будет ли Mac работать или уснёт, а приложение не
скрывает ограничения и риски выбранного режима.

## Experience Principles

- Фактическое состояние macOS важнее optimistic UI.
- Основное действие остаётся быстрым и доступным из одной status-item иконки.
- Неизвестное состояние показывается как неизвестное, а не угадывается.
- Safety и узкая privileged boundary важнее удобства автоматизации.

## Product Non-Goals

- Обход системного mute/volume.
- Автоматический сон по температуре без отдельного явного решения владельца.
- Обещание Mac App Store distribution до подтверждения поддерживаемого API.
- Реализация iPhone companion в текущем desktop product scope.

Источник направления: `docs/discovery/fpf-decision-record.md`.
