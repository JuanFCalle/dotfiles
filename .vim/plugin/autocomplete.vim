if has('nvim')
  packadd deoplete
  call modules#defer#defer('call modules#autocomplete#deoplete_init()')

  inoremap <expr><C-j> pumvisible() ? "\<c-n>" : "\<c-j>"
  inoremap <expr><C-k> pumvisible() ? "\<c-p>" : "\<c-j>"
endif
