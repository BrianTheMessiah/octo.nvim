local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local octo_config = require "octo.config"
local utils = require "octo.utils"
local keymap_help = require "octo.ui.keymap-help"
local M = {}

---@param formatted_items table<string, table> entry.ordinal -> entry
---@return table<string, function>
function M.common_buffer_actions(formatted_items)
  return {
    ["default"] = function(selected)
      picker_utils.open("default", formatted_items[selected[1]])
    end,
    ["ctrl-v"] = function(selected)
      picker_utils.open("vertical", formatted_items[selected[1]])
    end,
    ["ctrl-s"] = function(selected)
      picker_utils.open("horizontal", formatted_items[selected[1]])
    end,
    ["ctrl-t"] = function(selected)
      picker_utils.open("tab", formatted_items[selected[1]])
    end,
  }
end

---@param formatted_items table<string, table> entry.ordinal -> entry
---@return table<string, function>
function M.common_open_actions(formatted_items)
  local cfg = octo_config.values
  return vim.tbl_extend("force", M.common_buffer_actions(formatted_items), {
    [utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.open_in_browser.lhs)] = function(selected)
      picker_utils.open_in_browser(formatted_items[selected[1]])
    end,
    [utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.copy_url.lhs)] = function(selected)
      picker_utils.copy_url(formatted_items[selected[1]])
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
