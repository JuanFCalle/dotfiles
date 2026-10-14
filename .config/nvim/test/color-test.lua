-- Runnable check for the shared-theming state parser.
--
--   nvim -l ~/.config/nvim/test/color-test.lua
--
-- Covers the four cases `color()` can leave on disk: a good selection, a
-- malformed background, an unknown scheme, and no state at all.

local color = require('buho.color')

local function exists(scheme)
  return scheme == 'base16-default-dark'
end

local function write(lines)
  local path = vim.fn.tempname()
  vim.fn.writefile(lines, path)
  return path
end

-- Valid state is applied as-is, without complaint.
local scheme, background, warnings = color.read_state(write({ 'base16-default-dark', 'light' }), exists)
assert(scheme == 'base16-default-dark', 'valid scheme should be returned, got ' .. tostring(scheme))
assert(background == 'light', 'valid background should be returned, got ' .. tostring(background))
assert(#warnings == 0, 'valid state should not warn')

-- A malformed background warns and leaves the current one alone, but must not
-- discard the scheme alongside it.
scheme, background, warnings = color.read_state(write({ 'base16-default-dark', 'DARK' }), exists)
assert(scheme == 'base16-default-dark', 'scheme should survive a bad background')
assert(background == nil, 'bad background should not be applied')
assert(#warnings == 1, 'bad background should warn exactly once')

-- An unknown scheme warns rather than being silently repaired.
scheme, background, warnings = color.read_state(write({ 'base16-nonexistent', 'dark' }), exists)
assert(scheme == nil, 'unknown scheme should not be applied')
assert(background == 'dark', 'background should survive a bad scheme')
assert(#warnings == 1, 'unknown scheme should warn exactly once')

-- A missing line is malformed, not an empty slug.
scheme, background, warnings = color.read_state(write({ 'base16-default-dark' }), exists)
assert(background == nil, 'missing background should not be applied')
assert(#warnings == 1, 'missing background should warn exactly once')

-- No state yet: fall back to the same defaults as the shell.
scheme, background, warnings = color.read_state(vim.fn.tempname(), exists)
assert(scheme == color.DEFAULT_SCHEME, 'missing state should fall back to the default scheme')
assert(background == color.DEFAULT_BACKGROUND, 'missing state should fall back to the default background')
assert(#warnings == 0, 'missing state is normal and should not warn')

print('ok')
