--
-- Applies the theme selected by `color()` in ~/.zsh/color.zsh.
--
-- Ported from wincent/wincent (after/plugin/color.lua). See lua/buho/color.lua
-- for the state-file contract.
--

local augroup = require('buho.nvim.augroup')
local color = require('buho.color')

local function check()
  local scheme, background, warnings = color.read_state(color.CONFIG_FILE)

  for _, warning in ipairs(warnings) do
    vim.notify(warning, vim.log.levels.WARN)
  end

  if background then
    vim.o.background = background
  end

  if scheme then
    vim.cmd.colorscheme(scheme)
  end

  -- Overrides are optional: without pinnacle we still get the colorscheme.
  local has_pinnacle, pinnacle = pcall(require, 'wincent.pinnacle')
  if has_pinnacle then
    local dark = vim.o.background == 'dark'

    pinnacle.merge('Comment', { italic = true })

    -- Make floating windows look nicer, as seen in the nvim-lspconfig wiki:
    -- https://github.com/neovim/nvim-lspconfig/wiki/UI-customization
    local normal = pinnacle.adjust_lightness('Normal', dark and 0.1 or -0.1)
    pinnacle.set('NormalFloat', normal)
    normal['fg'] = dark and '#ffffff' or '#000000'
    normal['blend'] = vim.o.winblend
    pinnacle.set('FloatBorder', normal)
  end

  -- Allow for overrides; loupe re-sets Search and QuickFixLine here, and a
  -- statusline would re-set User1, User3 etc.
  vim.cmd.doautocmd('ColorScheme')
end

if vim.v.progname ~= 'vi' then
  augroup('buho.color', function(autocmd)
    autocmd('FocusGained', '*', check)

    -- Ideally we'd only do this outside of tmux (we don't get FocusGained
    -- events on launch outside of tmux), but we have to do it unconditionally
    -- because sometimes tmux doesn't get the events (for example, when Neovim
    -- is launched in a non-focused pane via `tmux send-keys`). This means that
    -- we'll run twice (VimEnter, then FocusGained) when launched conventionally
    -- inside tmux.
    autocmd('VimEnter', '*', check)
  end)
end
