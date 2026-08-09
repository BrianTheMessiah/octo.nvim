---@diagnostic disable
local eq = assert.are.same

local config = require "octo.config"
local loading = require "octo.ui.loading"

---Run a function with a `picker_config` key temporarily set.
---@param key string key under `picker_config`
---@param value any the value to install for the duration of the call
---@param fn fun() body to run under that setting
local function with_config(key, value, fn)
  local previous = config.values.picker_config[key]
  config.values.picker_config[key] = value
  local ok, err = pcall(fn)
  config.values.picker_config[key] = previous
  assert(ok, err)
end

---How many autocmds the module's own group holds.
---@return integer
local function autocmd_count()
  local ok, found = pcall(vim.api.nvim_get_autocmds, { group = "OctoPreviewLoading" })
  return ok and #found or 0
end

describe("octo preview loading:", function()
  after_each(function()
    loading.hide()
  end)

  it("defaults picker_config.preview_loading to on", function()
    eq(true, config.get_default_values().picker_config.preview_loading)
  end)

  it("has spinner frames that are all non-empty", function()
    assert.is_true(#loading.FRAMES > 1, "expected more than one frame")
    for index, frame in ipairs(loading.FRAMES) do
      assert.is_true(frame ~= "" and frame ~= nil, "frame " .. index .. " is empty")
      eq(1, vim.fn.strdisplaywidth(frame))
    end
  end)

  it("advances through the frames and wraps round", function()
    eq(loading.FRAMES[1], loading.frame_at(1))
    eq(loading.FRAMES[2], loading.frame_at(2))
    eq(loading.FRAMES[1], loading.frame_at(#loading.FRAMES + 1))
  end)

  it("indexes no frame off the end for a zero or negative tick", function()
    for _, tick in ipairs { 0, -1, -7, -#loading.FRAMES } do
      local frame = loading.frame_at(tick)
      assert.is_true(frame ~= nil and frame ~= "", "tick " .. tick .. " gave no frame")
    end
  end)

  it("says how many previews are warm out of how many", function()
    local message = loading.message(12, 50)
    assert.is_true(message:find "12" ~= nil, message)
    assert.is_true(message:find "50" ~= nil, message)
  end)

  it("returns exactly one line, never wider than the width given", function()
    for _, width in ipairs { 10, 24, 40, 80 } do
      local lines = loading.lines(loading.message(3, 40), 1, width)
      eq(1, #lines)
      assert.is_true(
        vim.fn.strdisplaywidth(lines[1]) <= width,
        string.format("width %d gave %d columns: %q", width, vim.fn.strdisplaywidth(lines[1]), lines[1])
      )
    end
  end)

  it("truncates a long message with an ellipsis rather than overflowing", function()
    local long = string.rep("warming previews ", 20)
    local line = loading.lines(long, 1, 30)[1]
    assert.is_true(vim.fn.strdisplaywidth(line) <= 30, line)
    assert.is_true(line:find "…" ~= nil, "expected an ellipsis, got " .. line)
  end)

  it("folds a newline out of the message, which nvim_buf_set_lines would reject", function()
    local line = loading.lines("warming\npreviews\rnow", 1, 60)[1]
    eq(nil, line:find "\n")
    eq(nil, line:find "\r")
  end)

  it("never returns an empty line even at an impossible width", function()
    for _, width in ipairs { 0, 1, 2 } do
      eq(1, #loading.lines("anything", 1, width))
    end
  end)

  it("opens nothing and reports closed before it is shown", function()
    eq(false, loading.is_open())
  end)

  it("opens a single-line, non-focusable float that does not take the cursor", function()
    local before = vim.api.nvim_get_current_win()
    loading.show(0, 50)

    eq(true, loading.is_open())
    eq(before, vim.api.nvim_get_current_win())
    local cfg = vim.api.nvim_win_get_config(loading.window())
    eq(1, cfg.height)
    eq(false, cfg.focusable)
    assert.is_true(cfg.zindex > 52, "must sit above the fzf picker, got " .. tostring(cfg.zindex))
  end)

  it("showing twice reuses the one window rather than stacking floats", function()
    loading.show(0, 50)
    local first = loading.window()
    loading.show(10, 50)

    eq(first, loading.window())
    eq(true, loading.is_open())
  end)

  it("closes the window and deletes its buffer on hide", function()
    loading.show(0, 50)
    local win, buf = loading.window(), loading.buffer()

    loading.hide()
    eq(false, loading.is_open())
    eq(false, vim.api.nvim_win_is_valid(win))
    eq(false, vim.api.nvim_buf_is_valid(buf))
  end)

  it("hiding when nothing is shown is harmless", function()
    loading.hide()
    loading.hide()
    eq(false, loading.is_open())
  end)

  it("leaves no autocmd behind once hidden", function()
    loading.show(0, 50)
    assert.is_true(autocmd_count() > 0, "expected a teardown autocmd while shown")

    loading.hide()
    eq(0, autocmd_count())
  end)

  it("tears itself down when its window is closed behind its back", function()
    loading.show(0, 50)
    local buf = loading.buffer()
    vim.api.nvim_win_close(loading.window(), true)

    eq(false, loading.is_open())
    eq(false, vim.api.nvim_buf_is_valid(buf))
    eq(0, autocmd_count())
  end)

  it("stays open while previews are still being warmed", function()
    loading.update(3, 50)
    eq(true, loading.is_open())
  end)

  it("takes itself down once every preview is warm", function()
    loading.update(3, 50)
    eq(true, loading.is_open())

    loading.update(50, 50)
    eq(false, loading.is_open())
  end)

  it("shows nothing for a list with nothing to warm", function()
    loading.update(0, 0)
    eq(false, loading.is_open())
  end)

  it("shows nothing at all when the option is off", function()
    with_config("preview_loading", false, function()
      loading.update(1, 50)
      eq(false, loading.is_open())
      loading.show(1, 50)
      eq(false, loading.is_open())
    end)
  end)

  it("writes the current count into the buffer as it advances", function()
    loading.update(7, 50)
    local text = table.concat(vim.api.nvim_buf_get_lines(loading.buffer(), 0, -1, false), "")
    assert.is_true(text:find "7" ~= nil, text)
    assert.is_true(text:find "50" ~= nil, text)

    loading.update(8, 50)
    local next_text = table.concat(vim.api.nvim_buf_get_lines(loading.buffer(), 0, -1, false), "")
    assert.is_true(next_text:find "8" ~= nil, next_text)
  end)

  it("keeps its buffer unmodifiable between writes", function()
    loading.update(2, 50)
    eq(false, vim.bo[loading.buffer()].modifiable)
  end)

  it("abandons cleanly for a warm that never started", function()
    loading.show(0, 50)
    loading.abandon()
    eq(false, loading.is_open())
    eq(0, autocmd_count())
  end)
end)
