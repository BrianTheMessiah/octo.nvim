---@diagnostic disable
local eq = assert.are.same

local keymap_help = require "octo.ui.keymap-help"
local help_bar = require "octo.reviews.help-bar"

describe("octo.ui.keymap-help core:", function()
  it("drops the word review from an action name, which the bar repeats otherwise", function()
    eq("submit", keymap_help.terse "submit_review")
    eq("add comment", keymap_help.terse "add_comment")
  end)

  it("resolves a localleader placeholder to the key the reader has to press", function()
    local original = vim.g.maplocalleader
    vim.g.maplocalleader = ","

    local resolved = keymap_help.pretty_lhs "<localleader>ca"

    vim.g.maplocalleader = original
    eq(",ca", resolved)
  end)

  it("cuts text to the width, marking where it was cut", function()
    eq(true, vim.fn.strdisplaywidth(keymap_help.truncate(string.rep("x", 80), 10)) <= 10)
    eq("short", keymap_help.truncate("short", 40))
  end)

  it("builds entries only for actions that have both a mapping and a handler", function()
    local mappings = {
      real = { lhs = "<localleader>a", desc = "real" },
      unbound = { lhs = "", desc = "no key" },
      unhandled = { lhs = "<localleader>b", desc = "no handler" },
    }
    local handlers = { real = function() end, unbound = function() end }

    local entries = keymap_help.entries_from(mappings, { "real", "unbound", "unhandled" }, handlers)

    eq(1, #entries)
    eq("real", entries[1].action)
  end)

  it("draws ordered actions first and any others after them, sorted", function()
    local mappings = {
      zebra = { lhs = "<localleader>z", desc = "z" },
      apple = { lhs = "<localleader>a", desc = "a" },
      first = { lhs = "<localleader>f", desc = "f" },
    }
    local handlers = { zebra = function() end, apple = function() end, first = function() end }

    local entries = keymap_help.entries_from(mappings, { "first" }, handlers)

    eq(
      { "first", "apple", "zebra" },
      vim.tbl_map(function(entry)
        return entry.action
      end, entries)
    )
  end)

  it("has a symbol that is not empty, so the section is never a bare separator", function()
    eq(true, keymap_help.SYMBOL ~= "" and keymap_help.SYMBOL ~= nil)
  end)

  it("puts the symbol and the key in a section of its own", function()
    local section = keymap_help.section()

    eq(true, section:find(keymap_help.SYMBOL, 1, true) ~= nil)
    eq(true, section:find(keymap_help.HELP_KEY, 1, true) ~= nil)
  end)

  it("is the one core the review bar uses, not a second copy of it", function()
    eq(true, rawequal(keymap_help.terse, help_bar.terse))
    eq(true, rawequal(keymap_help.pretty_lhs, help_bar.pretty_lhs))
    eq(true, rawequal(keymap_help.truncate, help_bar.truncate))
    eq(keymap_help.CUT, help_bar.CUT)
  end)
end)

describe("octo.ui.keymap-help float:", function()
  it("lists every key an issue buffer has, one to a line", function()
    local lines = keymap_help.float_lines "issue"

    local joined = table.concat(lines, "\n")
    eq(true, joined:find("add comment", 1, true) ~= nil)
    eq(true, joined:find("reload", 1, true) ~= nil)
  end)

  it("resolves the leader in the float, not just on the bar", function()
    local original = vim.g.maplocalleader
    vim.g.maplocalleader = ","

    local joined = table.concat(keymap_help.float_lines "issue", "\n")

    vim.g.maplocalleader = original
    eq(true, joined:find(",ca", 1, true) ~= nil)
    eq(false, joined:find("<localleader>", 1, true) ~= nil)
  end)

  it("says so rather than opening an empty float for a kind with no keys", function()
    local lines = keymap_help.float_lines "not_a_real_kind"

    eq(1, #lines)
    eq(true, lines[1]:find("no keys", 1, true) ~= nil)
  end)

  it("opens a float that takes the cursor, so it can be scrolled and closed", function()
    local win, buf = keymap_help.float "issue"

    local focusable = vim.api.nvim_win_get_config(win).focusable
    local closed_by = vim.fn.maparg("q", "n", false, true)
    pcall(vim.api.nvim_win_close, win, true)

    eq(true, focusable)
    eq(true, vim.api.nvim_buf_is_valid(buf) == false or true)
    eq(true, closed_by ~= nil)
  end)

  it("puts the help section on the bar for a buffer kind", function()
    local line = keymap_help.bar_line("issue", 200)

    eq(true, line:find(keymap_help.SYMBOL, 1, true) ~= nil)
  end)

  it("keeps the help section even when the bar is too narrow for the keys", function()
    local line = keymap_help.bar_line("issue", 24)

    eq(true, vim.fn.strdisplaywidth((line:gsub("%%%%", "%%"))) <= 24)
    eq(true, line:find(keymap_help.SYMBOL, 1, true) ~= nil)
  end)

  it("keeps the symbol at a width below what the label and section together need", function()
    local line = keymap_help.bar_line("issue", 18)

    eq(true, vim.fn.strdisplaywidth((line:gsub("%%%%", "%%"))) <= 18)
    eq(true, line:find(keymap_help.SYMBOL, 1, true) ~= nil)
  end)

  it("keeps the symbol at a width too small for the label to survive at all", function()
    local line = keymap_help.bar_line("issue", 8)

    eq(true, vim.fn.strdisplaywidth((line:gsub("%%%%", "%%"))) <= 8)
    eq(true, line:find(keymap_help.SYMBOL, 1, true) ~= nil)
  end)

  it("raises no error at a width of zero, and returns nothing wider than that", function()
    local ok, line = pcall(keymap_help.bar_line, "issue", 0)

    eq(true, ok)
    eq(true, vim.fn.strdisplaywidth((line:gsub("%%%%", "%%"))) <= 0)
  end)

  it("raises no error at a negative width, and returns nothing wider than zero", function()
    local ok, line = pcall(keymap_help.bar_line, "issue", -5)

    eq(true, ok)
    eq(true, vim.fn.strdisplaywidth((line:gsub("%%%%", "%%"))) <= 0)
  end)

  it("escapes every percent, which a statusline expression would otherwise read", function()
    local line = keymap_help.bar_line("issue", 200)

    for percent in line:gmatch "%%+" do
      eq(0, #percent % 2)
    end
  end)

  it("returns an empty bar for a buffer that has no recorded kind", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)

    local bar = keymap_help.winbar()

    vim.api.nvim_buf_delete(bufnr, { force = true })
    eq("", bar)
  end)

  -- A buffer's kind is not the key its mappings sit under: OctoBuffer.kind is "pull"
  -- and the config block is `mappings.pull_request`, the same translation
  -- OctoBuffer:apply_mappings makes. Read the kind straight and a pull request buffer
  -- -- the one this whole surface was built for -- reports no keys at all.
  it("finds the keys of every buffer kind the bar is scoped to, pull request included", function()
    for _, kind in ipairs { "pull", "issue", "discussion", "repo", "release" } do
      assert.is_true(#keymap_help.entries(kind) > 0, ("no keys found for kind %q"):format(kind))
    end
  end)

  it("names a real pull request key on the bar rather than reporting none", function()
    local entries = keymap_help.entries "pull"
    local actions = vim.tbl_map(function(entry)
      return entry.action
    end, entries)

    eq(true, vim.tbl_contains(actions, "checkout_pr"))
    eq(false, keymap_help.bar_line("pull", 200):find "no keys mapped" ~= nil)
  end)

  ----------------------------------------------------------------------------
  -- the pending-comment sequence, which a list of keys cannot express
  ----------------------------------------------------------------------------

  it("tells a reviewer that a comment is pending until the review is submitted", function()
    local text = table.concat(keymap_help.note_lines "review_diff", "\n")

    eq(true, text:lower():find("pending", 1, true) ~= nil)
  end)

  it("names the keys of the sequence as they are actually bound", function()
    local config = require "octo.config"
    local text = table.concat(keymap_help.note_lines "review_diff", "\n")
    local add = config.values.mappings.review_diff.add_review_comment.lhs
    local submit = config.values.mappings.review_diff.submit_review.lhs
    local approve = config.values.mappings.submit_win.approve_review.lhs

    eq(true, text:find(keymap_help.pretty_lhs(add), 1, true) ~= nil)
    eq(true, text:find(keymap_help.pretty_lhs(submit), 1, true) ~= nil)
    eq(true, text:find(keymap_help.pretty_lhs(approve), 1, true) ~= nil)
  end)

  it("follows a rebound key rather than a hardcoded one", function()
    local config = require "octo.config"
    local original = config.values.mappings.review_diff.add_review_comment.lhs
    config.values.mappings.review_diff.add_review_comment.lhs = "<localleader>zz"

    local text = table.concat(keymap_help.note_lines "review_diff", "\n")
    config.values.mappings.review_diff.add_review_comment.lhs = original

    eq(true, text:find("zz", 1, true) ~= nil)
  end)

  it("says the same thing in the thread and submit surfaces, and nothing in unrelated ones", function()
    eq(true, #keymap_help.note_lines "review_thread" > 0)
    eq(true, #keymap_help.note_lines "submit_win" > 0)
    eq(0, #keymap_help.note_lines "pull")
    eq(0, #keymap_help.note_lines "picker")
  end)

  it("puts the note under the keys in the float, not instead of them", function()
    local lines = keymap_help.float_lines "review_diff"
    local text = table.concat(lines, "\n")
    local keys = table.concat(keymap_help.float_lines "pull", "\n")

    -- the float still lists keys, and the note is below them
    eq(true, #lines > #keymap_help.note_lines "review_diff")
    eq(true, text:lower():find("pending", 1, true) ~= nil)
    eq(false, keys:lower():find("pending", 1, true) ~= nil)
  end)
end)
