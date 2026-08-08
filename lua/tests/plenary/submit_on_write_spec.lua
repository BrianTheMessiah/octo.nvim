---@diagnostic disable
local config = require "octo.config"
local eq = assert.are.same

describe("submit_on_write:", function()
  local octo = require "octo"
  local commands = require "octo.commands"
  local original_save
  local original_flag
  local saves

  before_each(function()
    saves = 0
    original_save = octo.save_buffer
    octo.save_buffer = function()
      saves = saves + 1
    end
    original_flag = config.values.submit_on_write
  end)

  after_each(function()
    octo.save_buffer = original_save
    config.values.submit_on_write = original_flag
  end)

  it("does not publish on write when submit_on_write is false", function()
    config.values.submit_on_write = false

    require("octo.autocmds").on_buf_write_cmd()

    eq(0, saves)
  end)

  it("publishes on write when submit_on_write is true", function()
    config.values.submit_on_write = true

    require("octo.autocmds").on_buf_write_cmd()

    eq(1, saves)
  end)

  it("leaves the buffer modified when a write does not publish", function()
    config.values.submit_on_write = false
    local bufnr = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "edited" })
    vim.bo[bufnr].modified = true

    vim.api.nvim_buf_call(bufnr, function()
      require("octo.autocmds").on_buf_write_cmd()
    end)

    eq(true, vim.bo[bufnr].modified)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it("publishes through commands.submit regardless of the flag", function()
    config.values.submit_on_write = false

    commands.submit()

    eq(1, saves)
  end)

  it("still publishes through commands.submit when writes also publish", function()
    config.values.submit_on_write = true

    commands.submit()

    eq(1, saves)
  end)
end)
