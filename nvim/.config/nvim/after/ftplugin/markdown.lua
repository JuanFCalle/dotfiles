vim.bo.synmaxcol = 0
vim.b.undo_ftplugin = (vim.b.undo_ftplugin or '') .. '\n setlocal synmaxcol<'
