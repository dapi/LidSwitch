---
title: "PRD-000: Existing LidSwitch Product Baseline"
doc_kind: prd
doc_function: canonical
purpose: Фиксирует подтверждённую продуктовую baseline существующего LidSwitch и границы initial Memory Bank adoption.
derived_from:
  - ../product/context.md
  - ../product/customers.md
  - ../domain/model.md
  - ../domain/rules.md
status: draft
audience: humans_and_agents
must_not_define:
  - implementation_sequence
  - architecture_decision
  - feature_level_verify_contract
---

# PRD-000: Existing LidSwitch Product Baseline

## Problem

До initial Memory Bank adoption устойчивый контекст LidSwitch был распределён
между README, QA, source code и discovery records. Delivery должна сохранять
наблюдаемое поведение и safety boundaries, не превращая template placeholders
или неподтверждённые предположения в product facts.

## Users And Jobs

| User | Job To Be Done | Current Pain |
| --- | --- | --- |
| Владелец Apple-silicon MacBook | Понять и выбрать исход закрытия крышки | Системная policy неочевидна без UI/CLI знания |
| Пользователь фоновой задачи | Осознанно продолжить работу с закрытой крышкой | Риск случайного сна, расхода батареи или перегрева |

## Goals

- Сохранить single source of truth в macOS read-back для lid policy.
- Сделать work, sleep и unknown различимыми без false success.
- Сохранить узкую privileged boundary и воспроизводимые проверки.
- Дать последующим задачам evidence-backed product, domain, engineering и ops context.

## Non-Goals

- Изобретать analytics, SLO, enterprise deployment или customer segments.
- Обещать App Store compatibility.
- Доставлять iPhone companion или automatic thermal sleep.
- Выполнять release/publication в рамках adoption.

## Product Scope

In scope: native menu-bar UI, actual macOS closed-lid state, energy modes,
battery forecast, helper/daemon boundaries, packaging and supported-hardware QA.

Out of scope: remote/cloud services, server environments, database, web UI,
fleet administration and unapproved release operations.

## Success Signals

- `memory-bank-cli lint` and `doctor` pass after adaptation.
- Existing automated checks remain green.
- One real issue is routed and delivered through a canonical flow.
- Unknown/conflicting facts remain explicitly marked rather than guessed.

## Risks And Open Questions

- Confidence high: runtime modules and public behavior, evidenced by current
  code, `README.md`, `README.ru.md`, `QA.md`, `Package.swift` and CI.
- Confidence medium: future Service Management direction; live production gate
  is still evidence-pending in `docs/discovery/m2-spike-result.md`.
- Unknown: product metric owner, release approver, rollback procedure,
  observability/crash reporting and formal support policy.
- Platform risk: IOKit property names and `pmset` keys are undocumented or not
  guaranteed stable; see `docs/discovery/fpf-decision-record.md`.

## Provenance And Retention

The temporary `brownfield-intake-prd.md` preserves discovery inventory,
source references, confidence and intentionally unadapted material. This PRD
owns only the adopted initiative baseline; durable project-wide facts remain in
their upstream product/domain/engineering/ops owners.
