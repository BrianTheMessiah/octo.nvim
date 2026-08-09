---@diagnostic disable
local eq = assert.are.same

local help_bar = require "octo.reviews.help-bar"
local config = require "octo.config"

--- Restores `config.values.mappings` after a test has edited it in place.
---@param kind string the review kind whose table is about to be edited
---@param action string the action whose entry is about to be edited
---@return fun() restore puts the original entry back
local function borrow(kind, action)
  local table_for_kind = config.values.mappings[kind]
  local original = table_for_kind[action]
  return function()
    table_for_kind[action] = original
  end
end

--- The bar entry for one action, or nil when the bar is not showing it.
---@param kind string the review kind to build entries for
---@param action string the action to look for
---@return table|nil entry as `help_bar.entries` produced it
local function entry_for(kind, action)
  for _, entry in ipairs(help_bar.entries(kind)) do
    if entry.action == action then
      return entry
    end
  end
end

describe("octo.reviews.help-bar entries:", function()
  it("takes each key from the mapping config rather than a literal of its own", function()
    local restore = borrow("review_diff", "submit_review")
    config.values.mappings.review_diff.submit_review = { lhs = "<localleader>zz", desc = "submit review" }

    local entry = entry_for("review_diff", "submit_review")

    restore()
    eq("\\zz", entry.lhs)
  end)

  it("shows every action the review diff mappings configure", function()
    local shown = {}
    for _, entry in ipairs(help_bar.entries "review_diff") do
      shown[entry.action] = true
    end

    for action in pairs(config.values.mappings.review_diff) do
      assert.is_true(shown[action] == true, action .. " is configured but missing from the bar")
    end
  end)

  it("skips an action whose lhs the user has blanked out", function()
    local restore = borrow("review_diff", "goto_file")
    config.values.mappings.review_diff.goto_file = { lhs = "", desc = "go to file" }

    local entry = entry_for("review_diff", "goto_file")

    restore()
    assert.is_nil(entry)
  end)

  it("skips an action octo has no handler for, because nothing bound it", function()
    local restore = borrow("review_diff", "no_such_review_action")
    config.values.mappings.review_diff.no_such_review_action = { lhs = "<localleader>zq", desc = "nothing" }

    local entry = entry_for("review_diff", "no_such_review_action")

    restore()
    assert.is_nil(entry)
  end)

  it("resolves <localleader> to the local leader key in use", function()
    local previous = vim.g.maplocalleader
    vim.g.maplocalleader = ","

    local entry = entry_for("review_diff", "submit_review")

    vim.g.maplocalleader = previous
    eq(",vs", entry.lhs)
  end)

  it("labels an action from its name with the redundant word review dropped", function()
    eq("submit", entry_for("review_diff", "submit_review").label)
    eq("add comment", entry_for("review_diff", "add_review_comment").label)
    eq("close tab", entry_for("review_diff", "close_review_tab").label)
  end)

  it("puts submit and discard first, ahead of the navigation keys", function()
    local entries = help_bar.entries "review_diff"
    eq("submit_review", entries[1].action)
    eq("discard_review", entries[2].action)
  end)
end)

describe("octo.reviews.help-bar contexts:", function()
  it("covers exactly the four windows review mode maps keys on", function()
    eq({ "file_panel", "review_diff", "review_thread", "submit_win" }, vim.fn.sort(vim.tbl_keys(help_bar.LABELS)))
  end)

  it("shows every action each review context configures", function()
    for kind in pairs(help_bar.LABELS) do
      local shown = {}
      for _, entry in ipairs(help_bar.entries(kind)) do
        shown[entry.action] = true
      end
      for action, mapping in pairs(config.values.mappings[kind]) do
        if not require("octo.utils").is_blank(require("octo.mappings")[action]) then
          assert.is_true(shown[action] == true, ("%s.%s is configured but missing from the bar"):format(kind, action))
        end
      end
    end
  end)

  it("names each context with a word short enough to leave room for keys", function()
    eq("diff", help_bar.LABELS.review_diff)
    eq("thread", help_bar.LABELS.review_thread)
    eq("files", help_bar.LABELS.file_panel)
    eq("submit", help_bar.LABELS.submit_win)
  end)

  it("leads the submit window with the three keys that decide the review", function()
    local entries = help_bar.entries "submit_win"
    eq({ "approve_review", "comment_review", "request_changes" }, {
      entries[1].action,
      entries[2].action,
      entries[3].action,
    })
  end)

  it("leads the thread context with commenting rather than file navigation", function()
    local entries = help_bar.entries "review_thread"
    eq("add_comment", entries[1].action)
    eq("add_reply", entries[2].action)
  end)

  it("leads the file panel with selecting and moving between files", function()
    local entries = help_bar.entries "file_panel"
    eq("select_entry", entries[1].action)
  end)
end)

describe("octo.reviews.help-bar line:", function()
  it("opens with the context's name and then its keys", function()
    local opening = " diff   \\vs submit  \\vd discard"
    eq(opening, help_bar.line("review_diff", 200):sub(1, #opening))
  end)

  it("never draws wider than the columns it was given", function()
    for _, width in ipairs { 200, 100, 60, 30, 12, 4, 1 } do
      local line = help_bar.line("review_diff", width)
      assert.is_true(
        vim.fn.strdisplaywidth(line) <= width,
        ("width %d produced %d columns: %q"):format(width, vim.fn.strdisplaywidth(line), line)
      )
    end
  end)

  it("marks a line it had to cut, so a missing key does not read as no key", function()
    local line = help_bar.line("review_diff", 40)
    eq("…", line:sub(-#"…"))
  end)

  it("measures columns rather than bytes, so a multibyte leader costs one column", function()
    local previous = vim.g.maplocalleader

    vim.g.maplocalleader = "$"
    local single_byte = help_bar.line("review_diff", 60)
    vim.g.maplocalleader = "€"
    local three_bytes = help_bar.line("review_diff", 60)

    vim.g.maplocalleader = previous
    eq(vim.fn.strchars(single_byte), vim.fn.strchars(three_bytes))
    assert.is_true(#three_bytes > #single_byte, "the euro leader should still be the longer string in bytes")
  end)

  it("escapes a percent so the statusline does not expand the key as an item", function()
    local restore = borrow("review_diff", "submit_review")
    config.values.mappings.review_diff.submit_review = { lhs = "<localleader>%", desc = "submit review" }

    local line = help_bar.line("review_diff", 200)

    restore()
    assert.is_truthy(line:find("\\%%%% submit", 1, false), line)
  end)

  it("says so rather than drawing a bare label when a context has no keys left", function()
    local mappings = config.values.mappings.review_diff
    config.values.mappings.review_diff = {}

    local line = help_bar.line("review_diff", 200)

    config.values.mappings.review_diff = mappings
    eq(" diff   no keys mapped", line)
  end)
end)

describe("octo.reviews.help-bar buffer contexts:", function()
  it("knows nothing about a buffer no mappings were applied to", function()
    assert.is_nil(help_bar.kind(vim.api.nvim_create_buf(false, true)))
  end)

  it("remembers the review context a buffer's keys came from", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    help_bar.remember(bufnr, "review_thread")
    eq("review_thread", help_bar.kind(bufnr))
  end)

  it("stays out of the contexts that are not review mode", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    help_bar.remember(bufnr, "pull_request")
    assert.is_nil(help_bar.kind(bufnr))
  end)

  it("records the context when octo applies a review context's mappings", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    require("octo.utils").apply_mappings("review_diff", bufnr)
    eq("review_diff", help_bar.kind(bufnr))
  end)
end)

describe("octo.reviews.help-bar winbar:", function()
  --- A scratch window carrying the bar, plus a scratch window to focus instead.
  ---@param bar_kind string|nil the review kind of the buffer the bar hangs on
  ---@param focused_kind string|nil the review kind of the buffer in focus
  ---@return integer bar_win the window the bar is drawn on
  local function two_windows(bar_kind, focused_kind)
    vim.cmd "silent! only"
    local bar_win = vim.api.nvim_get_current_win()
    local bar_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(bar_win, bar_buf)
    if bar_kind then
      help_bar.remember(bar_buf, bar_kind)
    end

    vim.cmd "silent split"
    local focused_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), focused_buf)
    if focused_kind then
      help_bar.remember(focused_buf, focused_kind)
    end

    vim.g.statusline_winid = bar_win
    return bar_win
  end

  after_each(function()
    vim.g.statusline_winid = nil
    vim.cmd "silent! only"
    vim.api.nvim_set_option_value("winbar", "", { scope = "global" })
  end)

  it("draws the context of the window in focus, not the window it hangs on", function()
    two_windows("file_panel", "review_diff")
    assert.is_truthy(help_bar.winbar():find(" diff   ", 1, true), help_bar.winbar())
  end)

  it("falls back to its own window's context when focus is somewhere else", function()
    two_windows("file_panel", nil)
    assert.is_truthy(help_bar.winbar():find(" files   ", 1, true), help_bar.winbar())
  end)

  it("draws nothing at all outside review mode", function()
    two_windows(nil, nil)
    eq("", help_bar.winbar())
  end)

  it("paints the bar in its own highlight group", function()
    two_windows("file_panel", "submit_win")
    assert.is_truthy(help_bar.winbar():find("%%#OctoReviewHelpBar#"), help_bar.winbar())
  end)
end)

describe("octo.reviews.help-bar highlight:", function()
  it("dims a group that exists in name only, which is all a winbar reference leaves behind", function()
    vim.api.nvim_set_hl(0, help_bar.GROUP, {})
    help_bar.highlight()
    eq("Comment", vim.api.nvim_get_hl(0, { name = help_bar.GROUP }).link)
  end)

  it("leaves a colourscheme's own opinion of the group alone", function()
    vim.api.nvim_set_hl(0, help_bar.GROUP, { fg = "#123456" })
    help_bar.highlight()
    local group = vim.api.nvim_get_hl(0, { name = help_bar.GROUP })
    vim.api.nvim_set_hl(0, help_bar.GROUP, {})
    eq(0x123456, group.fg)
  end)

  it("is defined by the time the bar is hung, so the bar is never bare winbar bold", function()
    vim.api.nvim_set_hl(0, help_bar.GROUP, {})
    help_bar.attach(vim.api.nvim_get_current_win())
    local group = vim.api.nvim_get_hl(0, { name = help_bar.GROUP })
    vim.api.nvim_set_option_value("winbar", "", { win = vim.api.nvim_get_current_win(), scope = "local" })
    eq("Comment", group.link)
  end)
end)

describe("octo.reviews.help-bar attach:", function()
  after_each(function()
    vim.cmd "silent! only"
    vim.api.nvim_set_option_value("winbar", "", { scope = "global" })
    vim.api.nvim_set_option_value("winbar", "", { win = vim.api.nvim_get_current_win(), scope = "local" })
  end)

  it("puts the bar on the window it was given", function()
    local win = vim.api.nvim_get_current_win()
    help_bar.attach(win)
    eq(help_bar.EXPRESSION, vim.api.nvim_get_option_value("winbar", { win = win, scope = "local" }))
  end)

  it("leaves the global winbar alone, so no other window inherits the bar", function()
    help_bar.attach(vim.api.nvim_get_current_win())
    eq("", vim.api.nvim_get_option_value("winbar", { scope = "global" }))
  end)

  it("takes the bar with the window, leaving nothing behind when a review is abandoned", function()
    vim.cmd "silent split"
    local win = vim.api.nvim_get_current_win()
    help_bar.attach(win)

    vim.api.nvim_win_close(win, true)

    eq("", vim.api.nvim_get_option_value("winbar", { scope = "global" }))
    for _, other in ipairs(vim.api.nvim_list_wins()) do
      eq("", vim.api.nvim_get_option_value("winbar", { win = other, scope = "local" }))
    end
  end)

  it("is hung on the changed files panel when review mode opens it", function()
    local panel = require("octo.reviews.file-panel").FilePanel:new {}
    panel:open()
    local winid = panel.winid

    local winbar = vim.api.nvim_get_option_value("winbar", { win = winid, scope = "local" })
    panel:destroy()

    eq(help_bar.EXPRESSION, winbar)
  end)

  it("does nothing for a window that has already gone", function()
    vim.cmd "silent split"
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_close(win, true)
    assert.has_no.errors(function()
      help_bar.attach(win)
    end)
  end)
end)
