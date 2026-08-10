---@diagnostic disable
local eq = assert.are.same

local buttons = require "octo.ui.buttons"
local config = require "octo.config"

---The action names a section's buttons carry.
---@param kind string
---@param caps table
---@return string[]
local function actions(kind, caps)
  return vim.tbl_map(function(button)
    return button.action
  end, buttons.rows(kind, caps))
end

describe("octo.ui.buttons rows:", function()
  it("defaults ui.section_buttons to on", function()
    eq(true, config.values.ui.section_buttons)
  end)

  it("offers a comment and a reaction on a body nobody may edit", function()
    eq({ "add_comment", "react_thumbs_up" }, actions("body", { viewer_can_update = false }))
  end)

  it("offers an edit on a body the viewer may update", function()
    eq(true, vim.tbl_contains(actions("body", { viewer_can_update = true }), "edit"))
  end)

  it("offers a reply on a comment", function()
    eq(true, vim.tbl_contains(actions("comment", {}), "add_reply"))
  end)

  it("offers delete only on a comment the viewer may update", function()
    eq(false, vim.tbl_contains(actions("comment", { viewer_can_update = false }), "delete_comment"))
    eq(true, vim.tbl_contains(actions("comment", { viewer_can_update = true }), "delete_comment"))
  end)

  it("offers resolve on an open thread and unresolve on a resolved one", function()
    eq(true, vim.tbl_contains(actions("thread", { is_resolved = false }), "resolve_thread"))
    eq(false, vim.tbl_contains(actions("thread", { is_resolved = false }), "unresolve_thread"))
    eq(true, vim.tbl_contains(actions("thread", { is_resolved = true }), "unresolve_thread"))
  end)

  it("offers the footer the entry point for a new comment", function()
    eq(true, vim.tbl_contains(actions("footer", {}), "add_comment"))
  end)

  it("returns nothing at all for a section kind it does not know", function()
    eq({}, buttons.rows("not_a_section", {}))
  end)

  it("prints the key on the button, because a virtual line cannot hold the cursor", function()
    local original = vim.g.maplocalleader
    vim.g.maplocalleader = ","

    local row = buttons.rows("comment", {})

    vim.g.maplocalleader = original
    for _, button in ipairs(row) do
      eq(true, button.lhs ~= "" and button.lhs ~= nil)
      eq(false, button.lhs:find("<localleader>", 1, true) ~= nil)
    end
  end)

  it("builds a virt_lines chunk list, each chunk a text and a highlight", function()
    local chunks = buttons.line(buttons.rows("comment", {}))

    eq(true, #chunks > 0)
    for _, chunk in ipairs(chunks) do
      eq("string", type(chunk[1]))
      eq("string", type(chunk[2]))
    end
  end)

  it("draws nothing for a section with no buttons", function()
    eq({}, buttons.line {})
  end)
end)
