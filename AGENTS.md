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
│   └── startup.lua         ← gui-startup: spawns initial window
├── utils/                  ← shared helpers, all `require('utils.X')`
│   ├── platform.lua        ← {os, is_win, is_linux, is_mac} via wezterm.target_triple
│   ├── cells.lua           ← Cells class for wezterm.format() segments (workhorse)
│   ├── opts-validator.lua  ← schema-validated event opts (used by right-status, tab-title)
│   ├── gpu-adapter.lua     ← auto-pick WebGPU adapter per OS
│   ├── math.lua            ← clamp, round
│   ├── dump.lua            ← global __dump/__pdump
│   └── help.lua            ← registers global _keys() (Russian descriptions)
├── colors/custom.lua       ← active color scheme (catppuccin-mocha variant)
└── docs/                   ← reference: default-config.md, default-keys.md,
                              ahk.md (Windows quake-style AHK script),
                              tempNotes.md (scratchpad, not authoritative)
```

## Hidden coupling — easy to miss

- **`config/domains.lua` is NOT in `wezterm.lua`'s append chain** (see the
  commented-out block at the bottom of `wezterm.lua`). But
  `events/new-tab-button.lua` requires it for `wsl_domains`/`ssh_domains`/
  `unix_domains` to populate the right-click launcher menu. Do **not** delete
  it as "dead code".
- `events/tab-title.lua` defines three custom events consumed by
  `config/bindings.lua`: `tabs.manual-update-tab-title`, `tabs.reset-tab-title`,
  `tabs.toggle-tab-bar`. Key names must stay in sync with both files.
- `utils/help.lua` installs `_G._keys`; the F12 debug overlay is the only way
  to invoke it from the running terminal. Don't move it out of `utils/` without
  keeping the `require` in `wezterm.lua`.

## Conventions to preserve

- **3-space indent, single quotes, `local M = {}` module pattern.**
- **`---@class` / `---@field` / `---@param` LuaCATS annotations everywhere** —
  they drive `lua-language-server` completions and are not noise. Keep them
  when editing.
- **Alignment-heavy tables** (key tables, color palettes) use a leading
  `-- stylua: ignore` marker. There is **no `stylua.toml`** in the repo;
  don't reformat those tables — they'll fight the markers.
- **`mod.SUPER` / `mod.SUPER_REV` in `config/bindings.lua`** map ALT/CTRL on
  Windows+Linux and SUPER/SUPER|CTRL on macOS (see top of that file). Use the
  table instead of hard-coding `ALT` or `SUPER` so cross-platform bindings
  stay consistent.
- **Platform branching** belongs in `utils/platform.lua` and (for OS-specific
  launch menu / default prog) in `config/launch.lua`. Do not re-detect the
  OS elsewhere.

## Adding things

**New event module:** create `events/foo.lua` exposing `M.setup(opts)`, then
add `require('events.foo').setup(...)` to `wezterm.lua` alongside the other
event setups. Use `utils.cells` + `utils.opts-validator` to match the existing
pattern (`right-status.lua` is the cleanest reference).

**New config option:** add it to the relevant `config/*.lua` file. The
`Config:append` chain runs in order — duplicate keys are dropped with a
warning, so don't define the same key in two files.

**New color segment / status field:** build it via `Cells:new()` +
`add_segment` + `update_segment_text`/`update_segment_colors` + `render({ids})`,
then wrap in `wezterm.format(...)`. Nerd Font glyphs come from
`wezterm.nerdfonts` (e.g. `nf.ple_left_half_circle_thick`).

## Verification

There are **no tests, no lint, no typecheck, no build step**. The only
verification is:

1. `wezterm.lua` is reloaded automatically on save
   (`automatically_reload_config = true` in `config/general.lua`).
2. On failure, wezterm surfaces the Lua error in a toast and logs to its log
   file (`wezterm log` or check the GUI window).
3. Reload manually with `wezterm cli send-text --no-paste "key:ctrl+shift+R"`
   or via the `ReloadConfiguration` action if you bind it.

Use `_keys()` from inside the debug overlay (F12) to print a categorized list
of current bindings (labels are in Russian — see `utils/help.lua`).

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

## Git state

`main` tracks `origin/main`. There is currently **one uncommitted local edit**
in `events/right-status.lua` (un-commenting the `date_text` update so the
clock actually renders). Do not commit it without asking — it may be WIP.