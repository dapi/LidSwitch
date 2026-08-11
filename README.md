# LidSwitch

LidSwitch is a tiny native macOS menu bar app that controls whether a running
MacBook keeps working or goes to sleep when its lid is closed.

Left-click the single laptop icon to switch the mode immediately:

- green screen — the Mac keeps working with its lid closed
- yellow screen — the Mac is allowed to sleep when its lid closes

After each switch, a short popover confirms what the Mac will do. Right-click
the icon to see the current state, refresh it, manage helper access, or quit.

While running on battery, the icon shows an estimated number of active hours
with the lid closed. The number is drawn inside the laptop screen, so the menu
bar item never grows wider. On AC power, the icon has no number.

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
helper. Subsequent switches do not ask for a password. An existing helper from
LidSwitch 0.3.x is automatically detected as outdated and replaced during that
one-time setup.

The installed helper is owned by `root` and accepts only three fixed operations:
check its version, enable closed-lid work, or disable closed-lid work. It does
not accept arbitrary shell commands or power settings from the app. Right-click
the icon and choose **Remove passwordless switching…** to remove it and its
permission.

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

During one-time setup, LidSwitch installs the helper at
`/Library/PrivilegedHelperTools/me.dapi.LidSwitch.Helper` and validates a narrow
rule in `/etc/sudoers.d/lidswitch`. The rule permits only the current account to
run that root-owned helper without another password prompt.

## Development

```sh
swift run LidSwitchCoreChecks
```
