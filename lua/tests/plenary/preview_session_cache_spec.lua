---@diagnostic disable
local eq = assert.are.same

local preview_cache = require "octo.pickers.fzf-lua.preview_cache"
local session_cache = require "octo.pickers.fzf-lua.preview_session_cache"

describe("octo preview session cache:", function()
  after_each(function() session_cache.reset() end)

  it("hands back the same cache instance on every call", function()
    local first = session_cache.get()
    local second = session_cache.get()
    assert(first == second, "expected the same cache instance both times")
  end)

  it("keeps a payload stored by one caller visible to the next", function()
    local key = preview_cache.key("pull_request", "o/n", 1)
    session_cache.get():store(key, { title = "PR 1" })
    eq({ title = "PR 1" }, session_cache.get():get(key))
  end)

  it("starts empty again once reset, for the next test to build on", function()
    local key = preview_cache.key("pull_request", "o/n", 1)
    session_cache.get():store(key, { title = "PR 1" })
    session_cache.reset()
    eq(nil, session_cache.get():get(key))
  end)
end)
