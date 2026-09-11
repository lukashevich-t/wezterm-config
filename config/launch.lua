local platform = require('utils.platform')

local options = {
    default_prog = {},
    launch_menu = {},
}

if platform.is_win then
    options.default_prog = { 'cmd' }
    options.mux_enable_ssh_agent = false
    options.launch_menu = {
        { label = 'cmd', args = { 'cmd' } },
        { label = 'cmd admin', args = { 'C:/Program Files/gsudo/Current/gsudo.exe', 'cmd.exe' } },
        {
            label = 'Cygwin Bash',
            args = { 'd:/cygwin64/bin/bash.exe', '--login', '-i' },
        },
        {
            label = 'Git Bash',
            args = { 'c:/Program Files/Git/bin/bash.exe', '--cd-to-home' },
        },
        { label = 'PowerShell Core', args = { 'pwsh', '-NoLogo' } },
        { label = 'PowerShell Desktop', args = { 'powershell' } },
        -- { label = 'Nushell', args = { 'nu' } },
        -- { label = 'Msys2', args = { 'ucrt64.cmd' } },
        {
            label = 'MSYS UCRT64',
            args = { 'd:/msys64/msys2_shell.cmd', '-defterm', '-no-start', '-ucrt64', '-shell', 'bash' },
            -- другой способ запуска:   args = { "cmd.exe ", "/k", "d:/msys64/msys2_shell.cmd -defterm -here -no-start -ucrt64 -shell zsh" },
        },
        {
            label = 'Cygwin zsh',
            args = { 'd:/cygwin64/bin/zsh.exe', '--login', '-i' },
        },
    }
elseif platform.is_mac then
    options.default_prog = { '/opt/homebrew/bin/fish', '-l' }
    options.launch_menu = {
        { label = 'Bash', args = { 'bash', '-l' } },
        { label = 'Fish', args = { '/opt/homebrew/bin/fish', '-l' } },
        { label = 'Nushell', args = { '/opt/homebrew/bin/nu', '-l' } },
        { label = 'Zsh', args = { 'zsh', '-l' } },
    }
elseif platform.is_linux then
    options.default_prog = { 'zsh' }
    options.launch_menu = {
        { label = 'Zsh', args = { 'zsh', '-l' } },
        { label = 'Bash', args = { 'bash', '-l' } },
        { label = 'Fish', args = { 'fish', '-l' } },
    }
end

return options
