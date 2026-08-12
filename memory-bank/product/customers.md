---
title: LidSwitch Customers And Users
doc_kind: product
doc_function: canonical
purpose: Пользователи LidSwitch, их jobs и подтверждённые ограничения.
derived_from:
  - ../dna/governance.md
  - context.md
status: active
audience: humans_and_agents
canonical_for:
  - product_customers
  - user_segments
  - jobs_to_be_done
---

# Customers And Users

| Segment | Job To Be Done | Current Pain | Success Signal | Evidence |
| --- | --- | --- | --- | --- |
| Владелец Apple-silicon MacBook | Быстро выбрать и проверить исход закрытия крышки | Системный режим неочевиден, CLI неудобен | Исход виден и переключается из menu bar без ложного подтверждения | `README.md`, `QA.md` |
| Пользователь долгой фоновой задачи | Оставить задачу работать с закрытой крышкой осознанно | Риск случайного сна либо перегрева в сумке | Пользователь видит активный режим и safety warning | `README.md:10-29,91-95` |

Владельцем продукта и текущим decision owner считается repository owner
`dapi`. Отдельные buyer/admin роли, customer research и подтверждённые сегменты
не обнаружены.

Нельзя молча предполагать наличие enterprise deployment, fleet management,
iPhone companion или потребность обходить системную громкость/mute.
