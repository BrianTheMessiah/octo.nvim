---@diagnostic disable
local eq = assert.are.same

local config = require "octo.config"
local gh = require "octo.gh"
local previewers = require "octo.pickers.fzf-lua.previewers"
local writers = require "octo.ui.writers"

---One picker entry as `entry_maker.gen_from_issue` builds it, trimmed to the
---fields the previewer reads.
---@param number integer pull request number, also used as the entry string
---@return table entry
local function entry_for(number)
  return {
    kind = "pull_request",
    repo = "fii-org/service.core",
    value = number,
    ordinal = tostring(number),
  }
end

---A response body shaped like the preview query's, for a given number.
---@param number integer pull request number
---@return string json
local function response_for(number)
  return vim.json.encode {
    data = { repository = { pullRequest = { title = "PR " .. number, state = "OPEN", body = "body" } } },
  }
end

---Replace the collaborators the previewer paints through, recording what it paints,
---and hold every gh request open so completion order can be chosen by the test.
---@return table harness with `painted`, `requests`, `respond(index, json)` and `restore()`
local function harness()
  local saved = {
    graphql = gh.api.graphql,
    write_title = writers.write_title,
    write_details = writers.write_details,
    write_body = writers.write_body,
    write_state = writers.write_state,
    write_block = writers.write_block,
    write_reactions = writers.write_reactions,
  }
  local h = { painted = {}, requests = {} }

  gh.api.graphql = function(opts)
    table.insert(h.requests, opts.opts.cb)
  end
  writers.write_title = function(bufnr, title)
    table.insert(h.painted, { bufnr = bufnr, title = title })
  end
  writers.write_details = function() end
  writers.write_body = function(_, issue)
    local last = h.painted[#h.painted]
    if last then
      last.body = type(issue) == "table" and issue.body or nil
    end
  end
  writers.write_state = function() end
  writers.write_block = function() end
  writers.write_reactions = function() end

  h.respond = function(index, json)
    h.requests[index](json, "")
  end
  h.restore = function()
    gh.api.graphql = saved.graphql
    for name, fn in pairs(saved) do
      if name ~= "graphql" then
        writers[name] = fn
      end
    end
  end
  return h
end

---A previewer instance standing in for a live one, with the fzf-lua window calls
---the previewer makes replaced by records.
---@param class table previewer class from `previewers.issue`
---@return table instance carrying `buffers`, the tmp buffers it handed out
local function instance_of(class)
  local instance = setmetatable({ buffers = {} }, { __index = class })
  instance.get_tmp_buffer = function(self)
    local bufnr = vim.api.nvim_create_buf(false, true)
    table.insert(self.buffers, bufnr)
    return bufnr
  end
  instance.set_preview_buf = function(self, bufnr)
    self.preview_bufnr = bufnr
  end
  instance.update_border = function() end
  return instance
end

describe("octo preview staleness:", function()
  local saved_prefetch, saved_fragment

  before_each(function()
    saved_prefetch = config.values.picker_config.preview_prefetch
    config.values.picker_config.preview_prefetch = 0
    -- octo.gh.setup builds the query strings and seeds the projects-v2 fragment
    -- before spawning a gh process; the previewer needs the former, not the latter.
    require("octo.gh.fragments").setup()
    require("octo.gh.queries").setup()
    saved_fragment = _G.octo_pv2_fragment
    _G.octo_pv2_fragment = _G.octo_pv2_fragment or ""
  end)

  after_each(function()
    config.values.picker_config.preview_prefetch = saved_prefetch
    _G.octo_pv2_fragment = saved_fragment
  end)

  it("paints an on-demand response into the buffer that is still on screen", function()
    local h = harness()
    local class = previewers.issue { ["906"] = entry_for(906) }
    local previewer = instance_of(class)

    previewer:populate_preview_buf "906"
    h.respond(1, response_for(906))

    eq(1, #h.painted)
    eq("PR 906", h.painted[1].title)
    eq(previewer.buffers[1], h.painted[1].bufnr)
    h.restore()
  end)

  it("paints nothing when its response lands after the cursor moved on", function()
    local h = harness()
    local class = previewers.issue { ["906"] = entry_for(906), ["903"] = entry_for(903) }
    local previewer = instance_of(class)

    previewer:populate_preview_buf "906"
    previewer:populate_preview_buf "903"
    h.respond(1, response_for(906))

    eq({}, h.painted)
    h.restore()
  end)

  it("cannot overwrite the entry under the cursor with a slower earlier entry", function()
    local h = harness()
    local class = previewers.issue { ["906"] = entry_for(906), ["903"] = entry_for(903) }
    local previewer = instance_of(class)

    previewer:populate_preview_buf "906"
    previewer:populate_preview_buf "903"
    h.respond(2, response_for(903))
    h.respond(1, response_for(906))

    eq(1, #h.painted)
    eq("PR 903", h.painted[1].title)
    eq(previewer.buffers[2], h.painted[1].bufnr)
    h.restore()
  end)

  it("paints nothing into a buffer that has already been deleted", function()
    local h = harness()
    local class = previewers.issue { ["906"] = entry_for(906) }
    local previewer = instance_of(class)

    previewer:populate_preview_buf "906"
    vim.api.nvim_buf_delete(previewer.buffers[1], { force = true })
    h.respond(1, response_for(906))

    eq({}, h.painted)
    h.restore()
  end)

  it("serves a revisited entry from cache without a second request", function()
    local h = harness()
    local class = previewers.issue { ["906"] = entry_for(906), ["903"] = entry_for(903) }
    local previewer = instance_of(class)

    previewer:populate_preview_buf "906"
    h.respond(1, response_for(906))
    previewer:populate_preview_buf "903"
    previewer:populate_preview_buf "906"

    eq(2, #h.requests)
    eq(2, #h.painted)
    eq("PR 906", h.painted[2].title)
    eq(previewer.buffers[3], h.painted[2].bufnr)
    h.restore()
  end)

  it("warms neighbours without painting any of them", function()
    local h = harness()
    config.values.picker_config.preview_prefetch = 2
    local formatted = { ["906"] = entry_for(906), ["903"] = entry_for(903), ["898"] = entry_for(898) }
    local class = previewers.issue(formatted, { "906", "903", "898" })
    local previewer = instance_of(class)

    previewer:populate_preview_buf "906"
    eq(3, #h.requests)

    h.respond(2, response_for(903))
    h.respond(3, response_for(898))
    eq({}, h.painted)

    h.respond(1, response_for(906))
    eq(1, #h.painted)
    eq("PR 906", h.painted[1].title)
    h.restore()
  end)

  it("renders a cached body once per paint, never compounding the transform", function()
    local h = harness()
    local class = previewers.issue { ["906"] = entry_for(906) }
    local previewer = instance_of(class)
    local raw = vim.json.encode {
      data = {
        repository = {
          pullRequest = { title = "PR 906", state = "OPEN", body = "<p>hello <b>there</b></p>" },
        },
      },
    }

    previewer:populate_preview_buf "906"
    h.respond(1, raw)
    previewer:populate_preview_buf "906"
    previewer:populate_preview_buf "906"

    eq(1, #h.requests)
    eq(3, #h.painted)
    local expected = require("octo.ui.html").to_markdown "<p>hello <b>there</b></p>"
    eq("hello **there**", expected)
    for index, paint in ipairs(h.painted) do
      eq(expected, paint.body, "paint " .. index .. " should carry the same rendered body")
    end
    h.restore()
  end)

  it("shows a warmed neighbour with no further request when the cursor reaches it", function()
    local h = harness()
    config.values.picker_config.preview_prefetch = 1
    local formatted = { ["906"] = entry_for(906), ["903"] = entry_for(903) }
    local class = previewers.issue(formatted, { "906", "903" })
    local previewer = instance_of(class)

    previewer:populate_preview_buf "906"
    h.respond(2, response_for(903))
    local requests_before = #h.requests

    previewer:populate_preview_buf "903"

    eq(requests_before, #h.requests)
    eq(1, #h.painted)
    eq("PR 903", h.painted[1].title)
    eq(previewer.buffers[2], h.painted[1].bufnr)
    h.restore()
  end)
end)
