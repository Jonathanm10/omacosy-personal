# Agent pointers

- **Super / hotkeys / gestures** — read live `~/.config/omniwm/settings.toml` and `~/.config/karabiner/karabiner.json` first. This desk’s Super is **Left Option** (e.g. `focus.up` = `Left Option+Up Arrow`). Repo `config/karabiner` and `config/omniwm` are upstream defaults (Caps Lock → Hyper), not the live map.
- **modifier+scroll** — Karabiner cannot take scroll as a `from` event. Remaps live in `helper/gesture` + `config/gesture/config.omniwm.json` (`super_scroll_stack`). Rebuild with `./bin/rebuild-gesture` (stable Apple Development identity; never hardened runtime).
- **Personal bar** — `PERSONAL-BAR.md`; build/activate under `personal-bar/`.
- **Local secrets / desk prefs** — never commit `config/bar.local.conf` or `config/apps.local.conf`. Calendar events stay in EventKit at runtime; optional `CALENDAR_TITLES` in `bar.local.conf` (see `config/bar.local.conf.example`) can narrow which calendars feed the meeting pill.
