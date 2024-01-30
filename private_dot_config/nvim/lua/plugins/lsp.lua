return {
  {
    "neovim/nvim-lspconfig",
    dependencies = { { "folke/neodev.nvim", lazy = true } },
    config = function()
      -- IMPORTANT: make sure to setup neodev BEFORE lspconfig
      require("neodev").setup({
        -- add any options here, or leave empty to use the default settings
      })
      local lspconfig = require("lspconfig")
      -- pacman -S lua-language-server
      lspconfig.lua_ls.setup({})
      lspconfig.denols.setup({ single_file_support = true })

      vim.keymap.set('n', 'K', vim.lsp.buf.hover, {})
      vim.keymap.set('n', 'gd', vim.lsp.buf.definition, {})
      vim.keymap.set('n', '<leader>ca', vim.lsp.buf.code_action, { desc = "Code action" })
    end,
  }
}

