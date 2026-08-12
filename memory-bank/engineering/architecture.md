---
title: LidSwitch Engineering Architecture
doc_kind: engineering
doc_function: canonical
purpose: Code boundaries, runtime adapters, concurrency and failure handling in LidSwitch.
derived_from:
  - ../dna/governance.md
  - ../domain/context-map.md
status: active
audience: humans_and_agents
---

# Engineering Architecture

| Module / layer | Owns | Boundary |
| --- | --- | --- |
| `LidSwitchCore` | deterministic policies, estimates, enum mappings | no AppKit/IOKit or privileged side effects |
| `LidSwitch` | AppKit lifecycle/UI, desired lid policy, `NSSound`, energy/helper adapter and persistent daemon client | UI consumes confirmed daemon policy; app never owns persistent privileged wake |
| `LidSwitchHelper` | fixed privileged energy-mode `pmset` execution | accepts only enumerated energy operations; no longer owns lid policy after FT-003 |
| `LidSwitchDaemonProtocol` | XPC constants, primitive contract enums and bilateral peer requirements | shared by app, daemon and probe; no arbitrary command surface |
| `LidSwitchDaemonCore` | deterministic lease, lid transition, acknowledgement and fail-safe state machine | no XPC, IOKit, AppKit, timers or privileged effects |
| `LidSwitchDaemon` | root Service Management runtime for managed lid policy | owns `disablesleep`, clamshell observation, deadlines and explicit sleep under ADR-001 |
| check executables | deterministic contract/regression checks | no mutating root operations |

AppKit callbacks and UI updates run on the main thread. Forecast sampling uses a
main-run-loop `Timer`; daemon replies are dispatched to main before UI mutation.
General deterministic product policy remains in `LidSwitchCore`; privileged
managed-lid lifecycle lives in `LidSwitchDaemonCore` and is serialized by the
daemon around explicit adapter actions.

Failures must not claim success. A missing/incompatible daemon or invalid lease
is UI `unknown`, never inferred from raw `SleepDisabled`. Managed control loss
must restore native sleep before optional explicit sleep. Cancelled
authorization is silent; other interactive failures are shown to the user.
No database, remote API or retry queue exists; active leases are in-memory only.

Configuration owners are `Package.swift`, `Resources/Info.plist`, launchd plist,
and narrowly named build/release environment variables documented in
`../ops/config.md`.
