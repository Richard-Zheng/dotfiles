return {
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
      },
    },
  },
}
