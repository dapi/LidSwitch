# LidSwitch QA

This document is the release-independent QA checklist for LidSwitch. It covers
the supported runtime surface without changing signing, notarization, or release
infrastructure.

## Supported test matrix

Run the manual matrix on real MacBooks. A VM or desktop Mac cannot validate the
battery, clamshell, backlight, or `IOPMrootDomain` behavior.

| Dimension | Required coverage |
| --- | --- |
| Hardware | At least one Apple silicon MacBook; include a model that supports High Power mode when available |
| macOS | Latest macOS 15.x and the newest supported macOS release |
| Power source | Battery and AC adapter |
| Lid | Open; closed while the Mac remains active; reopen after each closed-lid run |
| Managed daemon | Not registered, requires approval, enabled, app disconnected, daemon restarted, removed |
| Helper | Not installed, installed/current and removed for Energy Mode only |
| Energy mode | Low Power, Automatic, High Power (or the expected rejection on unsupported hardware) |
| Forecast | Learning, modeled display-off, measured closed-lid, learned-on-AC, baseline-on-AC |
| UI | Green hours, yellow `Zz`, gray `?`, left click, Control/right click, hover card, menu, confirmations, errors |

Record the Mac model, chip, macOS build (`sw_vers`), power source, energy mode,
and whether an external display is attached for every failed case.

## Automated checks

The core check executable intentionally needs only Xcode Command Line Tools;
full Xcode and XCTest are not required.

```sh
swift run LidSwitchCoreChecks
swift run LidSwitchDaemonCoreChecks
swift run LidSwitchDaemonProtocolChecks
swift build
```

The checks cover:

- parsing all three `pmset` energy modes and rejecting malformed values;
- open-lid display modeling, direct closed-lid measurement, invalid inputs, and
  displayed-hour bounds;
- rolling median behavior and resets after wake, clamshell transitions, and
  energy-mode transitions;
- battery learning and AC learned/baseline selection for every energy mode;
- rejection of invalid power samples and learned wattages;
- the helper's energy-only operation allowlist and fixed `pmset` mapping;
- managed lease activation, lid transitions, acknowledgement/deadline races,
  stale events and fail-safe lease loss;
- the exact bidirectional XPC selectors, signing requirements and launchd plist.

After building, the non-mutating helper protocol can also be smoke-tested:

```sh
.build/debug/LidSwitchHelper check-v3
! .build/debug/LidSwitchHelper unsupported-operation
! .build/debug/LidSwitchHelper check-v3 extra-argument
```

These commands do not invoke `pmset`. Do not run the mutating helper operations
directly as root during an automated check.

## Manual test procedure

### 1. Clean launch and menu bar UI

1. Launch the locally built app on an Apple silicon MacBook.
2. Confirm exactly one laptop icon appears and the app does not appear in the
   Dock.
3. Verify the initial icon is green with hours, yellow with `Zz`, or temporarily
   gray with `?`; it must agree with the status row after refresh.
4. Hover for at least 0.35 seconds. Verify the card shows the same closed-lid
   state and forecast as the icon/menu, and that leaving closes it.
5. Right-click and Control-click. Both must open the menu without changing the
   setting. `Refresh` and Command-R must refresh it.
6. Left-click before daemon approval. It must explain that managed lid control
   is required and must not show false success. After approval, it switches the
   effective daemon policy and shows a short confirmation.

### 2. Privileged helper lifecycle

1. With no helper installed, choose setup for an Energy Mode, approve once, and
   verify subsequent energy-mode switches do not request a password.
2. Verify `/Library/PrivilegedHelperTools/me.dapi.LidSwitch.Helper` is executable,
   owned by `root:wheel`, and `/etc/sudoers.d/lidswitch` is `root:wheel` mode
   `0440`.
3. Run `sudo -n /Library/PrivilegedHelperTools/me.dapi.LidSwitch.Helper check-v3`;
   it must succeed for the installing account. An unsupported operation must
   fail and must not alter power settings.
4. Replace the installed helper only with an intentionally outdated test build,
   then verify the app detects it as invalid and offers setup again. Restore the
   current build immediately afterward.
5. Choose **Remove passwordless switching…**, cancel once, then approve. Cancel
   must preserve both files; approval must remove the helper and both current
   and legacy sudoers entries.
6. Reinstall once to leave the test Mac in the normal supported state.

### 3. Energy modes on battery and AC

For each power source, select Low Power, Automatic, and High Power. Confirm the
menu checkmark moves only after `pmset -g` reports the requested `powermode`.
Reconnect/disconnect AC and verify the selected mode and forecast refresh.

High Power is not available on every Apple silicon MacBook. On unsupported
hardware, verify LidSwitch reports the `pmset` failure and does not show a false
High Power checkmark. After the matrix, restore the user's original energy mode.

### 4. Forecast sources and transitions

Use a steady workload long enough to collect several 10-second samples.

| Setup | Expected result |
| --- | --- |
| Battery, lid open | Forecast appears; menu/hover basis says current draw without the built-in display |
| Battery, lid closed and Mac active | Basis changes to measured with lid closed; reopening starts a fresh sample profile |
| Change energy mode on battery | First new-mode forecast uses only new-mode samples, not the previous mode's median |
| Sleep/wake | Old rolling samples are discarded and the forecast relearns |
| AC after battery learning | Basis says last battery-learned draw for the selected mode |
| AC with no learned value for that mode | Basis names the 6 W, 8 W, or 12 W baseline |
| Invalid/near-zero current sample | UI remains in learning state until a valid sample exists; no zero/infinite hours appear |

Compare trends rather than demanding exact hours: CPU/GPU load and battery
voltage vary. Raising sustained load must lower the estimate; lowering it must
raise the estimate after the rolling window updates. The icon must show hours
only while closed-lid work is enabled.

### 5. Actual lid behavior and safety

1. Register and approve **Managed lid control**. Confirm the daemon version is
   `managed-lid-v1` and the menu shows a confirmed policy.
2. On AC, select work, start a visible/logged task, close the lid, and verify one
   `Glass` sound occurs and the task continues. Duplicate clamshell events must
   not produce repeated sounds.
3. Select sleep, close the lid, and verify the distinct `Sosumi` warning repeats
   for 15 seconds. Open the lid during that warning and confirm the warning
   stops and sleep is cancelled.
4. Close the lid again after cancellation. Confirm a new 15-second warning
   starts and the previous event does not cause a delayed sleep.
5. Repeat step 3 muted and at zero volume: no audible bypass, but sleep still
   follows the playback completion/fail-safe path.
6. In sleep policy, force-quit the app immediately after closing. Confirm the
   Mac sleeps rather than remaining awake. Repeat with daemon connection loss.
7. Restart/kill the daemon while managed control is active. Confirm native sleep
   is restored; work policy may safely degrade to sleep.
8. Repeat work/sleep cases on battery in a ventilated stationary location.
9. Never perform this test in a bag or enclosed space. Monitor temperature and
   stop immediately if the Mac becomes unusually hot.

## Pass criteria

- No crash, hang, duplicate status item, or false success confirmation.
- UI state always follows the effective managed daemon lease, not raw
  `SleepDisabled`.
- Helper accepts only its four documented energy/check operations and requires no repeated
  prompt after valid installation.
- Work and sleep sounds are distinct and occur once; sleep begins only after
  sound completion or bounded fail-safe.
- App/XPC/daemon failure never leaves a closed Mac indefinitely awake.
- Forecast source changes correctly across battery/AC, lid, wake, and energy-mode
  transitions; displayed hours remain between 1 and 999.
- Cancel and error paths do not change settings or claim success.
