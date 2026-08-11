---@diagnostic disable
local eq = assert.are.same

local gh = require "octo.gh"
local config = require "octo.config"
local preview_cache = require "octo.pickers.fzf-lua.preview_cache"
local session_cache = require "octo.pickers.fzf-lua.preview_session_cache"
local previewers = require "octo.pickers.fzf-lua.previewers"
local startup = require "octo.pickers.fzf-lua.preview_startup"
local writers = require "octo.ui.writers"

---Stand in for every writer `render_preview` calls, so a test can drive a real
---previewer without needing a payload shaped for the real renderer.
---@return fun() restore puts the real writers back
local function stub_writers()
  local saved = {
    write_title = writers.write_title,
    write_details = writers.write_details,
    write_body = writers.write_body,
    write_state = writers.write_state,
    write_block = writers.write_block,
    write_reactions = writers.write_reactions,
  }
  writers.write_title = function() end
  writers.write_details = function() end
  writers.write_body = function() end
  writers.write_state = function() end
  writers.write_block = function() end
  writers.write_reactions = function() end
  return function()
    for name, fn in pairs(saved) do
      writers[name] = fn
    end
  end
end

---A `search.nodes` response body for one pull request.
---@param number integer pull request number
---@param repo? string "owner/name", default "fii-org/service.core"
---@return table node shaped as the search query returns it
local function node(number, repo)
  return {
    __typename = "PullRequest",
    number = number,
    title = "PR " .. number,
    repository = { nameWithOwner = repo or "fii-org/service.core" },
  }
end

---Replace `gh.api.graphql`, recording every call and answering search calls from
---a canned reply queue and preview calls from a second one, matched by whether
---the request carries a `prompt` field.
---@return table harness with `search_replies`, `preview_replies`, `search_calls`, `preview_calls`, `restore()`
local function harness()
  local saved = gh.api.graphql
  local h = { search_replies = {}, preview_replies = {}, search_calls = {}, preview_calls = {} }

  gh.api.graphql = function(opts)
    local cb = opts.opts.cb
    if opts.fields and opts.fields.prompt then
      table.insert(h.search_calls, opts.fields.prompt)
      local reply = table.remove(h.search_replies, 1)
      -- `--jq ".data.search.nodes"` already ran by the time real `gh` hands stdout
      -- to the callback, so the stub answers with the bare node list too.
      cb(vim.json.encode(reply or {}), "")
    else
      table.insert(h.preview_calls, true)
      local reply = table.remove(h.preview_replies, 1)
      if reply == nil then
        cb(nil, "not stubbed")
      else
        cb(vim.json.encode { data = { repository = { pullRequest = reply } } }, "")
      end
    end
  end

  h.restore = function() gh.api.graphql = saved end
  return h
end

describe("octo preview startup warming:", function()
  local saved_prefetch_all, saved_concurrency

  before_each(function()
    session_cache.reset()
    saved_prefetch_all = config.values.picker_config.preview_prefetch_all
    saved_concurrency = config.values.picker_config.preview_prefetch_concurrency
    config.values.picker_config.preview_prefetch_concurrency = 10
  end)

  after_each(function()
    config.values.picker_config.preview_prefetch_all = saved_prefetch_all
    config.values.picker_config.preview_prefetch_concurrency = saved_concurrency
    session_cache.reset()
  end)

  it("fetches a query's entries and stores their previews in the session cache", function()
    local h = harness()
    h.search_replies = { { node(1), node(2) } }
    h.preview_replies = { { title = "PR 1" }, { title = "PR 2" } }

    startup.warm_query "is:pr is:open author:@me"
    eq({ "is:pr is:open author:@me" }, h.search_calls)
    eq(2, #h.preview_calls)

    local cache = session_cache.get()
    eq({ title = "PR 1" }, cache:get(preview_cache.key("pull_request", "fii-org/service.core", 1)))
    eq({ title = "PR 2" }, cache:get(preview_cache.key("pull_request", "fii-org/service.core", 2)))
    h.restore()
  end)

  it("warms every query in a list, one search request each", function()
    local h = harness()
    h.search_replies = { { node(1) }, { node(9) } }
    h.preview_replies = { { title = "PR 1" }, { title = "PR 9" } }

    startup.warm { "is:pr is:open author:@me", "is:pr is:open org:acme" }

    eq(2, #h.search_calls)
    local cache = session_cache.get()
    eq({ title = "PR 1" }, cache:get(preview_cache.key("pull_request", "fii-org/service.core", 1)))
    eq({ title = "PR 9" }, cache:get(preview_cache.key("pull_request", "fii-org/service.core", 9)))
    h.restore()
  end)

  it("asks for nothing when the query returns no results", function()
    local h = harness()
    h.search_replies = { {} }

    startup.warm_query "is:pr is:open author:@me"

    eq(1, #h.search_calls)
    eq(0, #h.preview_calls)
    h.restore()
  end)

  it("leaves the session cache empty when full prefetch is switched off", function()
    config.values.picker_config.preview_prefetch_all = false
    local h = harness()
    h.search_replies = { { node(1) } }

    startup.warm_query "is:pr is:open author:@me"

    eq(1, #h.search_calls)
    eq(0, #h.preview_calls)
    h.restore()
  end)

  it("is what a search picker opened afterwards reads from -- no second fetch", function()
    local unstub = stub_writers()
    local h = harness()
    h.search_replies = { { node(4) } }
    h.preview_replies = { { title = "PR 4", state = "OPEN" } }
    startup.warm_query "is:pr is:open author:@me"
    eq(1, #h.preview_calls)

    local formatted = {
      ["pull_request fii-org service.core 4 PR 4"] = {
        kind = "pull_request",
        repo = "fii-org/service.core",
        value = 4,
        ordinal = "4",
      },
    }
    local class = previewers.search(formatted)
    local instance = setmetatable({}, { __index = class })
    instance.get_tmp_buffer = function() return vim.api.nvim_create_buf(false, true) end
    instance.set_preview_buf = function(self, bufnr) self.preview_bufnr = bufnr end
    instance.update_border = function() end
    instance.win = { update_preview_scrollbar = function() end }

    instance:populate_preview_buf "pull_request fii-org service.core 4 PR 4"

    eq(1, #h.preview_calls)
    h.restore()
    unstub()
  end)
end)
