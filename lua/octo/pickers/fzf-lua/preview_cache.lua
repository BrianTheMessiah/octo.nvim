---A payload store for picker previews, shared by the on-demand and prefetch paths.
---
---Every value the cache holds is plain Lua data. A fetch that completes writes to
---this table and nothing else, so a prefetch landing after the picker closed, or
---after the cursor moved on, touches no buffer and no window.
local M = {}

---@class octo.PreviewCache
---@field private payloads table<string, any> decoded preview payload per key
---@field private order string[] insertion order of `payloads`, oldest first
---@field private waiters table<string, fun(payload: any)[]> paint callbacks per in-flight key
---@field private limit integer greatest number of payloads to retain
local Cache = {}
Cache.__index = Cache

---Build an empty preview cache.
---@param limit? integer greatest number of payloads to retain, default 64
---@return octo.PreviewCache
function M.new(limit)
  return setmetatable({ payloads = {}, order = {}, waiters = {}, limit = limit or 64 }, Cache)
end

---Cache key for one previewable item.
---@param kind string octo entry kind, e.g. "issue" or "pull_request"
---@param repo string "owner/name" the item belongs to
---@param number string|integer the issue or pull request number
---@return string key stable across pickers and across picker invocations
function M.key(kind, repo, number)
  return string.format("%s:%s:%s", kind, repo, number)
end

---Drop the oldest payloads until the cache is within its limit.
---@param self octo.PreviewCache
local function evict_overflow(self)
  while #self.order > self.limit do
    local oldest = table.remove(self.order, 1)
    self.payloads[oldest] = nil
  end
end

---The payload for a key, if one has already been fetched.
---@param key string key from `M.key`
---@return any? payload nil when the key has never completed a fetch
function Cache:get(key)
  return self.payloads[key]
end

---Whether a fetch for this key is already running.
---@param key string key from `M.key`
---@return boolean
function Cache:is_inflight(key)
  return self.waiters[key] ~= nil
end

---Store a payload, evicting the oldest entries past the cache limit.
---@param key string key from `M.key`
---@param payload any decoded preview payload
function Cache:store(key, payload)
  if self.payloads[key] == nil then
    table.insert(self.order, key)
  end
  self.payloads[key] = payload
  evict_overflow(self)
end

---Hand a completed payload to everyone waiting on it and clear the waiter list.
---@param self octo.PreviewCache
---@param key string key from `M.key`
---@param payload any decoded preview payload
local function flush_waiters(self, key, payload)
  local waiting = self.waiters[key]
  self.waiters[key] = nil
  if not waiting then
    return
  end
  for _, waiter in ipairs(waiting) do
    waiter(payload)
  end
end

---Ask for a payload, fetching it only if no fetch for that key has run or is running.
---
---`on_ready` is called with the payload: at once when the payload is already
---cached, or when the in-flight fetch completes. Pass nil to warm the cache
---without registering any callback, which is what prefetching does.
---@param key string key from `M.key`
---@param fetch fun(done: fun(payload: any?)) starts the request; calls `done` with the payload, or nil on failure
---@param on_ready? fun(payload: any) receives the payload; must guard its own target's liveness
---@return "cached"|"pending"|"started" how the request was satisfied
function Cache:request(key, fetch, on_ready)
  local payload = self.payloads[key]
  if payload ~= nil then
    if on_ready then
      on_ready(payload)
    end
    return "cached"
  end

  if self.waiters[key] then
    if on_ready then
      table.insert(self.waiters[key], on_ready)
    end
    return "pending"
  end

  self.waiters[key] = on_ready and { on_ready } or {}
  fetch(function(fetched)
    if fetched == nil then
      self.waiters[key] = nil
      return
    end
    self:store(key, fetched)
    flush_waiters(self, key, fetched)
  end)
  return "started"
end

---Forget every registered paint callback, leaving payloads in place.
---
---Called when the picker closes. In-flight fetches cannot be cancelled, because
---`octo.gh` returns no job handle for an async request, so instead their
---completions are made inert: they store a payload and find nobody to notify.
function Cache:abandon()
  self.waiters = {}
end

M.Cache = Cache

return M
