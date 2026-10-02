" ~/.vimrc (configuration file for vim only)
" filetypes
filetype indent on
syntax on
set ruler
set confirm
set showmode
set showmatch
set esckeys
set nocompatible
set backspace=indent,eol,start
set spelllang=en
nnoremap Y y$
nnoremap <up> gk
nnoremap <down> gj
nnoremap <F2> :set invpaste paste?<CR>
set pastetoggle=<F2>
set showmode
"vim too old
"set cm=blowfish2
set ignorecase smartcase infercase
set hlsearch
set cindent
set smartindent
set shiftwidth=2
set wildmenu wildmode=list:full
 
"allows case-insensitivity for saving/quitting
if has("user_commands")
    command! -bang -nargs=? -complete=file W w<bang> <args>
    command! -bang -nargs=? -complete=file Wq wq<bang> <args>
    command! -bang -nargs=? -complete=file WQ wq<bang> <args>
    command! -bang Wa wa<bang>
    command! -bang WA wa<bang>
    command! -bang Q q<bang>
    command! -bang QA qa<bang>
    command! -bang Qa qa<bang>
endif
 
set splitbelow
set splitright
set wildmode=longest,list
set gdefault
nnoremap n nzz
nnoremap } }zz
nnoremap N Nzz
nnoremap { {zz
 
"This allows for change paste motion cp{motion}
nmap <silent> cp :set opfunc=ChangePaste<CR>g@
function! ChangePaste(type, ...)
    silent exe "normal! `[v`]\"_c"
    silent exe "normal! p"
endfunction
 
let mapleader = ","
 
" Press Space to turn off highlighting and clear any message already
" displayed.
nnoremap <silent> <Space> :nohlsearch<Bar>:echo<CR>
 
" copy visually selected command to cmd-mode by pressing :
vnoremap : y:<C-r>"<C-b>
 
" secure encrypted files
augroup cryptstore
    au!
    " First make sure nothing is written to ~/.viminfo while editing
    " an encrypted file.
    autocmd BufReadPre,FileReadPre      *.crypt set viminfo=
    " We don't want a swap file, as it writes unencrypted data to disk.
    autocmd BufReadPre,FileReadPre      *.crypt set noswapfile
augroup END
 
" Airline
set laststatus=2
"let g:airline#extensions#tabline#enabled = 1
" ~/.vimrc ends here
