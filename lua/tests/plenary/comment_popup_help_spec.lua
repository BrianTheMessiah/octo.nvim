---@diagnostic disable
local eq = assert.are.same

local popup = require "octo.ui.comment-popup"
local window = require "octo.ui.window"
local keymap_help = require "octo.ui.keymap-help"

describe("octo comment popup help:", function()
  it("names the three keys that matter, and the symbol", function()
    eq(true, popup.FOOTER:find("<C-s>", 1, true) ~= nil)
    eq(true, popup.FOOTER:find("q", 1, true) ~= nil)
    eq(true, popup.FOOTER:find(keymap_help.SYMBOL, 1, true) ~= nil)
    eq(true, popup.FOOTER:find(keymap_help.HELP_KEY, 1, true) ~= nil)
  end)

  it("hangs the footer on the popup's own window", function()
    local winid, bufnr = popup.open {
      target = {},
      on_submit = function(_, _, done)
        done(true)
      end,
    }

    local footer = vim.api.nvim_win_get_config(winid).footer
    popup.cancel(bufnr)

    eq(true, footer ~= nil)
  end)

  it("binds the help key inside the popup", function()
    local winid, bufnr = popup.open {
      target = {},
      on_submit = function(_, _, done)
        done(true)
      end,
    }

    local mapping = vim.fn.maparg(keymap_help.HELP_KEY, "n", false, true)
    local bound = mapping and mapping.buffer == 1
    popup.cancel(bufnr)

    eq(true, bound)
  end)

  it("passes a footer straight through to the float it opens", function()
    local winid, bufnr = window.create_centered_float {
      header = "Test",
      content = { "one", "two" },
      footer = "a footer",
      enter = false,
    }

    local footer = vim.api.nvim_win_get_config(winid).footer
    pcall(vim.api.nvim_win_close, winid, true)

    eq(true, footer ~= nil)
  end)

  it("opens a float with no footer when none was asked for", function()
    local winid = window.create_centered_float {
      header = "Test",
      content = { "one" },
      enter = false,
    }

    local config_footer = vim.api.nvim_win_get_config(winid).footer
    pcall(vim.api.nvim_win_close, winid, true)

    eq(true, config_footer == nil or config_footer == "")
  end)

  it("renders the four keys a comment popup binds, with the leader resolved", function()
    local original = vim.g.mapleader
    vim.g.mapleader = ";"

    local lines = keymap_help.float_lines "comment_popup"
    local joined = table.concat(lines, "\n")

    vim.g.mapleader = original

    local first_words = {}
    for _, line in ipairs(lines) do
      first_words[line:match "%S+"] = true
    end

    eq(true, first_words["<C-s>"] == true)
    eq(true, first_words[";op"] == true)
    eq(true, first_words["q"] == true)
    eq(true, first_words["<C-c>"] == true)
    eq(false, joined:find("<leader>", 1, true) ~= nil)
    eq(true, joined:find("send this comment", 1, true) ~= nil)
    eq(true, joined:find("close, keeping a draft", 1, true) ~= nil)
  end)
end)
