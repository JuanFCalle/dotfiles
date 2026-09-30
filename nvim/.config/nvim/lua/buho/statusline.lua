-- Appearance adapted from Wincent 824beaea9 (public domain).
local M = {}

function M.gutterpadding()
  local signs = 0
  if vim.wo.signcolumn == 'yes' then
    signs = 2
  elseif vim.wo.signcolumn == 'auto' and #vim.fn.sign_getplaced('')[1].signs > 0 then
    signs = 2
  end
  return (' '):rep(math.max(#tostring(vim.api.nvim_buf_line_count(0)) + 1, 2, vim.wo.numberwidth) + signs - 1)
end

function M.lhs()
  return M.gutterpadding() .. (vim.bo.modified and '✘ ' or '  ')
end

function M.fileprefix()
  local directory = vim.fn.fnamemodify(vim.fn.expand('%:h'), ':p:~:.')
  return (directory == '' or directory == '.') and '' or directory:gsub('/$', '') .. '/'
end

function M.filetype()
  return vim.bo.filetype == '' and '' or ',' .. vim.bo.filetype
end

function M.fileencoding()
  local encoding = vim.bo.fileencoding
  return (encoding == '' or encoding == 'utf-8') and '' or ',' .. encoding
end

function M.rhs()
  if vim.fn.winwidth(0) <= 80 then
    return ' '
  end
  local column, width = vim.fn.virtcol('.'), vim.fn.virtcol('$')
  local line, height = vim.api.nvim_win_get_cursor(0)[1], vim.api.nvim_buf_line_count(0)
  return ' ' .. (' '):rep(#tostring(height) - #tostring(line))
    .. 'ℓ ' .. line .. '/' .. height .. ' 𝚌 ' .. column .. '/' .. width .. ' '
    .. (#tostring(column) < 2 and ' ' or '') .. (#tostring(width) < 2 and ' ' or '')
end

local expression = 'v:lua.require("buho.statusline").'
local left = '%7*%{' .. expression .. 'lhs()}%*%4*'
local right = '%= %5*%{' .. expression .. 'rhs()}%*'
local quickfix = left .. ' %*%3*%q %{get(w:,"quickfix_title","")}%*%< ' .. right
local inactive = '%{' .. expression .. 'gutterpadding()}    %<'

function M.set()
  vim.o.statusline = left .. '%* %<%{' .. expression .. 'fileprefix()}%3*%t%* '
    .. '%1*%([%R%{' .. expression .. 'filetype()}%{' .. expression .. 'fileencoding()}]%)%*' .. right
end

function M.focus_statusline()
  vim.wo.statusline = vim.bo.filetype == 'qf' and quickfix or ''
end

function M.blur_statusline()
  vim.wo.statusline = inactive
    .. (vim.bo.filetype == 'qf' and '%q %{get(w:,"quickfix_title","")}' or '%f') .. '%='
end

function M.update_highlight()
  local p = require('wincent.pinnacle')
  p.set('User1', p.italicize('StatusLine'))
  p.set('User3', p.embolden('StatusLine'))
  local accent = p.fg(vim.bo.modified and 'ModeMsg' or 'Identifier')
  p.set('User4', { bg = p.bg('StatusLine'), fg = accent })
  p.set('User7', { bg = accent, fg = p.fg('Normal'), bold = true })
  p.set('User5', { bg = p.fg('User3'), fg = p.fg('Cursor'), bold = true })
  p.link('StatusLineNC', 'User1')
end

M.check_modified = M.update_highlight

return M
