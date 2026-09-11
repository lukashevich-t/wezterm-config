local gpu_adapters = require('utils.gpu-adapter')
-- local backdrops = require('utils.backdrops')
local colors = require('colors.custom')

return {
    max_fps = 60,
    front_end = 'OpenGL',
    webgpu_power_preference = 'HighPerformance',
    webgpu_preferred_adapter = gpu_adapters:pick_best(),
    -- webgpu_preferred_adapter = gpu_adapters:pick_manual('Dx12', 'IntegratedGpu'),
    -- webgpu_preferred_adapter = gpu_adapters:pick_manual('Gl', 'Other'),
    underline_thickness = '1.5pt',

    -- cursor
    animation_fps = 40,
    cursor_blink_ease_in = 'Linear',
    cursor_blink_ease_out = 'Linear',
    default_cursor_style = 'BlinkingBar', -- SteadyBlock, BlinkingBlock, SteadyUnderline, BlinkingUnderline, SteadyBar,  BlinkingBar
    cursor_blink_rate = 500,

    window_decorations = 'NONE', -- NONE, RESIZE, TITLE, "RESIZE | TITLE"

    -- color scheme
    colors = colors,
    -- color_scheme = 'Mariana', -- not so bad
    -- color_scheme = 'Material (base16)', -- not so bad
    -- background
    -- background = backdrops:initial_options(false), -- set to true if you want wezterm to start on focus mode

    -- scrollbar
    enable_scroll_bar = true,

    -- tab bar
    enable_tab_bar = true,
    hide_tab_bar_if_only_one_tab = false,
    use_fancy_tab_bar = false,
    tab_max_width = 25,
    show_tab_index_in_tab_bar = false,
    switch_to_last_active_tab_when_closing_tab = true,

    -- window
    window_padding = {
        left = 5,
        right = 5,
        top = 5,
        bottom = 5,
    },
    adjust_window_size_when_changing_font_size = false,
    window_close_confirmation = 'NeverPrompt', -- *AlwaysPrompt, NeverPrompt
    window_frame = {
        active_titlebar_bg = '#ffffff',
        -- font = fonts.font,
        -- font_size = fonts.font_size,
    },
    inactive_pane_hsb = {
        saturation = 0.8,
        brightness = 0.4,
    },

    visual_bell = {
        fade_in_function = 'Constant',
        fade_in_duration_ms = 30,
        fade_out_function = 'Constant',
        fade_out_duration_ms = 30,
        target = 'BackgroundColor', -- BackgroundColor, CursorColor
    },
}
