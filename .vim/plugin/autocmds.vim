scriptencoding utf-8

if has('autocmd')
  function! s:IntelloAutocmds()
    augroup IntelloAutocmds
      autocmd!
      " Make current window more obvious by turning off/adjusting some features in non-current windows
      if exists('+winhighlight')
        autocmd BufEnter,FocusGained,VimEnter,WinEnter * set winhighlight=
        autocmd FocusLost,WinLeave * set winhighlight=CursorLineNr:LineNr,EndOfBuffer:ColorColumn,IncSearc:ColorColumn,Normal:ColorColumn,NormalNC:ColorColumn,SignColumn:ColorColumn
      endif
      if has('statusline')
        autocmd BufEnter,FocusGained,VimEnter,WinEnter * call modules#autocmds#focus_statusline()
        autocmd FocusLost,WinLeave * call modules#autocmds#blur_statusline()
      endif
      if has('mksession')
        " Save/restore folds and cursor position.
        autocmd BufWritePost,BufLeave,WinLeave ?* if modules#autocmds#should_mkview() | call modules#autocmds#mkview() | endif
        if has('folding')
          autocmd BufWinEnter ?* if modules#autocmds#should_mkview() | silent! loadview | execute 'silent! ' . line('.') . 'foldopen!' | endif
        else
          autocmd BufWinEnter ?* if modules#autocmds#should_mkview() | silent! loadview | endif
        endif
      elseif has('folding')
        " Like the autocmd described in `:h last-position-jump` but we add `:foldopen!`.
        autocmd BufWinEnter * if line("'\"") > 1 && line("'\"") <= line('$') | execute "normal! g`\"" | execute 'silent! ' . line("'\"") . 'foldopen!' | endif
      else
        autocmd BufWinEnter * if line("'\"") > 1 && line("'\"") <= line('$') | execute "normal! g`\"" | endif
      endif
    augroup END
  endfunction

  call s:IntelloAutocmds()
endif
