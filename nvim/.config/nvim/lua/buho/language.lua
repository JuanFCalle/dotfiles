-- Appearance adapted from Wincent 824beaea9 (public domain).
local M = {}
local languages = {
  c = 'c', lua = 'lua', markdown = 'markdown', query = 'query', scheme = 'query',
  vim = 'vim', help = 'vimdoc', kotlin = 'kotlin', python = 'python', yaml = 'yaml',
  json = 'json', zsh = 'zsh', sh = 'bash', bash = 'bash',
}

local function large(buf)
  local stat = vim.uv.fs_stat(vim.api.nvim_buf_get_name(buf))
  return (stat and stat.size > 1024 * 1024)
    or vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf)) > 1024 * 1024
end

function M.refresh(buf)
  local lang = languages[vim.bo[buf].filetype]
  local oversized = large(buf)
  require('ibl').setup_buffer(buf, { enabled = vim.bo[buf].expandtab and not oversized })
  if not lang then
    return
  end
  if oversized then
    vim.treesitter.stop(buf)
  elseif not vim.treesitter.highlighter.active[buf] then
    vim.treesitter.start(buf, lang)
  end
end

function M.setup()
  require('nvim-treesitter').setup({ install_dir = vim.fn.stdpath('data') .. '/site' })
  vim.treesitter.language.register('bash', { 'sh', 'bash' })
  vim.treesitter.language.register('query', { 'query', 'scheme' })
  for _, lang in ipairs({ 'c', 'lua', 'markdown', 'markdown_inline', 'query', 'vim', 'vimdoc',
    'kotlin', 'python', 'yaml', 'json', 'zsh', 'bash' }) do
    local ok, err = vim.treesitter.language.add(lang)
    assert(ok, 'Neovim appearance: missing parser ' .. lang .. '; see docs/COLOR_THEME.md. ' .. tostring(err))
    assert(vim.treesitter.query.get(lang, 'highlights'), 'Neovim appearance: missing highlights for ' .. lang)
  end
end

return M
