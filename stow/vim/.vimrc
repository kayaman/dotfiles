" ── Core ─────────────────────────────────────────────────────────────
set nocompatible
filetype plugin indent on
syntax enable
set encoding=utf-8
scriptencoding utf-8
set hidden
set autoread
set backspace=indent,eol,start
set mouse=a
set ttyfast
set lazyredraw
set updatetime=300
set timeoutlen=500
set history=10000

" ── UI ───────────────────────────────────────────────────────────────
set number
set relativenumber
set cursorline
set ruler
set showcmd
set showmatch
set laststatus=2
set wildmenu
set wildmode=longest:full,full
set wildignore+=*/.git/*,*/node_modules/*,*/.DS_Store,*.pyc,*.o
set scrolloff=5
set sidescrolloff=8
set signcolumn=yes
set splitbelow
set splitright
set display+=lastline
set shortmess+=c
set noerrorbells
set novisualbell

" True color support
if has('termguicolors')
  set termguicolors
endif

" ── Indentation ──────────────────────────────────────────────────────
set expandtab
set tabstop=4
set softtabstop=4
set shiftwidth=4
set shiftround
set autoindent
set smartindent

augroup ft_indent
  autocmd!
  autocmd FileType yaml,yml,html,css,scss,javascript,typescript,json,lua,sh,zsh
        \ setlocal tabstop=2 softtabstop=2 shiftwidth=2
  autocmd FileType make setlocal noexpandtab
augroup END

" ── Search ───────────────────────────────────────────────────────────
set incsearch
set hlsearch
set ignorecase
set smartcase

" ── Files ────────────────────────────────────────────────────────────
set nobackup
set nowritebackup
set noswapfile

if has('persistent_undo')
  let s:undodir = expand('~/.vim/undo')
  if !isdirectory(s:undodir)
    call mkdir(s:undodir, 'p', 0700)
  endif
  let &undodir = s:undodir
  set undofile
  set undolevels=1000
endif

" ── Clipboard ────────────────────────────────────────────────────────
if has('clipboard')
  if has('unnamedplus')
    set clipboard=unnamedplus
  else
    set clipboard=unnamed
  endif
endif

" ── Keymaps ──────────────────────────────────────────────────────────
let mapleader = ' '
let maplocalleader = ','

" Clear search highlight
nnoremap <silent> <leader><space> :nohlsearch<CR>

" Quick save / quit
nnoremap <leader>w :w<CR>
nnoremap <leader>q :q<CR>

" Window navigation
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" Buffer navigation
nnoremap <leader>bn :bnext<CR>
nnoremap <leader>bp :bprevious<CR>
nnoremap <leader>bd :bdelete<CR>

" Keep selection after indent
vnoremap < <gv
vnoremap > >gv

" Move lines
vnoremap J :m '>+1<CR>gv=gv
vnoremap K :m '<-2<CR>gv=gv

" Center on jumps
nnoremap n nzzzv
nnoremap N Nzzzv
nnoremap <C-d> <C-d>zz
nnoremap <C-u> <C-u>zz

" ── Colorscheme ──────────────────────────────────────────────────────
set background=dark
silent! colorscheme habamax

" ── Misc ─────────────────────────────────────────────────────────────
" Return to last edit position when opening files
augroup last_position
  autocmd!
  autocmd BufReadPost *
        \ if line("'\"") > 1 && line("'\"") <= line("$") |
        \   exe "normal! g`\"" |
        \ endif
augroup END

" Trim trailing whitespace on save
augroup trim_whitespace
  autocmd!
  autocmd BufWritePre * let s:_pos = getpos('.') |
        \ keeppatterns %s/\s\+$//e |
        \ call setpos('.', s:_pos)
augroup END
