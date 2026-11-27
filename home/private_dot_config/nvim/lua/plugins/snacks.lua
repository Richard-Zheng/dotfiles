return {
  "folke/snacks.nvim",
  keys = {
    {
      "<LeftMouse>",
      function()
        local pos = vim.fn.getmousepos()
        if pos.winid ~= 0 and pos.line > 0 and pos.column > 0 and package.loaded["snacks.picker"] then
          for _, picker in ipairs(Snacks.picker.get({ source = "explorer" })) do
            if picker.list.win:valid() and pos.winid == picker.list.win.win then
              local idx = picker.list:row2idx(pos.line)
              local item = picker.list:get(idx)
              if item and item.dir then
                vim.schedule(function()
                  if not picker.closed and picker.list.win:valid() then
                    picker.list:_move(idx, true, true)
                    picker:action("confirm")
                  end
                end)
              end
              break
            end
          end
        end
        return "<LeftMouse>"
      end,
      mode = "n",
      expr = true,
      desc = "Single-click folder in Snacks Explorer",
    },
  },
  opts = {
    picker = {
      sources = {
        explorer = {
          actions = {
            explorer_double_click = function(picker, item)
              if item and not item.dir then
                picker:action("confirm")
              end
            end,
          },
          win = {
            list = {
              keys = {
                ["<2-LeftMouse>"] = "explorer_double_click",
                ["<c-j>"] = false,
                ["<c-k>"] = false,
                ["<c-b>"] = false,
              },
            },
          },
        },
      },
    },
  },
}
