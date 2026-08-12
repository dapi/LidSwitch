---
title: "FT-003: Lid Closure Outcome Sounds"
doc_kind: feature
doc_function: canonical
purpose: Фиксирует problem space, scope, validation profile и verify contract для разных звуков при закрытии крышки.
derived_from:
  - ../../flows/feature.md
  - ../../product/context.md
  - ../../domain/rules.md
  - ../../domain/states.md
  - ../../use-cases/UC-003-close-lid.md
status: active
delivery_status: planned
audience: humans_and_agents
must_not_define:
  - implementation_sequence
  - solution_space
---

# FT-003: Lid Closure Outcome Sounds

Source task: [GitHub issue #3](https://github.com/dapi/LidSwitch/issues/3).

Routing record: `Feature Flow`. The request is one delivery-unit that changes
observable user behavior. It is not an incident, bug or research task, and it
does not satisfy Small Change because sound source and transition handling need
an explicit solution decision.

## What

### Problem

When the lid closes, a LidSwitch user cannot hear whether the Mac is expected
to continue working or enter normal sleep. The icon/menu may no longer be
visible, so the action lacks immediate outcome feedback.

### Outcome

| Metric | Baseline | Target | Measurement |
| --- | --- | --- | --- |
| Outcome-specific sound per confirmed open → closed transition | none | exactly one of two distinguishable sounds for known policy; none for unknown | deterministic policy checks plus real-MacBook acceptance |

### Scope

- `REQ-01`: Detect a confirmed lid transition from open to closed.
- `REQ-02`: Emit exactly one feedback outcome for that transition: work, sleep,
  or none when closed-lid policy is unknown.
- `REQ-03`: Work and sleep feedback must use readily distinguishable sounds.
- `REQ-04`: The verdict must use the last policy state LidSwitch displays
  immediately before closure.
- `REQ-05`: Playback must respect macOS system volume and mute behavior.
- `REQ-06`: macOS must not begin automatic lid-close sleep before the outcome
  sound completes. In the sleep policy, LidSwitch must explicitly request
  system sleep after playback; in the work policy it must keep running.
- `REQ-07`: Loss of the LidSwitch control process must fail safe: a sleep-policy
  Mac must not remain indefinitely awake with its lid closed.
- `REQ-08`: In sleep policy, LidSwitch repeats an alarming system sound for 15
  seconds; opening the lid during that warning cancels pending sleep and stops
  the warning, while a later close starts a new warning.

### Non-Scope

- `NS-01`: No sound preference or settings UI in this delivery-unit.
- `NS-02`: No bundled/licensed custom audio unless selected design proves
  system sounds insufficient.
- `NS-03`: No change to energy modes, forecast math or public distribution.
- `NS-04`: No sound for app startup, duplicate closed samples, lid opening,
  sleep/wake alone or unknown state.

### Constraints / Assumptions

- `CON-01`: Lid state and `SleepDisabled` are undocumented IOKit properties;
  unreadable values must remain unknown.
- `CON-02`: A sleep-enabled Mac may suspend quickly after lid closure, so
  audibility timing requires hardware validation.
- `CON-03`: Deterministic transition/verdict policy must be separated from
  AppKit/IOKit playback so initial and duplicate observations are testable.
- `CON-04`: Public power assertions do not prevent lid-close sleep; controlled
  sequencing therefore changes the effective `disablesleep` ownership and needs
  a crash-safe controller.
- `DEC-01`: Select system sounds or bundled custom sounds in `design.md`.
- `DEC-02`: Select an observation mechanism that produces one transition without
  converting an unreadable lid state into open.
- `DEC-03`: Select the runtime owner and fail-safe lease/watchdog that restores
  native sleep if the app cannot complete a sleep-policy close.

## Design Requirement Decision

| Decision | Reason | Downstream owner |
| --- | --- | --- |
| `Design required: yes` | The issue leaves a sound-source trade-off and introduces temporal state/unknown handling that must not be decided inside the execution plan. | `design.md` |

## Artifact Routing Decision

| Artifact | Decision | Trigger / reason | Route / owner |
| --- | --- | --- | --- |
| `design.md` | selected | Own sound and observation decisions | feature root design |
| Project-level use case | selected before closure | Materially changes stable lid-close workflow | `memory-bank/use-cases/UC-003-*` |
| UI reference/mockup | omitted | No visual layout or navigation change | none |
| Separate interaction contract | selected | Persistent bidirectional XPC, lease, timeout and trust semantics require a direct owner | `contracts/managed-lid-control.md` |
| Separate sequence diagram | omitted | Temporal projection is compact enough to embed in `design.md` | embedded design view |

## Validation Profile Decision

| Profile | Triggers / rationale | Downgrade approval |
| --- | --- | --- |
| `standard` | New observable runtime transition behavior uses undocumented hardware state and has a manual-only immediate-sleep acceptance surface. It is not proven low-risk; no production/live mutation occurs. | none |

## Verify

### Exit Criteria

- `EC-01`: Each confirmed open → closed transition maps to one work/sleep/none verdict.
- `EC-02`: Work and sleep play distinct sounds; unknown plays none.
- `EC-03`: Startup, duplicates and open transitions do not play sounds.
- `EC-04`: Existing build, core checks and M2 verification remain green.
- `EC-05`: A supported MacBook confirms both sounds occur early enough to be
  heard and respect system volume/mute.
- `EC-06`: In sleep policy, automatic lid sleep is held until sound completion,
  then LidSwitch explicitly requests sleep.
- `EC-07`: Killing or disconnecting the controlling process in sleep policy
  restores a safe path to sleep instead of leaving the closed Mac awake.
- `EC-08`: Opening the lid during the 15-second sleep warning cancels sleep;
  reclosing starts a new warning with a new event.

### Traceability Matrix

| Requirement | Acceptance | Checks | Evidence |
| --- | --- | --- | --- |
| `REQ-01`, `REQ-02`, `REQ-04` | `SC-01`, `SC-02`, `NEG-01` | `CHK-01` | `EVID-01` |
| `REQ-03`, `REQ-05` | `SC-01`, `SC-02`, `SC-03` | `CHK-02`, `CHK-03` | `EVID-02`, `EVID-03` |
| `REQ-06`, `REQ-07` | `SC-02`, `NEG-02` | `CHK-03`, `CHK-05` | `EVID-03`, `EVID-05` |
| all | `EC-04` | `CHK-04` | `EVID-04` |

### Acceptance Scenarios

- `SC-01`: Given displayed policy is work and lid was open, closing it produces
  exactly one work sound.
- `SC-02`: Given displayed policy is sleep and lid was open, closing it prevents
  automatic sleep, repeats one distinct alarming sleep sound for 15 seconds and
  then LidSwitch explicitly requests system sleep if the lid remains closed.
- `SC-03`: System mute or zero output volume prevents audible feedback without
  any application bypass.
- `NEG-01`: Initial closed observation, repeated closed observation, lid opening
  and unknown policy produce no misleading sound.
- `NEG-02`: If the controlling app/connection fails during sleep policy, the
  fail-safe controller restores native sleep or explicitly sleeps the Mac.
- `NEG-03`: If the lid opens during the sleep warning, LidSwitch cancels pending
  sleep and a subsequent close receives a new event ID.

### Checks And Evidence

| Check | Covers | How | Expected | Evidence |
| --- | --- | --- | --- | --- |
| `CHK-01` | transition/verdict policy | `swift run LidSwitchCoreChecks` | deterministic main and negative paths pass | `EVID-01`: command output |
| `CHK-02` | distinct system sound mapping | code review and build | two different valid macOS sound identifiers, no direct audio-device bypass | `EVID-02`: diff/build output |
| `CHK-03` | hardware timing and mute | manual `QA.md` procedure on supported MacBook | one audible outcome per close when unmuted; no audible sound when muted | `EVID-03`: human test record and approval ref |
| `CHK-04` | regression and package | repository automated profile | build and required verification scripts pass | `EVID-04`: command/CI outputs |
| `CHK-05` | fail-safe ownership | deterministic controller tests plus forced app/connection failure on hardware | sleep policy cannot strand a closed Mac awake | `EVID-05`: test output and hardware failure-injection record |

`CHK-03` is manual-only because closing the physical lid and immediate system
sleep cannot be validated by SwiftPM or a desktop/VM. Human approval is required
before the feature can reach `Done`.
