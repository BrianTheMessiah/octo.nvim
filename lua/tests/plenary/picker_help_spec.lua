---@diagnostic disable
local eq = assert.are.same

local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"
local keymap_help = require "octo.ui.keymap-help"
local utils = require "octo.utils"
local prs = require "octo.pickers.fzf-lua.pickers.prs"
local issues = require "octo.pickers.fzf-lua.pickers.issues"

local help_key = utils.convert_vim_mapping_to_fzf(keymap_help.PICKER_HELP_KEY)

describe("octo picker help:", function()
  it("puts the symbol and its key in the header", function()
    local header = picker_utils.help_header()

    eq(true, header:find(keymap_help.SYMBOL, 1, true) ~= nil)
    eq(true, header:find("ctrl-g", 1, true) ~= nil or header:find("<C-g>", 1, true) ~= nil)
  end)

  it("sets the header off in a section of its own", function()
    eq(true, picker_utils.help_header():find(vim.fn.nr2char(0x2502), 1, true) ~= nil)
  end)

  it("binds the help key in the fzf form fzf-lua expects", function()
    local action = fzf_actions.help_action()
    local key = utils.convert_vim_mapping_to_fzf(keymap_help.PICKER_HELP_KEY)

    eq(true, action[key] ~= nil)
    eq("function", type(action[key]))
  end)

  it("lists the picker's own keys, not a buffer's", function()
    local joined = table.concat(keymap_help.float_lines "picker", "\n")

    eq(true, joined:find("open in browser", 1, true) ~= nil or joined:find("browser", 1, true) ~= nil)
  end)

  describe("the PR list's own tables", function()
    it("carries the shared help header in the real fzf_opts it hands fzf", function()
      eq(picker_utils.help_header(), prs.fzf_opts()["--header"])
    end)

    it("binds a working help key in the real actions table it hands fzf", function()
      local actions = prs.list_actions({}, {}, "owner/repo", nil, nil)

      eq("function", type(actions[help_key]))
    end)
  end)

  describe("the issue list's own tables", function()
    it("carries the shared help header in the real fzf_opts it hands fzf", function()
      eq(picker_utils.help_header(), issues.fzf_opts()["--header"])
    end)

    it("binds a working help key when the list is opened for browsing", function()
      local actions = issues.list_actions({}, nil)

      eq("function", type(actions[help_key]))
    end)

    it("binds a working help key when the list is opened to choose one issue for a caller", function()
      local actions = issues.list_actions({}, function() end)

      eq("function", type(actions[help_key]))
    end)

    it("still hands the chosen issue to the caller's callback, help key aside", function()
      local chosen
      local actions = issues.list_actions({ ["some-ordinal"] = { title = "picked" } }, function(entry)
        chosen = entry
      end)

      actions["default"] { "some-ordinal" }

      eq({ title = "picked" }, chosen)
    end)
  end)
end)
