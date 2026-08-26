local new_pull_request = require "octo.pickers.fzf-lua.new_pull_request"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local octo_config = require "octo.config"
local utils = require "octo.utils"
local keymap_help = require "octo.ui.keymap-help"
local M = {}

---@param formatted_items table<string, table> entry.ordinal -> entry
---@return table<string, function>
function M.common_buffer_actions(formatted_items)
  ---Opens the chosen entry, or the new-pull-request row when that is what was chosen.
  ---
  ---`formatted_items` has no entry for that row, so opening it the ordinary way would
  ---hand `nil` to `picker_utils.open`. Every way of opening goes through here, so the row
  ---works from `<CR>` and from the split, vsplit and tab keys alike.
  ---@param how string the window `picker_utils.open` should use
  ---@return fun(selected: string[])
  local function open(how)
    return function(selected)
      if new_pull_request.is(selected and selected[1]) then
        return new_pull_request.run()
      end
      picker_utils.open(how, formatted_items[selected[1]])
    end
  end

  return {
    ["default"] = open "default",
    ["ctrl-v"] = open "vertical",
    ["ctrl-s"] = open "horizontal",
    ["ctrl-t"] = open "tab",
  }
end

---@param formatted_items table<string, table> entry.ordinal -> entry
---@return table<string, function>
function M.common_open_actions(formatted_items)
  local cfg = octo_config.values
  return vim.tbl_extend("force", M.common_buffer_actions(formatted_items), {
    -- Browsing to a row that is not a pull request, or copying its URL, has nothing to
    -- do. Doing nothing beats reaching into an entry that was never there.
    [utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.open_in_browser.lhs)] = function(selected)
      if not new_pull_request.is(selected and selected[1]) then
        picker_utils.open_in_browser(formatted_items[selected[1]])
      end
    end,
    [utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.copy_url.lhs)] = function(selected)
      if not new_pull_request.is(selected and selected[1]) then
        picker_utils.copy_url(formatted_items[selected[1]])
      end
    end,
  })
end

---The one action every octo picker adds: open the list of keys it has.
---
---Scheduled, because fzf-lua is still tearing its own window down when the action
---runs and a float opened inside that teardown is closed with it.
---@return table<string, function>
function M.help_action()
  return {
    [utils.convert_vim_mapping_to_fzf(keymap_help.PICKER_HELP_KEY)] = function()
      vim.schedule(function()
        keymap_help.float "picker"
      end)
    end,
  }
end

return M
