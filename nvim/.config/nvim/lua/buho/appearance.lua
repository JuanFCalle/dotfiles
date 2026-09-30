-- Appearance adapted from Wincent 824beaea9 (public domain).
local M = {}
local status = require('buho.statusline')
local theme = require('buho.theme')
local language = require('buho.language')
local focused = true
local band = '+' .. table.concat(vim.fn.range(0, 254), ',+')
local blurred = table.concat({
  'CursorLineNr:LineNr', 'EndOfBuffer:ColorColumn', 'IncSearch:ColorColumn',
  'Normal:ColorColumn', 'NormalNC:ColorColumn', 'Search:ColorColumn', 'SignColumn:ColorColumn',
}, ',')
local listchars = { nbsp = '⦸', extends = '»', precedes = '«', tab = '▷─', trail = '•' }
local signs = { '✖', '⚐', '𝒾', '✶' }

M.refresh_theme = theme.refresh

function M.tablabel(number)
  local buffers = vim.fn.tabpagebuflist(number)
  return vim.fn.pathshorten(vim.fn.fnamemodify(vim.fn.bufname(buffers[vim.fn.tabpagewinnr(number)]), ':~:.'))
end

function M.tabline()
  local line = ''
  for i = 1, vim.fn.tabpagenr('$') do
    line = line .. (i == vim.fn.tabpagenr() and '%#TabLineSel#' or '%#TabLine#')
      .. '%' .. i .. 'T %{v:lua.require("buho.appearance").tablabel(' .. i .. ')} '
  end
  return line .. '%#TabLineFill#%T'
end

function M.foldtext()
  local count = vim.v.foldend - vim.v.foldstart + 1
  local first = vim.fn.getline(vim.v.foldstart)
  local whitespace = first:match('^%s*')
  local indent = #whitespace:gsub(' +', '') * vim.bo.tabstop + #whitespace:gsub('\t', '')
  return '»··[' .. count .. 'ℓ]' .. ('·'):rep(math.max(indent - #tostring(count) - 8, 0))
    .. ': ' .. first:match('^%s*(.-)$')
end

local function floating(win)
  local config = vim.api.nvim_win_get_config(win)
  return config.relative ~= '' or config.external
end

local function window(active)
  if floating(0) then
    return
  end
  local ft = vim.bo.filetype
  local diff = ft == 'diff' or vim.wo.diff
  local special = diff or ft == 'qf'
  if vim.b.buho_lsp_attached then
    if vim.w.buho_signcolumn == nil then vim.w.buho_signcolumn = vim.wo.signcolumn end
    vim.wo.signcolumn = 'yes'
  elseif vim.w.buho_signcolumn ~= nil then
    vim.wo.signcolumn = vim.w.buho_signcolumn
    vim.w.buho_signcolumn = nil
  end
  if ft ~= 'help' and not special and vim.bo.buftype == '' then
    vim.wo.number, vim.wo.relativenumber = true, active
  end
  vim.wo.winhighlight = (active or special) and '' or blurred
  vim.wo.colorcolumn = special and '' or band
  vim.wo.list = active and ft ~= 'help' and ft ~= 'mail'
  vim.wo.conceallevel = ft == 'help' and 2 or 0
  vim.wo.cursorline = active and not vim.api.nvim_get_mode().mode:match('^i')
  local plaintext = ft == 'markdown' or ft == 'hgcommit' or ft == 'arc'
  vim.opt_local.listchars = plaintext and { trail = '•' } or listchars
  vim.wo.concealcursor = (plaintext or ft == 'vim') and 'nc' or vim.go.concealcursor
  vim.wo.breakindent = ft == 'markdown'
  vim.wo.breakindentopt = ft == 'markdown' and 'sbr,shift:' .. vim.bo.shiftwidth or vim.go.breakindentopt
  if active then
    status.focus_statusline()
  else
    status.blur_statusline()
  end
end

local function windows()
  local current = vim.api.nvim_get_current_win()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    vim.api.nvim_win_call(win, function() window(focused and win == current) end)
  end
  status.check_modified()
end

function M.setup()
  for _, package in ipairs({ 'base16-nvim', 'pinnacle', 'nvim-treesitter', 'indent-blankline.nvim' }) do
    vim.cmd.packadd(package)
  end
  language.setup()
  vim.opt.fillchars = { diff = '╱', eob = ' ', fold = '·', vert = '│' }
  vim.opt.listchars = listchars
  vim.opt.linebreak = true
  vim.opt.showbreak = '↳ '
  vim.opt.pumheight = 20
  vim.opt.showcmd = false
  vim.opt.shortmess:append('AIOTWacot')
  vim.opt.sidescrolloff = 3
  vim.opt.synmaxcol = 200
  vim.g.vim_json_syntax_conceal = 0
  vim.o.tabline = '%!v:lua.require("buho.appearance").tabline()'
  vim.o.foldtext = 'v:lua.require("buho.appearance").foldtext()'
  status.set()
  local numhl, texthl = {}, {}
  for i, severity in ipairs({ 'Error', 'Warn', 'Info', 'Hint' }) do
    numhl[i], texthl[i] = 'DiagnosticSign' .. severity, ''
  end
  vim.diagnostic.config({
    severity_sort = true, virtual_lines = true,
    signs = { text = signs, texthl = texthl, numhl = numhl },
    float = {
      border = 'single', header = 'Diagnostics',
      prefix = function(diagnostic) return (signs[diagnostic.severity] or '•') .. ' ', '' end,
    },
  })
  local group = vim.api.nvim_create_augroup('buho.appearance', { clear = true })
  local function on(events, callback, pattern)
    vim.api.nvim_create_autocmd(events, { group = group, pattern = pattern, callback = callback })
  end
  on('ColorScheme', theme.on_colorscheme)
  on('FocusGained', function() focused = true; M.refresh_theme(); windows() end)
  on('FocusLost', function() focused = false; windows() end)
  on({ 'VimEnter', 'BufEnter', 'BufWinEnter', 'WinEnter' }, function()
    windows()
    language.refresh(vim.api.nvim_get_current_buf())
  end)
  on('WinLeave', function() window(false) end)
  on('BufLeave', function()
    if vim.w.buho_signcolumn ~= nil then
      vim.wo.signcolumn = vim.w.buho_signcolumn
      vim.w.buho_signcolumn = nil
    end
  end)
  on('FileType', function(event)
    language.refresh(event.buf)
    windows()
    -- Built-in ftplugins can run after this hook (notably qf's statusline).
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(event.buf) then windows() end
    end)
  end)
  on('InsertEnter', function() if not floating(0) then vim.wo.cursorline = false end end)
  on('InsertLeave', windows)
  on({ 'BufModifiedSet', 'BufWritePost', 'TextChanged', 'TextChangedI' }, function(event)
    status.check_modified()
    language.refresh(event.buf)
  end)
  on('OptionSet', function(event) language.refresh(event.buf) end, 'expandtab')
  on('OptionSet', windows, 'diff')
  on('LspAttach', function(event)
    vim.b[event.buf].buho_lsp_attached = true
    windows()
  end)
  on('LspDetach', function(event)
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(event.buf) then
        vim.b[event.buf].buho_lsp_attached = #vim.lsp.get_clients({ bufnr = event.buf }) > 0
        windows()
      end
    end)
  end)
  on('TextYankPost', function() vim.hl.on_yank({ higroup = 'Substitute', timeout = 200 }) end)
  require('ibl').setup({ indent = { char = '│' }, exclude = { filetypes = { 'markdown' } } })
  M.refresh_theme()
  windows()
  language.refresh(vim.api.nvim_get_current_buf())
end

return M
