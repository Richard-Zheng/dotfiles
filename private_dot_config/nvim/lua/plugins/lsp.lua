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
    end,
  }
}

