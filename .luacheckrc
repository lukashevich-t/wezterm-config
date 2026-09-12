-- luacheck config for the wezterm config repo
-- ref: https://github.com/lunarmodules/luacheck

std = "lua51"
cache = true
max_line_length = false
ignore = {
   ".luacheckcache",
}

exclude_files = {
   "docs/",
   ".luarocks/",
}

-- Globals available in the wezterm runtime:
--   wezterm      — the wezterm API namespace
--   window, pane — available only inside the F12 debug overlay REPL
--                  (see utils/help.lua: `_G._keys` reads `window:effective_config()`)
read_globals = {
   wezterm = { other_fields = true },
   window = { other_fields = true },
   pane = { other_fields = true },
}

-- Debug/dump helpers intentionally set as globals:
globals = {
   "dump",
}
