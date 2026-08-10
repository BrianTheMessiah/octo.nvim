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
    -- The test's own name claims "below": assert the direction, not just that some
    -- virt_lines mark exists. virt_lines_above = true would draw it above the
    -- section instead and nothing else here would notice.
    eq(false, marks[1][4].virt_lines_above)
  end)

  it("clears already-drawn rows when the option is switched off before the next repaint", function()
    local bufnr, wipe = scratch { "a comment" }
    buttons.render(bufnr, { { kind = "comment", last_line = 1, caps = {} } })

    local original = config.values.ui.section_buttons
    config.values.ui.section_buttons = false
    buttons.render(bufnr, { { kind = "comment", last_line = 1, caps = {} } })
    local count = #vim.api.nvim_buf_get_extmarks(bufnr, buttons.namespace(), 0, -1, {})

    config.values.ui.section_buttons = original
    wipe()
    eq(0, count)
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

describe("octo.ui.buttons click handling:", function()
  ---A real floating window over a scratch buffer, so `screenpos`/`getwininfo` answer
  ---for real geometry rather than a guess. `click()` reads window/screen state that
  ---only exists once a buffer is actually displayed, so `M.hit` alone (columns and
  ---chunks, no window) cannot cover the glue in `M.click` that turns a mouse event
  ---into those same columns and chunks.
  ---@param lines string[]
  ---@param width integer
  ---@param winopts? table<string, any>
  ---@return integer bufnr
  ---@return integer win
  ---@return fun() close
  local function window(lines, width, winopts)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    local win = vim.api.nvim_open_win(bufnr, false, {
      relative = "editor",
      width = width,
      height = 10,
      row = 0,
      col = 0,
    })
    for opt, value in pairs(winopts or {}) do
      vim.wo[win][opt] = value
    end
    return bufnr, win, function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
  end

  ---Makes `win` current (a real mouse click always switches window/buffer before its
  ---mapping fires, which is what lets click()'s buffer-local mapping run at all), then
  ---calls fn with `vim.fn.getmousepos` replaced by `pos`. Always restores both.
  ---@param win integer
  ---@param pos table
  ---@param fn fun()
  local function click_at(win, pos, fn)
    local original_win = vim.api.nvim_get_current_win()
    local original_getmousepos = vim.fn.getmousepos
    vim.api.nvim_set_current_win(win)
    vim.fn.getmousepos = function()
      return pos
    end
    local ok, err = pcall(fn)
    vim.fn.getmousepos = original_getmousepos
    if vim.api.nvim_win_is_valid(original_win) then
      vim.api.nvim_set_current_win(original_win)
    end
    if not ok then
      error(err, 0)
    end
  end

  ---Runs fn with a mappings action replaced by a counting spy, then restores it.
  ---@param action string
  ---@param fn fun(calls: fun(): integer)
  local function with_spy(action, fn)
    local mappings = require "octo.mappings"
    local original = mappings[action]
    local count = 0
    mappings[action] = function()
      count = count + 1
    end
    local ok, err = pcall(fn, function()
      return count
    end)
    mappings[action] = original
    if not ok then
      error(err, 0)
    end
  end

  it("accounts for the window's gutter when measuring the click's display column", function()
    -- signcolumn = "yes:9" is deliberately wide: row[1] ("Reply") spans several
    -- columns on its own (see "finds the button a column falls inside" above), so a
    -- gutter error that is smaller than one button's width would still land inside
    -- the same button by accident and this test would pass whether or not the fix
    -- was there at all. A gutter this wide instead overshoots row[1] into row[2]
    -- ("React") once uncorrected, which fires the wrong action and leaves this
    -- test's spy on row[1] uncalled -- that is what actually distinguishes the fix
    -- from its absence.
    local bufnr, win, close = window({ "a comment" }, 60, { signcolumn = "yes:9" })
    buttons.render(bufnr, { { kind = "comment", last_line = 1, caps = {} } })
    local row = buttons.rows("comment", {})
    local textoff = vim.fn.getwininfo(win)[1].textoff
    -- The whole test is moot if this window granted no gutter to correct for.
    assert.is_true(textoff > 0)

    with_spy(row[1].action, function(calls)
      local anchor_row = vim.fn.screenpos(win, 1, 1).row
      -- Column 3 (see "finds the button a column falls inside" above) lands inside
      -- row[1]; a real click there reports wincol as textoff plus that column, 1-based.
      click_at(win, { winid = win, line = 1, screenrow = anchor_row + 1, wincol = textoff + 4 }, function()
        buttons.click()
      end)
      eq(1, calls())
    end)

    close()
  end)

  it("rejects a click on a wrapped anchor line's own continuation row", function()
    local bufnr, win, close = window({ string.rep("x", 40) }, 10, { wrap = true })
    buttons.render(bufnr, { { kind = "comment", last_line = 1, caps = {} } })
    local row = buttons.rows("comment", {})

    vim.api.nvim_set_current_win(win)
    local first_row = vim.fn.screenpos(win, 1, 1).row
    local last_row = vim.fn.screenpos(win, 1, vim.fn.col { 1, "$" }).row
    -- The whole test is moot if a 40-char line in a 10-column window didn't wrap.
    assert.is_true(last_row > first_row)

    with_spy(row[1].action, function(calls)
      click_at(win, { winid = win, line = 1, screenrow = first_row + 1, wincol = 4 }, function()
        buttons.click()
      end)
      eq(0, calls())

      click_at(win, { winid = win, line = 1, screenrow = last_row + 1, wincol = 4 }, function()
        buttons.click()
      end)
      eq(1, calls())
    end)

    close()
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

  it("draws the button row on a review thread buffer's first paint, not only after an edit", function()
    -- render_threads is the one render_* method that never called render_markdown
    -- (now render_decorations) before this fix; a thread buffer showed no button row
    -- until the user typed and the 150ms debounce fired. threads = {} is enough to
    -- prove the wiring: a footer section is unconditional, so a footer row appearing
    -- proves render_decorations ran, without needing full review-thread comment
    -- fixtures.
    local bufnr = vim.api.nvim_create_buf(false, true)
    local buffer = OctoBuffer:new {
      bufnr = bufnr,
      repo = "owner/name",
      commentsMetadata = {},
      threadsMetadata = {},
    }

    buffer:render_threads {}
    local button_marks = vim.api.nvim_buf_get_extmarks(bufnr, buttons.namespace(), 0, -1, {})

    vim.api.nvim_buf_delete(bufnr, { force = true })
    eq("reviewthread", buffer.kind)
    eq(true, buffer.ready)
    eq(true, #button_marks > 0)
  end)

  it("tells buttons.teardown the buffer is gone, so its drawn rows cannot leak or be clicked past it", function()
    local buffer, bufnr, wipe = issue_buffer(true)
    buffer:configure()

    local original_teardown = buttons.teardown
    local received
    buttons.teardown = function(n)
      received = n
    end

    local ok = pcall(wipe)
    buttons.teardown = original_teardown

    eq(true, ok)
    eq(bufnr, received)
  end)
end)

describe("OctoBuffer review thread resolved state:", function()
  local OctoBuffer = require("octo.model.octo-buffer").OctoBuffer

  ---A minimal but real octo.ReviewThread, just complete enough for
  ---writers.write_threads to run its actual code path without erroring.
  ---diffHunk = "" short-circuits write_thread_snippet immediately (it returns
  ---without doing anything for a blank hunk), which sidesteps needing a real diff.
  ---@param is_resolved boolean
  ---@return table
  local function review_thread(is_resolved)
    return {
      id = "thread-1",
      path = "lua/example.lua",
      diffSide = "RIGHT",
      isOutdated = false,
      isResolved = is_resolved,
      isCollapsed = false,
      resolvedBy = nil,
      originalStartLine = vim.NIL,
      originalLine = 10,
      comments = {
        nodes = {
          {
            id = "comment-1",
            databaseId = 1,
            url = "https://example.com/comment/1",
            replyTo = nil,
            state = "SUBMITTED",
            body = "a thread comment",
            createdAt = "2024-01-01T00:00:00Z",
            lastEditedAt = vim.NIL,
            includesCreatedEdit = vim.NIL,
            viewerCanUpdate = true,
            viewerCanDelete = true,
            viewerDidAuthor = false,
            reactionGroups = {},
            diffHunk = "",
            originalCommit = { abbreviatedOid = "abc1234" },
            pullRequestReview = { id = "review-1" },
          },
        },
      },
    }
  end

  ---A real review-thread OctoBuffer, rendered the way thread-panel.lua and the
  ---review-thread previewer actually render one (kind is derived, not passed:
  ---both real call sites construct OctoBuffer with no `node`, which is what
  ---produces kind == "reviewthread").
  ---@param is_resolved boolean
  ---@return OctoBuffer buffer
  ---@return integer bufnr
  ---@return fun() wipe
  local function thread_buffer(is_resolved)
    local bufnr = vim.api.nvim_create_buf(false, true)
    local buffer = OctoBuffer:new {
      bufnr = bufnr,
      repo = "owner/name",
      commentsMetadata = {},
      threadsMetadata = {},
    }
    buffer:render_threads { review_thread(is_resolved) }
    return buffer, bufnr, function()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end

  ---The action names the thread-kind section's buttons carry.
  ---@param buffer OctoBuffer
  ---@return string[]
  local function thread_actions(buffer)
    for _, section in ipairs(buffer:button_sections()) do
      if section.kind == "thread" then
        return vim.tbl_map(function(button)
          return button.action
        end, buttons.rows(section.kind, section.caps))
      end
    end
    return {}
  end

  it("offers Resolve, not Unresolve, on an open thread's button row", function()
    local buffer, _, wipe = thread_buffer(false)

    local actions = thread_actions(buffer)

    wipe()
    eq({ "add_reply", "resolve_thread", "react_thumbs_up" }, actions)
  end)

  it("offers Unresolve, not Resolve, on a resolved thread's button row", function()
    -- This is the test that actually distinguishes the fix from its absence:
    -- caps.is_resolved defaulting to nil (the unplumbed state) satisfies
    -- VOCABULARY.thread's "Resolve" gate (is_resolved ~= true) just as well as
    -- caps.is_resolved = false does, so the "offers Resolve" test above would
    -- pass whether or not button_sections ever looked up the real thread state.
    -- Only a resolved thread that stops offering Resolve and starts offering
    -- Unresolve proves the association was actually made.
    local buffer, _, wipe = thread_buffer(true)

    local actions = thread_actions(buffer)

    wipe()
    eq({ "add_reply", "unresolve_thread", "react_thumbs_up" }, actions)
  end)
end)
