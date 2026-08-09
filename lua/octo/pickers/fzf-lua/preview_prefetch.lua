---Chooses which picker entries to warm a preview for, ahead of the cursor.
---
---Knows only about positions in a list. It starts no requests and touches no
---buffers, so it can be reasoned about and tested on its own.
local config = require "octo.config"

local M = {}

---How many entries beyond the one under the cursor to warm, per
---`picker_config.preview_prefetch`. Zero turns prefetching off and leaves only the
---on-demand fetch plus the warm cache.
---@return integer count never negative
function M.window()
  local configured = config.values.picker_config.preview_prefetch
  return math.max(0, math.floor(tonumber(configured) or 0))
end

---Positions of each entry string in a list, for locating the cursor's neighbours.
---@param order string[] entry strings in list order
---@return table<string, integer> position by entry string
function M.positions_of(order)
  local positions = {}
  for index, entry_str in ipairs(order) do
    positions[entry_str] = index
  end
  return positions
end

---The entries to warm next: those just beyond the cursor, in its direction of travel.
---
---Direction is inferred from the previously previewed position, so scrolling back
---up a list warms upwards instead of re-warming what was already passed.
---@param order string[] entry strings in list order
---@param from integer position of the entry now under the cursor
---@param previous integer? position previewed before this one, nil on the first preview
---@param window integer how many entries to return at most
---@return string[] entry strings, nearest to the cursor first
function M.targets(order, from, previous, window)
  local step = (previous and previous > from) and -1 or 1
  local targets = {}
  for offset = 1, window do
    local target = order[from + offset * step]
    if not target then
      break
    end
    table.insert(targets, target)
  end
  return targets
end

return M
