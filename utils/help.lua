-- local wt = require('wezterm')

local function format_shortcut(mods, key, description)
    -- max len for mods: 10, max len for key: 11
    return string.format('%-10s + %-12s - %s', mods, string.format('%q', key), description)
end

local actionDesctiptions = {
    ClearScrollback = {
        groups = { 'History' },
        describe = function(command)
            if command.action.ClearScrollback == 'ScrollbackOnly' then
                return 'Очистить буфер вывода (' .. command.action.ClearScrollback .. ')'
            else
                return 'Очистить буфер вывода и окно вывода ('
                    .. command.action.ClearScrollback
                    .. ')'
            end
        end,
    },
    ActivateCopyMode = {
        groups = { 'Search & selection' },
        describe = function(command)
            return 'Включает режим копирования'
        end,
    },
    ActivateCommandPalette = {
        groups = { 'Interface' },
        describe = function(command)
            return 'Показать командную панель'
        end,
    },
    ShowLauncher = {
        groups = { 'Interface' },
        describe = function(command)
            return 'Запуск предопределенных команд'
        end,
    },
    ToggleFullScreen = {
        groups = { 'Windows & tabs' },
        describe = function(command)
            return 'На весь экран'
        end,
    },
    ShowDebugOverlay = {
        groups = { 'Interface' },
        describe = function(command)
            return 'Отладочный терминал'
        end,
    },
    Search = {
        groups = { 'Search & selection' },
        describe = function(command)
            return 'Поиск'
        end,
    },
    QuickSelectArgs = {
        groups = { 'Search & selection' },
        describe = function(command)
            return 'копирование предопределенных паттернов в clipboard'
        end,
    },
    ShowLauncherArgs = {
        groups = { 'Interface' },
        describe = function(command)
            result = 'Подбор: '
            flags = string.upper(command.action.ShowLauncherArgs.flags)
            if string.find(flags, 'TABS') then
                result = result .. 'табов, '
            end
            if string.find(flags, 'LAUNCH_MENU_ITEMS') then
                result = result .. 'предопределенных команд, '
            end
            if string.find(flags, 'DOMAINS') then
                result = result .. 'доменов, '
            end
            if string.find(flags, 'KEY_ASSIGNMENTS') then
                result = result .. 'сочетаний клавиш, '
            end
            if string.find(flags, 'WORKSPACES') then
                result = result .. 'рабочих пространств, '
            end
            if string.find(flags, 'COMMANDS') then
                result = result .. 'стандартных команд, '
            end
            if string.find(flags, 'FUZZY') then
                result = result .. '(fuzzy only)'
            end
            return result
        end,
    },
    ActivateTabRelative = {
        groups = { 'Windows & tabs' },
        describe = function(command)
            if command.action.ActivateTabRelative > 0 then
                return 'Переход на следующую вкладку'
            else
                return 'Переход на предыдущую вкладку'
            end
        end,
    },
    ActivateTab = {
        groups = { 'Windows & tabs' },
        describe = function(command)
            return string.format('Переход на вкладку # %d', command.action.ActivateTab + 1)
        end,
    },
    SendString = {
        groups = { 'Input' },
        describe = function(command)
            return string.format('Послать в терминал строку %q', command.action.SendString)
        end,
    },
    CopyTo = {
        groups = { 'Input' },
        describe = function(command)
            t = {
                ClipboardAndPrimarySelection = 'буфер обмена и PrimarySelection',
                Clipboard = 'буфер обмена',
                PrimarySelection = 'PrimarySelection',
            }
            return string.format('скопировать выделенное в %s', t[command.action.CopyTo])
        end,
    },
    PasteFrom = {
        groups = { 'Input' },
        describe = function(command)
            t = {
                Clipboard = 'буфера обмена',
                PrimarySelection = 'PrimarySelection',
            }
            return string.format('вставить из %s', t[command.action.PasteFrom])
        end,
    },
    SpawnTab = {
        groups = { 'Windows & tabs' },
        describe = function(command)
            domain = command.action.SpawnTab
            if type(domain) == 'table' then
                domain = domain.DomainName
            end
            return string.format('Новая вкладка в домене %s', domain)
        end,
    },
    CloseCurrentTab = {
        groups = { 'Windows & tabs' },
        describe = function(command)
            if command.action.CloseCurrentTab.confirm then
                return 'Закрыть текущую вкладку с подтверждением'
            else
                return 'Закрыть текущую вкладку без подтверждения'
            end
        end,
    },
    EmitEvent = {
        groups = { 'Interface' },
        describe = function(command)
            return 'Послать сообщение ' .. command.action.EmitEvent
        end,
    },
    SpawnWindow = {
        groups = { 'Windows & tabs' },
        describe = function(command)
            return 'Создать новое ОКНО со вкладкой из домена по умолчанию'
        end,
    },
    SplitVertical = {
        groups = { 'Panes' },
        describe = function(command)
            return 'Создать панель ниже из домена ' .. command.action.SplitVertical.domain
        end,
    },
    SplitHorizontal = {
        groups = { 'Panes' },
        describe = function(command)
            return 'Создать панель справа из домена '
                .. command.action.SplitHorizontal.domain
        end,
    },
    TogglePaneZoomState = {
        groups = { 'Panes' },
        describe = function(command)
            return 'Развернуть текущую панель на все окно'
        end,
    },
    ScrollByLine = {
        groups = { 'History' },
        describe = function(command)
            count = command.action.ScrollByLine
            if count > 0 then
                return string.format('скролл на %d строк ниже', count)
            else
                return string.format('скролл на %d строк выше', math.abs(count))
            end
        end,
    },
    ScrollByPage = {
        groups = { 'history' },
        describe = function(command)
            count = command.action.ScrollByPage
            if count > 0 then
                return string.format('скролл на %d страниц ниже', count)
            else
                return string.format('скролл на %d страниц выше', math.abs(count))
            end
        end,
    },
    ActivatePaneDirection = {
        groups = { 'Panes' },
        describe = function(command)
            direction = command.action.ActivatePaneDirection
            if string.lower(direction) == 'left' then
                return 'Переключиться на панель левее'
            end
            if string.lower(direction) == 'right' then
                return 'Переключиться на панель правее'
            end
            if string.lower(direction) == 'up' then
                return 'Переключиться на панель выше'
            end
            if string.lower(direction) == 'down' then
                return 'Переключиться на панель ниже'
            end
        end,
    },
    ActivateKeyTable = {
        groups = { 'Interface' },
        describe = function(command)
            p = command.action.ActivateKeyTable
            return string.format(
                'Включить keytable %s. one_shot = %s, prevent_fallback = %s, replace_current = %s, p.until_unknown = %s',
                p.name,
                tostring(p.one_shot),
                tostring(p.prevent_fallback),
                tostring(p.replace_current),
                tostring(p.until_unknown)
            )
        end,
    },
}

local function get_uniq_groups()
    local d = actionDesctiptions
    local result = {}
    for k, description in pairs(actionDesctiptions) do
        if description.groups then
            for k1, v1 in ipairs(description.groups) do
                result[string.lower(v1)] = v1
            end
        else
            result['other'] = 'Other'
        end
    end
    result['other'] = 'Other'
    return result
end

local function describe_action(command)
    local action = command['action']
    local actionName = 'Unknown'
    if type(action) == 'string' then
        actionName = action
    else
        for k, v in pairs(action) do
            actionName = k
            break
        end
    end
    if actionDesctiptions[actionName] == nil or actionDesctiptions[actionName].describe == nil then
        return actionName
    else
        return actionDesctiptions[actionName].describe(command)
    end
end

local function filter_keys(all_keys, group_id)
    local result = {}
    for k, v in ipairs(all_keys) do
        local action_name = ''
        local action = v.action
        if type(action) == 'string' then
            action_name = action
        else
            for x, y in pairs(action) do
                action_name = x
                break
            end
        end
        if action_name == '' then
            goto continue
        end
        if actionDesctiptions[action_name] and actionDesctiptions[action_name].groups then
            for g_idx, g_name in ipairs(actionDesctiptions[action_name].groups) do
                if string.lower(g_name) == group_id then
                    table.insert(result, v)
                    break
                end
            end
        else
            if group_id == 'other' then
                table.insert(result, v)
            end
        end
        ::continue::
    end
    return result
end

local function srep(str, count)
    local result = ''
    for i = 1, count do
        result = result .. str
    end
    return result
end

local function cpad(str, count, symbol)
    local l = string.len(str)
    if l >= count or #symbol ~= 1 then
        return str
    end
    local left_spaces = math.floor((count - l + 1) / 2)
    local right_spaces = count - l - left_spaces
    return srep(symbol, left_spaces) .. str .. srep(symbol, right_spaces)
end

_G._keys = function(group_id)
    local uniq_groups = get_uniq_groups()

    local conf = window:effective_config()
    local result = '\n'

    local all_keys = conf['keys']
    for group_id, group_name in pairs(uniq_groups) do
        result = result .. cpad(group_name, 80, '=') .. '\n'
        keys = filter_keys(all_keys, group_id)
        for k, v in ipairs(keys) do
            result = result .. format_shortcut(v['mods'], v['key'], describe_action(v)) .. '\n'
        end
    end

    print(result)
end
