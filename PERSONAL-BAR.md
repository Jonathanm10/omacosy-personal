# Personal omacosy bar

This checkout owns Jonathan's Calendar, CodexBar, and patched-OmniWM bar. It is intentionally separate from `~/.local/share/omacosy`, which remains a clean upstream checkout.

## Build and activate

```sh
./personal-bar/build
./personal-bar/activate
```

The build stays at `build/omacosy-bar.app`. The launch job is `com.omacosy.personal-bar`; the app retains bundle identifier `com.omacosy.bar` and uses the installed Apple Development identity so existing macOS privacy grants survive rebuilds.

Activation archives any upstream `com.omacosy.bar.plist` under `~/.config/omacosy-personal/backups/launch-agents/`, unloads that job, and installs the personal job. It also makes `~/.local/bin/omacosy-update` point to `personal-bar/update-upstream`.

## Updating

Run the usual command:

```sh
omacosy-update
```

The wrapper temporarily stops the personal bar, runs the updater from the clean upstream checkout, then archives the upstream bar plist and restores the personal job and wrapper symlink. It does not run this checkout's full installer.

To bring upstream source changes into this personal branch:

```sh
git fetch upstream main
git merge upstream/main
./personal-bar/build
./personal-bar/activate
git add helper/bar.swift helper/bar-info.plist
git commit
```

Resolve `helper/bar.swift` by retaining the Calendar/CodexBar sections and both OmniWM bundle identifiers. Remotes in this checkout have disabled push URLs; this branch is local-only.

## Limitations

- Running `~/.local/share/omacosy/install.sh` directly bypasses the wrapper and can start a second, plain upstream bar. Run `./personal-bar/activate` afterward to unload and archive it.
- If an update is forcibly interrupted after upstream starts its bar but before reactivation, run `./personal-bar/activate`.
- Upstream's `omacosy-toggle` knows only `com.omacosy.bar`, not `com.omacosy.personal-bar`; use `launchctl bootout gui/$(id -u)/com.omacosy.personal-bar` when you specifically want this bar stopped.
- Visual Calendar content depends on macOS Calendar permission. The bar hides the pill when access or data is unavailable.

## Rollback

```sh
launchctl bootout gui/$(id -u)/com.omacosy.personal-bar 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.omacosy.personal-bar.plist
cp ~/.config/omacosy-personal/backups/20260907-085410/com.omacosy.bar.plist \
  ~/Library/LaunchAgents/com.omacosy.bar.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.omacosy.bar.plist
ln -sfn ~/.local/share/omacosy/bin/omacosy-update ~/.local/bin/omacosy-update
```

The original pre-change launch plist is preserved at `~/.config/omacosy-personal/backups/20260907-085410/com.omacosy.bar.plist`.
