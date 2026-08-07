---@diagnostic disable
local prs = require "octo.pickers.fzf-lua.pickers.prs"
local eq = assert.are.same

describe("pr picker author filter:", function()
  local original_viewer

  before_each(function()
    original_viewer = vim.g.octo_viewer
    vim.g.octo_viewer = "BrianTheMessiah"
  end)

  after_each(function()
    vim.g.octo_viewer = original_viewer
  end)

  it("uses the repository query when no author is given", function()
    local _, fields, jq = prs.build_query({ states = { "OPEN" } }, "fii-org", "api-gateway")

    eq("fii-org", fields.owner)
    eq(".data.repository.pullRequests.nodes", jq)
  end)

  it("switches to the search query when an author is given", function()
    local _, fields, jq = prs.build_query({ states = { "OPEN" }, author = "someone" }, "fii-org", "api-gateway")

    eq(".data.search.nodes", jq)
    eq("repo:fii-org/api-gateway is:pr is:open author:someone", fields.prompt)
  end)

  it("resolves @me to the logged-in viewer", function()
    local _, fields = prs.build_query({ states = { "OPEN" }, author = "@me" }, "fii-org", "api-gateway")

    eq("repo:fii-org/api-gateway is:pr is:open author:BrianTheMessiah", fields.prompt)
  end)

  it("asks the search API for pull requests, not issues", function()
    local _, fields = prs.build_query({ states = { "OPEN" }, author = "@me" }, "fii-org", "api-gateway")

    eq("ISSUE", fields.type)
  end)

  it("reflects a closed-state request in the search prompt", function()
    local _, fields = prs.build_query({ states = { "CLOSED" }, author = "me" }, "o", "n")

    eq("repo:o/n is:pr is:closed author:me", fields.prompt)
  end)

  it("omits the state qualifier when several states are requested", function()
    local _, fields = prs.build_query({ states = { "OPEN", "CLOSED" }, author = "me" }, "o", "n")

    eq("repo:o/n is:pr author:me", fields.prompt)
  end)
end)
