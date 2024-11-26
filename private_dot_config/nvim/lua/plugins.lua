return {
  {
    "catppuccin/nvim",
    lazy = false, -- make sure we load this during startup
    name = "catppuccin",
    priority = 1000, -- make sure to load this before all the other start plugins
    config = function()
      -- load the colorscheme here
      vim.cmd([[colorscheme catppuccin]])
    end,
  },
  {
    "max397574/better-escape.nvim",
    lazy = false,
    opts = {
      timeout = 100, -- the time in which the keys must be hit in ms. Use option timeoutlen by default
      mappings = {
        i = {
            j = {
                k = "<Esc>",
            },
            k = {
                j = "<Esc>",
            },
        },
      }
    }
  },
  {
    'nvim-telescope/telescope.nvim',
    branch = '0.1.x',
    dependencies = { 'nvim-lua/plenary.nvim' },
    opts = {
        defaults = {
        file_ignore_patterns = {
          "node_modules",
          "go",
        }
      }
    },
    keys = {
      { '<C-p>', "<cmd>Telescope find_files<cr>", desc = "Find files" },
      { '<leader>ff', "<cmd>Telescope find_files<cr>", desc = "Find files" },
      { '<leader>fg', "<cmd>Telescope live_grep<cr>", desc = "Live grep" },
      { '<leader>fb', "<cmd>Telescope buffers<cr>", desc = "Buffers" },
      { '<leader>fh', "<cmd>Telescope help_tags<cr>", desc = "Help tags" },
      {
        '<leader>fp',
        function ()
          require'telescope'.extensions.projects.projects{}
        end,
        desc = "Recent projects"
      },
    },
    config = function (_, opts)
      require('telescope').setup(opts)
      require('telescope').load_extension('projects')
    end
  },
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    config = function ()
      local configs = require("nvim-treesitter.configs")

      configs.setup({
        ensure_installed = { "c", "lua", "vim", "vimdoc", "query", "elixir", "heex", "javascript", "html" },
        sync_install = false,
        auto_install = true,
        ignore_install = {},
        highlight = { enable = true },
        indent = { enable = true },
      })
    end
  },
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    init = function()
      vim.o.timeout = true
      vim.o.timeoutlen = 300
    end,
    opts = {}
  },
  {
    'nvim-lualine/lualine.nvim',
    dependencies = { 'nvim-tree/nvim-web-devicons' },
    opts = {
      theme = 'dracula'
    }
  },
  {
    'ahmedkhalf/project.nvim',
    config = function()
      require("project_nvim").setup {
        patterns = { ".git", "Makefile", "package.json", "init.lua" },
      }
    end
  }
}

