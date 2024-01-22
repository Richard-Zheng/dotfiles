-- Enable shada file
vim.o.shada = "'1000,f1,<500,:100"
-- Use <Esc> to go from terminal mode to normal mode
vim.keymap.set('t', '<Esc>', [[<C-\><C-n>]])
-- Line number
vim.opt.number = true
-- vim.opt.relativenumber = true
-- <Tab> = 2 spaces
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.bo.softtabstop = 2

require("plugins")
