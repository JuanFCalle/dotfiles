--
-- Shared theming: Zsh owns theme selection, Neovim reads it.
--
-- `color()` in ~/.zsh/color.zsh applies the scheme to the shell, Kitty and
-- tmux, then records it in ~/.zsh/.tinted as two lines:
--
--   1. the scheme slug (eg. "base16-default-dark"), shared with Kitty, tmux
--      and tinted-vim, whose colorscheme names match it exactly;
--   2. "dark" or "light", derived from the scheme's background luma.
--
-- This module only *reads* that state. Malformed values are reported, never
-- silently repaired or rewritten: the shell owns the file.
--

local M = {}

M.CONFIG_FILE = '~/.zsh/.tinted'

-- Must match the startup default in ~/.zsh/color.zsh.
M.DEFAULT_SCHEME = 'base16-bright'
M.DEFAULT_BACKGROUND = 'dark'

--- Default probe for colorscheme availability.
--- @param scheme string
--- @return boolean
function M.colorscheme_exists(scheme)
  return vim.list_contains(vim.fn.getcompletion(scheme, 'color'), scheme)
end

--- Reads the saved theme state.
---
--- Returns the background and scheme to apply, plus any warnings. A `nil`
--- value means "leave the current setting alone", which is what we want for a
--- malformed line: better to keep working colors than to force a fallback over
--- a scheme the user did select.
---
--- @param path string
--- @param exists? fun(scheme: string): boolean
--- @return string|nil scheme
--- @return string|nil background
--- @return string[] warnings
function M.read_state(path, exists)
  exists = exists or M.colorscheme_exists

  local expanded = vim.fn.expand(path)
  local warnings = {}

  if vim.fn.filereadable(expanded) ~= 1 then
    return M.DEFAULT_SCHEME, M.DEFAULT_BACKGROUND, warnings
  end

  local lines = vim.fn.readfile(expanded, '', 2)
  local scheme, background = lines[1], lines[2]

  if background ~= 'dark' and background ~= 'light' then
    table.insert(warnings, 'Bad background ' .. tostring(background) .. ' in ' .. expanded)
    background = nil
  end

  if scheme == nil or scheme == '' or not exists(scheme) then
    table.insert(warnings, 'Bad scheme ' .. tostring(scheme) .. ' in ' .. expanded)
    scheme = nil
  end

  return scheme, background, warnings
end

return M
