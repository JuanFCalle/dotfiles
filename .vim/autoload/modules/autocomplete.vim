let s:deoplete_init_done=0
function! modules#autocomplete#deoplete_init() abort
  if s:deoplete_init_done || !has('nvim')
    return
  endif
  let s:deoplete_init_done=1
  call deoplete#enable()
  call deoplete#custom#source('_', 'matchers', ['matcher_full_fuzzy'])
endfunction
