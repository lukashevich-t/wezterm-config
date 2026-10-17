------------------------------------------------------------------------------------------
-- Справка по горячим клавишам: два способа вызова из самого wezterm.
--
--   F1           → событие help.show-pager  — полный список в новой вкладке
--                   (Linux/macOS: less, Windows: PowerShell Get-Content)
--   LEADER + ?   → событие help.show-picker — fuzzy-поиск по активным сочетаниям,
--                   ENTER копирует сочетание в буфер обмена
--
-- Обработчики читают window:effective_config(), поэтому в списке видны и
-- переопределения, сделанные через window:set_config_overrides().
--
-- Текст справки пишется во временный файл уже при загрузке конфига (в wezterm
-- запись в файл внутри обработчика события может быть недоступна), а в
-- обработчике файл обновляется по возможности.
--
-- Биндинги на эти события живут в config/bindings.lua (раздел misc/useful и
-- key-tables), обработчики — здесь.
------------------------------------------------------------------------------------------

local wezterm = require('wezterm')
local act = wezterm.action
local platform = require('utils.platform')
local help = require('utils.help')

local M = {}

local nf = wezterm.nerdfonts

---Файл справки, созданный при загрузке конфига (запасной вариант)
---@type string|nil
local cached_path = nil

---Команда для показа файла: less на unix, PowerShell Get-Content на Windows
---@param path string
---@return string program, string[] args
local function pager_command(path)
    if platform.is_win then
        return 'powershell.exe',
            {
                '-NoProfile',
                '-Command',
                string.format('Get-Content -Raw -Encoding UTF8 "%s"', path),
            }
    end
    return { 'less', '-R', '-X', '-F', path }
end

---Записать справку в новый временный файл
---@param text string
---@return string|nil path
local function write_help_file(text)
    wezterm.log_info('help.lua write_help_file')
    local got_path, path = pcall(os.tmpname)
    if not got_path or type(path) ~= 'string' then
        return nil
    end
    local ok, file = pcall(io.open, path, 'w')
    if not ok or file == nil then
        return nil
    end
    local written = pcall(function()
        file:write(text)
        file:flush()
    end)
    pcall(function()
        file:close()
    end)
    if not written then
        return nil
    end
    return path
end

---Данные текущего окна (с учётом set_config_overrides)
---@param window any wezterm.GuiWindow
---@return Help.Opts
local function effective_opts(window)
    wezterm.log_info('help.lua effective_opts')
    local ok, config = pcall(function()
        return window:effective_config()
    end)
    if not ok or type(config) ~= 'table' then
        return {}
    end
    return {
        keys = config.keys,
        key_tables = config.key_tables,
        mouse_bindings = config.mouse_bindings,
        leader = config.leader,
        defaults_disabled = config.disable_default_key_bindings,
        from_effective = true,
    }
end

---Справочный файл для показа: пробуем перезаписать его под текущее окно,
---иначе отдаём тот, что создан при загрузке конфига
---@param window any wezterm.GuiWindow
---@return string|nil path, string|nil error
local function help_file(window)
    wezterm.log_info('help.lua help_file')
    local ok, text = pcall(help.render, effective_opts(window))
    if ok then
        local written = write_help_file(text)
        if written ~= nil then
            return written
        end
    end
    return cached_path, not ok and tostring(text) or nil
end

---Показать справку в отдельной вкладке с пайпером
---@param window any wezterm.GuiWindow
---@param pane any wezterm.GuiPane|nil
local function show_pager(window, pane)
    wezterm.log_info('help.lua show_pager')
    local path, err = help_file(window)
    if path == nil then
        window:toast_notification(
            'WezTerm',
            'Не удалось подготовить справку: ' .. tostring(err),
            nil,
            4000
        )
        return
    end

    local args = pager_command(path)
    window:perform_action(act.SpawnCommandInNewTab({ args = args }), pane)
end

---Fuzzy-поиск по активным сочетаниям + копирование в буфер обмена
---@param window any wezterm.GuiWindow
---@param pane any wezterm.GuiPane|nil
local function show_picker(window, pane)
    wezterm.log_info('help.lua show_picker')
    local ok, entries = pcall(help.active_entries, effective_opts(window))
    if not ok or #entries == 0 then
        window:toast_notification('WezTerm', 'Список сочетаний недоступен', nil, 3000)
        return
    end

    local chords, choices = {}, {}
    for idx, entry in ipairs(entries) do
        chords[idx] = entry.chord
        choices[idx] = {
            id = tostring(idx),
            label = string.format('%-24s  %s', entry.chord, entry.description),
            -- description = entry.category,
        }
    end

    window:perform_action(
        act.InputSelector({
            title = string.format('%s Справка: горячие клавиши', nf.md_lightbulb),
            description = 'ENTER — скопировать сочетание в буфер обмена',
            fuzzy = true,
            fuzzy_description = 'Поиск сочетания: ',
            choices = choices,
            action = wezterm.action_callback(function(_window, _pane, id)
                if id == nil then
                    return
                end
                local chord = chords[tonumber(id)]
                if chord == nil then
                    return
                end
                local copied = pcall(function()
                    wezterm.clipboard.set(chord)
                end)
                window:toast_notification(
                    'WezTerm',
                    copied and string.format('%s — скопировано', chord)
                        or string.format('%s (буфер недоступен)', chord),
                    nil,
                    1500
                )
            end),
        }),
        pane
    )
end

M.setup = function()
    wezterm.log_info('help.lua setup')
    local ok, err = pcall(function()
        cached_path = write_help_file(help.render())
    end)
    if not ok or cached_path == nil then
        wezterm.log_error(
            string.format('help: не удалось создать файл справки: %s', tostring(err))
        )
    end

    wezterm.on('help.show-pager', show_pager)
    wezterm.on('help.show-picker', show_picker)
end

return M
