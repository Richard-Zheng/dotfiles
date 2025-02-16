-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- Enable shada file
vim.o.shada = "'1000,f1,<500,:100"
-- Line number
vim.opt.number = true
vim.opt.relativenumber = true
-- vim.opt.relativenumber = true
-- <Tab> = 2 spaces
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.bo.softtabstop = 2

-- Make sure to setup `mapleader` and `maplocalleader` before
-- loading lazy.nvim so that mappings are correct.
vim.g.mapleader = ' '
-- <leader>, as original comma
vim.keymap.set('n', '<leader>,', ',', { desc = "original ,", noremap = true, silent = true })
-- Key mappings
local map = vim.keymap.set
local nsopt = { noremap = true, silent = true }
-- Use <Esc>/jk/kj to go from terminal mode to normal mode
map('t', '<Esc>', [[<C-\><C-n>]], nsopt)
map('t', 'jk', [[<C-\><C-n>]], nsopt)
map('t', 'kj', [[<C-\><C-n>]], nsopt)
-- Ctrl+HJKL as window selection
map("n", "<C-h>", "<C-w>h", nsopt)
map("n", "<C-j>", "<C-w>j", nsopt)
map("n", "<C-k>", "<C-w>k", nsopt)
map("n", "<C-l>", "<C-w>l", nsopt)
map("t", "<C-h>", "<cmd>wincmd h<CR>", nsopt)
map("t", "<C-j>", "<cmd>wincmd j<CR>", nsopt)
map("t", "<C-k>", "<cmd>wincmd k<CR>", nsopt)
map("t", "<C-l>", "<cmd>wincmd l<CR>", nsopt)
-- Netrw
vim.api.nvim_create_autocmd('filetype', {
  pattern = 'netrw',
  desc = 'Better mappings for netrw',
  callback = function()
    local bind = function(lhs, rhs)
      vim.keymap.set('n', lhs, rhs, { remap = true, buffer = true })
    end
    -- edit new file
    bind('n', '%')
    -- rename file
    bind('r', 'R')
    bind("<C-l>", "<C-w>l")
  end
})
-- Window resize
map("n", "<C-Up>", ":resize -2<CR>", nsopt)
map("n", "<C-Down>", ":resize +2<CR>", nsopt)
map("n", "<C-Left>", ":vertical resize -2<CR>", nsopt)
map("n", "<C-Right>", ":vertical resize +2<CR>", nsopt)
map("t", "<C-Up>", "<cmd>resize -2<CR>", nsopt)
map("t", "<C-Down>", "<cmd>resize +2<CR>", nsopt)
map("t", "<C-Left>", "<cmd>vertical resize -2<CR>", nsopt)
map("t", "<C-Right>", "<cmd>vertical resize +2<CR>", nsopt)
-- Buffers
map("n", "<TAB>", ":bp<CR>", nsopt)
map("n", "<S-TAB>", ":bn<CR>", nsopt)
map("n", "<leader>bd", ":bd<CR>", { desc = "Unload current buffer", noremap = true, silent = true })
-- Indenting
map("v", "<", "<gv", nsopt)
map("v", ">", ">gv", nsopt)

-- Install lazy.nvim first
-- paru -S nvim-lazy
require("lazy").setup("plugins")

