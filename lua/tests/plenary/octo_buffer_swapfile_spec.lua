---@diagnostic disable
local OctoBuffer = require("octo.model.octo-buffer").OctoBuffer
local eq = assert.are.same

describe("OctoBuffer swap files:", function()
  ---An OctoBuffer over a real scratch buffer, named and then configured in the
  ---order create_buffer uses (lua/octo/init.lua: the buffer is named at :427,
  ---configured at :443, and only rendered afterwards at :450).
  ---@param number integer the pull request number to name the buffer after
  ---@return integer bufnr the configured buffer
  local function configured_buffer(number)
    local bufnr = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(bufnr, ("octo://owner/name/pull/%d"):format(number))
    local buffer = OctoBuffer:new {
      bufnr = bufnr,
      number = number,
      repo = "owner/name",
      node = {},
      kind = "pull_request",
      commentsMetadata = {},
      threadsMetadata = {},
    }
    buffer:configure()
    return bufnr
  end

  -- An octo:// buffer is `buftype=acwrite` and is always modified by its own
  -- render, but it can never be written to a real path -- so a swap file for one
  -- is never recoverable work, and outlives an unclean exit only to raise E325
  -- the next time that URL is opened. The file panel (reviews/file-panel.lua) and
  -- the debug buffer (debug/buffer.lua) already refuse one.
  it("refuses a swap file, which could never be recovered to a path anyway", function()
    local bufnr = configured_buffer(906)
    local swapfile = vim.bo[bufnr].swapfile
    vim.api.nvim_buf_delete(bufnr, { force = true })
    eq(false, swapfile)
  end)

  it("allocates no swap on disk once the render modifies it", function()
    -- 'updatecount' of 0 disables swap files outright, which would make this pass
    -- for the wrong reason -- `nvim -l` sets exactly that. Pin it, so the
    -- assertion is about the buffer and not about the harness.
    local updatecount = vim.o.updatecount
    vim.o.updatecount = 200

    local bufnr = configured_buffer(907)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "# a title", "", "a body" })
    local swapname = vim.api.nvim_buf_call(bufnr, function()
      return vim.fn.swapname "%"
    end)

    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.o.updatecount = updatecount

    eq("", swapname)
  end)
end)
