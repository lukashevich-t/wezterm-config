----------------------------------------------------------------------------------------------
-- Стартовое окно wezterm: спавн первого окна + подсказка «как открыть справку».
--
-- Подсказка выводится двумя независимыми способами:
--   * toast поверх окна (рисует сам wezterm, живёт TOAST_MS мс)
--   * строки в скроллбэке первой панели через pane:inject_output
--
-- Инъекция отложенная: p10k instant prompt (~/.zshrc, строки 1-5) перерисовывает
-- экран на первой отрисовке промпта и затирает всё, что вброшено раньше.
--
-- Текст лидера берётся из effective_config, чтобы не расходиться с config/bindings.lua.
----------------------------------------------------------------------------------------------

local wezterm = require('wezterm')

local mux = wezterm.mux

---Задержка перед inject_output, сек — ждём первую отрисовку промпта
local INJECT_DELAY = 1.5

---Время жизни toast, мс
local TOAST_MS = 6000

---@alias StartupHint string[] строки подсказки, '%s' — лидер

---@type StartupHint
local HINT = {
    ' F1 — справка по горячим клавишам',
    ' %s + / — поиск по сочетаниям',
    ' F12 → _keys() — та же справка в Debug Overlay',
}

local SGR_DIM_ITALIC = '\27[2;3m'
local SGR_RESET = '\27[0m'

---Лидер из effective_config окна: 'CTRL+SPACE', 'SUPER+CTRL+SPACE', ...
---@param gui any wezterm.GuiWindow
---@return string
local function leader_hint(gui)
    local ok, cfg = pcall(gui.effective_config, gui)
    local leader = ok and type(cfg) == 'table' and cfg.leader or nil
    if type(leader) ~= 'table' or type(leader.key) ~= 'string' then
        return 'LEADER'
    end
    local mods = type(leader.mods) == 'string' and leader.mods:gsub('|', '+') or ''
    if mods == '' then
        return string.upper(leader.key)
    end
    return mods .. '+' .. string.upper(leader.key)
end

---Подставить лидер в строки подсказки (в шаблонах HINT ровно один '%s' и никаких '%')
---@param leader string
---@return string[] lines строки с отступом, 'plain' — те же строки без отступа
local function hint_lines(leader)
    local lines, plain = {}, {}
    for _, line in ipairs(HINT) do
        local formatted = (string.format(line, leader))
        table.insert(lines, formatted)
        table.insert(plain, (formatted:gsub('^%s+', '')))
    end
    return lines, plain
end

wezterm.on('gui-startup', function(cmd)
    local _, pane, win = mux.spawn_window(cmd or {})
    local gui = win:gui_window()
    gui:maximize()

    local lines, plain = hint_lines(leader_hint(gui))

    gui:toast_notification('WezTerm', table.concat(plain, '  ·  '), nil, TOAST_MS)

    wezterm.time.call_after(INJECT_DELAY, function()
        local ok, err = pcall(function()
            local body = SGR_DIM_ITALIC .. table.concat(lines, SGR_RESET .. '\r\n' .. SGR_DIM_ITALIC)
            pane:inject_output('\r\n' .. body .. SGR_RESET .. '\r\n')
        end)
        if not ok then
            wezterm.log_error('startup: inject_output не удался: ' .. tostring(err))
        end
    end)
end)
