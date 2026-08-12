---
title: LidSwitch Runtime Environments
doc_kind: ops
doc_function: canonical
purpose: Applicable local, hardware-validation and public distribution environments.
derived_from:
  - ../dna/governance.md
status: active
audience: humans_and_agents
---

# Runtime Environments

| Environment | Purpose | Access / evidence |
| --- | --- | --- |
| local development | compile and deterministic checks | SwiftPM and `Scripts/build-app.sh` |
| supported MacBook | manual lid, battery, sound, helper and Service Management validation | `QA.md`; record hardware/macOS facts |
| public distribution | GitHub Release and Homebrew installation | repository release assets and public README |

There is no server production, staging, database, health endpoint, centralized
logs, metrics or traces. Release artifacts and M2 live-gate evidence are written
under ignored `dist/` paths. Live privileged, signing, notarization and
distribution operations require their documented credentials and approval.
