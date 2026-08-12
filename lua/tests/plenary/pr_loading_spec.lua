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

  ----------------------------------------------------------------------------
  -- what the review needs: its own wording, and a float that survives the
  -- `tab split` in `Layout:open`
  ----------------------------------------------------------------------------

  it("says 'fetching' when no message is given, so the buffer path is unchanged", function()
    pr_loading.show("pwntester/octo.nvim", "pull", 123)
    local text = table.concat(vim.api.nvim_buf_get_lines(pr_loading.buffer(), 0, -1, false), "\n")

    eq(true, text:find("fetching", 1, true) ~= nil)
  end)

  it("carries a message given to it, so a review can say what it is waiting on", function()
    pr_loading.show("pwntester/octo.nvim", "pull", 123, "loading changed files")
    local text = table.concat(vim.api.nvim_buf_get_lines(pr_loading.buffer(), 0, -1, false), "\n")

    eq(true, text:find("loading changed files", 1, true) ~= nil)
  end)

  it("replaces the message on a second show without reopening the float", function()
    pr_loading.show("pwntester/octo.nvim", "pull", 123, "starting review")
    local first = pr_loading.window()

    pr_loading.show("pwntester/octo.nvim", "pull", 123, "loading changed files")
    local text = table.concat(vim.api.nvim_buf_get_lines(pr_loading.buffer(), 0, -1, false), "\n")

    eq(first, pr_loading.window())
    eq(true, text:find("loading changed files", 1, true) ~= nil)
    eq(false, text:find("starting review", 1, true) ~= nil)
  end)

  it("is not open once a tab split has left it in the previous tabpage", function()
    -- `Layout:open` runs `tab split`. A float belongs to the tabpage it was created in, so
    -- without this the float is stranded where the reader can no longer see it while
    -- `is_open` still answers true -- and `show` would then update an invisible window.
    pr_loading.show("pwntester/octo.nvim", "pull", 123, "starting review")
    local before = pr_loading.window()

    vim.cmd "tab split"

    eq(true, vim.api.nvim_win_is_valid(before))
    eq(false, pr_loading.is_open())

    vim.cmd "tabclose"
  end)

  it("reopens in the tabpage the reader is now in", function()
    pr_loading.show("pwntester/octo.nvim", "pull", 123, "starting review")
    vim.cmd "tab split"

    pr_loading.show("pwntester/octo.nvim", "pull", 123, "loading changed files")

    eq(true, pr_loading.is_open())
    eq(vim.api.nvim_get_current_tabpage(), vim.api.nvim_win_get_tabpage(pr_loading.window()))

    pr_loading.hide()
    vim.cmd "tabclose"
  end)
end)
