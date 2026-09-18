# Personal omacosy bar

This checkout owns the Calendar, CodexBar, and OmniWM-aware personal bar. It is intentionally separate from `~/.local/share/omacosy`, which remains a clean upstream checkout.

## Privacy

- **Calendar:** EventKit reads today's events in memory for the meeting pill. Titles, notes, attendees, and links are never written into this repo. Optional calendar-title allowlists go in gitignored `config/bar.local.conf` (copy from `config/bar.local.conf.example`) or `~/.config/omacosy-personal/bar.local.conf`.
- **AI usage:** CodexBar owns auth; the bar only parses CLI JSON. Tests use synthetic fixtures (`./personal-bar/test-usage`). `--live` prints reserves only, not account identities.

## Build and activate

```sh
./personal-bar/build
./personal-bar/activate
```

The build stays at `build/omacosy-bar.app`. The launch job is `com.omacosy.personal-bar`; the app retains bundle identifier `com.omacosy.bar` and uses the installed Apple Development identity so existing macOS privacy grants survive rebuilds.

Gesture daemon rebuilds follow the same identity rule: `./bin/rebuild-gesture` (see `AGENTS.md`).

Activation archives any upstream `com.omacosy.bar.plist` under `~/.config/omacosy-personal/backups/launch-agents/`, unloads that job, and installs the personal job. It also makes `~/.local/bin/omacosy-update` point to `personal-bar/update-upstream`.

## AI usage pill

The shared pill is ordered **◎ Codex | ✳ Claude | ➤ Cursor**. It shows
CodexBar's **pace reserve**, not quota remaining: **expected usage − actual usage**.
`+13%` means 13 percentage points in reserve; `−16%` means 16 points in deficit;
`0%` means CodexBar's **On pace** band (unrounded delta within ±2 points).
Reserve/on-pace is green; deficits up to 6 points are amber, larger deficits red.
Cached readings retain the dimmed-dot styling. The pill shows the signed reserve
figure without `%` (`+13`, `-16`, `0`) plus a coarse local-day reset tag when the
scoped lane has `resetsAt`: `0` today, `t` tomorrow, `2`…`9` days, `w` for 10+
days (ceiling weeks). Missing reset keeps the figure and omits the tag. Hover and
the popup still use the `%` wording and the exact reset time, and name the scope:

- **Codex weekly:** CLI `pace.secondary`, not model-specific windows
  (including the unrelated `gpt-reserve` quota).
- **Claude Fable weekly:** exact `claude-weekly-scoped-fable` window. The bar computes
  CodexBar's weekly pace formula from its reset, 10,080-minute duration, and raw
  usage. General Claude limits remain visible in the popup and can still constrain
  Fable; they do not replace the requested scoped reserve.
- **Cursor Third Party monthly:** CLI `pace.tertiary`, with its
  matching tertiary usage window. Neither Cursor models nor Grok Bot is substituted.

The supplied Codex/Cursor pace stage controls On pace; otherwise the signed delta
is rounded as CodexBar does. Fable uses the current local calendar and the same
`weeklyProgressWorkDays` key, checking `com.steipete.codexbar` then
`com.steipete.codexbar.debug`. Unset (as verified locally) means seven-day linear
progress. Values 2–6 count Monday through that ISO weekday, slicing at local day
boundaries (including DST); other values use continuous progress. Every valid
Fable cycle is visible immediately, including zero progress. Invalid/missing
reset, duration, scoped window, or supplied pace shows unknown.
The popup retains every raw usage limit and reset, explicitly labelled **used**.
The three fixed-width segments stay together when the bar has room.
On the built-in MacBook display, weather / Wi-Fi / Bluetooth / brightness
are omitted so the Codex pill keeps its slot; external displays still show them.
On a notched built-in, the meeting pill moves left of the notch so Codex can
stay on the right strip.

### Reserve source evidence

Verified against CodexBar source commit
[`08ef7710ff548cdd6b297db58cac6c42e47c19f6`](https://github.com/steipete/CodexBar/tree/08ef7710ff548cdd6b297db58cac6c42e47c19f6):

- [`UsagePace.swift`](https://github.com/steipete/CodexBar/blob/08ef7710ff548cdd6b297db58cac6c42e47c19f6/Sources/CodexBarCore/UsagePace.swift):
  `weekly`, `workdayProgress`, and `stage` define expected elapsed-cycle usage,
  optional local workdays, actual-minus-expected delta, and the ±2 band.
- [`UsagePaceText.swift`](https://github.com/steipete/CodexBar/blob/08ef7710ff548cdd6b297db58cac6c42e47c19f6/Sources/CodexBar/UsagePaceText.swift)
  `detailLeftLabel` names negative deltas “in reserve” and positive ones “in deficit”.
  [`MenuCardView+ModelHelpers.swift`](https://github.com/steipete/CodexBar/blob/08ef7710ff548cdd6b297db58cac6c42e47c19f6/Sources/CodexBar/MenuCardView%2BModelHelpers.swift)
  `extraRateWindowPaceDetail` applies weekly pace to Claude scoped weekly windows.
- [`CLIRenderer.swift`](https://github.com/steipete/CodexBar/blob/08ef7710ff548cdd6b297db58cac6c42e47c19f6/Sources/CodexBarCLI/CLIRenderer.swift)
  `pacePayload` exports rounded delta plus stage; its `PaceComputation` comment
  explicitly says CLI Codex pace omits the GUI's historical refinement. We use the
  service/CLI's supplied pace, not a claim of full GUI historical-forecast parity.
  [`CLIHelpers.swift`](https://github.com/steipete/CodexBar/blob/08ef7710ff548cdd6b297db58cac6c42e47c19f6/Sources/CodexBarCLI/CLIHelpers.swift)
  establishes the GUI preference key/domain order (the bar does not inherit the
  CLI process's own standard-defaults fallback).
- [`docs/cursor.md`](https://github.com/steipete/CodexBar/blob/08ef7710ff548cdd6b297db58cac6c42e47c19f6/docs/cursor.md#snapshot-mapping)
  names tertiary **Third Party**;
  [`CursorStatusProbe.swift`](https://github.com/steipete/CodexBar/blob/08ef7710ff548cdd6b297db58cac6c42e47c19f6/Sources/CodexBarCore/Providers/Cursor/CursorStatusProbe.swift)
  maps it from `apiPercentUsed` and the billing-cycle duration/end.

Fresh sanitized September 8 checks confirmed CLI `pace.secondary` and the exact
Fable id; installed CLI/app version 0.56.6 exports `pace.tertiary` and the monthly
tertiary window. Source commit is an independent semantic reference, not an
assertion that these installed binaries were built from that exact revision.

A dash means unknown, never zero. CodexBar owns authentication: enable providers
and sign in there (for Cursor, use **Add / switch account**). Missing providers,
connection errors without a previous reading, and snapshots at least one hour old
show a dash. Readings at least five minutes old, or retained after a failed refresh,
are dimmed with a dot beside the icon. Hover and popup show cached status and the
provider timestamp. Each provider retains its last-known reading independently,
for at most one hour from that timestamp. Usage refreshes every minute; the popup
also offers **refresh usage now**. All three providers run
`/opt/homebrew/bin/codexbar usage --json` on a background queue, with a 30-second
deadline and 1 MiB output cap, so the pill tracks the same live CLI as the CodexBar
app instead of a long-lived local HTTP serve that can go stale after upgrades.
Popup **open CodexBar dashboard…** still opens `http://127.0.0.1:50891/` when the
optional `com.omacosy.codexbar` serve is running. With multiple accounts, the newest
usable snapshot is selected, skipping failed accounts; values are not summed.

Run the synthetic parser and refresh-sequence checks without launching the bar:

```sh
./personal-bar/test-usage
```

Add `--live` (or the older `--live-cursor`) to verify the actual CLI retrieval and
production parser using current authentication. The test prints only the resulting
reserves, not account identities or credentials.

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

Resolve `helper/bar.swift` by retaining the Calendar/CodexBar sections and the OmniWM bundle id (`com.barut.OmniWM`). After publishing, `origin` pushes to this fork; `upstream` stays fetch-only for paulsp94/omacosy.

## Limitations

- Running `~/.local/share/omacosy/install.sh` directly bypasses the wrapper and can start a second, plain upstream bar. Run `./personal-bar/activate` afterward to unload and archive it.
- If an update is forcibly interrupted after upstream starts its bar but before reactivation, run `./personal-bar/activate`.
- Upstream's `omacosy-toggle` knows only `com.omacosy.bar`, not `com.omacosy.personal-bar`; use `launchctl bootout gui/$(id -u)/com.omacosy.personal-bar` when you specifically want this bar stopped.
- Visual Calendar content depends on macOS Calendar permission. The bar hides the pill when access or data is unavailable. Event contents never enter git; desk-specific calendar filters belong in `config/bar.local.conf` (gitignored).

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
