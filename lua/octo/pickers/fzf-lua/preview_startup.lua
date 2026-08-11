---Warms the session preview cache from a GitHub search query, before any picker
---has opened one.
---
---Runs the identical query the fzf-lua search picker runs (`octo.pickers.fzf-lua.
---pickers.search`), then hands the results to `preview_warmer` against the shared
---`preview_session_cache` -- the same cache `previewers.search` reads from. A
---search picker opened later with the same query, or with any query that returns
---an overlapping pull request, finds those previews already there.
local gh = require "octo.gh"
local queries = require "octo.gh.queries"
local utils = require "octo.utils"
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local preview_warmer = require "octo.pickers.fzf-lua.preview_warmer"
local preview_session_cache = require "octo.pickers.fzf-lua.preview_session_cache"
local previewers = require "octo.pickers.fzf-lua.previewers"

local M = {}

---Adapt `previewers.fetch_preview` to the shape a warmer wants.
---@param entry table an entry from `entry_maker.gen_from_issue`
---@param done fun(payload: table?, remaining: integer?) called when the request ends
local function fetch_entry(entry, done) previewers.fetch_preview(entry.kind, entry.repo, entry.value, done) end

---Runs one search query and hands back the entries it found.
---@param query string a GitHub search query, as `Octo search` would take it
---@param search_type string GraphQL search type, "ISSUE" covers issues and pull requests
---@param done fun(entries: table[]) called with zero or more entries, never nil
---@return nil
function M.fetch_entries(query, search_type, done)
  if utils.is_blank(query) then
    done {}
    return
  end
  gh.api.graphql {
    query = queries.search,
    jq = ".data.search.nodes",
    fields = { prompt = vim.trim(query), type = search_type },
    opts = {
      cb = gh.create_callback {
        success = function(stdout)
          local ok, nodes = pcall(vim.json.decode, stdout)
          if not ok or type(nodes) ~= "table" then
            done {}
            return
          end
          local entries = {}
          for _, node in ipairs(nodes) do
            local entry = entry_maker.gen_from_issue(node)
            if entry then
              entries[#entries + 1] = entry
            end
          end
          done(entries)
        end,
        failure = function() done {} end,
      },
    },
  }
end

---Warms the session cache for one search query.
---
---Fire-and-forget: nothing here notifies the caller of completion, because
---nothing a startup warm-up does needs a buffer or a window to still exist by
---the time it finishes.
---@param query string a GitHub search query
---@param opts? { type?: string, on_progress?: fun(completed: integer, total: integer) }
---@return nil
function M.warm_query(query, opts)
  opts = opts or {}
  M.fetch_entries(query, opts.type or "ISSUE", function(entries)
    if #entries == 0 then
      return
    end
    local warmer = preview_warmer.new {
      cache = preview_session_cache.get(),
      fetch = fetch_entry,
      on_progress = opts.on_progress,
      entries = function() return entries end,
    }
    warmer:warm()
  end)
end

---Warms the session cache for every query in a list, one `gh` round trip each.
---@param search_queries string[] GitHub search queries
---@param opts? { type?: string, on_progress?: fun(completed: integer, total: integer) }
---@return nil
function M.warm(search_queries, opts)
  for _, query in ipairs(search_queries) do
    M.warm_query(query, opts)
  end
end

return M
