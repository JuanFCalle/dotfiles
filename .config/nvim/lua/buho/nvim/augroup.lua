--- Encapsulates the common pattern of creating (or redeclaring) an augroup,
--- clearing it, and populating it with autocommands.
---
--- Ported from wincent/wincent (lua/wincent/nvim/augroup.lua).
---
--- @param group_name string
--- @param callback fun(autocmd: fun(event: string|string[], pattern: string|string[], cmd: function|string, opts?: table))
local function augroup(group_name, callback)
  local group = vim.api.nvim_create_augroup(group_name, { clear = true })

  callback(function(event, pattern, cmd, opts)
    opts = vim.tbl_extend('keep', { group = group, pattern = pattern }, opts or {})
    opts[type(cmd) == 'function' and 'callback' or 'command'] = cmd
    vim.api.nvim_create_autocmd(event, opts)
  end)
end

return augroup
