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

    eq({ "first", "apple", "zebra" }, vim.tbl_map(function(entry)
      return entry.action
    end, entries))
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
