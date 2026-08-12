---@diagnostic disable
local eq = assert.are.same

local mappings = require "octo.mappings"
local config = require "octo.config"

---An `octo://` buffer standing in for a real one: the name is what marks it octo's.
---@param name string the octo:// url
---@return integer bufnr
local function octo_buffer(name)
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(bufnr, name)
  vim.bo[bufnr].filetype = "octo"
  return bufnr
end

describe("octo close buffer:", function()
  it("binds a key to leave a pull request buffer", function()
    eq("<C-c>", config.values.mappings.pull_request.close_buffer.lhs)
  end)

  it("binds the same key on every buffer kind a reader can land in", function()
    for _, kind in ipairs { "pull_request", "issue", "discussion", "repo", "release" } do
      local mapping = config.values.mappings[kind].close_buffer
      assert.is_truthy(mapping, ("no close_buffer for %s"):format(kind))
      eq("<C-c>", mapping.lhs)
    end
  end)

  it("returns to the buffer the reader came from", function()
    vim.cmd "enew"
    local origin = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_name(origin, "/tmp/origin_file.lua")

    local bufnr = octo_buffer "octo://pwntester/octo.nvim/pull/1"
    vim.api.nvim_set_current_buf(bufnr)

    mappings.close_buffer()

    eq(origin, vim.api.nvim_get_current_buf())
    eq(false, vim.api.nvim_buf_is_valid(bufnr))
  end)

  it("wipes the octo buffer rather than leaving it in the buffer list", function()
    vim.cmd "enew"
    local bufnr = octo_buffer "octo://pwntester/octo.nvim/pull/2"
    vim.api.nvim_set_current_buf(bufnr)

    mappings.close_buffer()

    eq(false, vim.api.nvim_buf_is_valid(bufnr))
  end)

  it("closes the tabpage when the octo buffer is the only thing in it", function()
    local before = #vim.api.nvim_list_tabpages()
    vim.cmd "tabnew"
    local bufnr = octo_buffer "octo://pwntester/octo.nvim/pull/3"
    vim.api.nvim_set_current_buf(bufnr)

    mappings.close_buffer()

    eq(before, #vim.api.nvim_list_tabpages())
  end)

  it("leaves the other windows of a split alone, closing only its own", function()
    vim.cmd "tabnew"
    vim.cmd "split"
    local windows = #vim.api.nvim_tabpage_list_wins(0)
    local bufnr = octo_buffer "octo://pwntester/octo.nvim/pull/4"
    vim.api.nvim_set_current_buf(bufnr)

    mappings.close_buffer()

    eq(windows - 1, #vim.api.nvim_tabpage_list_wins(0))
    vim.cmd "tabclose"
  end)

  it("raises nothing when it is the last window of the last tabpage", function()
    vim.cmd "tabonly"
    vim.cmd "only"
    local bufnr = octo_buffer "octo://pwntester/octo.nvim/pull/5"
    vim.api.nvim_set_current_buf(bufnr)

    eq(true, pcall(mappings.close_buffer))
    -- nvim is still up, and is no longer showing the octo buffer
    eq(false, vim.api.nvim_get_current_buf() == bufnr)
  end)

  it("does nothing to a buffer that is not octo's", function()
    vim.cmd "enew"
    local plain = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_name(plain, "/tmp/not_octo.lua")

    mappings.close_buffer()

    eq(plain, vim.api.nvim_get_current_buf())
    eq(true, vim.api.nvim_buf_is_valid(plain))
  end)
end)
