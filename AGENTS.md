# AGENTS.md

Personal wezterm configuration repo (Lua). Lives at `~/.config/wezterm/` and is
versioned as a git repo (`origin` → `git@github.com:lukashevich-t/wezterm-config.git`).

## Architecture

`wezterm.lua` is the **only** entry point wezterm auto-discovers. It:

1. Builds a `Config` object via `config/init.lua` (small OO wrapper with `init()` + `append(tbl)` that dedupes keys with a `wezterm.log_warn`).
2. Calls `setup()` on every event module under `events/`.
3. Returns the merged options table built by `:append(require('config.*'))`.

```
wezterm.lua                 ← entrypoint
├── config/                 ← pure option tables returned by each file
│   ├── init.lua            ← Config class
│   ├── appearance.lua      ← colors, GPU adapter, tab bar, window padding
│   ├── bindings.lua        ← key/mouse bindings, key_tables, leader
│   ├── domains.lua         ← wsl_domains / ssh_domains / unix_domains
│   ├── fonts.lua           ← font, font_size (uses utils.platform)
│   ├── general.lua         ← hyperlink_rules, scrollback, auto-reload
│   └── launch.lua          ← default_prog + launch_menu per-OS
├── events/                 ← modules exposing M.setup(opts) → register handlers
│   ├── left-status.lua     ← left status bar (active key table)
│   ├── right-status.lua    ← right status bar (date + battery)
│   ├── tab-title.lua       ← format-tab-title + custom tab events
│   ├── new-tab-button.lua  ← right-click on new-tab button
│   ├── help.lua            ← help.show-pager / help.show-picker handlers
│   └── startup.lua         ← gui-startup: spawns initial window
├── utils/                  ← shared helpers, all `require('utils.X')`
│   ├── platform.lua        ← {os, is_win, is_linux, is_mac} via wezterm.target_triple
│   ├── cells.lua           ← Cells class for wezterm.format() segments (workhorse)
│   ├── opts-validator.lua  ← schema-validated event opts (used by right-status, tab-title)
│   ├── gpu-adapter.lua     ← auto-pick WebGPU adapter per OS
│   ├── math.lua            ← clamp, round
│   ├── dump.lua            ← global __dump/__pdump
│   ├── help.lua            ← keybindings reference: Russian descriptions,
│   │                         categories, render()/active_entries(), _G._keys
│   └── default-bindings.lua← GENERATED stock wezterm bindings (see below)
├── colors/custom.lua       ← active color scheme (catppuccin-mocha variant)
└── docs/                   ← reference: default-config.md, default-keys.md,
                              ahk.md (Windows quake-style AHK script),
                              tempNotes.md (scratchpad, not authoritative)
```

## Keybindings help (F1)

`utils/help.lua` builds one reference text out of **config bindings + stock
wezterm bindings**, grouped into categories (Интерфейс, Окна и вкладки, Панели,
Ввод и буфер обмена, Скролл и буфер, Поиск и выделение, Мышь, Клавиатурные
таблицы). `*` = from config, `→` = stock binding overridden by config, `-` =
stock binding (in the main table it is **inactive**, because
`disable_default_key_bindings = true`; key tables and mouse bindings stay
active).

Two entry points, both wired as custom events in `events/help.lua`:

- `help.show-pager` → **F1**. Writes the text to a temp file and opens a new
  tab with a pager: `less -R -X -F` on Linux/macOS, PowerShell
  `Get-Content -Raw -Encoding UTF8` on Windows.
- `help.show-picker` → **LEADER + ?** (`CTRL+Space`, then `?`). Fuzzy
  `InputSelector` over *active* bindings; ENTER copies the chord to the
  clipboard and shows a toast.

`F12 → _keys()` prints the same text inside the debug overlay.

Both handlers render from `window:effective_config()`, so `set_config_overrides`
changes are reflected. The text is also rendered to a temp file at config load
(`events/help.lua` → `M.setup`), because writing files from inside an event
handler is not guaranteed in wezterm's Lua runtime — the handler re-writes the
file if it can and falls back to the pre-generated one.

## Hidden coupling — easy to miss

- **`config/domains.lua` is NOT in `wezterm.lua`'s append chain** (see the
  commented-out block at the bottom of `wezterm.lua`). But
  `events/new-tab-button.lua` requires it for `wsl_domains`/`ssh_domains`/
  `unix_domains` to populate the right-click launcher menu. Do **not** delete
  it as "dead code".
- `events/tab-title.lua` defines three custom events consumed by
  `config/bindings.lua`: `tabs.manual-update-tab-title`, `tabs.reset-tab-title`,
  `tabs.toggle-tab-bar`. Key names must stay in sync with both files.
- `events/help.lua` defines `help.show-pager` and `help.show-picker`, consumed
  by `config/bindings.lua` (F1 and LEADER+?). Keep both sides in sync.
- **`utils/default-bindings.lua` is generated data, not hand-written.** It holds
  the stock wezterm bindings used by the help reference. Regenerate it after a
  wezterm upgrade (see "Environment quirks" for the exact commands), never edit
  it by hand — descriptions for stock actions live in `utils/help.lua`.
- `utils/help.lua` requires `config.bindings` **lazily, inside `M.entries()`** —
  that indirection is what keeps `config/bindings.lua` free of a require cycle
  with the help module.
- `utils/help.lua` installs `_G._keys`; the F12 debug overlay is a fallback way
  to invoke it (F1 is the normal one). Don't move it out of `utils/` without
  keeping the `require` in `wezterm.lua`.

## Conventions to preserve

- **4-space indent** (per `stylua.toml`), single quotes, `local M = {}` module
  pattern. Run `stylua` after editing; CI enforces it.
- **`---@class` / `---@field` / `---@param` LuaCATS annotations everywhere** —
  they drive `lua-language-server` completions and are not noise. Keep them
  when editing.
- **Alignment-heavy tables** (key tables, color palettes, `MOUSE_DEFAULTS` in
  `utils/help.lua`) use a leading `-- stylua: ignore` marker. Don't reformat
  those by hand — they'll fight the markers. `utils/default-bindings.lua` has
  no marker because it is machine-generated and already stylua-formatted.
- **`mod.SUPER` / `mod.SUPER_REV` in `config/bindings.lua`** map ALT/CTRL on
  Windows+Linux and SUPER/SUPER|CTRL on macOS (see top of that file). Use the
  table instead of hard-coding `ALT` or `SUPER` so cross-platform bindings
  stay consistent.
- **Platform branching** belongs in `utils/platform.lua` and (for OS-specific
  launch menu / default prog / pager) in `config/launch.lua` and
  `events/help.lua`. Do not re-detect the OS elsewhere.

## Adding things

**New event module:** create `events/foo.lua` exposing `M.setup(opts)`, then
add `require('events.foo').setup(...)` to `wezterm.lua` alongside the other
event setups. Use `utils.cells` + `utils.opts-validator` to match the existing
pattern (`right-status.lua` is the cleanest reference).

**New config option:** add it to the relevant `config/*.lua` file. The
`Config:append` chain runs in order — duplicate keys are dropped with a
warning, so don't define the same key in two files.

**New key binding:** add it to `config/bindings.lua`. If it is a custom event,
declare the event in the owning `events/*.lua` file too. If you want a Russian
description in the F1 reference, add an entry to `action_descriptions` in
`utils/help.lua` (`groups` puts it into a category).

**New color segment / status field:** build it via `Cells:new()` +
`add_segment` + `update_segment_text`/`update_segment_colors` + `render({ids})`,
then wrap in `wezterm.format(...)`. Nerd Font glyphs come from
`wezterm.nerdfonts` (e.g. `nf.ple_left_half_circle_thick`).

## Verification

There are **no tests and no build step**, but there *is* linting (see
`.github/workflows/lint.yml`):

1. `stylua --check .` — formatting; must pass (it is currently the only thing
   failing, due to the known WIP in `events/right-status.lua`).
2. `luacheck .` — warnings/lint; should be 0 warnings.
3. `luac -p <file>` — quick syntax check for one file.
4. `wezterm --config-file ~/.config/wezterm/wezterm.lua show-keys` — proves the
   whole config loads and shows the effective key table (works headless).
5. To preview the help output without the GUI:
   `wezterm --config-file /tmp/run-help.lua show-keys` where that temp config
   sets `package.path`, `require`s `utils.help`, writes `help.render()` to a
   file and calls `os.exit(0)`.

At runtime `wezterm.lua` reloads automatically on save
(`automatically_reload_config = true` in `config/general.lua`); on failure wezterm
shows the Lua error in a toast and writes it to its log file.

## Environment quirks

- **Font is hard-pinned** to `IosevkaTerm Nerd Font Mono` in `config/fonts.lua`.
  See `readme.md` for the download link. Many glyphs (semi-circles, battery,
  nerd icons) require this exact font — switching to a non-nerd variant will
  render them as `?`.
- `config/launch.lua` has hard-coded Windows paths (`d:/cygwin64/...`,
  `d:/msys64/...`) and `config/domains.lua` has a hard-coded WSL username
  (`kevin`). These are personal-environment artifacts — confirm with the user
  before "fixing" them.
- WSL image previews in `yazi` only work when launched via the SSH domain
  defined in `config/domains.lua` (commented in the file).
- The right-side date is driven by `update-right-status` on a 1 s cadence
  (`status_update_interval = 1000` in `config/general.lua`).
- **Regenerate `utils/default-bindings.lua` after upgrading wezterm:**
  ```sh
  wezterm --skip-config show-keys --lua > /tmp/dk-default.lua
  wezterm --skip-config show-keys --lua --key-table copy_mode  > /tmp/dk-copy.lua
  wezterm --skip-config show-keys --lua --key-table search_mode > /tmp/dk-search.lua
  ```
  (the generator lives in the commit history / ask the user; the `--lua` files
  are loaded with a stubbed `wezterm.action` and re-serialized as plain tables).
- **Lua 5.1 runtime**: `string.format` does **not** support `%-*s` (use
  `utils/help.lua`'s `pad_right`), and `goto`/integer division quirks apply.
  `wezterm.time.now()` and `wezterm.gui.*` are not safely callable while the
  config file itself is loading — hence the generated defaults table and
  `os.date` for timestamps.

## Git state

`main` tracks `origin/main`. There is currently **one uncommitted local edit**
in `events/right-status.lua` (un-commenting the `date_text` update so the
clock actually renders). Do not commit it without asking — it may be WIP.