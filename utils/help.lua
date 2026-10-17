------------------------------------------------------------------------------------------
-- Справка по горячим клавишам: собирает объединённый список сочетаний (из конфига
-- + стандартные сочетания wezterm), сгруппированный по категориям.
--
-- Вызов из терминала:
--   * F1            — полный список в новой вкладке (less / PowerShell Get-Content)
--   * LEADER + ?    — быстрый fuzzy-поиск по активным сочетаниям + копирование
--   * F12 → _keys() — тот же текст в отладочном оверлее
--
-- Источники данных: config/bindings.lua (свои сочетания) + utils/default-bindings.lua
-- (стандартные привязки wezterm, снятые через `wezterm show-keys`). Если вызывающий
-- код передал window:effective_config(), используются фактические данные окна.
------------------------------------------------------------------------------------------

local wezterm = require('wezterm')
local platform = require('utils.platform')

local M = {}

---@alias Help.Category
---| 'Интерфейс'
---| 'Окна и вкладки'
---| 'Панели'
---| 'Ввод и буфер обмена'
---| 'Скролл и буфер'
---| 'Поиск и выделение'
---| 'Мышь'
---| 'Клавиатурные таблицы'
---| 'Прочее'

---@alias Help.Source 'config'|'default'
---@alias Help.Origin 'custom'|'override'|'standard'

---Порядок категорий в выводе
---@type Help.Category[]
local CATEGORY_ORDER = {
    'Интерфейс',
    'Окна и вкладки',
    'Панели',
    'Ввод и буфер обмена',
    'Скролл и буфер',
    'Поиск и выделение',
    'Мышь',
    'Клавиатурные таблицы',
    'Прочее',
}

local CATEGORY_RANK = {}
for idx, name in ipairs(CATEGORY_ORDER) do
    CATEGORY_RANK[name:lower()] = idx
end

---@class Help.Entry
---@field category Help.Category
---@field label string Левая колонка: сочетание (для таблиц — с отступом)
---@field chord string Сочетание в виде CTRL+SHIFT+P
---@field description string Описание действия
---@field source Help.Source
---@field active boolean Активно ли сочетание в основной таблице
---@field origin Help.Origin
---@field section string? Имя клавиатурной таблицы
---@field signature string? Ключ для сопоставления со стандартными
---@field rank number Поле для стабильной сортировки

---@class Help.Opts
---@field keys? table[] Клавиши (по умолчанию — config/bindings.lua)
---@field key_tables? table<string, table[]> Клавиатурные таблицы
---@field mouse_bindings? table[] Мышиные привязки
---@field leader? {key: string, mods: string, timeout_milliseconds: number|nil}
---@field defaults_disabled? boolean Значение disable_default_key_bindings
---@field from_effective? boolean Данные взяты из window:effective_config()

--------------------------------------------------------------------------------
-- Мелкие помощники
--------------------------------------------------------------------------------

---@param str string
---@param count number
---@return string
local function srep(str, count)
    local result = ''
    for _ = 1, count do
        result = result .. str
    end
    return result
end

---@param str string
---@param count number
---@param symbol string
---@return string
local function cpad(str, count, symbol)
    local l = #str
    if l >= count or #symbol ~= 1 then
        return str
    end
    local left = math.floor((count - l) / 2)
    return srep(symbol, left) .. str .. srep(symbol, count - l - left)
end

---Дополнить строку пробелами до width (Lua 5.1 не умеет %-*s)
---@param str string
---@param width number
---@return string
local function pad_right(str, width)
    local diff = width - #str
    if diff <= 0 then
        return str
    end
    return str .. srep(' ', diff)
end

--------------------------------------------------------------------------------
-- Описания действий
--------------------------------------------------------------------------------

local describe_copy_mode, action_name

---Число в виде строки без «хвостовых» нулей (1.0 -> 1)
---@param value any
---@return string
local function fmt_num(value)
    local n = tonumber(value)
    if n == nil then
        return tostring(value)
    end
    if n == math.floor(n) then
        return string.format('%d', n)
    end
    return tostring(n)
end

---Переводы имён CopyMode (режимы копирования и поиска)
---@type table<string, string>
local COPY_MODE_NAMES = {
    MoveForwardWord = 'вперёд на слово',
    MoveBackwardWord = 'назад на слово',
    MoveForwardWordEnd = 'вперёд до конца слова',
    MoveToStartOfLine = 'в начало строки',
    MoveToStartOfLineContent = 'в начало текста строки',
    MoveToEndOfLineContent = 'в конец текста строки',
    MoveToStartOfNextLine = 'в начало следующей строки',
    MoveToScrollbackTop = 'в начало буфера',
    MoveToScrollbackBottom = 'в конец буфера',
    MoveToViewportTop = 'в начало экрана',
    MoveToViewportMiddle = 'в центр экрана',
    MoveToViewportBottom = 'в конец экрана',
    MoveToSelectionOtherEnd = 'к другому краю выделения',
    MoveToSelectionOtherEndHoriz = 'к другому краю выделения',
    MoveLeft = 'влево',
    MoveRight = 'вправо',
    MoveUp = 'вверх',
    MoveDown = 'вниз',
    MoveByPage = 'прокрутка на страниц',
    PageUp = 'страница вверх',
    PageDown = 'страница вниз',
    JumpForward = 'следующее совпадение',
    JumpBackward = 'предыдущее совпадение',
    JumpReverse = 'обратный поиск',
    JumpAgain = 'повторить поиск',
    NextMatch = 'следующее совпадение',
    PriorMatch = 'предыдущее совпадение',
    NextMatchPage = 'следующее совпадение (страница)',
    PriorMatchPage = 'предыдущее совпадение (страница)',
    CycleMatchType = 'сменить режим поиска',
    ClearPattern = 'очистить образец',
    Close = 'выйти из режима',
}

---Направления панелей/окон (в нижнем регистре — как в wezterm)
---@type table<string, string>
local DIRS = {
    up = 'вверх',
    down = 'вниз',
    left = 'влево',
    right = 'вправо',
}

---@type table<string, string>
local COPY_TARGETS = {
    ClipboardAndPrimarySelection = 'буфер обмена + PrimarySelection',
    Clipboard = 'буфер обмена',
    PrimarySelection = 'PrimarySelection',
}

---@type table<string, string>
local SELECTION_MODES = {
    Cell = 'символ',
    Line = 'строку',
    Block = 'прямоугольник',
}

---@class Help.ActionDesc
---@field groups Help.Category[]
---@field describe fun(command: table): string|nil

---@type table<string, Help.ActionDesc>
local action_descriptions = {
    ------------------------------------------------------------------ Интерфейс --
    ActivateCommandPalette = {
        groups = { 'Интерфейс' },
        describe = function(_)
            return 'Командная панель (в т.ч. стандартные команды wezterm)'
        end,
    },
    ShowLauncher = {
        groups = { 'Интерфейс' },
        describe = function(_)
            return 'Лаунчер: список запуска (launch_menu)'
        end,
    },
    ShowLauncherArgs = {
        groups = { 'Интерфейс' },
        describe = function(command)
            local flags = string.upper(tostring(command.action.ShowLauncherArgs.flags))
            local parts = {}
            if flags:find('FUZZY') then
                table.insert(parts, 'fuzzy')
            end
            if flags:find('TABS') then
                table.insert(parts, 'вкладки')
            end
            if flags:find('WORKSPACES') then
                table.insert(parts, 'рабочие пространства')
            end
            if flags:find('LAUNCH_MENU_ITEMS') then
                table.insert(parts, 'список запуска')
            end
            if flags:find('DOMAINS') then
                table.insert(parts, 'домены')
            end
            if flags:find('KEY_ASSIGNMENTS') then
                table.insert(parts, 'сочетания клавиш')
            end
            if flags:find('COMMANDS') then
                table.insert(parts, 'команды')
            end
            return string.format('Лаунчер (%s)', table.concat(parts, ', '))
        end,
    },
    ShowDebugOverlay = {
        groups = { 'Интерфейс' },
        describe = function(_)
            return 'Отладочный оверлей (там же _keys() печатает эту справку)'
        end,
    },
    ShowTabNavigator = {
        groups = { 'Интерфейс' },
        describe = function(_)
            return 'Навигатор вкладок'
        end,
    },
    EmitEvent = {
        groups = { 'Интерфейс' },
        describe = function(command)
            local event = tostring(command.action.EmitEvent)
            local known = {
                ['tabs.manual-update-tab-title'] = 'Переименовать вкладку',
                ['tabs.reset-tab-title'] = 'Сбросить имя вкладки',
                ['tabs.toggle-tab-bar'] = 'Показать/скрыть панель вкладок',
                ['help.show-pager'] = 'Справка по горячим клавишам',
                ['help.show-picker'] = 'Поиск сочетаний (LEADER+?)',
            }
            if known[event] ~= nil then
                return string.format('%s [%s]', known[event], event)
            end
            if event:find('user%-defined') ~= nil then
                return 'обработчик из конфига (wezterm.action_callback)'
            end
            return string.format('событие [%s]', event)
        end,
    },
    ActivateKeyTable = {
        groups = { 'Интерфейс' },
        describe = function(command)
            local p = command.action.ActivateKeyTable
            local name = type(p) == 'table' and tostring(p.name) or tostring(p)
            return string.format('Включить клавиатурную таблицу «%s»', name)
        end,
    },
    PopKeyTable = {
        groups = { 'Интерфейс' },
        describe = function(_)
            return 'Выйти из клавиатурной таблицы'
        end,
    },
    ClearKeyTableStack = {
        groups = { 'Интерфейс' },
        describe = function(_)
            return 'Сбросить стек клавиатурных таблиц'
        end,
    },
    InputSelector = {
        groups = { 'Интерфейс' },
        describe = function(_)
            return 'Диалог выбора'
        end,
    },
    PromptInputLine = {
        groups = { 'Интерфейс' },
        describe = function(_)
            return 'Запрос строки ввода'
        end,
    },
    --------------------------------------------------------- Окна и вкладки --
    ToggleFullScreen = {
        groups = { 'Окна и вкладки' },
        describe = function(_)
            return 'Полноэкранный режим'
        end,
    },
    SpawnWindow = {
        groups = { 'Окна и вкладки' },
        describe = function(_)
            return 'Новое окно'
        end,
    },
    SpawnCommandInNewWindow = {
        groups = { 'Окна и вкладки' },
        describe = function(_)
            return 'Новое окно с командой'
        end,
    },
    SpawnTab = {
        groups = { 'Окна и вкладки' },
        describe = function(command)
            local domain = command.action.SpawnTab
            if type(domain) == 'table' then
                domain = domain.DomainName or 'CurrentPaneDomain'
            end
            return string.format('Новая вкладка (домен: %s)', domain)
        end,
    },
    SpawnCommandInNewTab = {
        groups = { 'Окна и вкладки' },
        describe = function(_)
            return 'Новая вкладка с командой'
        end,
    },
    CloseCurrentTab = {
        groups = { 'Окна и вкладки' },
        describe = function(command)
            local t = command.action.CloseCurrentTab
            local confirm = type(t) == 'table' and t.confirm
            return 'Закрыть вкладку'
                .. (confirm and ' (с подтверждением)' or ' (без подтверждения)')
        end,
    },
    ActivateTab = {
        groups = { 'Окна и вкладки' },
        describe = function(command)
            local idx = tonumber(command.action.ActivateTab) or 0
            if idx < 0 then
                return 'Перейти на последнюю вкладку'
            end
            return string.format('Перейти на вкладку #%d', idx + 1)
        end,
    },
    ActivateLastTab = {
        groups = { 'Окна и вкладки' },
        describe = function(_)
            return 'Перейти на последнюю вкладку'
        end,
    },
    ActivateTabRelative = {
        groups = { 'Окна и вкладки' },
        describe = function(command)
            local delta = tonumber(command.action.ActivateTabRelative) or 0
            return string.format('Вкладка %s (%+d)', delta > 0 and 'вперёд' or 'назад', delta)
        end,
    },
    ActivateTabRelativeNoWrap = {
        groups = { 'Окна и вкладки' },
        describe = function(command)
            local delta = tonumber(command.action.ActivateTabRelativeNoWrap) or 0
            return string.format(
                'Вкладка %s (%+d, без перехода через край)',
                delta > 0 and 'вперёд' or 'назад',
                delta
            )
        end,
    },
    MoveTab = {
        groups = { 'Окна и вкладки' },
        describe = function(_)
            return 'Переместить вкладку на позицию'
        end,
    },
    MoveTabRelative = {
        groups = { 'Окна и вкладки' },
        describe = function(command)
            local delta = tonumber(command.action.MoveTabRelative) or 0
            return string.format('Переместить вкладку (%+d)', delta)
        end,
    },
    ActivateWindow = {
        groups = { 'Окна и вкладки' },
        describe = function(command)
            return string.format('Перейти на окно #%d', (tonumber(command.action.ActivateWindow) or 0) + 1)
        end,
    },
    ActivateWindowRelative = {
        groups = { 'Окна и вкладки' },
        describe = function(command)
            local delta = tonumber(command.action.ActivateWindowRelative) or 0
            return string.format('Окно %s (%+d)', delta > 0 and 'вперёд' or 'назад', delta)
        end,
    },
    ActivateWindowRelativeNoWrap = {
        groups = { 'Окна и вкладки' },
        describe = function(command)
            local delta = tonumber(command.action.ActivateWindowRelativeNoWrap) or 0
            return string.format(
                'Окно %s (%+d, без перехода через край)',
                delta > 0 and 'вперёд' or 'назад',
                delta
            )
        end,
    },
    SwitchToWorkspace = {
        groups = { 'Окна и вкладки' },
        describe = function(_)
            return 'Переключиться на рабочее пространство'
        end,
    },
    SwitchWorkspaceRelative = {
        groups = { 'Окна и вкладки' },
        describe = function(command)
            local delta = tonumber(command.action.SwitchWorkspaceRelative) or 0
            return string.format(
                'Рабочее пространство %s (%+d)',
                delta > 0 and 'вперёд' or 'назад',
                delta
            )
        end,
    },
    Hide = {
        groups = { 'Окна и вкладки' },
        describe = function(_)
            return 'Свернуть окно'
        end,
    },
    HideApplication = {
        groups = { 'Окна и вкладки' },
        describe = function(_)
            return 'Скрыть приложение (macOS)'
        end,
    },
    Show = {
        groups = { 'Окна и вкладки' },
        describe = function(_)
            return 'Показать окно'
        end,
    },
    QuitApplication = {
        groups = { 'Окна и вкладки' },
        describe = function(_)
            return 'Закрыть wezterm'
        end,
    },
    SetWindowLevel = {
        groups = { 'Окна и вкладки' },
        describe = function(command)
            local levels =
                { Normal = 'обычное', Floating = 'поверх всех', Below = 'под всеми' }
            local level = tostring(command.action.SetWindowLevel)
            return string.format('Уровень окна: %s', levels[level] or level)
        end,
    },
    ReloadConfiguration = {
        groups = { 'Окна и вкладки' },
        describe = function(_)
            return 'Перезагрузить конфиг'
        end,
    },
    ResetFontAndWindowSize = {
        groups = { 'Окна и вкладки' },
        describe = function(_)
            return 'Сбросить шрифт и размер окна'
        end,
    },
    StartWindowDrag = {
        groups = { 'Окна и вкладки' },
        describe = function(_)
            return 'Перетащить окно мышью'
        end,
    },
    AttachDomain = {
        groups = { 'Окна и вкладки' },
        describe = function(_)
            return 'Подключить домен'
        end,
    },
    DetachDomain = {
        groups = { 'Окна и вкладки' },
        describe = function(_)
            return 'Отключить домен'
        end,
    },
    -------------------------------------------------------------------- Панели --
    SplitVertical = {
        groups = { 'Панели' },
        describe = function(command)
            return string.format(
                'Разделить панель снизу (домен: %s)',
                command.action.SplitVertical.domain
            )
        end,
    },
    SplitHorizontal = {
        groups = { 'Панели' },
        describe = function(command)
            return string.format(
                'Разделить панель справа (домен: %s)',
                command.action.SplitHorizontal.domain
            )
        end,
    },
    SplitPane = {
        groups = { 'Панели' },
        describe = function(_)
            return 'Разделить панель (с опциями)'
        end,
    },
    CloseCurrentPane = {
        groups = { 'Панели' },
        describe = function(command)
            local t = command.action.CloseCurrentPane
            local confirm = type(t) == 'table' and t.confirm
            return 'Закрыть панель'
                .. (confirm and ' (с подтверждением)' or ' (без подтверждения)')
        end,
    },
    TogglePaneZoomState = {
        groups = { 'Панели' },
        describe = function(_)
            return 'Развернуть панель на всё окно'
        end,
    },
    SetPaneZoomState = {
        groups = { 'Панели' },
        describe = function(command)
            local state = tostring(command.action.SetPaneZoomState)
            return state == 'true' and 'Развернуть панель' or 'Свернуть панель'
        end,
    },
    AdjustPaneSize = {
        groups = { 'Панели' },
        describe = function(command)
            local dir, delta = command.action.AdjustPaneSize[1], command.action.AdjustPaneSize[2]
            local dirs = DIRS
            return string.format(
                'Изменить размер панели: %s (%+d)',
                dirs[tostring(dir):lower()] or tostring(dir),
                tonumber(delta) or 0
            )
        end,
    },
    ActivatePaneDirection = {
        groups = { 'Панели' },
        describe = function(command)
            local dirs = DIRS
            local dir = tostring(command.action.ActivatePaneDirection)
            return string.format('Фокус на панель %s', dirs[dir:lower()] or dir)
        end,
    },
    ActivatePaneByIndex = {
        groups = { 'Панели' },
        describe = function(command)
            return string.format(
                'Фокус на панель #%d',
                (tonumber(command.action.ActivatePaneByIndex) or 0) + 1
            )
        end,
    },
    RotatePanes = {
        groups = { 'Панели' },
        describe = function(_)
            return 'Повернуть панели'
        end,
    },
    PaneSelect = {
        groups = { 'Панели' },
        describe = function(command)
            local p = command.action.PaneSelect
            local modes = {
                SwapWithActive = 'поменять местами с активной',
                SwapWithActiveKeepFocus = 'поменять местами (фокус оставить)',
                MoveToActive = 'переместить на место активной',
            }
            return string.format(
                'Выбрать панель буквой (%s)',
                (type(p) == 'table' and modes[p.mode]) or '?'
            )
        end,
    },
    ---------------------------------------------------- Ввод и буфер обмена --
    CopyTo = {
        groups = { 'Ввод и буфер обмена' },
        describe = function(command)
            local t = {
                ClipboardAndPrimarySelection = 'буфер обмена + PrimarySelection',
                Clipboard = 'буфер обмена',
                PrimarySelection = 'PrimarySelection',
            }
            return string.format(
                'Скопировать выделенное в %s',
                t[tostring(command.action.CopyTo)] or '?'
            )
        end,
    },
    Copy = {
        groups = { 'Ввод и буфер обмена' },
        describe = function(_)
            return 'Скопировать выделенное'
        end,
    },
    PasteFrom = {
        groups = { 'Ввод и буфер обмена' },
        describe = function(command)
            local t = {
                ClipboardAndPrimarySelection = 'буфера обмена + PrimarySelection',
                Clipboard = 'буфера обмена',
                PrimarySelection = 'PrimarySelection',
            }
            return string.format('Вставить из %s', t[tostring(command.action.PasteFrom)] or '?')
        end,
    },
    Paste = {
        groups = { 'Ввод и буфер обмена' },
        describe = function(_)
            return 'Вставить'
        end,
    },
    PastePrimarySelection = {
        groups = { 'Ввод и буфер обмена' },
        describe = function(_)
            return 'Вставить из PrimarySelection'
        end,
    },
    SendString = {
        groups = { 'Ввод и буфер обмена' },
        describe = function(command)
            return string.format(
                'Отправить в терминал строку %q',
                tostring(command.action.SendString)
            )
        end,
    },
    SendKey = {
        groups = { 'Ввод и буфер обмена' },
        describe = function(command)
            local k = command.action.SendKey or {}
            return string.format('Отправить клавишу %s + %s', k.mods or 'NONE', k.key or '?')
        end,
    },
    ------------------------------------------------------- Скролл и буфер --
    ClearScrollback = {
        groups = { 'Скролл и буфер' },
        describe = function(command)
            local mode = tostring(command.action.ClearScrollback)
            return mode == 'ScrollbackOnly' and 'Очистить буфер прокрутки'
                or 'Очистить буфер прокрутки и экран'
        end,
    },
    ScrollByLine = {
        groups = { 'Скролл и буфер' },
        describe = function(command)
            local count = tonumber(command.action.ScrollByLine) or 0
            return string.format(
                'Скролл на %d строк %s',
                math.abs(count),
                count > 0 and 'вниз' or 'вверх'
            )
        end,
    },
    ScrollByPage = {
        groups = { 'Скролл и буфер' },
        describe = function(command)
            local count = tonumber(command.action.ScrollByPage) or 0
            local unit = math.abs(count) == 1 and 'страницу' or 'страниц'
            return string.format(
                'Скролл на %s %s %s',
                fmt_num(math.abs(count)),
                unit,
                count > 0 and 'вниз' or 'вверх'
            )
        end,
    },
    ScrollToTop = {
        groups = { 'Скролл и буфер' },
        describe = function(_)
            return 'Скролл в начало буфера'
        end,
    },
    ScrollToBottom = {
        groups = { 'Скролл и буфер' },
        describe = function(_)
            return 'Скролл в конец'
        end,
    },
    ScrollToPrompt = {
        groups = { 'Скролл и буфер' },
        describe = function(_)
            return 'Скролл к последнему промту'
        end,
    },
    ScrollByCurrentEventWheelDelta = {
        groups = { 'Скролл и буфер', 'Мышь' },
        describe = function(_)
            return 'Скролл колесом мыши'
        end,
    },
    IncreaseFontSize = {
        groups = { 'Скролл и буфер' },
        describe = function(_)
            return 'Увеличить шрифт'
        end,
    },
    DecreaseFontSize = {
        groups = { 'Скролл и буфер' },
        describe = function(_)
            return 'Уменьшить шрифт'
        end,
    },
    ResetFontSize = {
        groups = { 'Скролл и буфер' },
        describe = function(_)
            return 'Сбросить размер шрифта'
        end,
    },
    ResetTerminal = {
        groups = { 'Скролл и буфер' },
        describe = function(_)
            return 'Сбросить терминал'
        end,
    },
    ------------------------------------------------------ Поиск и выделение --
    ActivateCopyMode = {
        groups = { 'Поиск и выделение' },
        describe = function(_)
            return 'Режим копирования (см. таблицу copy_mode)'
        end,
    },
    Search = {
        groups = { 'Поиск и выделение' },
        describe = function(command)
            local search = command.action.Search
            if type(search) == 'string' then
                return 'Поиск по буферу (старт с выделения)'
            end
            local needle = type(search) == 'table' and (search.CaseInsensitiveString or search.CaseSensitiveString)
            return needle == nil and 'Поиск по буферу' or string.format('Поиск: %q', needle)
        end,
    },
    QuickSelect = {
        groups = { 'Поиск и выделение' },
        describe = function(_)
            return 'Быстрый выбор строки'
        end,
    },
    QuickSelectArgs = {
        groups = { 'Поиск и выделение' },
        describe = function(command)
            local label = type(command.action.QuickSelectArgs) == 'table' and command.action.QuickSelectArgs.label
            return string.format('Выбор по паттерну%s', label and string.format(' (%s)', label) or '')
        end,
    },
    CharSelect = {
        groups = { 'Поиск и выделение' },
        describe = function(_)
            return 'Выбор символа по набору'
        end,
    },
    CopyMode = {
        groups = { 'Поиск и выделение' },
        describe = function(command)
            return describe_copy_mode(command.action.CopyMode)
        end,
    },
    ClearSelection = {
        groups = { 'Поиск и выделение' },
        describe = function(_)
            return 'Снять выделение'
        end,
    },
    SelectTextAtMouseCursor = {
        groups = { 'Мышь' },
        describe = function(command)
            local mode = SELECTION_MODES[tostring(command.action.SelectTextAtMouseCursor)]
            return string.format('Выделить %s под курсором', mode or 'текст')
        end,
    },
    ExtendSelectionToMouseCursor = {
        groups = { 'Мышь' },
        describe = function(command)
            local mode = SELECTION_MODES[tostring(command.action.ExtendSelectionToMouseCursor)]
            return string.format(
                'Продлить выделение до курсора%s',
                mode and string.format(' (%s)', mode) or ''
            )
        end,
    },
    CompleteSelection = {
        groups = { 'Мышь' },
        describe = function(command)
            local where = COPY_TARGETS[tostring(command.action.CompleteSelection)]
            return 'Закончить выделение' .. (where and string.format(' в %s', where) or '')
        end,
    },
    CompleteSelectionOrOpenLinkAtMouseCursor = {
        groups = { 'Мышь' },
        describe = function(command)
            local where = COPY_TARGETS[tostring(command.action.CompleteSelectionOrOpenLinkAtMouseCursor)]
            return 'Закончить выделение или открыть ссылку'
                .. (where and string.format(' (%s)', where) or '')
        end,
    },
    OpenLinkAtMouseCursor = {
        groups = { 'Мышь' },
        describe = function(_)
            return 'Открыть ссылку под курсором'
        end,
    },
    ------------------------------------------------------------------ Прочее --
    Nop = {
        groups = { 'Прочее' },
        describe = function(_)
            return 'Ничего не делать'
        end,
    },
    DisableDefaultAssignment = {
        groups = { 'Прочее' },
        describe = function(_)
            return 'Отключить стандартное сочетание'
        end,
    },
}

---Описать действие CopyMode
---@param value any
---@return string
describe_copy_mode = function(value)
    if type(value) == 'string' then
        return COPY_MODE_NAMES[value] or value
    end
    if type(value) == 'table' then
        local k, v = next(value)
        if k == 'MoveByPage' then
            local unit = math.abs(tonumber(v) or 0) == 1 and 'страницу' or 'страниц'
            return string.format('прокрутка на %s %s', fmt_num(v), unit)
        elseif k == 'JumpBackward' or k == 'JumpForward' then
            return string.format(
                '%s (%s)',
                COPY_MODE_NAMES[k] or k,
                v.prev_char and 'символ' or 'подстрока'
            )
        elseif k == 'SetSelectionMode' then
            return string.format('выделять по %s', SELECTION_MODES[tostring(v)] or tostring(v))
        elseif COPY_MODE_NAMES[k] ~= nil then
            return COPY_MODE_NAMES[k]
        elseif k ~= nil then
            return string.format('%s = %s', k, tostring(v))
        end
    end
    return 'CopyMode'
end

---Имя действия (ключ таблицы-энумерации KeyAssignment)
---@param action any
---@return string
action_name = function(action)
    if type(action) == 'string' then
        return action
    end
    if type(action) == 'function' then
        return 'Callback'
    end
    if type(action) == 'table' then
        return next(action) or 'Unknown'
    end
    return 'Unknown'
end

---Разобрать составное действие Multiple{...}
---@param command table
---@return string
local function describe_multiple(command)
    local parts = {}
    for _, item in ipairs(command.action.Multiple) do
        if type(item) == 'table' and item.CopyMode then
            table.insert(parts, describe_copy_mode(item.CopyMode))
        elseif type(item) == 'table' and item.ScrollToBottom then
            table.insert(parts, 'скролл в конец')
        elseif type(item) == 'table' and item.CopyTo then
            table.insert(parts, 'скопировать выделенное')
        elseif type(item) == 'string' then
            local strings = {
                ScrollToBottom = 'скролл в конец',
                ScrollToTop = 'скролл в начало',
                Nop = 'ничего',
            }
            table.insert(parts, strings[item] or item)
        else
            local name = action_name(item)
            local desc = action_descriptions[name]
            table.insert(parts, desc and desc.describe({ action = item }) or name)
        end
    end
    return 'затем: ' .. table.concat(parts, '; ')
end

---Человекочитаемое описание действия
---@param command table
---@return string
local function describe_action(command)
    local action = command.action
    local name = action_name(action)
    if name == 'Callback' then
        return 'обработчик из конфига (wezterm.action_callback)'
    end
    if name == 'Multiple' and type(action.Multiple) == 'table' then
        return describe_multiple(command)
    end
    local desc = action_descriptions[name]
    if desc == nil or desc.describe == nil then
        return name
    end
    local ok, result = pcall(desc.describe, command)
    if not ok or result == nil then
        return name
    end
    return result
end

---Категория действия (первая указанная в описании)
---@param command table
---@return Help.Category
local function category_of(command)
    local desc = action_descriptions[action_name(command.action)]
    if desc == nil or desc.groups == nil then
        return 'Прочее'
    end
    for _, group in ipairs(desc.groups) do
        if CATEGORY_RANK[group:lower()] ~= nil then
            return group
        end
    end
    return 'Прочее'
end

--------------------------------------------------------------------------------
-- Нормализация клавиш и модификаторов
--------------------------------------------------------------------------------

local MOD_ORDER = { 'CTRL', 'SHIFT', 'ALT', 'SUPER', 'LEADER' }

---Привести модификаторы к каноническому виду (SUPER→ALT на Linux/Windows)
---@param mods string|nil
---@return string через |
local function normalize_mods(mods)
    if type(mods) ~= 'string' or mods == '' or mods == 'NONE' then
        return ''
    end
    local seen = {}
    for token in mods:gmatch('[^|]+') do
        local t = token:upper()
        if t == 'SUPER' or t == 'CMD' or t == 'WIN' then
            t = platform.is_mac and 'SUPER' or 'ALT'
        elseif t == 'OPT' or t == 'META' then
            t = 'ALT'
        end
        seen[t] = true
    end
    local out, rest = {}, {}
    for _, token in ipairs(MOD_ORDER) do
        if seen[token] then
            table.insert(out, token)
            seen[token] = nil
        end
    end
    for token in pairs(seen) do
        table.insert(rest, token)
    end
    table.sort(rest)
    for _, token in ipairs(rest) do
        table.insert(out, token)
    end
    return table.concat(out, '|')
end

---@param mods string нормализованные, через |
---@return string[]
local function mods_list(mods)
    local out = {}
    if mods == '' then
        return out
    end
    for token in mods:gmatch('[^|]+') do
        table.insert(out, token)
    end
    return out
end

---Разделить префикс phys:/raw:
---@param key any
---@return string base, string|nil prefix
local function split_key(key)
    local k = tostring(key or '')
    local prefix, rest = k:match('^(%a+):(.+)$')
    if prefix ~= nil then
        return rest, prefix:lower()
    end
    return k, nil
end

---@param key string
---@param prefix string|nil
---@return string
local function key_label(key, prefix)
    if prefix == 'phys' then
        return string.format('%s (физ.)', key)
    end
    if prefix == 'raw' then
        return string.format('%s (raw)', key)
    end
    return key
end

--------------------------------------------------------------------------------
-- Мышь
--------------------------------------------------------------------------------

---Эталонные мышиные привязки wezterm — справочные данные, нужны когда
---вызывающий код не передал effective_config (в API нет
---wezterm.gui.default_mouse_bindings; точный источник — wezterm show-keys).
--- stylua: ignore
local MOUSE_DEFAULTS = {
    {
        mods = '',
        event = { Up = { streak = 1, button = 'Left' } },
        action = { CompleteSelectionOrOpenLinkAtMouseCursor = 'ClipboardAndPrimarySelection' },
    },
    {
        mods = 'SHIFT',
        event = { Up = { streak = 1, button = 'Left' } },
        action = { CompleteSelectionOrOpenLinkAtMouseCursor = 'ClipboardAndPrimarySelection' },
    },
    {
        mods = 'ALT',
        event = { Up = { streak = 1, button = 'Left' } },
        action = { CompleteSelection = 'ClipboardAndPrimarySelection' },
    },
    {
        mods = 'SHIFT|ALT',
        event = { Up = { streak = 1, button = 'Left' } },
        action = { CompleteSelectionOrOpenLinkAtMouseCursor = 'PrimarySelection' },
    },
    {
        mods = '',
        event = { Up = { streak = 2, button = 'Left' } },
        action = { CompleteSelection = 'ClipboardAndPrimarySelection' },
    },
    {
        mods = '',
        event = { Up = { streak = 3, button = 'Left' } },
        action = { CompleteSelection = 'ClipboardAndPrimarySelection' },
    },
    {
        mods = '',
        event = { Down = { streak = 1, button = 'Left' } },
        action = { SelectTextAtMouseCursor = 'Cell' },
    },
    {
        mods = 'SHIFT',
        event = { Down = { streak = 1, button = 'Left' } },
        action = { ExtendSelectionToMouseCursor = 'Cell' },
    },
    {
        mods = 'ALT',
        event = { Down = { streak = 1, button = 'Left' } },
        action = { SelectTextAtMouseCursor = 'Block' },
    },
    {
        mods = 'SHIFT|ALT',
        event = { Down = { streak = 1, button = 'Left' } },
        action = { ExtendSelectionToMouseCursor = 'Block' },
    },
    {
        mods = '',
        event = { Down = { streak = 1, button = 'Middle' } },
        action = { PasteFrom = 'PrimarySelection' },
    },
    {
        mods = '',
        event = { Down = { streak = 1, button = 'WheelUp' } },
        action = { ScrollByCurrentEventWheelDelta = '' },
    },
    {
        mods = '',
        event = { Down = { streak = 1, button = 'WheelDown' } },
        action = { ScrollByCurrentEventWheelDelta = '' },
    },
    {
        mods = '',
        event = { Down = { streak = 2, button = 'Left' } },
        action = { SelectTextAtMouseCursor = 'Word' },
    },
    {
        mods = '',
        event = { Down = { streak = 3, button = 'Left' } },
        action = { SelectTextAtMouseCursor = 'Line' },
    },
    {
        mods = '',
        event = { Drag = { streak = 1, button = 'Left' } },
        action = { ExtendSelectionToMouseCursor = 'Cell' },
    },
    {
        mods = 'ALT',
        event = { Drag = { streak = 1, button = 'Left' } },
        action = { ExtendSelectionToMouseCursor = 'Block' },
    },
    { mods = 'SHIFT|CTRL', event = { Drag = { streak = 1, button = 'Left' } }, action = { StartWindowDrag = '' } },
    { mods = 'SUPER', event = { Drag = { streak = 1, button = 'Left' } }, action = { StartWindowDrag = '' } },
    {
        mods = '',
        event = { Drag = { streak = 2, button = 'Left' } },
        action = { ExtendSelectionToMouseCursor = 'Word' },
    },
    {
        mods = '',
        event = { Drag = { streak = 3, button = 'Left' } },
        action = { ExtendSelectionToMouseCursor = 'Line' },
    },
}

---@param mods string нормализованные, через |
---@param event table
---@return string
local function event_label(mods, event)
    if type(event) ~= 'table' then
        return tostring(event or '')
    end
    local kind, params = next(event)
    if kind == nil then
        return ''
    end
    params = params or {}
    local parts = {}
    if params.streak and params.streak > 1 then
        table.insert(parts, string.format('x%d', params.streak))
    end
    if params.button then
        table.insert(parts, params.button)
    end
    local label = kind
    if #parts > 0 then
        label = string.format('%s %s', kind, table.concat(parts, ' '))
    end
    local mods_str = table.concat(mods_list(mods), '+')
    if mods_str == '' then
        return label
    end
    return string.format('%s %s', mods_str, label)
end

---@param binding table
---@return string
local function mouse_signature(binding)
    local kind, params = 'none', {}
    if type(binding.event) == 'table' then
        kind, params = next(binding.event)
        params = params or {}
    end
    return string.format('%s|%s|%s|%s', normalize_mods(binding.mods), kind, params.streak or 1, params.button or '')
end

---@param action any
---@return string
local function action_signature(action)
    return action_name(action) .. '=' .. describe_action({ action = action })
end

--------------------------------------------------------------------------------
-- Стандартные привязки wezterm
--------------------------------------------------------------------------------

---Стандартные привязки wezterm (сгенерированы в utils/default-bindings.lua)
local DEFAULTS = require('utils.default-bindings')

--------------------------------------------------------------------------------
-- Сбор данных
--------------------------------------------------------------------------------

---Собрать плоский список записей справки
---@param opts? Help.Opts
---@return Help.Entry[] entries
---@return {leader: string|nil, defaults_off: boolean, defaults_available: boolean} meta
function M.entries(opts)
    opts = opts or {}
    local bindings = require('config.bindings')

    local active_keys = opts.keys or bindings.keys or {}
    local active_tables = opts.key_tables or bindings.key_tables or {}
    local active_mouse = opts.mouse_bindings or {}
    local leader = opts.leader or bindings.leader
    local defaults_off = opts.defaults_disabled
    if defaults_off == nil then
        defaults_off = bindings.disable_default_key_bindings == true
    end

    local leader_chord = nil
    if leader ~= nil then
        local mods = table.concat(mods_list(normalize_mods(leader.mods)), '+')
        leader_chord = mods == '' and tostring(leader.key) or string.format('%s+%s', mods, tostring(leader.key))
    end

    local entries = {}

    ---@param command table
    ---@param mods string нормализованные
    ---@param key any
    ---@param source Help.Source
    ---@param signature string|nil
    ---@param section string|nil
    local function push_key(command, raw_mods, key, source, signature, section)
        local mods = normalize_mods(raw_mods)
        local base, prefix = split_key(key)
        local parts = mods_list(mods)
        local label_mods = table.concat(parts, '+')
        local key_part = key_label(base, prefix)
        local chord
        if section ~= nil then
            chord = label_mods == '' and key_part or string.format('%s+%s', label_mods, key_part)
        elseif leader_chord ~= nil and mods:find('LEADER') then
            chord = string.format('%s, %s', leader_chord, key_part)
        else
            chord = label_mods == '' and key_part or string.format('%s+%s', label_mods, key_part)
        end
        table.insert(entries, {
            category = section ~= nil and 'Клавиатурные таблицы' or category_of(command),
            label = section ~= nil and string.format('    %s', chord) or chord,
            chord = chord,
            description = describe_action(command),
            source = source,
            active = true,
            origin = 'custom',
            signature = signature,
            section = section,
        })
    end

    -- сочетания из конфига / effective_config
    local active_signatures = {}
    for _, binding in ipairs(active_keys) do
        local mods = normalize_mods(binding.mods)
        local base = split_key(binding.key)
        local signature = mods .. '|' .. base
        active_signatures[signature] = action_signature(binding.action)
        push_key(binding, mods, base, 'config', signature)
    end

    -- стандартные сочетания wezterm: не перекрытые конфигом показываем как неактивные,
    -- перекрытые — помечаем у активной записи
    local inactive = {}
    for _, binding in ipairs(DEFAULTS.keys or {}) do
        local mods = normalize_mods(binding.mods)
        local base, prefix = split_key(binding.key)
        local signature = mods .. '|' .. base
        local current = active_signatures[signature]
        local key_part = key_label(base, prefix)
        local label_mods = table.concat(mods_list(mods), '+')
        local label = label_mods == '' and key_part or string.format('%s+%s', label_mods, key_part)
        if current == nil then
            table.insert(inactive, {
                category = category_of(binding),
                label = label,
                chord = label,
                description = describe_action(binding),
                source = 'default',
                active = false,
                origin = 'standard',
                signature = signature,
            })
        elseif current ~= action_signature(binding.action) then
            for _, entry in ipairs(entries) do
                if entry.signature == signature then
                    entry.origin = 'override'
                    entry.description = string.format(
                        '%s  [перекрыто, было: %s]',
                        entry.description,
                        describe_action(binding)
                    )
                end
            end
        end
    end

    -- мышиные привязки: стандартные + перекрытые конфигом (по сигнатуре mods+событие)
    local mouse_rows, mouse_order = {}, {}
    local function put_mouse(binding, source)
        local signature = mouse_signature(binding)
        local row = mouse_rows[signature]
        if row == nil then
            row = {
                binding = binding,
                source = source,
                overridden = false,
            }
            mouse_rows[signature] = row
            table.insert(mouse_order, signature)
        elseif source == 'config' then
            row.binding = binding
            if row.source == 'default' then
                row.overridden = true
            end
            row.source = 'config'
        end
        return row
    end

    for _, binding in ipairs(MOUSE_DEFAULTS) do
        put_mouse(binding, 'default')
    end
    for _, binding in ipairs(active_mouse) do
        put_mouse(binding, 'config')
    end

    for _, signature in ipairs(mouse_order) do
        local row = mouse_rows[signature]
        local binding = row.binding
        local label = event_label(normalize_mods(binding.mods), binding.event)
        table.insert(entries, {
            category = 'Мышь',
            label = label,
            chord = label,
            description = describe_action(binding),
            source = row.source,
            active = true,
            origin = row.overridden and 'override' or (row.source == 'default' and 'standard' or 'custom'),
            signature = signature,
        })
    end

    -- клавиатурные таблицы
    local tables = {}
    for name, rows in pairs(active_tables) do
        tables[name] = { source = 'config', rows = rows }
    end
    for name, rows in pairs(DEFAULTS.key_tables or {}) do
        if tables[name] == nil then
            tables[name] = { source = 'default', rows = rows }
        end
    end

    local table_names = {}
    for name in pairs(tables) do
        table.insert(table_names, name)
    end
    table.sort(table_names)

    for _, name in ipairs(table_names) do
        local info = tables[name]
        for _, row in ipairs(info.rows) do
            push_key(row, row.mods or 'NONE', row.key, info.source, name .. '|' .. tostring(row.key), name)
        end
    end

    for _, entry in ipairs(inactive) do
        table.insert(entries, entry)
    end

    for _, entry in ipairs(entries) do
        entry.rank = CATEGORY_RANK[entry.category:lower()] or (#CATEGORY_ORDER + 1)
    end

    return entries,
        {
            leader = leader_chord,
            defaults_off = defaults_off,
            defaults_available = #(DEFAULTS.keys or {}) > 0,
        }
end

--------------------------------------------------------------------------------
-- Рендер
--------------------------------------------------------------------------------

---@param value any
---@return string
local function now_string()
    local ok, text = pcall(os.date, '%Y-%m-%d %H:%M:%S')
    if ok and type(text) == 'string' then
        return text
    end
    return '?'
end

---Отрендерить справку в текст
---@param opts? Help.Opts
---@return string
function M.render(opts)
    opts = opts or {}
    local entries, meta = M.entries(opts)

    local width = 16
    for _, entry in ipairs(entries) do
        width = math.max(width, #entry.label)
    end
    width = math.min(width, 42)

    local out = {}
    local function add(line)
        table.insert(out, line)
    end

    add(cpad(' WezTerm — горячие клавиши ', 100, '='))
    add(string.format(' wezterm %s   ОС: %s', wezterm.version or '?', platform.os))
    add(string.format(' конфиг: %s', wezterm.config_file or '?'))
    add(string.format(' создано: %s', now_string()))
    if opts.from_effective == true then
        add(
            ' источник: window:effective_config() — фактические данные текущего окна'
        )
    else
        add(' источник: config/bindings.lua + utils/default-bindings.lua')
    end
    add('')
    add(' Легенда:')
    add('   *   сочетание из конфига (активно)')
    add('   →   стандартное сочетание, перекрыто конфигом')
    add('   -   стандартное сочетание wezterm')
    if meta.defaults_off then
        add(
            '       в основной таблице «-» = НЕ АКТИВНО (disable_default_key_bindings = true)'
        )
        add('       клавиатурные таблицы и мышь остаются активными')
    end
    add(
        '   (физ.) — по физической позиции клавиши, независимо от раскладки'
    )
    if meta.leader then
        add(
            string.format(
                '   лидер: %s — сочетания вида «лидер, H» набираются после него',
                meta.leader
            )
        )
    end
    add('   справка: F1 — полный список, CTRL+Space ? — поиск по сочетаниям')
    add('')

    local ordered = {}
    for _, entry in ipairs(entries) do
        table.insert(ordered, entry)
    end
    table.sort(ordered, function(a, b)
        if a.rank ~= b.rank then
            return a.rank < b.rank
        end
        if a.active ~= b.active then
            return a.active
        end
        if a.section ~= b.section then
            return (a.section or '') < (b.section or '')
        end
        if a.label ~= b.label then
            return a.label < b.label
        end
        return a.description < b.description
    end)

    local printed_category = nil
    local printed_section = nil
    for _, entry in ipairs(ordered) do
        if entry.category ~= printed_category then
            add('')
            add(cpad(' ' .. entry.category .. ' ', 100, '-'))
            printed_category = entry.category
            printed_section = nil
        end
        if entry.section ~= printed_section then
            printed_section = entry.section
            add(string.format('   [%s]', tostring(entry.section or 'основная таблица')))
        end
        local marker = ' *'
        if entry.source == 'default' then
            marker = ' -'
        end
        if entry.origin == 'override' then
            marker = ' →'
        end
        add(string.format(' %s %s  %s', marker, pad_right(entry.label, width), entry.description))
    end

    add('')
    add(cpad(' Подсказки ', 100, '-'))
    add(
        '   CTRL+SHIFT+P — командная панель со всеми стандартными командами wezterm'
    )
    add('   CTRL+F4 / CTRL+F5 — лаунчер по вкладкам / рабочим пространствам')
    add('   F12 — отладочный оверлей, там же _keys() печатает эту справку')
    add('')

    return table.concat(out, '\n')
end

---Активные сочетания основной таблицы — для fuzzy-поиска
---@param opts? Help.Opts
---@return Help.Entry[]
function M.active_entries(opts)
    local entries = M.entries(opts)
    local result = {}
    for _, entry in ipairs(entries) do
        if entry.active and entry.section == nil and entry.category ~= 'Мышь' then
            table.insert(result, entry)
        end
    end
    return result
end

---Отладочный хук: печатает справку в F12-оверлее
_G._keys = function()
    print(M.render())
end

return M
