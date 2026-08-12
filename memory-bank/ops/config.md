---
title: LidSwitch Configuration Guide
doc_kind: ops
doc_function: canonical
purpose: Build, bundle, persisted preference and credential ownership.
derived_from:
  - ../dna/governance.md
status: active
audience: humans_and_agents
---

# Configuration Guide

| Owner | Configuration |
| --- | --- |
| `Package.swift` | products, targets, platform and Swift mode |
| `Resources/Info.plist` | bundle identity, version and minimum macOS |
| `Resources/me.dapi.LidSwitch.Daemon.plist` | launchd daemon label/program/service |
| `UserDefaults` | learned closed-lid wattage by energy mode |
| environment | build/release inputs listed below |

Important environment variables are `LIDSWITCH_CODESIGN_IDENTITY`,
`LIDSWITCH_M2_PROTOCOL_VARIANT`, `LIDSWITCH_NOTARY_PROFILE`,
`LIDSWITCH_NOTARY_TIMEOUT`, `LIDSWITCH_LIVE_APP_PATH`,
`LIDSWITCH_M2_EVIDENCE_TAG` and `LIDSWITCH_M2_UPDATE_ID`. Their validation and
defaults are owned by the scripts that read them.

Signing identities and notary credentials live in macOS Keychain/environment;
never record their values in Memory Bank or repository files. There is no
application `.env`, remote config or feature-flag service.
