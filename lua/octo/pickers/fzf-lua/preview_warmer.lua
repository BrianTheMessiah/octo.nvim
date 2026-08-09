---Keeps a whole picker list's previews warm, a bounded number of fetches at a time.
---
---Separate from the previewer so the two things that can go quietly wrong here are
---testable without a picker: enqueueing an entry twice as a streaming list grows, and
---failing to release a concurrency slot when a request ends badly.
---
---Nothing here touches a buffer or a window. Warming writes to the cache only, so a
---request that lands after the picker closed remains inert.
local preview_cache = require "octo.pickers.fzf-lua.preview_cache"
local preview_throttle = require "octo.pickers.fzf-lua.preview_throttle"

local M = {}

---@class octo.PreviewWarmer
---@field private cache octo.PreviewCache cache warmed payloads land in
---@field private entries fun(): table[] the picker entries loaded so far
---@field private fetch fun(entry: table, done: fun(payload: table?, remaining: integer?)) starts one request
---@field private runner octo.PreviewThrottle? built on first use
---@field private pushed table<string, boolean> cache keys already enqueued
---@field private on_progress? fun(completed: integer, total: integer)
local Warmer = {}
Warmer.__index = Warmer

---Build a warmer for one picker.
---@param opts { cache: octo.PreviewCache, entries: fun(): table[], fetch: fun(entry: table, done: fun(payload: table?, remaining: integer?)), on_progress?: fun(completed: integer, total: integer) }
---@return octo.PreviewWarmer
function M.new(opts)
  return setmetatable({
    cache = opts.cache,
    entries = opts.entries,
    fetch = opts.fetch,
    pushed = {},
    on_progress = opts.on_progress,
  }, Warmer)
end

---Warm one entry, releasing its concurrency slot however the request ends.
---
---The slot is released from the fetch callback rather than from a cache waiter,
---because a fetch that fails clears its waiters without calling them: a waiter would
---leave the slot taken and the count short for the rest of the picker's life.
---@param self octo.PreviewWarmer
---@param entry table the formatted picker entry to warm
---@param done fun() called once, when the request no longer occupies a slot
local function warm_one(self, entry, done)
  local key = preview_cache.key(entry.kind, entry.repo, entry.value)
  local status = self.cache:request(key, function(store)
    self.fetch(entry, function(payload, remaining)
      self.runner:note_remaining(remaining)
      store(payload)
      done()
    end)
  end)
  if status ~= "started" then
    done()
  end
end

---Enqueue every loaded entry that is not already enqueued.
---
---Called on every paint rather than once, because a streaming picker holds only part
---of its list when the first preview is painted. Each entry is enqueued once, so a
---repeat call costs one table lookup per entry already known.
---@return integer added how many entries this call enqueued
function Warmer:warm()
  if not preview_throttle.prefetch_all() then
    return 0
  end
  self.runner = self.runner or preview_throttle.new { on_progress = self.on_progress }
  if self.runner:is_stopped() then
    return 0
  end

  local added = 0
  for _, entry in ipairs(self.entries()) do
    local key = preview_cache.key(entry.kind, entry.repo, entry.value)
    if not self.pushed[key] then
      self.pushed[key] = true
      added = added + 1
      self.runner:push(function(done)
        warm_one(self, entry, done)
      end)
    end
  end
  return added
end

---Give up warming and drop everything not yet started.
function Warmer:stop()
  if self.runner then
    self.runner:stop()
  end
end

---How far the warming has got.
---@return integer completed previews warmed
---@return integer total previews asked for
function Warmer:progress()
  if not self.runner then
    return 0, 0
  end
  return self.runner:completed(), self.runner:total()
end

M.Warmer = Warmer

return M
