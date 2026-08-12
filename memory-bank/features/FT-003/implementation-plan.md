---
title: "FT-003: Implementation Plan"
doc_kind: feature
doc_function: derived
purpose: Execution-план daemon-owned lid feedback и fail-safe sleep для FT-003.
derived_from:
  - brief.md
  - design.md
  - contracts/managed-lid-control.md
  - ../../adr/ADR-001-daemon-owned-lid-sleep.md
status: active
audience: humans_and_agents
must_not_define:
  - ft_003_scope
  - ft_003_selected_design
  - ft_003_acceptance_criteria
  - ft_003_blocker_state
  - ft_003_validation_profile
---

# План имплементации

## Цель текущего плана

Реализовать accepted FT-003 design: root daemon удерживает automatic lid sleep
только под живой app lease, app воспроизводит различимый outcome sound, а
acknowledgement, deadline или control loss приводят к безопасному explicit/native
sleep согласно policy.

## Grounding Evidence

- Grounded repository revision: `3ed193533cef76574b1fb20195855ebcc625916d`
- Grounded at: `2026-08-12T15:36:23Z`

| Grounding ID | Inspected path / command | Observed current-state fact | Plan impact |
| --- | --- | --- | --- |
| `GRND-01` | `Package.swift` | App, helper, daemon, protocol and two executable check targets exist; no daemon-core target | Add explicit daemon-core/check targets and dependencies |
| `GRND-02` | `Sources/LidSwitchDaemonProtocol/LidSwitchDaemonProtocol.swift` | XPC exports only `checkVersion`; bilateral signing helper already exists | Expand exact primitive contract while preserving peer validation |
| `GRND-03` | `Sources/LidSwitchDaemon/main.swift` | Root Mach listener authenticates app but service has no policy, lid observer, timers or effects | Replace spike service with serialized managed controller/adapters |
| `GRND-04` | `Sources/LidSwitch/ServiceManagedDaemonManager.swift` | App makes one-shot version connection and invalidates it | Convert to persistent bidirectional client with reconnect/heartbeat callbacks |
| `GRND-05` | `Sources/LidSwitch/main.swift` symbols `refresh`, `toggleClosedLidWork`, `readSleepDisabled`, M2 menu | UI derives policy from raw `SleepDisabled`, mutates it through helper and labels daemon as spike | Store desired policy, consume daemon effective state, play/ack sounds, make daemon setup first-class |
| `GRND-06` | `Sources/LidSwitchCore/PrivilegedHelperOperation.swift`, `Sources/LidSwitchHelper/main.swift` | Helper allowlist currently includes lid and energy operations | Remove lid mutation operations after app switches to daemon; retain energy operations |
| `GRND-07` | `Tests/LidSwitchCoreChecks/main.swift` | Deterministic executable checks cover helper allowlist but no lid feedback state | Update helper expectation; add daemon-core behavior suite |
| `GRND-08` | `Tests/LidSwitchDaemonProtocolChecks/main.swift` | Protocol check requires exactly one selector and validates plist/signing | Replace exact surface assertion with accepted methods/callbacks/enums |
| `GRND-09` | `Scripts/build-app.sh`, `scripts/verify-m2-spike.sh`, `scripts/m2-live-gate.sh` | Build embeds/signs daemon; spike verify and live gate already inspect bundle/auth/version | Reuse packaging; rename/update verification expectations and include new core checks |
| `GRND-10` | installed macOS SDK `IOKit/pwr_mgt/IOPM.h`, `IOPMLib.h` and Apple `IOPMSleepSystem` docs | Clamshell general-interest message precedes sleep; `IOPMSleepSystem` is public; assertions do not block lid sleep | Implement IOKit observer and explicit sleep adapter; keep hardware gate |

## Implementation Priming

Before first runtime write, confirm `git rev-parse HEAD` equals the grounded SHA.

| Order | Exact path / stable source | Section / symbol | Grounding refs | Purpose | Required before |
| --- | --- | --- | --- | --- | --- |
| 1 | `memory-bank/features/FT-003/brief.md` | Scope, Verify | `GRND-01..10` | Confirm acceptance/evidence contract | `STEP-01` |
| 2 | `memory-bank/features/FT-003/design.md` | Selected Solution, Invariants, Failure Modes | `GRND-01..10` | Confirm realization boundaries | `STEP-01` |
| 3 | `memory-bank/features/FT-003/contracts/managed-lid-control.md` | Operations, Idempotency And Ordering | `GRND-02..05`, `GRND-08` | Confirm exact XPC semantics | `STEP-02` |
| 4 | `memory-bank/adr/ADR-001-daemon-owned-lid-sleep.md` | Решение, Confirmation | `GRND-03..06`, `GRND-09..10` | Confirm ownership/fail-safe rationale | `STEP-01` |
| 5 | `Package.swift` | products and targets | `GRND-01` | Preserve SwiftPM conventions | `STEP-01` |
| 6 | `Sources/LidSwitchDaemonProtocol/LidSwitchDaemonProtocol.swift` | XPC protocol and peer requirement | `GRND-02` | Reuse signing boundary | `STEP-02` |
| 7 | `Sources/LidSwitchDaemon/main.swift` | listener/service | `GRND-03` | Ground daemon runtime replacement | `STEP-03` |
| 8 | `Sources/LidSwitch/ServiceManagedDaemonManager.swift` | manager lifecycle | `GRND-04` | Ground persistent client | `STEP-04` |
| 9 | `Sources/LidSwitch/main.swift` | launch, refresh, toggle, daemon menu, UI | `GRND-05` | Ground UX integration | `STEP-04` |
| 10 | `Tests/LidSwitchDaemonProtocolChecks/main.swift` | selector/plist/signing checks | `GRND-08` | Preserve exact contract regression style | `STEP-02` |
| 11 | `scripts/verify-m2-spike.sh` | build/bundle/check execution | `GRND-09` | Preserve packaged verification | `STEP-05` |

## Grounding / Support References

| Document | Role | Facts reused | Conflict action |
| --- | --- | --- | --- |
| `brief.md` | canonical problem/verify | `REQ-*`, `SC-*`, `CHK-*`, `EVID-*`, standard profile | Update brief first |
| `design.md` | solution root | `SOL-*`, `C4-*`, `SD-*`, `INV-*`, `FM-*`, `RB-*` | Update design first |
| `contracts/managed-lid-control.md` | connector owner | `CTR-01..07` | Update contract then design routing |
| `../../adr/ADR-001-daemon-owned-lid-sleep.md` | accepted architecture | daemon lease/fail-safe ownership | Supersede ADR if decision changes |
| `../../use-cases/UC-003-close-lid.md` | stable user scenario | observable close-lid result | Update UC before changed behavior |

## Current State / Reference Points

| Path / module | Grounding refs | Current role | Reuse / change |
| --- | --- | --- | --- |
| `LidSwitchDaemonProtocol` | `GRND-02` | One-method XPC + signing | Reuse identity code; replace protocol version/surface |
| `LidSwitchDaemon` | `GRND-03` | Authenticated check-version listener | Reuse Service Management/Mach listener; add controller/adapters |
| `ServiceManagedDaemonManager` | `GRND-04` | Registration and one-shot probe | Reuse SMAppService status; own persistent session |
| `ApplicationDelegate` | `GRND-05` | Menu policy/UI and helper mutation | Migrate lid policy to daemon; keep energy/helper paths |
| check executables | `GRND-07..09` | Deterministic no-framework regression style | Add pure core suite and exact transport assertions |

## Test Strategy

| Test surface | Canonical refs | Existing coverage | Planned automated coverage | Required local / CI commands | Manual-only gap | Approval |
| --- | --- | --- | --- | --- | --- | --- |
| Pure managed state machine | `REQ-01..02`, `REQ-06..07`, `SC-01..02`, `NEG-01..02`, `SOL-02`, `INV-01..06`, `FM-03..06`, `CHK-01`, `CHK-05` | none | activation, initial/duplicate/unknown, work, sleep ack, races, stale ack, lease loss, wake | `swift run LidSwitchDaemonCoreChecks`; same command in CI | none | none |
| XPC/signing/plist | `CTR-01..07`, `SOL-01`, `SOL-06`, `CHK-04` | one selector + identity/plist | exact daemon/app selectors, enums, version, no arbitrary operation | `swift run LidSwitchDaemonProtocolChecks`; `scripts/verify-m2-spike.sh`; same in CI | production Team-ID/live registration | `AG-01` |
| App audio/policy integration | `REQ-03..05`, `SOL-04`, `FM-02`, `CHK-02..03` | none | build and source-level mapping check; NSSound delegate path | `swift build`; packaged verification | audible distinction, mute and callback timing require hardware | `AG-02` |
| Fail-safe adapters/runtime | `REQ-06..07`, `SOL-03..05`, `FM-01`, `FM-03..07`, `CHK-05` | package/live gate only | pure action tests + packaged build | core/protocol checks and `scripts/verify-m2-spike.sh` | real clamshell, app kill, daemon restart, sleep API result | `AG-02` |
| Existing functionality | `EC-04`, `RB-01` | core/helper/build suites | update exact helper allowlist and retain forecast/energy checks | `swift run LidSwitchCoreChecks`; `swift build`; CI equivalents | none | none |
| Memory Bank | plan/process | lint + doctor local | no runtime semantics | `memory-bank-cli lint`; `memory-bank-cli doctor` | CI doctor job warning remains outside FT-003 | none |

## Open Questions / Ambiguities

`none`. Numeric heartbeat/feedback durations are compatible bounded tuning
constants under `SD-04`; hardware evidence may tune them without changing
contract semantics.

## Environment Contract

| Area | Contract | Used by | Failure symptom |
| --- | --- | --- | --- |
| setup | macOS 15 SDK, Swift 6.1 package, clean base SHA | `STEP-01..05` | SDK symbols/build unavailable or SHA mismatch |
| automated test | unprivileged pure checks plus ad-hoc packaged verification | `CHK-01..05` | command non-zero or unexpected selector/signature |
| privileged hardware | approved embedded daemon on supported MacBook | `STEP-06`, `CHK-03`, `CHK-05` | registration/Team ID unavailable or lid transition unobservable |
| secrets/network | no secrets/network for local implementation; notarized live gate uses existing release prerequisites | `STEP-05..06` | production gate cannot authenticate exact Team ID |

## Preconditions

| ID | Canonical ref | Required state | Used by | Blocks start |
| --- | --- | --- | --- | --- |
| `PRE-01` | `design.md` Solution Ready; accepted ADR-001; accepted contract | active/accepted unchanged | `STEP-01..05` | yes |
| `PRE-02` | grounded SHA | current `git rev-parse HEAD` equals exact SHA | `STEP-01` | yes |
| `PRE-03` | `AG-01`, `AG-02` | human approval/hardware available | `STEP-06` | no for code; yes for Done |

## Design Realization Mapping

| Canonical refs | Owner | Realization target | Steps | Checks | Evidence |
| --- | --- | --- | --- | --- | --- |
| `SOL-02`, `SD-01`, `INV-01..06`, `FM-03..06` | `design.md` | `LidSwitchDaemonCore` + checks | `STEP-01` | `CHK-01`, `CHK-05` | `EVID-01`, `EVID-05` |
| `CTR-01..07`, `SD-02` | contract | `LidSwitchDaemonProtocol` + protocol checks | `STEP-02` | `CHK-04` | `EVID-04` |
| `SOL-01`, `SOL-03`, `SOL-05`, `SD-03..04`, `FM-01`, `FM-03..07` | `design.md` | daemon controller, IOKit/pmset/sleep/timers | `STEP-03` | `CHK-01`, `CHK-05` | `EVID-01`, `EVID-05` |
| `SOL-04`, `SOL-06`, `FM-02`, `C4-L2-01` | `design.md` | persistent app client, sound delegate, menu policy | `STEP-04` | `CHK-02..04` | `EVID-02..04` |
| `RB-01` | `design.md` | package/build/helper migration | `STEP-05` | `CHK-04` | `EVID-04` |
| `RB-02` | `design.md` | hardware QA procedure/evidence | `STEP-06` | `CHK-03`, `CHK-05` | `EVID-03`, `EVID-05` |
| ADR-001 | accepted ADR | all daemon/app ownership surfaces | `STEP-01..06` | `CHK-01..05` | `EVID-01..05` |

## Workstreams

| ID | Implements | Result | Owner | Dependencies |
| --- | --- | --- | --- | --- |
| `WS-1` | core/protocol refs | deterministic state machine and exact transport | agent | `PRE-01..02` |
| `WS-2` | daemon/app refs | runtime adapters, persistent client and sounds | agent | `WS-1` |
| `WS-3` | rollout/verification refs | package, docs and hardware evidence | agent + Danil | `WS-2`, `AG-01..02` |

## Approval Gates

| ID | Trigger | Applies to | Why | Approver / evidence |
| --- | --- | --- | --- | --- |
| `AG-01` | Register/approve or run production daemon live gate | `STEP-06` | Changes privileged external system state | Danil; live-gate record |
| `AG-02` | Close physical lid and inject app/daemon failures | `STEP-06` | Suspends machine and cannot be automated in this session | Danil; QA checklist record |

## Порядок работ

| Step | Actor | Implements | Goal | Touchpoints / artifact | Verifies | Evidence | Procedure | Blocked by | Approval | Escalate if |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `STEP-01` | agent | `SOL-02`, `SD-01`, `INV-01..06`, `FM-03..06` | Add pure controller/action model and exhaustive checks | `Package.swift`, new `Sources/LidSwitchDaemonCore`, new `Tests/LidSwitchDaemonCoreChecks` | `CHK-01`, `CHK-05` | `EVID-01`, `EVID-05` | `swift run LidSwitchDaemonCoreChecks` | `PRE-01..02` | none | action model cannot express one terminal race outcome |
| `STEP-02` | agent | `CTR-01..07`, `SD-02` | Expand exact bidirectional primitive XPC | protocol source/checks and unauthorized probe compatibility | `CHK-04` | `EVID-04` | protocol checks + build | `STEP-01` | none | NSXPC cannot encode accepted surface safely |
| `STEP-03` | agent | `SOL-01`, `SOL-03`, `SOL-05`, `SD-03..04`, `FM-01`, `FM-03..07` | Apply core actions in root daemon | daemon main/runtime adapters | `CHK-01`, `CHK-05` | `EVID-01`, `EVID-05` | build + core checks | `STEP-02` | none | safe restore cannot precede sleep on SDK/runtime |
| `STEP-04` | agent | `SOL-04`, `SOL-06`, `FM-02`, `C4-L2-01` | Integrate persistent client, desired policy, sounds/ack and readiness UI | app manager/main, helper allowlist/checks | `CHK-02..04` | `EVID-02..04` | build + checks | `STEP-03` | none | UI can display confirmed policy without valid lease |
| `STEP-05` | agent | `RB-01`, ADR Confirmation | Update package verification and QA docs; run full automated profile | scripts, README/QA and all checks | `CHK-01..05` | `EVID-01..05` automated portion | build, checks, packaged verify, Memory Bank gates | `STEP-04` | none | any regression or daemon defaults to inhibited sleep |
| `STEP-06` | Danil + agent | `RB-02`, `SC-01..03`, `NEG-02` | Execute physical/live matrix and record outcome | built app, supported MacBook, QA evidence | `CHK-03`, `CHK-05` | `EVID-03`, `EVID-05` | approved hardware procedure | `STEP-05`, `PRE-03` | `AG-01..02` | closed Mac stays awake after any forced failure |

## Parallelizable Work

- `PAR-01`: After `STEP-02`, app-client scaffolding and daemon adapter
  scaffolding can be prepared independently, but final protocol integration is
  serialized.
- `PAR-02`: Hardware verification cannot start before the packaged automated
  checkpoint.

## Checkpoints

| ID | Refs | Condition | Evidence |
| --- | --- | --- | --- |
| `CP-01` | `STEP-01..02` | Pure state and exact transport suites green | `EVID-01`, `EVID-04` |
| `CP-02` | `STEP-03..05`, `RB-01` | Full package builds; safe inactive default and regressions pass | `EVID-01`, `EVID-02`, `EVID-04`, `EVID-05` |
| `CP-03` | `STEP-06`, `RB-02` | Hardware happy/failure matrix approved | `EVID-03`, `EVID-05` |

## Execution Risks

| ID | Risk | Impact | Mitigation | Trigger |
| --- | --- | --- | --- | --- |
| `ER-01` | Swift import/runtime behavior differs for IOKit constants | no close event | isolate header-derived constant; hardware gate | callback absent |
| `ER-02` | Root daemon cannot play/coordinate AppKit sound | missed acknowledgement | audio stays in GUI app; deadline fails safe | callback/proxy failure |
| `ER-03` | Explicit sleep interacts unexpectedly with restored native setting | delayed/no sleep | restore native first; stop at hardware gate | sleep API non-success |
| `ER-04` | Ad-hoc signing makes local identity weaker | false production confidence | label development evidence; require Team-ID live gate | Team ID absent |

## Stop Conditions / Fallback

| ID | Related refs | Trigger | Immediate action | Safe fallback |
| --- | --- | --- | --- | --- |
| `STOP-01` | `INV-05..06`, `FM-04..07` | any code path can leave `disablesleep=1` without valid lease | stop integration; force fixed restore action in daemon startup/revoke paths | native sleep enabled, no lease |
| `STOP-02` | `CTR-01..07` | arbitrary command/argument or unauthenticated activation becomes necessary | reject change and return to design/ADR | current narrow protocol, feature blocked |
| `STOP-03` | `RB-02` | physical failure leaves closed Mac awake | unregister managed behavior and restore native sleep | feature not Done; energy helper only |

## Plan-local Evidence

| ID | Artifact | Producer | Path contract | Used by |
| --- | --- | --- | --- | --- |
| `EVID-PLAN-01` | independent Plan Ready review | reviewer | `memory-bank/features/FT-003/reviews/plan-ready.md` | execution gate |
| `EVID-IMPL-01` | implementation/code review | reviewer | `memory-bank/features/FT-003/reviews/implementation-review.md` | Done gate |

## Готово для приемки

- Все steps/checkpoints завершены или остановлены через `STOP-*`.
- Required local/CI suites зелёные; manual-only gaps имеют Danil approval.
- Plan Ready и implementation reviews имеют отдельные clean verdicts.
- Final acceptance выполняется по `brief.md` Verify; только после physical
  evidence delivery может стать Done и plan — archived.
