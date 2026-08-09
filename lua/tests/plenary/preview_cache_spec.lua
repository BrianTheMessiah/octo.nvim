---@diagnostic disable
local eq = assert.are.same

local preview_cache = require "octo.pickers.fzf-lua.preview_cache"

---A fetch function that records its calls and completes only when told to.
---@return table harness with `fetch`, `calls` and `resolve(index, payload)`
local function deferred_fetch()
  local harness = { calls = 0, dones = {} }
  harness.fetch = function(done)
    harness.calls = harness.calls + 1
    table.insert(harness.dones, done)
  end
  harness.resolve = function(index, payload)
    harness.dones[index](payload)
  end
  return harness
end

describe("octo preview cache:", function()
  it("keys a payload by kind, repo and number so revisits hit", function()
    eq("pull_request:fii-org/service.core:906", preview_cache.key("pull_request", "fii-org/service.core", 906))
    eq("issue:fii-org/service.core:906", preview_cache.key("issue", "fii-org/service.core", 906))
    assert.are_not.same(
      preview_cache.key("pull_request", "a/b", 1),
      preview_cache.key("pull_request", "c/d", 1)
    )
  end)

  it("treats a number and its string form as the same entry", function()
    eq(preview_cache.key("issue", "a/b", 12), preview_cache.key("issue", "a/b", "12"))
  end)

  it("fetches once for a key and serves every later request from memory", function()
    local cache = preview_cache.new()
    local fetcher = deferred_fetch()

    eq("started", cache:request("k", fetcher.fetch))
    fetcher.resolve(1, { title = "one" })

    local seen
    eq("cached", cache:request("k", fetcher.fetch, function(payload)
      seen = payload
    end))
    eq(1, fetcher.calls)
    eq({ title = "one" }, seen)
  end)

  it("collapses concurrent requests for one key into a single fetch", function()
    local cache = preview_cache.new()
    local fetcher = deferred_fetch()
    local delivered = {}

    eq("started", cache:request("k", fetcher.fetch, function(p)
      table.insert(delivered, p)
    end))
    eq("pending", cache:request("k", fetcher.fetch, function(p)
      table.insert(delivered, p)
    end))

    eq(1, fetcher.calls)
    fetcher.resolve(1, { title = "one" })
    eq({ { title = "one" }, { title = "one" } }, delivered)
  end)

  it("reports an in-flight key so a prefetch does not duplicate it", function()
    local cache = preview_cache.new()
    local fetcher = deferred_fetch()

    eq(false, cache:is_inflight("k"))
    cache:request("k", fetcher.fetch)
    eq(true, cache:is_inflight("k"))
    fetcher.resolve(1, { title = "one" })
    eq(false, cache:is_inflight("k"))
  end)

  it("delivers a prefetched payload to the request that arrives while it is in flight", function()
    local cache = preview_cache.new()
    local fetcher = deferred_fetch()
    local painted

    cache:request("k", fetcher.fetch)
    eq("pending", cache:request("k", fetcher.fetch, function(payload)
      painted = payload
    end))
    fetcher.resolve(1, { title = "warm" })

    eq(1, fetcher.calls)
    eq({ title = "warm" }, painted)
  end)

  it("caches nothing and retries after a failed fetch", function()
    local cache = preview_cache.new()
    local fetcher = deferred_fetch()
    local called = false

    cache:request("k", fetcher.fetch, function()
      called = true
    end)
    fetcher.resolve(1, nil)

    eq(false, called)
    eq(nil, cache:get "k")
    eq(false, cache:is_inflight "k")
    eq("started", cache:request("k", fetcher.fetch))
    eq(2, fetcher.calls)
  end)

  it("abandons waiters so a fetch landing after the picker closed paints nothing", function()
    local cache = preview_cache.new()
    local fetcher = deferred_fetch()
    local painted = false

    cache:request("k", fetcher.fetch, function()
      painted = true
    end)
    cache:abandon()
    fetcher.resolve(1, { title = "late" })

    eq(false, painted)
    eq({ title = "late" }, cache:get "k")
  end)

  it("evicts the oldest payloads once the limit is passed", function()
    local cache = preview_cache.new(2)
    for _, key in ipairs { "a", "b", "c" } do
      local fetcher = deferred_fetch()
      cache:request(key, fetcher.fetch)
      fetcher.resolve(1, { title = key })
    end

    eq(nil, cache:get "a")
    eq({ title = "b" }, cache:get "b")
    eq({ title = "c" }, cache:get "c")
  end)

  it("keeps a re-stored key in place rather than growing the eviction list", function()
    local cache = preview_cache.new(2)
    cache:store("a", { title = "first" })
    cache:store("a", { title = "second" })
    cache:store("b", { title = "b" })

    eq({ title = "second" }, cache:get "a")
    eq({ title = "b" }, cache:get "b")
  end)
end)
