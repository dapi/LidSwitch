---
title: LidSwitch Testing Policy
doc_kind: engineering
doc_function: canonical
purpose: Automated and manual validation contract for LidSwitch changes.
derived_from:
  - ../dna/governance.md
  - ../flows/feature.md
  - validation-profiles.md
status: active
audience: humans_and_agents
canonical_for:
  - repository_testing_policy
  - automated_test_requirements
  - manual_only_verification_exceptions
---

# Testing Policy

## Automated Baseline

Run at minimum:

```sh
swift run LidSwitchCoreChecks
swift run LidSwitchDaemonProtocolChecks
swift build
git diff --check
```

For changes touching the app bundle, daemon, helper or signing boundary also run:

```sh
./Scripts/verify-m2-spike.sh debug
./Scripts/verify-m2-update-fixtures.sh debug
./Scripts/verify-m2-spike.sh release
```

CI on `macos-15` runs the build and all three M2 verification steps.

## Coverage Rules

- Deterministic policy belongs in `LidSwitchCore` and must receive executable
  regression checks in `Tests/LidSwitchCoreChecks/main.swift`.
- Protocol/security contracts receive checks in
  `Tests/LidSwitchDaemonProtocolChecks/main.swift` and verification scripts.
- Changed behavior covers main, duplicate/negative and unknown/error paths.
- Do not invoke mutating helper operations as root during automated checks.

## Manual-Only Surface

Actual lid transitions, immediate sleep timing, sound audibility, battery,
backlight, thermal behavior, authorization UI and Service Management approval
require a real supported MacBook. Record model, macOS build, power source and
external-display state for failures. Follow `QA.md` and never test active
closed-lid work inside a bag or enclosed space.

After tests, perform an implementation review and a separate simplify pass.
