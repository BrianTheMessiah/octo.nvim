---@diagnostic disable
local eq = assert.are.same

local config = require "octo.config"
local prefetch = require "octo.pickers.fzf-lua.preview_prefetch"

local ORDER = { "a", "b", "c", "d", "e", "f" }

---Run a function with `picker_config.preview_prefetch` temporarily set.
---@param value any the value to install for the duration of the call
---@param fn fun() body to run under that setting
local function with_prefetch(value, fn)
  local previous = config.values.picker_config.preview_prefetch
  config.values.picker_config.preview_prefetch = value
  local ok, err = pcall(fn)
  config.values.picker_config.preview_prefetch = previous
  assert(ok, err)
end

describe("octo preview prefetch:", function()
  it("defaults picker_config.preview_prefetch to a small window", function()
    local default = config.get_default_values().picker_config.preview_prefetch
    eq("number", type(default))
    assert.is_true(default > 0 and default <= 10, "expected a small window, got " .. tostring(default))
  end)

  it("reads the window size from config and never returns a negative one", function()
    with_prefetch(3, function()
      eq(3, prefetch.window())
    end)
    with_prefetch(0, function()
      eq(0, prefetch.window())
    end)
    with_prefetch(-4, function()
      eq(0, prefetch.window())
    end)
    with_prefetch(nil, function()
      eq(0, prefetch.window())
    end)
  end)

  it("warms the entries after the cursor when travelling down", function()
    eq({ "c", "d" }, prefetch.targets(ORDER, 2, 1, 2))
  end)

  it("warms the entries before the cursor when travelling up", function()
    eq({ "d", "c" }, prefetch.targets(ORDER, 5, 6, 2))
  end)

  it("travels down on the first preview, when there is no previous position", function()
    eq({ "b", "c" }, prefetch.targets(ORDER, 1, nil, 2))
  end)

  it("stops at the end of the list instead of returning holes", function()
    eq({ "f" }, prefetch.targets(ORDER, 5, 4, 3))
    eq({}, prefetch.targets(ORDER, 6, 5, 3))
    eq({}, prefetch.targets(ORDER, 1, 2, 3))
  end)

  it("returns nothing for a zero window", function()
    eq({}, prefetch.targets(ORDER, 3, 2, 0))
  end)

  it("maps every entry string to its position", function()
    eq({ a = 1, b = 2, c = 3, d = 4, e = 5, f = 6 }, prefetch.positions_of(ORDER))
    eq({}, prefetch.positions_of {})
  end)
end)
