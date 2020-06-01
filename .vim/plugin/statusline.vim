scriptencoding utf-8

if has('statusline')
  set statusline=%7*                                 " Switch to User7 highlight group
  set statusline+=%{modules#statusline#lhs()}
  set statusline+=%*                                 " Reset highlight group.
  set statusline+=%4*                                " Switch to User4 highlight group (Powerline arrow).
  set statusline+=                                  " Powerline arrow.
  set statusline+=%*                                 " Reset highlight group.
  set statusline+=\                                  " Space.
  set statusline+=%<                                 " Truncation point, if not enough width available.
  set statusline+=%{modules#statusline#fileprefix()} " Relative path to file's directory.
  set statusline+=%3*                                " Switch to User3 highlight group (bold).
  set statusline+=%t                                 " Filename.
  set statusline+=%*                                 " Reset highlight group.
  set statusline+=\                                  " Space.
  set statusline+=%([%R%{modules#statusline#ft()}%{modules#statusline#fenc()}]%)
  set statusline+=%*   " Reset highlight group.
  set statusline+=%=   " Split point for left and right groups.
  set statusline+=\               " Space.
  set statusline+=               " Powerline arrow.
  set statusline+=%5*             " Switch to User5 highlight group.
  set statusline+=%{modules#statusline#rhs()}
  set statusline+=%*              " Reset highlight group.

  if has('autocmd')
    augroup IntelloStatusline
      autocmd!
      autocmd ColorScheme * call modules#statusline#update_highlight()
      if exists('##TextChangedI')
        autocmd BufWinEnter,BufWritePost,FileWritePost,TextChanged,TextChangedI,WinEnter * call modules#statusline#check_modified()
      else
        autocmd BufWinEnter,BufWritePost,FileWritePost,WinEnter * call modules#statusline#check_modified()
      endif
    augroup END
  endif
endif
