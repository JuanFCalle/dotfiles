let g:IntelloColorColumnBufferNameBlacklist = []
let g:IntelloColorColumnFileTypeBlacklist = ['command-t', 'diff', 'qf']
let g:IntelloMkviewFiletypeBlacklist = ['diff', 'gitcommit']

function! modules#autocmds#should_colorcolumn() abort
  if index(g:IntelloColorColumnBufferNameBlacklist, bufname(bufnr('%'))) != -1
    return 0
  endif
  if index(g:IntelloColorColumnFileTypeBlacklist, &filetype) != -1
    return 0
  endif
  return &buflisted
endfunction

function! modules#autocmds#blur_window() abort
  if modules#autocmds#should_colorcolumn()
    ownsyntax off
    set nolist
    if has('conceal')
      set conceallevel=0
    endif
  endif
endfunction

function! modules#autocmds#focus_window() abort
  if modules#autocmds#should_colorcolumn()
    if !empty(&ft)
      ownsyntax on
      set list
      if has('conceal')
        set conceallevel=1
      endif
    endif
  endif
endfunction

function! modules#autocmds#should_mkview() abort
  return
        \ &buftype ==# '' &&
        \ index(g:IntelloMkviewFiletypeBlacklist, &filetype) == -1 &&
        \ !exists('$SUDO_USER') " Don't create root-owned files.
endfunction

function! modules#autocmds#mkview() abort
  try
    if exists('*haslocaldir') && haslocaldir()
      " We never want to save an :lcd command, so hack around it...
      cd -
      mkview
      lcd -
    else
      mkview
    endif
  catch /\<E186\>/
    " No previous directory: probably a `git` operation.
  catch /\<E190\>/
    " Could be name or path length exceeding NAME_MAX or PATH_MAX.
  endtry
endfunction


function! modules#autocmds#blur_statusline() abort
  " Default blurred statusline (buffer number: filename).
  let l:blurred='%{modules#statusline#gutterpadding()}'
  let l:blurred.='\ ' " space
  let l:blurred.='\ ' " space
  let l:blurred.='\ ' " space
  let l:blurred.='\ ' " space
  let l:blurred.='%<' " truncation point
  let l:blurred.='%f' " filename
  let l:blurred.='%=' " split left/right halves (makes background cover whole)
  call s:update_statusline(l:blurred, 'blur')
endfunction

function! modules#autocmds#focus_statusline() abort
  " `setlocal statusline=` will revert to global 'statusline' setting.
  call s:update_statusline('', 'focus')
endfunction

function! s:update_statusline(default, action) abort
  let l:statusline = s:get_custom_statusline(a:action)
  if type(l:statusline) == type('')
    " Apply custom statusline.
    execute 'setlocal statusline=' . l:statusline
  elseif l:statusline == 0
    return
  else
    execute 'setlocal statusline=' . a:default
  endif
endfunction

function! s:get_custom_statusline(action) abort
  if &ft ==# 'command-t'
    return '\ \ ' . substitute(bufname('%'), ' ', '\\ ', 'g')
  elseif &ft ==# 'qf'
    if a:action ==# 'blur'
      return
            \ '%{modules#statusline#gutterpadding()}'
            \ . '\ '
            \ . '\ '
            \ . '\ '
            \ . '\ '
            \ . '%<'
            \ . '%q'
            \ . '\ '
            \ . '%{get(w:,\"quickfix_title\",\"\")}'
            \ . '%='
    else
      return g:IntelloQuickfixStatusline
    endif
  endif

  return 1 " Use default.
endfunction

function! modules#autocmds#idleboot() abort
  augroup IntelloIdleboot
    autocmd!
  augroup END
  doautocmd User IntelloDefer
  autocmd! User IntelloDefer
endfunction
