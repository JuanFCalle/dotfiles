scriptencoding uft-8

" Variant of statusline from plugin/statusline.vim (can't comment inline
" with line continuation markers without Vim freaking out).
let g:IntelloQuickfixStatusline =
      \ '%7*'
      \ . '%{modules#statusline#lhs()}'
      \ . '%*'
      \ . '%4*'
      \ . ''
      \ . '\ '
      \ . '%*'
      \ . '%3*'
      \ . '%q'
      \ . '\ '
      \ . '%{get(w:,\"quickfix_title\",\"\")}'
      \ . '%*'
      \ . '%<'
      \ . '\ '
      \ . '%='
      \ . '\ '
      \ . ''
      \ . '%5*'
      \ . '%{modules#statusline#rhs()}'
      \ . '%*'
