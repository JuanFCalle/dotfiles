function! modules#pinnacle#active()
  try
    call pinnacle#highlight({})
    return 1
  catch /E117/
    return 0
  endtry
endfunction
