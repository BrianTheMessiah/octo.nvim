---@diagnostic disable
local eq = assert.are.same

local config = require "octo.config"
local preview_cache = require "octo.pickers.fzf-lua.preview_cache"
local warmer = require "octo.pickers.fzf-lua.preview_warmer"

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

---One picker entry.
---@param number integer the issue or pull request number
---@param repo? string the repository it belongs to
---@return table entry shaped as the pickers build them
local function entry(number, repo)
  return { kind = "pull_request", repo = repo or "o/n", value = number }
end

---A fetch that records what it was asked for and answers on demand.
---@return table harness with `fetch`, `answer`, `asked` and `pending`
local function fetches()
  local self = { asked = {}, waiting = {} }

  ---@param e table the entry being warmed
  ---@param done fun(payload: table?, remaining: integer?)
  function self.fetch(e, done)
    table.insert(self.asked, e.value)
    table.insert(self.waiting, done)
  end

  ---Answer the oldest outstanding request.
  ---@param payload table? the payload to answer with, nil to fail the request
  ---@param remaining integer? rate limit points to report
  ---@return boolean answered false when nothing was outstanding
  function self.answer(payload, remaining)
    local next_done = table.remove(self.waiting, 1)
    if not next_done then
      return false
    end
    next_done(payload, remaining)
    return true
  end

  ---Answer every outstanding request, including any started as a result.
  ---@param payload table? the payload to answer each with
  function self.drain(payload)
    while self.answer(payload) do
    end
  end

  return self
end

---Build a warmer over a fixed list of entries.
---@param list table[] the entries the picker has loaded
---@param harness table the fetch harness to drive it with
---@return octo.PreviewWarmer, octo.PreviewCache
local function build(list, harness)
  local cache = preview_cache.new()
  return warmer.new {
    cache = cache,
    entries = function()
      return list
    end,
    fetch = harness.fetch,
  },
    cache
end

describe("octo preview warmer:", function()
  it("enqueues every loaded entry once", function()
    local h = fetches()
    local w = build({ entry(1), entry(2), entry(3) }, h)

    eq(3, w:warm())
    h.drain { body = "x" }
    eq({ 1, 2, 3 }, h.asked)
    eq({ 3, 3 }, { select(1, w:progress()), select(2, w:progress()) })
  end)

  it("enqueues nothing a second time when the list has not grown", function()
    local h = fetches()
    local w = build({ entry(1), entry(2) }, h)

    eq(2, w:warm())
    eq(0, w:warm())
    eq(0, w:warm())
    h.drain { body = "x" }
    eq({ 1, 2 }, h.asked)
  end)

  it("picks up entries that arrive after the first warm, as a streaming list grows", function()
    local h = fetches()
    local list = { entry(1) }
    local cache = preview_cache.new()
    local w = warmer.new {
      cache = cache,
      entries = function()
        return list
      end,
      fetch = h.fetch,
    }

    eq(1, w:warm())
    list[#list + 1] = entry(2)
    list[#list + 1] = entry(3)
    eq(2, w:warm())
    h.drain { body = "x" }
    eq({ 1, 2, 3 }, h.asked)
    eq(3, select(2, w:progress()))
  end)

  it("treats the same item in two repositories as two entries", function()
    local h = fetches()
    local w = build({ entry(7, "o/a"), entry(7, "o/b") }, h)

    eq(2, w:warm())
    h.drain { body = "x" }
    eq(2, #h.asked)
  end)

  it("releases the slot for a request that fails, so the rest of the list still runs", function()
    with_config("preview_prefetch_concurrency", 1, function()
      local h = fetches()
      local w = build({ entry(1), entry(2), entry(3) }, h)
      w:warm()

      eq({ 1 }, h.asked)
      h.answer(nil)
      eq({ 1, 2 }, h.asked)
      h.answer(nil)
      eq({ 1, 2, 3 }, h.asked)
      h.answer(nil)
      eq(3, select(1, w:progress()))
    end)
  end)

  it("caches a payload that arrives, and asks for nothing already cached", function()
    local h = fetches()
    local w, cache = build({ entry(1) }, h)
    w:warm()
    h.answer { body = "one" }

    eq({ body = "one" }, cache:get(preview_cache.key("pull_request", "o/n", 1)))

    local h2 = fetches()
    local w2 = warmer.new {
      cache = cache,
      entries = function()
        return { entry(1) }
      end,
      fetch = h2.fetch,
    }
    eq(1, w2:warm())
    eq({}, h2.asked)
    eq(1, select(1, w2:progress()))
  end)

  it("honours the concurrency cap over the whole list", function()
    with_config("preview_prefetch_concurrency", 2, function()
      local h = fetches()
      local list = {}
      for i = 1, 9 do
        list[i] = entry(i)
      end
      local w = build(list, h)
      w:warm()

      eq(2, #h.asked)
      h.answer { body = "x" }
      eq(3, #h.asked)
      h.drain { body = "x" }
      eq(9, #h.asked)
    end)
  end)

  it("stops warming when the rate limit reading reaches the reserve", function()
    with_config("preview_prefetch_concurrency", 1, function()
      with_config("preview_rate_limit_reserve", 400, function()
        local h = fetches()
        local list = {}
        for i = 1, 6 do
          list[i] = entry(i)
        end
        local w = build(list, h)
        w:warm()

        eq(1, #h.asked)
        h.answer({ body = "x" }, 399)
        h.drain { body = "x" }
        eq(1, #h.asked)
      end)
    end)
  end)

  it("starts nothing once stopped, even for entries that arrive afterwards", function()
    with_config("preview_prefetch_concurrency", 1, function()
      local h = fetches()
      local list = { entry(1), entry(2), entry(3) }
      local w = warmer.new {
        cache = preview_cache.new(),
        entries = function()
          return list
        end,
        fetch = h.fetch,
      }
      w:warm()
      eq(1, #h.asked)

      w:stop()
      h.drain { body = "x" }
      list[#list + 1] = entry(4)
      list[#list + 1] = entry(5)

      eq(0, w:warm())
      eq(1, #h.asked)
    end)
  end)

  it("does nothing at all when full prefetch is off", function()
    with_config("preview_prefetch_all", false, function()
      local h = fetches()
      local w = build({ entry(1), entry(2) }, h)

      eq(0, w:warm())
      eq({}, h.asked)
      eq({ 0, 0 }, { select(1, w:progress()), select(2, w:progress()) })
    end)
  end)

  it("reports no progress before it has been asked to warm anything", function()
    local h = fetches()
    local w = build({ entry(1) }, h)
    eq({ 0, 0 }, { select(1, w:progress()), select(2, w:progress()) })
  end)

  it("reports no progress once stopped, so a closed picker's display is left alone", function()
    with_config("preview_prefetch_concurrency", 4, function()
      local h = fetches()
      local seen = {}
      local list = {}
      for i = 1, 10 do
        list[i] = entry(i)
      end
      local w = warmer.new {
        cache = preview_cache.new(),
        entries = function()
          return list
        end,
        fetch = h.fetch,
        on_progress = function(completed, total)
          table.insert(seen, { completed, total })
        end,
      }
      w:warm()
      h.answer { body = "x" }
      eq(1, #seen)

      w:stop()
      h.drain { body = "x" }
      eq(1, #seen)
    end)
  end)

  it("survives a stop while requests are still in flight", function()
    with_config("preview_prefetch_concurrency", 3, function()
      local h = fetches()
      local list = {}
      for i = 1, 8 do
        list[i] = entry(i)
      end
      local w = build(list, h)
      w:warm()
      eq(3, #h.asked)

      w:stop()
      h.drain { body = "x" }
      eq(3, #h.asked)
      eq(3, select(1, w:progress()))
    end)
  end)
end)
