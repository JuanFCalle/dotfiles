-- Appearance adapted from Wincent 824beaea9 (public domain).
local M = {}
local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))))
local colors = root .. '/pack/bundle/opt/base16-nvim/colors/'
local status = require('buho.statusline')
local applying, initialized = false, false
local last_warning

local function read(path, limit)
  if vim.fn.filereadable(path) ~= 1 then
    return nil, 'Cannot read ' .. path
  end
  local ok, lines
  if limit then
    ok, lines = pcall(vim.fn.readfile, path, '', limit)
  else
    ok, lines = pcall(vim.fn.readfile, path)
  end
  if not ok then
    return nil, 'Cannot read ' .. path .. ': ' .. lines
  end
  return lines
end

local function palette(lines, pattern, label, count)
  local result = {}
  for _, line in ipairs(lines) do
    local role, rgb = line:match(pattern)
    if role then
      if #rgb ~= 6 or result[role] then
        return nil, 'Invalid or duplicate ' .. label .. ' base' .. role
      end
      result[role] = rgb:lower()
    end
  end
  for i = 0, count - 1 do
    local role = ('%02X'):format(i)
    if not result[role] then
      return nil, 'Missing ' .. label .. ' base' .. role
    end
  end
  return result
end

local function selection()
  local path = vim.fn.expand('~/.zsh/.tinted')
  local stat, err, code = vim.uv.fs_lstat(path)
  if not stat then
    if code == 'ENOENT' then
      return 'bright', 'dark'
    end
    return nil, 'Cannot inspect ' .. path .. ': ' .. tostring(err)
  end
  local lines, problem = read(path, 3)
  if not lines then
    return nil, problem
  end
  if #lines ~= 2 or (lines[2] ~= 'dark' and lines[2] ~= 'light') then
    return nil, 'Expected a scheme and dark/light on exactly two lines in ' .. path
  end
  local family, name = lines[1]:match('^base(%d+)%-([a-z0-9][a-z0-9_-]*)$')
  if (family ~= '16' and family ~= '24') or not name then
    return nil, 'Unsupported or unsafe scheme ' .. vim.inspect(lines[1]) .. '; use a full Base16/Base24 palette'
  end
  local theme, theme_error = read(colors .. name .. '.lua')
  if not theme then
    return nil, theme_error
  end
  local shell, shell_error = read(vim.fn.expand('~/.zsh/tinted-shell/scripts/') .. lines[1] .. '.sh')
  if not shell then
    return nil, shell_error
  end
  local expected, expected_error = palette(theme, '^local gui(%x%x) = "#(%x+)"$', 'Neovim', 24)
  if not expected then
    return nil, expected_error
  end
  local actual, actual_error = palette(shell,
    '^%s*export BASE' .. family .. '_COLOR_(%x%x)_HEX="(%x+)"%s*$', 'shell', tonumber(family))
  if not actual then
    return nil, actual_error
  end
  if family == '16' then
    for role, parent in pairs({
      ['10'] = '00', ['11'] = '00', ['12'] = '08', ['13'] = '0A',
      ['14'] = '0B', ['15'] = '0C', ['16'] = '0D', ['17'] = '0E',
    }) do
      actual[role] = actual[parent]
    end
  end
  for i = 0, 23 do
    local role = ('%02X'):format(i)
    if actual[role] ~= expected[role] then
      return nil, lines[1] .. ' conflicts with the reference palette at base' .. role
        .. ' (shell #' .. actual[role] .. ', Neovim #' .. expected[role] .. ')'
    end
  end
  return name, lines[2]
end

local function highlights()
  local p = require('wincent.pinnacle')
  local dark = vim.o.background == 'dark'
  p.merge('Comment', { italic = true })
  p.set('Conceal', { ctermfg = dark and 239 or 249, fg = 'Grey30' })
  p.merge('IndentBlanklineChar', { fg = dark and 'Grey10' or 'Grey30', nocombine = true })
  p.link('NonText', 'Conceal')
  p.set('CursorLineNr', p.dump('DiffText'))
  p.link('Pmenu', 'Visual')
  p.link('VertSplit', 'LineNr')
  p.clear('vimUserFunc')
  p.merge('PmenuSel', { blend = 0 })
  for _, group in ipairs({ 'DiffAdded', 'DiffFile', 'DiffNewFile', 'DiffLine', 'DiffRemoved' }) do
    local definition = p.dump(group)
    definition.bg = nil
    p.set(group, definition)
  end
  p.link('DiffDelete', 'Conceal')
  p.merge('DiffAdd', { bg = 'green' })
  p.merge('DiffText', { bg = 'blue' })
  local float = p.adjust_lightness('Normal', dark and 0.1 or -0.1)
  p.set('NormalFloat', float)
  float.fg, float.blend = dark and '#ffffff' or '#000000', vim.o.winblend
  p.set('FloatBorder', float)
  p.merge('SpellBad', { sp = 'Red' })
  p.link('QuickFixLine', 'PmenuSel')
  p.set('Search', p.embolden('Underlined'))
  for _, severity in ipairs({ 'Error', 'Warn', 'Info', 'Hint' }) do
    local group = 'Diagnostic' .. severity
    p.set('DiagnosticSign' .. severity, { bg = p.bg('ColorColumn'), fg = p.fg(group) })
    p.set('DiagnosticVirtualLines' .. severity, p.italicize(group))
    p.set('DiagnosticVirtualText' .. severity, p.decorate('italic,underline', group))
    p.set('DiagnosticFloating' .. severity, p.decorate(severity == 'Error' and 'italic,bold' or 'italic', group))
  end
  status.update_highlight()
  -- The rendered v3 guides use these groups, not IndentBlanklineChar.
  p.set('IblIndent', vim.api.nvim_get_hl(0, { name = 'Whitespace' }))
  p.set('IblWhitespace', vim.api.nvim_get_hl(0, { name = 'Whitespace' }))
  p.set('IblScope', vim.api.nvim_get_hl(0, { name = 'LineNr' }))
  require('ibl.highlights').setup()
  require('ibl').refresh_all()
end

function M.refresh()
  local name, background = selection()
  if not name then
    if last_warning ~= background then
      vim.notify('Neovim appearance: ' .. background .. '. Keeping '
        .. (initialized and 'the current theme/background.' or 'Bright/dark.'), vim.log.levels.WARN)
      last_warning = background
    end
    if initialized then
      return
    end
    name, background = 'bright', 'dark'
  else
    last_warning = nil
  end
  applying = true
  local ok, err = pcall(function()
    vim.o.background = background
    vim.cmd.colorscheme(name)
  end)
  applying = false
  if not ok then
    error('Neovim appearance: cannot apply ' .. name .. ': ' .. err)
  end
  highlights()
  initialized = true
end

function M.on_colorscheme()
  if not applying then
    highlights()
    initialized = true
  end
end

return M
