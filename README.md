# LidSwitch

LidSwitch is a tiny native macOS menu bar app that controls whether a MacBook
starts automatically when its lid is opened.

It changes only lid-open behavior. If startup on power connection was already
disabled, LidSwitch preserves that preference.

## Requirements

- A MacBook with Apple silicon
- macOS Sequoia 15 or later

These are the systems on which Apple officially supports the `BootPreference`
setting used by LidSwitch.

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

Left-click the laptop icon in the menu bar to switch the setting immediately.
Right-click it to see the current state, refresh it, or quit LidSwitch. macOS
asks for one-time approval of its narrowly scoped privileged helper. Subsequent
switches do not ask for a password.

The installed helper is owned by `root` and accepts only three fixed operations:
check access, enable lid startup, or disable lid startup. It does not accept
shell commands or arbitrary NVRAM keys from the app. Right-click the icon and
choose **Remove passwordless switching…** to remove it and its permission.

## How it works

LidSwitch reads the `BootPreference` NVRAM variable and uses Apple's documented
values:

- `%01` disables startup when opening the lid
- deleting `BootPreference` restores the default behavior
- `%00` and `%02` are handled in a way that preserves the existing preference
  for startup when power is connected

LidSwitch refuses to overwrite unknown values.

During one-time setup, LidSwitch installs the helper at
`/Library/PrivilegedHelperTools/me.dapi.LidSwitch.Helper` and validates a narrow
rule in `/etc/sudoers.d/me.dapi.LidSwitch`. The rule permits only the current
account to run that root-owned helper without another password prompt.

Apple documentation:
https://support.apple.com/en-gb/120622

## Development

```sh
swift run LidSwitchCoreChecks
```
