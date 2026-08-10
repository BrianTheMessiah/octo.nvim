---@diagnostic disable
local eq = assert.are.same

local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"
local keymap_help = require "octo.ui.keymap-help"
local utils = require "octo.utils"

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
end)
