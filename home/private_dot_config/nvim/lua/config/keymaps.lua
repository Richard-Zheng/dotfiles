-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
vim.keymap.set("n", "H", "<Cmd>BufferLineCyclePrev<CR>", { desc = "Prev Buffer" })
vim.keymap.set("n", "L", "<Cmd>BufferLineCycleNext<CR>", { desc = "Next Buffer" })

-- Toggle Snacks explorer with Ctrl+b
vim.keymap.set("n", "<C-b>", function()
  Snacks.explorer({ cwd = LazyVim.root() })
end, { desc = "Toggle Explorer (root dir)" })
