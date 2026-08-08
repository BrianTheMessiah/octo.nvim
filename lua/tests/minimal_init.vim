set rtp +=.
set rtp +=../plenary.nvim/
set rtp +=../fzf-lua/

lua _G.__is_log = true
lua vim.fn.setenv("DEBUG_PLENARY", true)
runtime! plugin/plenary.vim
runtime! plugin/octo.nvim

" Load fzf-lua before plenary.busted replaces the global `assert`. fzf-lua's
" own Lua 5.1 compatibility shim (fzf-lua/utils.lua) expects the original
" `assert`; luassert's callable table breaks it on first touch, and once
" broken it takes any spec requiring the fzf-lua picker down with it.
lua require("fzf-lua")

lua << EOF
require("plenary/busted")
require("tests/test_utils")
require("octo").setup()
EOF
