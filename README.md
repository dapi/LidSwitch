# LidSwitch

LidSwitch is a tiny native macOS menu bar app that controls whether a running
MacBook keeps working or goes to sleep when its lid is closed.

Left-click the single laptop icon to switch the mode immediately:

- green screen — the Mac keeps working with its lid closed
- yellow half-closed screen — the Mac is allowed to sleep when its lid closes

After each switch, a short popover confirms what the Mac will do. Right-click
the icon to see the current state, refresh it, manage helper access, or quit.

The right-click menu also switches macOS Energy Mode between Low Power,
Automatic, and High Power. A checkmark shows the active mode. LidSwitch applies
the selection to both battery and power-adapter profiles.

The icon shows an estimated number of active hours with the lid closed, both on
battery and on AC power. The number is drawn inside the laptop screen, so the
menu bar item never grows wider. It appears only in the green state, when
closed-lid work is enabled; the yellow sleep state stays visually uncluttered.
On AC, LidSwitch uses the last learned battery consumption for the selected
Energy Mode; before it has learned one, it uses a conservative baseline model.

## Requirements

- A MacBook
- macOS Sequoia 15 or later

## Build and run

Full Xcode is not required. The Swift toolchain from Xcode Command Line Tools is
enough.

```sh
./Scripts/build-app.sh
open dist/LidSwitch.app
```

To install it for the current user:

```sh
mkdir -p ~/Applications
cp -R dist/LidSwitch.app ~/Applications/
open ~/Applications/LidSwitch.app
```

macOS asks for one-time approval of LidSwitch's narrowly scoped privileged
helper through its system authorization UI. Touch ID is available when macOS
offers it, with an administrator password as the fallback. Subsequent switches
do not ask again. An outdated helper is detected and replaced during this
one-time setup.

The installed helper is owned by `root` and accepts only a fixed allowlist of
operations: check its version, change closed-lid work, or select one of the
three energy modes. It does not accept arbitrary shell commands or power
settings from the app. Right-click the icon and choose **Remove passwordless
switching…** to remove it and its permission.

## How it works

The helper changes macOS's system-wide `disablesleep` power setting through
`pmset`. The app reads the resulting `SleepDisabled` state directly from the
`IOPMrootDomain` registry, so its color and menu show the actual macOS state
rather than a separately saved preference.

The forecast uses a rolling median of live battery power measurements. With the
lid open, it models closed-lid consumption by subtracting the internal display's
brightness-dependent draw. If the Mac is already awake with its lid closed, it
uses the directly measured power instead. The workload is assumed to remain
similar, so the number changes as CPU/GPU activity changes.

On AC power, the battery reports no discharge rate. LidSwitch therefore stores
the most recent predicted closed-lid wattage learned on battery and applies it
to the current charge. Until the first battery measurement is available, it
uses a mode-specific baseline: 6 W for Low Power, 8 W for Automatic, or 12 W
for High Power. The menu identifies when a baseline is being used.

During one-time setup, LidSwitch installs the helper at
`/Library/PrivilegedHelperTools/me.dapi.LidSwitch.Helper` and validates a narrow
rule in `/etc/sudoers.d/lidswitch`. The rule permits only the current account to
run that root-owned helper without another password prompt.

## Development

```sh
swift run LidSwitchCoreChecks
```
