---@diagnostic disable
local eq = assert.are.same

local pr_loading = require "octo.ui.pr-loading"
local config = require "octo.config"

describe("octo pr loading:", function()
  after_each(function()
    pr_loading.hide()
  end)

  it("defaults ui.pr_loading to on", function()
    eq(true, config.values.ui.pr_loading)
  end)

  it("names what is being opened, so the float says which one", function()
    eq("pwntester/octo.nvim #123", pr_loading.title("pwntester/octo.nvim", "pull", 123))
  end)

  it("names a release by its tag rather than a number", function()
    eq("pwntester/octo.nvim v1.2.0", pr_loading.title("pwntester/octo.nvim", "release", "v1.2.0"))
  end)

  it("names a repository without an id at all", function()
    eq("pwntester/octo.nvim", pr_loading.title("pwntester/octo.nvim", "repo", nil))
  end)

  it("returns two lines, neither wider than the width given", function()
    local lines = pr_loading.lines("pwntester/octo.nvim #123", "fetching", 1, 30)
    eq(2, #lines)
    for _, line in ipairs(lines) do
      eq(true, vim.fn.strdisplaywidth(line) <= 30)
    end
  end)

  it("truncates a long title rather than overflowing", function()
    local lines = pr_loading.lines(string.rep("x", 200), "fetching", 1, 20)
    eq(true, vim.fn.strdisplaywidth(lines[1]) <= 20)
  end)

  it("folds a newline out, which nvim_buf_set_lines would reject", function()
    local lines = pr_loading.lines("a\nb", "c\nd", 1, 40)
    for _, line in ipairs(lines) do
      eq(nil, line:find "\n")
    end
  end)

  it("opens nothing and reports closed before it is shown", function()
    eq(false, pr_loading.is_open())
    eq(nil, pr_loading.window())
  end)

  it("opens a non-focusable float that does not take the cursor", function()
    local before = vim.api.nvim_get_current_win()

    pr_loading.show("pwntester/octo.nvim", "pull", 123)

    eq(true, pr_loading.is_open())
    eq(before, vim.api.nvim_get_current_win())
    eq(false, vim.api.nvim_win_get_config(pr_loading.window()).focusable)
  end)

  it("showing twice reuses the one window rather than stacking floats", function()
    pr_loading.show("pwntester/octo.nvim", "pull", 123)
    local first = pr_loading.window()
    pr_loading.show("pwntester/octo.nvim", "pull", 456)

    eq(first, pr_loading.window())
  end)

  it("closes the window and deletes its buffer on hide", function()
    pr_loading.show("pwntester/octo.nvim", "pull", 123)
    local win, buf = pr_loading.window(), pr_loading.buffer()

    pr_loading.hide()

    eq(false, vim.api.nvim_win_is_valid(win))
    eq(false, vim.api.nvim_buf_is_valid(buf))
    eq(false, pr_loading.is_open())
  end)

  it("hiding when nothing is shown is harmless", function()
    eq(true, pcall(pr_loading.hide))
    eq(true, pcall(pr_loading.hide))
  end)

  it("tears itself down when its window is closed behind its back", function()
    pr_loading.show("pwntester/octo.nvim", "pull", 123)
    local win = pr_loading.window()

    vim.api.nvim_win_close(win, true)

    eq(false, pr_loading.is_open())
  end)

  it("shows nothing at all when the option is off", function()
    local original = config.values.ui.pr_loading
    config.values.ui.pr_loading = false

    pr_loading.show("pwntester/octo.nvim", "pull", 123)
    local open = pr_loading.is_open()

    config.values.ui.pr_loading = original
    eq(false, open)
  end)
end)
