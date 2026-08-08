local vim = vim
local config = require "octo.config"

local create = vim.api.nvim_create_augroup
local define = vim.api.nvim_create_autocmd

local M = {}

create("octo_autocmds", { clear = true })
create("octobuffer_autocmds", { clear = false })

---Handles `:w` in an octo:// buffer.
---
---Publishing is gated on `submit_on_write`. When it is off the buffer is left
---modified on purpose: clearing the flag would make `:w` look like it saved,
---which is the confusion this option exists to remove.
---@return nil
function M.on_buf_write_cmd()
  if not config.values.submit_on_write then
    require("octo.utils").info "Writing does not publish. Use `:Octo submit` (\\op) to send changes."
    return
  end
  require("octo").save_buffer()
end

function M.setup()
  define({ "BufEnter" }, {
    group = "octo_autocmds",
    pattern = { "octo://*" },
    callback = function()
      require("octo").configure_octo_buffer()
    end,
  })

  if config.values.use_local_fs then
    define({ "BufEnter" }, {
      group = "octo_autocmds",
      pattern = { "*" },
      callback = function()
        local current_buffer = vim.api.nvim_buf_get_name(0)
        if not current_buffer:match "^octo://" then
          require("octo").update_layout_for_current_file()
        end
      end,
    })
  end

  define({ "BufDelete", "BufWipeout" }, {
    group = "octo_autocmds",
    pattern = { "octo://*" },
    callback = function(ev)
      require("octo.polling").untrack_buffer(ev.buf)
      -- Explicitly remove the vim.on_key callback for details fold arrow updates
      local on_key_ns = vim.api.nvim_create_namespace("octo_details_on_key_" .. ev.buf)
      vim.on_key(nil, on_key_ns)
    end,
  })

  define({ "BufReadCmd" }, {
    group = "octo_autocmds",
    pattern = { "octo://*" },
    callback = function(ev)
      require("octo").load_buffer { bufnr = ev.buf }
    end,
  })
  define({ "BufWriteCmd" }, {
    group = "octo_autocmds",
    pattern = { "octo://*" },
    callback = function()
      M.on_buf_write_cmd()
    end,
  })
  define({ "CursorHold" }, {
    group = "octo_autocmds",
    pattern = { "octo://*" },
    callback = function()
      require("octo").on_cursor_hold()
    end,
  })
  if config.values.reviews.auto_show_threads then
    define({ "CursorMoved" }, {
      group = "octo_autocmds",
      pattern = { "*" },
      callback = function()
        require("octo.reviews.thread-panel").show_review_threads(false)
      end,
    })
  end
  define({ "TabClosed" }, {
    group = "octo_autocmds",
    pattern = { "*" },
    callback = function()
      require("octo.reviews").close(tonumber(vim.fn.expand "<afile>"))
    end,
  })
  define({ "TabEnter" }, {
    group = "octo_autocmds",
    pattern = { "*" },
    callback = function()
      require("octo.reviews").on_tab_enter()
    end,
  })
  define({ "TabLeave" }, {
    group = "octo_autocmds",
    pattern = { "*" },
    callback = function()
      require("octo.reviews").on_tab_leave()
    end,
  })
  define({ "WinLeave" }, {
    group = "octo_autocmds",
    pattern = { "*" },
    callback = function()
      require("octo.reviews").on_win_leave()
    end,
  })
end

function M.update_signs(bufnr)
  define({ "TextChanged", "TextChangedI" }, {
    group = "octobuffer_autocmds",
    buffer = bufnr,
    callback = function()
      require("octo").render_signs()
    end,
  })
end

return M
