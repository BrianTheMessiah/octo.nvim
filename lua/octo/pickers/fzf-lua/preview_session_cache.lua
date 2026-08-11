---The one preview cache that outlives a single picker.
---
---`previewers.lua` used to build a fresh `preview_cache.new()` every time a search
---picker opened, so a preview fetched five seconds ago was fetched again the next
---time the same pull request scrolled past the cursor. Cache keys are content
---addressed (kind:repo:number) and carry no picker-specific state, so nothing
---stops one instance answering for every search picker opened in the session --
---this module is that instance.
local preview_cache = require "octo.pickers.fzf-lua.preview_cache"

local M = {}

---Payloads a session realistically holds: a startup warm-up of two or three
---organisation-wide searches plus whatever else gets opened by hand, comfortably
---under a thousand pull requests without the eviction limit ever seeing daylight.
local DEFAULT_LIMIT = 512

---@type octo.PreviewCache?
local instance = nil

---The shared cache, built on first use.
---@return octo.PreviewCache
function M.get()
  instance = instance or preview_cache.new(DEFAULT_LIMIT)
  return instance
end

---Drops the shared cache, so the next `M.get()` starts empty. Test-only: nothing
---in normal operation needs the session cache to forget what it holds.
---@return nil
function M.reset() instance = nil end

return M
