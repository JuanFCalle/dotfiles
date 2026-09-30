-- Run: nvim --headless -u NONE -i NONE -n -l check-appearance.lua
local script = vim.fs.abspath(debug.getinfo(1, 'S').source:sub(2))
local root = assert(vim.uv.fs_realpath(vim.fs.dirname(script)))
if vim.env.BUHO_APPEARANCE_CHECK == 'startup' then
  local expected = vim.json.decode(vim.env.BUHO_STARTUP_EXPECT)
  local notifications, schemes = {}, 0
  vim.notify = function(message, level)
    if level and level >= vim.log.levels.WARN then
      notifications[#notifications + 1] = { message = message, level = level }
    end
  end
  vim.api.nvim_create_autocmd('ColorScheme', { callback = function() schemes = schemes + 1 end })
  vim.api.nvim_create_autocmd('VimEnter', {
    once = true,
    callback = function()
      vim.schedule(function()
        local ok, err = xpcall(function()
          assert(vim.v.errmsg == '', vim.v.errmsg)
          assert(#notifications == (expected.warnings or 0), vim.inspect(notifications))
          for _, notification in ipairs(notifications) do
            assert(notification.level == vim.log.levels.WARN, notification.message)
            assert(notification.message:find('Keeping Bright/dark.', 1, true), notification.message)
          end
          local entry, ftplugin = 0, 0
          for _, source in ipairs(vim.fn.getscriptinfo()) do
            local path = vim.uv.fs_realpath(source.name)
            if path == root .. '/plugin/appearance.lua' then entry = entry + 1 end
            if path == root .. '/after/ftplugin/' .. (expected.filetype or '') .. '.lua' then
              ftplugin = ftplugin + 1
            end
          end
          if expected.disabled then
            assert(entry == 0 and schemes == 0, '--noplugin must skip appearance setup')
            assert(package.loaded['buho.appearance'] == nil, 'appearance must not be required by init.lua')
          else
            assert(entry == 1, 'native appearance entry must be discovered exactly once')
            assert(vim.g.colors_name == expected.theme, vim.inspect(vim.g.colors_name))
            assert(vim.o.background == 'dark', vim.o.background)
            assert(schemes == 1, 'appearance must apply the theme once during startup: ' .. schemes)
            assert(vim.api.nvim_get_hl(0, { name = 'Comment', link = false }).italic)
            assert(vim.diagnostic.config().virtual_lines == true)
            local handlers = {}
            for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ group = 'buho.appearance' })) do
              local key = autocmd.event .. ':' .. autocmd.pattern
              assert(not handlers[key], 'duplicate appearance handler: ' .. key)
              handlers[key] = true
            end
            assert(handlers['ColorScheme:*'] and handlers['VimEnter:*'], vim.inspect(handlers))
          end
          assert(vim.bo.filetype == (expected.filetype or ''), vim.bo.filetype)
          if expected.filetype == 'markdown' or expected.filetype == 'mail' then
            assert(ftplugin == 1 and vim.bo.synmaxcol == 0, 'after-ftplugin override not loaded')
            assert(vim.b.undo_ftplugin:find('synmaxcol<', 1, true), vim.b.undo_ftplugin)
          elseif not expected.disabled then
            assert(vim.bo.synmaxcol == 200, 'default syntax-column limit changed')
          end
          if not expected.disabled and (expected.filetype == 'lua' or expected.filetype == 'markdown') then
            assert(vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], 'startup highlighting missing')
          end
          print('STARTUP OK')
        end, debug.traceback)
        if not ok then
          print(err)
          vim.cmd.cquit(1)
        else
          vim.cmd('qa!')
        end
      end)
    end,
  })
  return
end
if vim.env.BUHO_APPEARANCE_CHECK ~= 'child' then
  local home = vim.fn.tempname()
  vim.fn.mkdir(home, 'p')
  -- -l runs before screen initialization; use a normal child for real window widths.
  local result = vim.system({
    vim.v.progpath, '--headless', '-u', 'NONE', '-i', 'NONE', '-n',
    '-c', 'lua local ok,err=pcall(dofile,vim.env.BUHO_CHECK_SCRIPT); if not ok then print(err); vim.cmd.cquit(1) end',
    '-c', 'qa!',
  }, {
    text = true,
    env = {
      HOME = home, XDG_CONFIG_HOME = home .. '/config', XDG_DATA_HOME = home .. '/data',
      XDG_STATE_HOME = home .. '/state', XDG_CACHE_HOME = home .. '/cache', NVIM_APPNAME = 'nvim',
      XDG_CONFIG_DIRS = home .. '/config-empty', XDG_DATA_DIRS = home .. '/data-empty',
      VIMINIT = '', EXINIT = '',
      BUHO_APPEARANCE_CHECK = 'child', BUHO_CHECK_SCRIPT = script,
      BUHO_PARSER_SITE = vim.fn.stdpath('data') .. '/site',
      BUHO_SHELL_SCRIPTS = vim.fn.expand('~/.zsh/tinted-shell/scripts'),
    },
  }):wait(120000)
  vim.fn.delete(home, 'rf')
  io.stdout:write(result.stdout or '')
  io.stdout:write(result.stderr or '')
  if result.code ~= 0 then vim.cmd.cquit(1) end
  return
end

local passed, failed = 0, 0
local warnings, allow_warnings = 0, false
local function eq(expected, actual, label)
  assert(vim.deep_equal(expected, actual), (label or 'mismatch')
    .. '\nexpected: ' .. vim.inspect(expected) .. '\nactual: ' .. vim.inspect(actual))
end
local function test(name, callback, expected_warnings)
  allow_warnings = expected_warnings == true
  local ok, err = xpcall(callback, debug.traceback)
  allow_warnings = false
  if ok then
    passed = passed + 1
    print('PASS ' .. name)
  else
    failed = failed + 1
    print('FAIL ' .. name .. '\n' .. err)
  end
end
local function drain()
  vim.wait(20)
end
local home = vim.env.HOME
vim.fn.mkdir(vim.env.XDG_CONFIG_HOME, 'p')
assert(vim.uv.fs_symlink(root, vim.fn.stdpath('config')))
local site = vim.fn.stdpath('data') .. '/site'
vim.fn.mkdir(site, 'p')
for _, directory in ipairs({ 'parser', 'queries' }) do
  assert(vim.uv.fs_symlink(vim.env.BUHO_PARSER_SITE .. '/' .. directory, site .. '/' .. directory))
end
local scripts = home .. '/.zsh/tinted-shell/scripts/'
vim.fn.mkdir(scripts, 'p')
for _, name in ipairs({
  'base16-default-dark', 'base16-bright', 'base16-solarized-light',
  'base24-0x96f', 'base16-ayu-dark', 'base16-apprentice', 'base24-apprentice', 'base16-atlas',
}) do
  vim.fn.writefile(vim.fn.readfile(vim.env.BUHO_SHELL_SCRIPTS .. '/' .. name .. '.sh'), scripts .. name .. '.sh')
end
local state = home .. '/.zsh/.tinted'
local function save(name, background)
  vim.fn.writefile({ name, background or 'dark' }, state)
end
local function startup(expected, file)
  local command = {
    vim.v.progpath, '--headless', '-i', 'NONE', '-n',
    '--cmd', 'lua dofile(vim.env.BUHO_CHECK_SCRIPT)',
  }
  if expected.disabled then command[#command + 1] = '--noplugin' end
  if file then command[#command + 1] = file end
  local result = vim.system(command, {
    text = true,
    env = { BUHO_APPEARANCE_CHECK = 'startup', BUHO_STARTUP_EXPECT = vim.json.encode(expected) },
  }):wait(30000)
  local output = (result.stdout or '') .. (result.stderr or '')
  assert(result.code == 0 and output:find('STARTUP OK', 1, true),
    'startup exit ' .. tostring(result.code) .. ':\n' .. output)
end
save('base16-default-dark')
local bundled = assert(vim.api.nvim_get_runtime_file('parser/c.*', false)[1], 'bundled C parser missing')
vim.opt.runtimepath = { root, vim.env.VIMRUNTIME, vim.fs.dirname(vim.fs.dirname(bundled)), root .. '/after' }
vim.opt.packpath = { root }
vim.o.loadplugins = true
vim.cmd('filetype plugin indent on')
vim.cmd('syntax enable')
vim.cmd('runtime plugin/matchparen.vim')
local notifications = {}
vim.notify = function(message, level)
  notifications[#notifications + 1] = { message = message, level = level }
  if level == vim.log.levels.WARN and not allow_warnings then
    warnings = warnings + 1
    print('UNEXPECTED WARNING ' .. message)
  end
end
local maps = {}
for _, mode in ipairs({ 'n', 'i', 'x', 'o' }) do maps[mode] = vim.api.nvim_get_keymap(mode) end
local work = home .. '/workspace'
vim.fn.mkdir(work, 'p')
vim.cmd.cd(work)
vim.o.columns, vim.o.lines = 120, 40
test('startup uses the shell selection without writes', function()
  dofile(root .. '/init.lua')
  vim.cmd('runtime plugin/appearance.lua')
  eq('default-dark', vim.g.colors_name)
  eq('dark', vim.o.background)
  eq({ 'base16-default-dark', 'dark' }, vim.fn.readfile(state))
  eq({}, notifications)
end)
if failed > 0 then vim.cmd.cquit(1) end
local appearance = require('buho.appearance')
local status = require('buho.statusline')
local function event(name, opts)
  vim.api.nvim_exec_autocmds(name, opts or {})
  drain()
end
local function theme(name, background)
  save(name, background)
  event('FocusGained')
end
local function buffer(name, ft, lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(buf)
  if name then vim.api.nvim_buf_set_name(buf, work .. '/' .. name) end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines or { 'local answer = 42', '  return answer', '' })
  vim.bo[buf].filetype = ft or ''
  vim.bo[buf].modified = false
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  event('BufEnter', { buffer = buf })
  return buf
end
local function render(width)
  vim.o.columns = width
  vim.api.nvim_win_set_width(0, width)
  eq(width, vim.fn.winwidth(0), 'real window width')
  return vim.api.nvim_eval_statusline(vim.wo.statusline, {
    winid = vim.api.nvim_get_current_win(), maxwidth = width, highlights = true,
  })
end
local function line(left, right, width)
  return left .. (' '):rep(width - vim.fn.strwidth(left .. right)) .. right
end
local function hl(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false })
end
local function rgb(group, fg, bg)
  eq(fg and tonumber(fg, 16) or nil, hl(group).fg, group .. ' foreground')
  eq(bg and tonumber(bg, 16) or nil, hl(group).bg, group .. ' background')
end

test('native startup discovers appearance without an explicit setup call', function()
  startup({ theme = 'default-dark' })
  eq({ 'base16-default-dark', 'dark' }, vim.fn.readfile(state))
end)

for ft, extension in pairs({ lua = 'lua', markdown = 'md', mail = 'eml' }) do
  test('native startup with an initial ' .. ft .. ' file', function()
    local path = work .. '/startup.' .. extension
    vim.fn.writefile({ 'local answer = 42' }, path)
    startup({ theme = 'default-dark', filetype = ft }, path)
    eq({ 'base16-default-dark', 'dark' }, vim.fn.readfile(state))
  end)
end

test('--noplugin skips appearance bootstrap but not native ftplugins', function()
  startup({ disabled = true, filetype = 'markdown' }, work .. '/startup.md')
end)

test('editing options, mappings and native presentation defaults survive', function()
  eq(80, vim.go.textwidth)
  eq(2, vim.go.tabstop)
  eq(2, vim.go.shiftwidth)
  eq(true, vim.go.expandtab)
  eq(true, vim.go.autoindent)
  eq('expr', vim.go.foldmethod)
  eq('0', vim.go.foldexpr)
  eq(99, vim.o.foldlevelstart)
  eq(true, vim.o.undofile)
  eq(vim.fn.stdpath('data') .. '/undodir', vim.o.undodir)
  eq(false, vim.o.swapfile)
  eq(false, vim.o.backup)
  eq(' ', vim.g.mapleader)
  for mode, before in pairs(maps) do eq(before, vim.api.nvim_get_keymap(mode), 'mappings ' .. mode) end
  eq(2, vim.o.laststatus)
  eq(1, vim.o.showtabline)
  eq(1, vim.o.cmdheight)
  eq(4, vim.wo.numberwidth)
  eq('auto', vim.wo.signcolumn)
  eq(20, vim.o.pumheight)
  eq('↳ ', vim.o.showbreak)
  eq(true, vim.o.linebreak)
  eq({ diff = '╱', eob = ' ', fold = '·', vert = '│' }, vim.opt.fillchars:get())
  eq({ nbsp = '⦸', extends = '»', precedes = '«', tab = '▷─', trail = '•' }, vim.opt.listchars:get())
  eq(1, vim.fn.exists('#matchparen'))
  eq(0, #vim.lsp.get_clients())
end)

-- RGB values recorded from the isolated reference, with the same Neovim binary.
local palettes = {
  ['base16-default-dark'] = { '181818', '282828', '383838', '585858', 'b8b8b8', 'd8d8d8',
    'ab4642', 'dc9656', 'a1b56c', '7cafc2', '323232', 'f2f2f2', 'dark' },
  ['base16-bright'] = { '000000', '303030', '505050', 'b0b0b0', 'd0d0d0', 'e0e0e0',
    'fb0120', 'fc6d24', 'a1c659', '6fb3d2', '1a1a1a', 'fafafa', 'dark' },
  ['base16-solarized-light'] = { 'fdf6e3', 'eee8d5', '93a1a1', '839496', '657b83', '586e75',
    'dc322f', 'cb4b16', '859900', '268bd2', 'fae7b3', '425358', 'light' },
  ['base24-0x96f'] = { '262427', '3b393c', '514f52', '676567', '7c7b7d', 'fcfcfc',
    'ff7272', 'fc9d6f', 'bcdf59', '49cae4', '403c42', 'ffffff', 'dark' },
}
for name, p in pairs(palettes) do
  test('reference RGB/style parity: ' .. name, function()
    vim.bo.modified = false
    theme(name, p[13])
    rgb('Normal', p[6], p[1])
    rgb('ColorColumn', nil, p[2])
    rgb('CursorLineNr', p[10], p[2])
    rgb('StatusLine', p[5], p[3])
    rgb('StatusLineNC', p[5], p[3])
    rgb('User1', p[5], p[3])
    rgb('User3', p[5], p[3])
    rgb('User4', p[7], p[3])
    rgb('User5', p[1], p[5])
    rgb('User7', p[6], p[7])
    eq(true, hl('Comment').italic)
    eq(true, hl('User1').italic)
    eq(true, hl('StatusLineNC').italic)
    for _, group in ipairs({ 'User3', 'User5', 'User7', 'Search' }) do eq(true, hl(group).bold) end
    rgb('TabLine', p[4], p[2])
    rgb('TabLineFill', p[4], p[2])
    rgb('TabLineSel', p[9], p[2])
    for _, group in ipairs({ 'NonText', 'Whitespace', 'Conceal', 'IblIndent', '@ibl.indent.char.1' }) do
      rgb(group, '4d4d4d')
    end
    rgb('IblScope', p[4], p[2])
    rgb('@ibl.scope.char.1', p[4], p[2])
    eq(true, hl('@ibl.scope.char.1').nocombine)
    rgb('Pmenu', nil, p[3])
    rgb('PmenuSel', p[2], p[6])
    eq(0, hl('PmenuSel').blend)
    eq(hl('PmenuSel'), hl('QuickFixLine'))
    eq(hl('LineNr'), hl('VertSplit'))
    rgb('MatchParen', nil, p[4])
    rgb('Search', p[7])
    rgb('IncSearch', p[2], p[8])
    rgb('DiffAdd', p[9], '008000')
    rgb('DiffText', p[10], '0000ff')
    rgb('DiffChange', p[4], p[2])
    eq(hl('Conceal'), hl('DiffDelete'))
    rgb('NormalFloat', p[12], p[11])
    rgb('FloatBorder', p[13] == 'dark' and 'ffffff' or '000000', p[11])
    eq(vim.o.winblend, hl('FloatBorder').blend)
    eq(0xff0000, hl('SpellBad').sp)
    eq(true, hl('SpellBad').undercurl)
    for _, severity in ipairs({ 'Error', 'Warn', 'Info', 'Hint' }) do
      eq(hl('Diagnostic' .. severity).fg, hl('DiagnosticSign' .. severity).fg)
      eq(tonumber(p[2], 16), hl('DiagnosticSign' .. severity).bg)
      eq(true, hl('DiagnosticVirtualLines' .. severity).italic)
      eq(true, hl('DiagnosticVirtualText' .. severity).underline)
      eq(true, hl('DiagnosticFloating' .. severity).italic)
    end
    eq(true, hl('DiagnosticFloatingError').bold)
    vim.bo.modified = true
    event('BufModifiedSet')
    rgb('User7', p[6], p[9])
    vim.bo.modified = false
    event('BufModifiedSet')
  end)
end

test('invalid theme states warn once and retain the last good theme/background', function()
  theme('base16-solarized-light', 'light')
  local before = hl('Normal')
  for _, lines in ipairs({
    {}, { 'base16-bright' }, { 'base16-bright', 'wrong' }, { 'base16-bright', 'dark', 'extra' },
    { '../bright', 'dark' }, { 'base16-bright|quit', 'dark' }, { 'tinted8-gruvbox-dark', 'dark' },
    { 'base16-does-not-exist', 'dark' }, { 'base16-apprentice', 'dark' },
    { 'base16-ayu-dark', 'dark' }, { 'base24-apprentice', 'dark' },
  }) do
    theme('base16-solarized-light', 'light')
    vim.fn.writefile(lines, state)
    local count = #notifications
    event('FocusGained')
    eq(count + 1, #notifications, 'warning for ' .. vim.inspect(lines))
    eq(vim.log.levels.WARN, notifications[#notifications].level)
    event('FocusGained')
    eq(count + 1, #notifications, 'unchanged invalid state must not spam')
    eq('solarized-light', vim.g.colors_name)
    eq('light', vim.o.background)
    eq(before, hl('Normal'))
    eq(lines, vim.fn.readfile(state), 'state is read-only')
  end
end, true)

test('RGB compatibility ignores hexadecimal letter case', function()
  theme('base16-atlas')
  eq('atlas', vim.g.colors_name)
  theme('base16-default-dark')
end)

test('unreadable state, missing script, incomplete and duplicate palette declarations', function()
  theme('base16-solarized-light', 'light')
  assert(vim.uv.fs_chmod(state, 0))
  eq(0, vim.fn.filereadable(state))
  local count = #notifications
  event('FocusGained')
  eq(count + 1, #notifications)
  eq('light', vim.o.background)
  assert(vim.uv.fs_chmod(state, 384))
  for _, replacement in ipairs({ {}, { '  export BASE16_COLOR_00_HEX="000000"' } }) do
    local path = scripts .. 'base16-bright.sh'
    local original = vim.fn.readfile(path)
    vim.fn.writefile(replacement, path)
    save('base16-bright')
    event('FocusGained')
    eq('solarized-light', vim.g.colors_name)
    vim.fn.writefile(original, path)
  end
  local path = scripts .. 'base16-bright.sh'
  local original = vim.fn.readfile(path)
  local duplicate = vim.deepcopy(original)
  duplicate[#duplicate + 1] = '  export BASE16_COLOR_00_HEX="000000"'
  vim.fn.writefile(duplicate, path)
  event('FocusGained')
  eq('solarized-light', vim.g.colors_name)
  vim.fn.delete(path)
  event('FocusGained')
  eq('solarized-light', vim.g.colors_name)
  vim.fn.writefile(original, path)
  event('FocusGained')
  eq('bright', vim.g.colors_name, 'changed palette is retried')
end, true)

test('directories and dangling state symlinks are unreadable, not missing', function()
  theme('base16-solarized-light', 'light')
  vim.fn.delete(state)
  vim.fn.mkdir(state)
  event('FocusGained')
  eq('solarized-light', vim.g.colors_name)
  vim.fn.delete(state, 'd')
  assert(vim.uv.fs_symlink(home .. '/absent-state', state))
  event('FocusGained')
  eq('solarized-light', vim.g.colors_name)
  eq('light', vim.o.background)
  vim.fn.delete(state)
  theme('base16-default-dark')
end, true)

test('missing state and first-start invalid state use Bright/dark', function()
  vim.fn.delete(state)
  event('FocusGained')
  eq('bright', vim.g.colors_name)
  eq('dark', vim.o.background)
  eq(0, vim.fn.filereadable(state))
  startup({ theme = 'bright' })
  eq(0, vim.fn.filereadable(state), 'native startup must not create shell state')
  save('base16-bright', 'invalid')
  startup({ theme = 'bright', warnings = 1 })
  eq({ 'base16-bright', 'invalid' }, vim.fn.readfile(state))
  theme('base16-default-dark')
end, true)

test('explicit colorscheme overrides and setup are non-recursive and idempotent', function()
  local count = #vim.api.nvim_get_autocmds({ group = 'buho.appearance' })
  appearance.setup()
  appearance.setup()
  eq(count, #vim.api.nvim_get_autocmds({ group = 'buho.appearance' }))
  vim.cmd.colorscheme('bright')
  rgb('CursorLineNr', '6fb3d2', '303030')
  rgb('DiffText', '6fb3d2', '0000ff')
  eq(true, hl('Comment').italic)
  event('FocusGained')
  eq('default-dark', vim.g.colors_name)
end)

test('exact statusline strings and byte/display-cell boundaries at 79/80/81/120', function()
  buffer('src/example.lua', 'lua')
  for _, width in ipairs({ 79, 80, 81, 120 }) do
    local rendered = render(width)
    local left = '     src/example.lua [lua]'
    local right = width > 80 and '  ℓ 1/3 𝚌 1/18  ' or '  '
    eq(line(left, right, width), rendered.str)
    eq(width, rendered.width)
    -- strdisplaywidth() includes buffer wrapping/showbreak; bars do not wrap.
    eq(width, vim.fn.strwidth(rendered.str))
    local starts = {}
    for _, highlight in ipairs(rendered.highlights) do starts[highlight.group] = highlight.start end
    eq(0, starts.User7)
    eq(4, starts.User4)
    eq(#'     src/', starts.User3)
    eq(#'     src/example.lua ', starts.User1)
    eq(rendered.str:find('', 1, true) - 1 + #'', starts.User5)
  end
end)

test('modified, read-only, encoding and multi-digit position padding', function()
  buffer('flags.lua', 'lua')
  vim.bo.modified, vim.bo.readonly, vim.bo.fileencoding = true, true, 'latin1'
  event('BufModifiedSet')
  local rendered = render(120)
  assert(rendered.str:find('  ✘  flags.lua [RO,lua,latin1]', 1, true), rendered.str)
  local lines = {}
  for i = 1, 123 do lines[i] = ('x'):rep(120) end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, { 12, 10 })
  vim.wo.wrap = false
  eq('  ℓ 12/123 𝚌 11/121 ', status.rhs())
  vim.wo.wrap = true
  eq('  ℓ 12/123 𝚌 11/123 ', status.rhs())
  vim.bo.readonly, vim.bo.modified = false, false
  event('BufWritePost')
  eq(hl('Identifier').fg, hl('User7').bg)
  assert(not render(120).str:find('✘', 1, true))
end)

test('unnamed, long, Unicode and percent-containing names', function()
  buffer(nil, '')
  local unnamed = render(120).str
  assert(unnamed:find('[No Name]', 1, true))
  assert(not unnamed:find('[]', 1, true))
  buffer('deep/naïve%file.lua', 'lua')
  local unicode = render(81)
  assert(unicode.str:find('deep/naïve%file.lua [lua]', 1, true), unicode.str)
  eq(81, vim.fn.strwidth(unicode.str))
  buffer(('long-directory/'):rep(12) .. 'last.lua', 'lua')
  local long = render(79)
  assert(long.str:find('<', 1, true))
  assert(long.str:find('last.lua', 1, true))
  eq(79, vim.fn.strwidth(long.str))
end)

test('gutter alignment tracks number width, signs and line totals', function()
  local buf = buffer('gutter.lua', 'lua')
  eq('   ', status.gutterpadding())
  vim.wo.signcolumn = 'yes'
  eq('     ', status.gutterpadding())
  vim.wo.signcolumn = 'auto'
  vim.fn.sign_define('AppearanceCheck', { text = '!' })
  vim.fn.sign_place(1, '', 'AppearanceCheck', buf, { lnum = 1 })
  eq('     ', status.gutterpadding())
  vim.fn.sign_unplace('', { buffer = buf })
  vim.wo.numberwidth = 6
  eq('     ', status.gutterpadding())
  vim.wo.numberwidth = 4
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.fn['repeat']({ '' }, 10000))
  eq('     ', status.gutterpadding())
end)

test('tab labels, padding, active highlights and native click regions', function()
  buffer('src/tab-one.lua', 'lua')
  vim.cmd.tabnew()
  buffer('nested/tab%二.lua', 'lua')
  local format = appearance.tabline()
  eq('%#TabLine#%1T %{v:lua.require("buho.appearance").tablabel(1)} '
    .. '%#TabLineSel#%2T %{v:lua.require("buho.appearance").tablabel(2)} %#TabLineFill#%T', format)
  local result = vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true, maxwidth = 120, highlights = true })
  eq(' s/tab-one.lua  n/tab%二.lua ', result.str)
  eq(vim.fn.strwidth(result.str), result.width)
  eq('TabLine', result.highlights[1].group)
  eq('TabLineSel', result.highlights[2].group)
  eq(#' s/tab-one.lua ', result.highlights[2].start)
  vim.cmd('tabonly!')
end)

test('focus, split and buffer transitions keep appearance window-local', function()
  buffer('focus-one.lua', 'lua')
  local first = vim.api.nvim_get_current_win()
  vim.cmd.vsplit()
  buffer('focus-two.py', 'python')
  local second = vim.api.nvim_get_current_win()
  eq(false, vim.wo[first].relativenumber)
  eq(true, vim.wo[second].relativenumber)
  eq(false, vim.wo[first].list)
  assert(vim.wo[first].winhighlight:find('Normal:ColorColumn', 1, true))
  eq('', vim.wo[second].winhighlight)
  eq('+' .. table.concat(vim.fn.range(0, 254), ',+'), vim.wo[second].colorcolumn)
  event('InsertEnter')
  eq(false, vim.wo.cursorline)
  event('InsertLeave')
  eq(true, vim.wo.cursorline)
  event('FocusLost')
  eq(false, vim.wo.relativenumber)
  eq(false, vim.wo.list)
  event('FocusGained')
  eq(true, vim.wo.relativenumber)
  vim.api.nvim_set_current_win(first)
  eq(true, vim.wo[first].relativenumber)
  eq(false, vim.wo[second].relativenumber)
  vim.cmd('only!')
end)

test('help, diff, Markdown, mail and floating-window exemptions', function()
  vim.cmd('help help')
  drain()
  eq(false, vim.wo.list)
  eq(2, vim.wo.conceallevel)
  eq(false, vim.wo.number)
  vim.cmd('only!')
  buffer('changes.diff', 'diff')
  eq('', vim.wo.colorcolumn)
  event('FocusLost')
  eq('', vim.wo.winhighlight)
  event('FocusGained')
  buffer('prose.md', 'markdown')
  eq('trail:•', vim.wo.listchars)
  eq(true, vim.wo.breakindent)
  eq('sbr,shift:' .. vim.bo.shiftwidth, vim.wo.breakindentopt)
  eq(0, vim.bo.synmaxcol)
  buffer('mail.txt', 'mail')
  eq(false, vim.wo.list)
  buffer('normal-again.lua', 'lua')
  eq(false, vim.wo.breakindent)
  local float = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true, {
    relative = 'editor', width = 24, height = 3, row = 2, col = 4, style = 'minimal', border = 'single',
  })
  local highlight = vim.wo[float].winhighlight
  event('FocusLost')
  eq(highlight, vim.wo[float].winhighlight)
  assert(not highlight:find('Normal:ColorColumn', 1, true))
  vim.api.nvim_win_close(float, true)
  event('FocusGained')
end)

for _, ft in ipairs({ 'markdown', 'mail' }) do
  test(ft .. ' after-ftplugin composes cleanup and survives repeated filetype changes', function()
    local buf = buffer('cleanup-' .. ft, ft)
    eq(0, vim.bo.synmaxcol)
    eq(1, vim.b.did_ftplugin, 'built-in ftplugin must remain active')
    event('FileType', { buffer = buf })
    local _, cleanups = vim.b.undo_ftplugin:gsub('synmaxcol<', '')
    eq(1, cleanups, 'reloading must not accumulate undo commands')
    vim.bo.filetype = ''
    eq(vim.go.synmaxcol, vim.bo.synmaxcol, 'reset custom syntax limit')
    eq(vim.go.commentstring, vim.bo.commentstring, 'retain native comment cleanup')
    eq(vim.go.comments, vim.bo.comments, 'retain native comments cleanup')
    vim.bo.filetype = ft
    eq(0, vim.bo.synmaxcol)
    vim.bo.filetype = 'lua'
    eq(vim.go.synmaxcol, vim.bo.synmaxcol, 'same-buffer filetype change')
    vim.bo.filetype = ft
    buffer('cleanup-other-' .. ft .. '.lua', 'lua')
    eq(vim.go.synmaxcol, vim.bo.synmaxcol, 'override must not leak to another buffer')
    vim.api.nvim_set_current_buf(buf)
    eq(0, vim.bo.synmaxcol, 'returning to the original buffer retains its override')
  end)
end

test('quickfix/location-list formatting preserves native ftplugins', function()
  local buf = buffer('diagnostics.lua', 'lua')
  vim.fn.setqflist({}, ' ', { title = 'Build % diagnostics', items = { { bufnr = buf, lnum = 1, text = 'example' } } })
  vim.cmd.copen()
  drain()
  eq('quickfix', vim.bo.buftype)
  assert(vim.b.undo_ftplugin and vim.b.undo_ftplugin ~= '', 'native qf ftplugin must remain active')
  eq('', vim.wo.colorcolumn)
  local quickfix = render(120).str
  assert(quickfix:find('[Quickfix List] Build % diagnostics', 1, true), quickfix)
  event('FocusLost')
  assert(not render(120).str:find('', 1, true))
  eq('', vim.wo.winhighlight)
  event('FocusGained')
  vim.cmd.cclose()
  vim.fn.setloclist(0, {}, ' ', { title = 'Local diagnostics', items = { { bufnr = buf, lnum = 2, text = 'example' } } })
  vim.cmd.lopen()
  drain()
  local location = render(120).str
  assert(location:find('[Location List] Local diagnostics', 1, true), location)
  vim.cmd.lclose()
end)

test('fold text changes presentation, not fold computation', function()
  buffer('fold.lua', 'lua', { 'before', '          nested()', '            body()', '          end', 'after' })
  local original = vim.wo.foldexpr
  vim.wo.foldmethod = 'manual'
  vim.cmd('2,4fold')
  eq('»··[3ℓ]·: nested()', vim.fn.foldtextresult(2))
  vim.wo.foldmethod = 'expr'
  eq(original, vim.wo.foldexpr)
end)

test('native yank highlighting uses Substitute and expires', function()
  local buf = buffer('yank.lua', 'lua')
  vim.cmd('normal! ggyy')
  local function marks()
    return vim.inspect(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true }))
  end
  assert(marks():find('Substitute', 1, true), 'yank highlight missing')
  vim.wait(250)
  assert(not marks():find('Substitute', 1, true), 'yank highlight did not expire')
end)

test('diagnostics use reference signs, virtual lines, floats and buffer-scoped LSP gutters', function()
  local buf = buffer('native-diagnostics.lua', 'lua')
  local config = vim.diagnostic.config()
  eq(true, config.severity_sort)
  eq(true, config.virtual_lines)
  eq({ '✖', '⚐', '𝒾', '✶' }, config.signs.text)
  eq('Diagnostics', config.float.header)
  eq('single', config.float.border)
  eq('✖ ', config.float.prefix({ severity = vim.diagnostic.severity.ERROR }))
  local ns = vim.api.nvim_create_namespace('appearance-test-diagnostics')
  vim.diagnostic.set(ns, buf, {
    { lnum = 0, col = 0, message = 'Error sample', severity = vim.diagnostic.severity.ERROR },
    { lnum = 1, col = 2, message = 'Warning sample', severity = vim.diagnostic.severity.WARN },
  })
  drain()
  assert(#vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, {}) > 0)
  local floatbuf, floatwin = vim.diagnostic.open_float({ bufnr = buf, scope = 'buffer' })
  assert(floatbuf and floatwin)
  assert(table.concat(vim.api.nvim_buf_get_lines(floatbuf, 0, -1, false), '\n'):find('Error sample', 1, true))
  vim.api.nvim_win_close(floatwin, true)
  local first = vim.api.nvim_get_current_win()
  vim.cmd.vsplit()
  event('LspAttach', { buffer = buf, data = { client_id = 999 } })
  eq('yes', vim.wo[first].signcolumn)
  eq('yes', vim.wo.signcolumn)
  buffer('unattached.lua', 'lua')
  eq('auto', vim.wo.signcolumn)
  eq('yes', vim.wo[first].signcolumn, 'other attached window keeps its gutter')
  vim.api.nvim_set_current_buf(buf)
  eq('yes', vim.wo.signcolumn)
  event('LspDetach', { buffer = buf, data = { client_id = 999 } })
  eq('auto', vim.wo.signcolumn)
  eq('auto', vim.wo[first].signcolumn)
  vim.cmd('only!')
  vim.diagnostic.reset(ns)
end)

local samples = {
  c = { 'c', { 'int main(void) {', '  return 0;', '}' } },
  lua = { 'lua', { 'local function answer()', '  return 42', 'end' } },
  markdown = { 'markdown', { '# Title', '', '**bold** and `code`' } },
  query = { 'query', { '(identifier) @variable' } },
  vim = { 'vim', { 'let answer = 42' } },
  vimdoc = { 'help', { '*example*', 'Use |help| for help.', '' } },
  kotlin = { 'kotlin', { 'fun answer(): Int {', '  return 42', '}' } },
  python = { 'python', { 'def answer():', '    return 42' } },
  yaml = { 'yaml', { 'answer:', '  value: 42' } },
  json = { 'json', { '{', '  "answer": 42', '}' } },
  zsh = { 'zsh', { 'function answer() {', '  print 42', '}' } },
  bash = { 'sh', { 'answer() {', '  echo 42', '}' } },
}
for lang, sample in pairs(samples) do
  test('parser, queries and highlighted sample: ' .. lang, function()
    local buf = buffer(nil, sample[1], sample[2])
    assert(vim.treesitter.highlighter.active[buf], 'highlighter not enabled')
    local parser = vim.treesitter.get_parser(buf, lang)
    local tree = parser:parse()[1]
    assert(tree and not tree:root():has_error(), 'sample must parse without errors')
    local query = assert(vim.treesitter.query.get(lang, 'highlights'))
    local count = 0
    for _ in query:iter_captures(tree:root(), buf, 0, -1) do count = count + 1 end
    assert(count > 0, 'no highlight captures')
  end)
end
test('bundled Markdown inline parser and injected highlighting', function()
  local buf = buffer(nil, 'markdown', { '# Heading', '', '**bold** and `code`' })
  local parser = vim.treesitter.get_parser(buf, 'markdown')
  parser:parse(true)
  assert(parser:children().markdown_inline, 'Markdown inline injection must be active')
  assert(vim.treesitter.query.get('markdown_inline', 'highlights'))
end)

test('real indent/scope extmarks, Markdown exclusion and per-buffer expandtab switching', function()
  local buf = buffer(nil, 'lua', { 'local function answer()', '  if true then', '    return 42', '  end', 'end' })
  vim.api.nvim_win_set_cursor(0, { 3, 5 })
  require('ibl').refresh(buf)
  local ns = vim.api.nvim_get_namespaces().indent_blankline
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  local serialized = vim.inspect(marks)
  assert(serialized:find('│', 1, true), 'indent glyph not rendered')
  assert(serialized:find('@ibl.scope', 1, true), 'scope highlight not rendered')
  vim.bo.expandtab = false
  event('OptionSet', { pattern = 'expandtab' })
  eq({}, vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}))
  vim.bo.expandtab = true
  event('OptionSet', { pattern = 'expandtab' })
  require('ibl').refresh(buf)
  assert(#vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) > 0)
  local other = buffer(nil, 'lua')
  vim.bo.expandtab = false
  event('OptionSet', { pattern = 'expandtab' })
  eq(true, require('ibl.config').get_config(buf).enabled)
  eq(false, require('ibl.config').get_config(other).enabled)
  local markdown = buffer(nil, 'markdown', { '# Heading', '', '  indented prose' })
  require('ibl').refresh(markdown)
  eq({}, vim.api.nvim_buf_get_extmarks(markdown, ns, 0, -1, {}))
end)

test('large-file protection covers disk size and growing unsaved buffers', function()
  local path = work .. '/large.lua'
  vim.fn.writefile({ '--' .. ('x'):rep(1024 * 1024) }, path)
  vim.cmd.edit(path)
  drain()
  eq(nil, vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()])
  eq(false, require('ibl.config').get_config(0).enabled)
  local buf = buffer(nil, 'lua', { '-- small' })
  assert(vim.treesitter.highlighter.active[buf])
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '--' .. ('x'):rep(1024 * 1024) })
  event('TextChanged', { buffer = buf })
  eq(nil, vim.treesitter.highlighter.active[buf])
  eq(false, require('ibl.config').get_config(buf).enabled)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'local answer = 42' })
  event('TextChanged', { buffer = buf })
  assert(vim.treesitter.highlighter.active[buf])
end)

for _, source in ipairs({ 'buffer', 'disk' }) do
  test('large-file ' .. source .. ' threshold is strictly greater than 1 MiB', function()
    local path = source == 'disk' and 'size-boundary.lua' or nil
    local buf = buffer(path, 'lua', { '-- small' })
    for _, size in ipairs({ 1024 * 1024 - 1, 1024 * 1024, 1024 * 1024 + 1 }) do
      local lines = { '--' .. ('x'):rep(size - 3) }
      if source == 'disk' then
        vim.fn.writefile(lines, work .. '/' .. path)
        eq(size, vim.uv.fs_stat(work .. '/' .. path).size)
        eq({ '-- small' }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      else
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        eq(size, vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf)))
      end
      event('TextChanged', { buffer = buf })
      eq(size <= 1024 * 1024, vim.treesitter.highlighter.active[buf] ~= nil, source .. ' highlighting')
      eq(size <= 1024 * 1024, require('ibl.config').get_config(buf).enabled, source .. ' guides')
    end
  end)
end

test('missing parsers/queries fail visibly; startup never installs dependencies', function()
  local add = vim.treesitter.language.add
  vim.treesitter.language.add = function(lang, ...)
    if lang == 'kotlin' then return nil, 'test: parser unavailable' end
    return add(lang, ...)
  end
  local ok, err = pcall(appearance.setup)
  vim.treesitter.language.add = add
  assert(not ok and err:find('missing parser kotlin', 1, true), tostring(err))
  local get = vim.treesitter.query.get
  vim.treesitter.query.get = function(lang, ...)
    if lang == 'kotlin' then return nil end
    return get(lang, ...)
  end
  ok, err = pcall(appearance.setup)
  vim.treesitter.query.get = get
  assert(not ok and err:find('missing highlights for kotlin', 1, true), tostring(err))
  local ts = require('nvim-treesitter')
  local install = ts.install
  ts.install = function() error('automatic downloads are forbidden') end
  ok, err = pcall(appearance.setup)
  ts.install = install
  assert(ok, err)
  assert(not vim.o.runtimepath:find('/code/wincent', 1, true))
  eq(0, #vim.lsp.get_clients())
end)

local errors = 0
for _, notification in ipairs(notifications) do
  if notification.level == vim.log.levels.ERROR then
    errors = errors + 1
    print('ERROR ' .. notification.message)
  end
end
print(('TOTAL %d; PASSED %d; FAILED %d; SKIPPED 0; WARNINGS %d; ERRORS %d')
  :format(passed + failed, passed, failed, warnings, errors))
if failed > 0 or warnings > 0 or errors > 0 then vim.cmd.cquit(1) end
