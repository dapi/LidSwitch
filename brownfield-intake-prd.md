# Brownfield intake: LidSwitch

Date: 2026-08-12

Status: temporary discovery evidence for initial Memory Bank adoption. This
document is not a canonical owner after conversion.

## Product problem and users

LidSwitch is a small native macOS menu-bar application for Apple-silicon
MacBooks. It lets a user choose whether the Mac continues working or may sleep
when its lid closes, and makes the current system-reported state visible.

- Evidence: `README.md:1-29`, `README.ru.md:1-28`.
- Confidence: high; current public product documentation.
- Owner: repository/product owner (`dapi`).

The current UI also exposes macOS energy modes and estimates remaining active
battery runtime with the lid closed.

- Evidence: `README.md:16-29`, `Sources/LidSwitch/main.swift:8-44`.
- Confidence: high; documentation and implementation agree.
- Owner: repository/product owner (`dapi`).

## Goals and success signals

- Keep the actual closed-lid policy easy to inspect and switch from the menu
  bar. Evidence: `README.md:10-20`, `Sources/LidSwitch/main.swift:148-211`.
- Reflect the value read back from macOS instead of persisting an independent
  guess. Evidence: `README.md:97-104`, `Sources/LidSwitch/main.swift:408-421`.
- Keep privileged mutations narrowly scoped to a fixed operation allowlist.
  Evidence: `README.md:81-91`, `Sources/LidSwitchCore/PrivilegedHelperOperation.swift`.
- Avoid false-success UI and unsafe closed-lid testing. Evidence: `QA.md:58-72`,
  `QA.md:122-138`.

Observed success checks are the automated build/security checks in CI and the
manual real-MacBook matrix in `QA.md`. Product analytics, usage targets, SLOs,
and a formal support policy are unknown.

## Non-goals and current boundaries

- The supported runtime is macOS 15+ on Apple-silicon MacBooks. Evidence:
  `README.md:31-34`, `Package.swift:6-10`, `Resources/Info.plist`.
- Mac App Store distribution is not the selected current path because the app
  relies on privileged, undocumented power-management behavior. Evidence:
  `docs/discovery/mac-app-store-feasibility.md:8-22`.
- An iPhone companion and automatic critical-temperature sleep are not part of
  the current shipped application. Evidence:
  `docs/discovery/iphone-companion-feasibility.md:185-224`.
- Release/deployment execution is outside the scope of the initial adoption and
  issue #3 implementation.

## Runtime inventory and boundaries

| Area | Observed fact | Evidence | Confidence / freshness |
| --- | --- | --- | --- |
| App UI | `LidSwitch` is an AppKit status-item executable. `ApplicationDelegate` owns menu actions, state refresh, confirmations, and IOKit reads. | `Sources/LidSwitch/main.swift`; `Resources/Info.plist` | High; current code |
| Testable policy | Forecasting, energy-mode parsing, estimates, and privileged operation mapping live in `LidSwitchCore`. | `Package.swift`; `Sources/LidSwitchCore/`; `Tests/LidSwitchCoreChecks/main.swift` | High; current code |
| Forecast adapter | `ClosedLidForecastController` samples battery, display, and clamshell state through IOKit every ten seconds and after wake. | `Sources/LidSwitch/ClosedLidForecastController.swift` | High; current code |
| Privileged helper | A bundled helper executes only fixed `pmset` operations selected by `PrivilegedHelperOperation`. | `Sources/LidSwitchHelper/main.swift`; `Sources/LidSwitch/PrivilegedHelperManager.swift`; `Sources/LidSwitchCore/PrivilegedHelperOperation.swift` | High; current code |
| M2 migration spike | A Service Management daemon, XPC protocol, and unauthorized-client probe coexist with the current helper as a migration experiment. | `docs/discovery/m2-spike-result.md`; `Sources/LidSwitchDaemon*`; `Sources/LidSwitch/ServiceManagedDaemonManager.swift` | High; dated 2026-08-11 |
| Persistence | Learned battery wattage is stored in `UserDefaults`, keyed by energy mode. No database or network service is present. | `Sources/LidSwitch/ClosedLidForecastController.swift:31-57` | High; current code |
| External integrations | IOKit/IOPowerSources, AppKit, `pmset`, Authorization Services, sudoers, Service Management/XPC, code signing and notarization. | `Package.swift`; `README.md`; `Sources/`; `Scripts/` | High; current code/docs |

There are no observed HTTP APIs, queues, webhooks, scheduled server jobs,
remote data stores, or server environments.

## Development, testing, and delivery inventory

- SwiftPM 6.1 defines four executable products plus two check executables;
  the package targets macOS 15 and uses Swift language mode 5. Evidence:
  `Package.swift`.
- Local baseline checks are `swift run LidSwitchCoreChecks` and `swift build`;
  real lid, sleep, battery, and helper lifecycle behavior requires a physical
  MacBook. Evidence: `README.md:121-127`, `QA.md:7-56`.
- GitHub Actions runs on `macos-15`, builds the package, and executes debug and
  release M2 verification scripts. Evidence: `.github/workflows/ci.yml`.
- Packaging is performed by `Scripts/package-release.sh`; it builds and signs
  an app bundle, then creates a versioned arm64 ZIP and checksum. Evidence:
  `Scripts/build-app.sh`, `Scripts/archive-app.sh`, `Scripts/package-release.sh`.
- Developer ID signing/notarization is supported by
  `Scripts/notarize-release.sh`; credential values remain in the keychain/env
  and are intentionally not recorded here.
- The latest repository tag observed during discovery is `v0.7.0`; freshness:
  2026-08-12 local checkout.
- Rollback procedure, release approver, branch-protection rules, incident
  response, monitoring, crash reporting, and SLOs are unknown.

## Existing decision and documentation inventory

- `README.md` and `README.ru.md`: public behavior, installation, safety, and
  architecture overview; current at version 0.7.0.
- `QA.md`: canonical observed test matrix and pass criteria for current runtime.
- `docs/discovery/fpf-decision-record.md`: ratified product/architecture
  direction and decision evidence, dated by adjacent discovery work in August
  2026.
- `docs/discovery/mac-app-store-feasibility.md`: distribution constraints and
  current direct-distribution direction.
- `docs/discovery/iphone-companion-feasibility.md`: companion scope and deferred
  decisions.
- `docs/discovery/m2-spike-result.md`: evidence and limitations of the Service
  Management daemon migration spike, dated 2026-08-11.

These sources remain canonical for their existing detailed evidence; Memory
Bank owners should link to them rather than duplicate full research records.

## Real-task trial scope: GitHub issue #3

Problem: when the lid closes, the user cannot hear whether the Mac will continue
working or enter sleep. Expected outcome: play one of two readily
distinguishable sounds according to the last known `SleepDisabled` state.

Acceptance evidence source: GitHub issue `dapi/LidSwitch#3`, created 2026-08-12.
The issue requires one sound on the open-to-closed transition, distinct sounds
for work and sleep, no duplicate sound, no misleading sound for unknown state,
and respect for system volume/mute.

Open implementation questions from the issue are whether to use system or
custom sounds and whether to expose a sound preference. For the smallest
compatible change, system sounds and no new preference are assumptions pending
routing; custom bundled assets or preferences would widen the product and
packaging surface.

## Risks, conflicts, and open questions

- `AppleClamshellState`, `SleepDisabled`, and `pmset disablesleep` are not stable
  public application contracts. Evidence:
  `docs/discovery/fpf-decision-record.md:58-73`. Owner: product/engineering.
- A Mac may sleep immediately after the lid transition. The implementation must
  observe the transition early enough for the sleep sound to be audible; exact
  timing requires manual validation on hardware. Owner: engineering.
- Reading a missing clamshell property currently falls back to `false`, which
  cannot distinguish “open” from “unknown.” Issue #3 must not turn an unknown
  reading into a misleading sound. Evidence:
  `Sources/LidSwitch/ClosedLidForecastController.swift:105-118`. Owner:
  engineering.
- Sound choice is not specified beyond distinguishability. Assumption for the
  trial: use two built-in macOS sounds, avoiding new binary assets and their
  licensing/packaging lifecycle. Owner confirmation remains possible during
  review.
- Whether sound feedback should be configurable is explicitly unresolved in
  issue #3 and is excluded from the first implementation unless requested.

## Intentionally unadapted

- Full research evidence, command transcripts, and fixture hashes from
  `docs/discovery/` remain in their existing owners.
- Generated `.build/` and `dist/` artifacts are not project facts.
- Secrets, signing identities, notary profiles, private keys, and credential
  values are not copied.
- iPhone companion implementation, cloud schema, analytics, observability, SLO,
  and deployment environments are not invented where no implementation exists.
