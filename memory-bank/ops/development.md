---
title: LidSwitch Development Environment
doc_kind: ops
doc_function: canonical
purpose: Local setup, build, test and native UI verification commands.
derived_from:
  - ../dna/governance.md
status: active
audience: humans_and_agents
---

# Development Environment

Requirements: macOS, Swift toolchain from Xcode Command Line Tools, and a
supported Apple-silicon MacBook for hardware-dependent manual checks. Full Xcode
is needed for some notarization/Service Management live gates, not core builds.

```sh
swift build
swift run LidSwitchCoreChecks
swift run LidSwitchDaemonProtocolChecks
./Scripts/build-app.sh debug
open dist/LidSwitch.app
```

There is no browser, database, container stack, seeded data or external local
service. UI verification is performed against the built native app. Do not run
mutating helper operations directly as root during routine automated checks.

Generated `.build/` and `dist/` directories are ignored. See `QA.md` for the
physical MacBook matrix.
