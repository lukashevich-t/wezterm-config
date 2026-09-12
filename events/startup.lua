local wezterm = require('wezterm')

local mux = wezterm.mux
wezterm.on('gui-startup', function(cmd)
    local _, pane, window = mux.spawn_window(cmd or {})
    window:gui_window():maximize()
    pane:inject_output(
        '==================================\r\n\x1b[3mecho Press F12 to open debug overlay, then call _keys() function\r\n==================================\r\n'
    )
end)
