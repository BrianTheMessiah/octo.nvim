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

  it("labels a button chunk with the shared button highlight group", function()
    local chunks = buttons.line(buttons.rows("comment", {}))

    -- Odd chunks are the leading separators (highlighted "Normal"); even chunks
    -- are the buttons themselves, and must carry the real, specific group Task
    -- 10 draws with -- not just some string.
    for index, chunk in ipairs(chunks) do
      if index % 2 == 0 then
        eq("OctoButton", chunk[2])
      end
    end
  end)

  it("draws nothing for a section with no buttons", function()
    eq({}, buttons.line {})
  end)
end)

describe("octo.ui.buttons drawing:", function()
  ---@param lines string[]
  ---@return integer bufnr
  ---@return fun() wipe
  local function scratch(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    return bufnr, function()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end

  it("draws a button row as virtual lines below the section", function()
    local bufnr, wipe = scratch { "a comment", "", "another" }

    buttons.render(bufnr, { { kind = "comment", last_line = 1, caps = {} } })
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, buttons.namespace(), 0, -1, { details = true })

    wipe()
    eq(1, #marks)
    eq(0, marks[1][2])
    eq(true, marks[1][4].virt_lines ~= nil)
  end)

  it("clears its previous rows so a repainted buffer does not accumulate them", function()
    local bufnr, wipe = scratch { "a comment" }

    buttons.render(bufnr, { { kind = "comment", last_line = 1, caps = {} } })
    buttons.render(bufnr, { { kind = "comment", last_line = 1, caps = {} } })
    local count = #vim.api.nvim_buf_get_extmarks(bufnr, buttons.namespace(), 0, -1, {})

    wipe()
    eq(1, count)
  end)

  it("uses a namespace of its own, never the markdown one", function()
    eq(false, buttons.namespace() == require("octo.ui.markdown").buffer_namespace())
  end)

  it("draws nothing at all when the option is off", function()
    local original = config.values.ui.section_buttons
    config.values.ui.section_buttons = false
    local bufnr, wipe = scratch { "a comment" }

    buttons.render(bufnr, { { kind = "comment", last_line = 1, caps = {} } })
    local count = #vim.api.nvim_buf_get_extmarks(bufnr, buttons.namespace(), 0, -1, {})

    config.values.ui.section_buttons = original
    wipe()
    eq(0, count)
  end)

  it("skips a section whose line is past the end of the buffer", function()
    local bufnr, wipe = scratch { "a comment" }

    local ok = pcall(buttons.render, bufnr, { { kind = "comment", last_line = 999, caps = {} } })
    local count = #vim.api.nvim_buf_get_extmarks(bufnr, buttons.namespace(), 0, -1, {})

    wipe()
    eq(true, ok)
    eq(0, count)
  end)

  it("refuses to touch a buffer that is no longer valid", function()
    local bufnr, wipe = scratch { "a comment" }
    wipe()

    eq(false, buttons.render(bufnr, { { kind = "comment", last_line = 1, caps = {} } }))
  end)
end)

describe("octo.ui.buttons hit testing:", function()
  it("finds the button a column falls inside", function()
    local row = buttons.rows("comment", {})
    local chunks = buttons.line(row)

    -- Column 0 and 1 are the leading separator; the first label starts at 2.
    eq(row[1].action, buttons.hit(chunks, 3, row).action)
  end)

  it("finds a later button past the first", function()
    local row = buttons.rows("comment", {})
    local chunks = buttons.line(row)
    local first_width = vim.fn.strdisplaywidth(chunks[1][1]) + vim.fn.strdisplaywidth(chunks[2][1])

    eq(row[2].action, buttons.hit(chunks, first_width + 3, row).action)
  end)

  it("finds nothing in the gap between two buttons", function()
    local row = buttons.rows("comment", {})

    eq(nil, buttons.hit(buttons.line(row), 0, row))
  end)

  it("finds nothing past the end of the row", function()
    local row = buttons.rows("comment", {})

    eq(nil, buttons.hit(buttons.line(row), 9999, row))
  end)

  it("finds nothing in an empty row", function()
    eq(nil, buttons.hit({}, 3, {}))
  end)
end)

describe("OctoBuffer button sections and decorations:", function()
  local OctoBuffer = require("octo.model.octo-buffer").OctoBuffer
  local writers = require "octo.ui.writers"
  local markdown = require "octo.ui.markdown"
  local constants = require "octo.constants"
  local utils = require "octo.utils"

  ---An OctoBuffer with a body written the way render_issue would write it, so
  ---bodyMetadata carries a real extmark rather than a hand-rolled one.
  ---@param viewer_can_update boolean
  ---@return OctoBuffer buffer
  ---@return integer bufnr
  ---@return fun() wipe
  local function issue_buffer(viewer_can_update)
    local bufnr = vim.api.nvim_create_buf(false, true)
    local buffer = OctoBuffer:new {
      bufnr = bufnr,
      number = 1,
      repo = "owner/name",
      node = {},
      kind = "issue",
      commentsMetadata = {},
      threadsMetadata = {},
    }
    writers.write_body(bufnr, {
      body = "# a body heading",
      viewerCanUpdate = viewer_can_update,
      lastEditedAt = vim.NIL,
      includesCreatedEdit = vim.NIL,
    })
    return buffer,
      bufnr,
      function()
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
  end

  it("builds a body section from the body's real extmark, carrying its capabilities", function()
    local buffer, _, wipe = issue_buffer(true)

    local sections = buffer:button_sections()

    wipe()
    eq("body", sections[1].kind)
    eq(true, sections[1].caps.viewer_can_update)
  end)

  it("denies edit capability when the viewer may not update the body", function()
    local buffer, _, wipe = issue_buffer(false)

    local sections = buffer:button_sections()

    wipe()
    eq(false, sections[1].caps.viewer_can_update)
  end)

  it("always appends a footer section anchored at the last line of the buffer", function()
    local buffer, bufnr, wipe = issue_buffer(true)

    local sections = buffer:button_sections()
    local total = vim.api.nvim_buf_line_count(bufnr)

    wipe()
    eq("footer", sections[#sections].kind)
    eq(total, sections[#sections].last_line)
  end)

  it("anchors a body's row on its actual last content line, not one line short", function()
    -- get_extmark_region answers in 0-based rows; button_sections' last_line is
    -- documented as 1-based (see octo.ButtonSection). Comparing the drawn extmark's
    -- row straight against get_extmark_region's own 0-based answer catches a
    -- regression that forgets the +1 and would otherwise render every button row
    -- one line above the section it belongs to.
    local buffer, bufnr, wipe = issue_buffer(true)

    local mark = vim.api.nvim_buf_get_extmark_by_id(
      bufnr,
      constants.OCTO_COMMENT_NS,
      buffer.bodyMetadata.extmark,
      { details = true }
    )
    local _, expected_row = utils.get_extmark_region(bufnr, mark)
    buffer.ready = true
    buffer:render_decorations()
    local rows = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, buttons.namespace(), 0, -1, {})) do
      rows[#rows + 1] = m[2]
    end
    table.sort(rows)

    wipe()
    eq(expected_row, rows[1])
  end)

  it("render_decorations draws both the markdown conceal and the button row, each in its own namespace", function()
    local buffer, bufnr, wipe = issue_buffer(true)
    buffer.ready = true

    buffer:render_decorations()
    local markdown_marks = vim.api.nvim_buf_get_extmarks(bufnr, markdown.buffer_namespace(), 0, -1, {})
    local button_marks = vim.api.nvim_buf_get_extmarks(bufnr, buttons.namespace(), 0, -1, {})

    wipe()
    eq(true, #markdown_marks > 0)
    eq(true, #button_marks > 0)
  end)

  it("does nothing at all -- not even the markdown -- when the buffer is not ready", function()
    local buffer, bufnr, wipe = issue_buffer(true)
    buffer.ready = false

    buffer:render_decorations()
    local markdown_marks = vim.api.nvim_buf_get_extmarks(bufnr, markdown.buffer_namespace(), 0, -1, {})
    local button_marks = vim.api.nvim_buf_get_extmarks(bufnr, buttons.namespace(), 0, -1, {})

    wipe()
    eq(0, #markdown_marks)
    eq(0, #button_marks)
  end)

  it("repainting the buttons does not touch the markdown namespace's own extmarks", function()
    local buffer, bufnr, wipe = issue_buffer(true)
    buffer.ready = true

    buffer:render_decorations()
    local before = #vim.api.nvim_buf_get_extmarks(bufnr, markdown.buffer_namespace(), 0, -1, {})
    buttons.render(bufnr, buffer:button_sections())
    local after = #vim.api.nvim_buf_get_extmarks(bufnr, markdown.buffer_namespace(), 0, -1, {})

    wipe()
    eq(true, before > 0)
    eq(before, after)
  end)

  it("binds <LeftRelease> in normal mode to the button click handler", function()
    local buffer, bufnr, wipe = issue_buffer(true)

    buffer:configure()
    local found = false
    for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
      if mapping.lhs == "<LeftRelease>" then
        found = true
      end
    end

    wipe()
    eq(true, found)
  end)
end)
