---
title: LidSwitch Product Metrics
doc_kind: product
doc_function: canonical
purpose: Текущие quality signals и пробелы product measurement LidSwitch.
derived_from:
  - ../dna/governance.md
  - context.md
status: active
audience: humans_and_agents
canonical_for:
  - product_metrics
  - success_measurement
---

# Product Metrics

Product analytics и числовые targets не реализованы и не должны выдумываться.
До появления instrumentation используются quality guardrails:

| Guardrail | Threshold | Evidence |
| --- | --- | --- |
| Ложное отображение/подтверждение closed-lid state | 0 известных случаев в acceptance matrix | `QA.md` |
| Выход privileged helper за allowlist | 0 операций вне фиксированного списка | core checks и M2 verification scripts |
| Crash, hang или duplicate status item | 0 в ручном smoke | `QA.md` |

Owner и cadence product metrics: Unknown; требует решения владельца продукта.
