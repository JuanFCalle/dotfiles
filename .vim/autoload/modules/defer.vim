function! modules#defer#defer(evalable) abort
  if has('autocmd') && has('vim_starting')
    execute 'autocmd User IntelloDefer ' . a:evalable
  else
    execute a:evalable
  endif
endfunction
