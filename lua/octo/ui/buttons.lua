---The actions each section of an octo buffer offers, and how they are drawn.
---
---Drawn as `virt_lines`, which is why every button carries the key that fires it: a
---virtual line is not buffer content, so the cursor can never be placed on one and no
---mapping can act on "the button under the cursor". The mouse can reach them, and a
---reader who is not using one reads the key off the button and presses it. `<CR>` is
---in any case already `pr_options` and `issue_options`.
---
---`rows` and `line` are pure and are where the whole vocabulary lives, so the button
---set for every capability combination is asserted without a buffer.
local config = require "octo.config"
local keymap_help = require "octo.ui.keymap-help"

local M = {}

---@class octo.Button
---@field label string what the button says
---@field action string the mapping action it fires
---@field lhs string the key, with any leader placeholder already resolved
---@field hl string the highlight group the button is drawn in

---@class octo.ButtonCaps
---@field viewer_can_update boolean? whether the viewer may edit or delete this section
---@field is_resolved boolean? whether a review thread is resolved

---The section kinds that have buttons.
M.KINDS = {
  body = true,
  comment = true,
  thread = true,
  footer = true,
}

---The highlight group a button is drawn in.
M.GROUP = "OctoButton"

---Which mapping table each section kind reads its keys from.
---
---A thread's keys are the review thread ones; everything else in a conversation
---buffer takes the issue table, which pull requests and discussions share.
local TABLES = {
  body = "issue",
  comment = "issue",
  thread = "review_thread",
  footer = "issue",
}

---The buttons each section kind offers, before capabilities are applied.
---
---`when` is the capability test; a button with no `when` is always offered.
local VOCABULARY = {
  body = {
    { label = "+ Comment", action = "add_comment" },
    { label = "React", action = "react_thumbs_up" },
    {
      label = "Edit",
      action = "edit",
      when = function(caps)
        return caps.viewer_can_update == true
      end,
    },
  },
  comment = {
    { label = "Reply", action = "add_reply" },
    { label = "React", action = "react_thumbs_up" },
    {
      label = "Delete",
      action = "delete_comment",
      when = function(caps)
        return caps.viewer_can_update == true
      end,
    },
  },
  thread = {
    { label = "Reply", action = "add_reply" },
    {
      label = "Resolve",
      action = "resolve_thread",
      when = function(caps)
        return caps.is_resolved ~= true
      end,
    },
    {
      label = "Unresolve",
      action = "unresolve_thread",
      when = function(caps)
        return caps.is_resolved == true
      end,
    },
    { label = "React", action = "react_thumbs_up" },
  },
  footer = {
    { label = "+ New Comment", action = "add_comment" },
    { label = "Reload", action = "reload" },
  },
}

---The key an action is bound to in a section kind's mapping table.
---
---`edit` has no mapping of its own -- editing a body in octo is done by typing in the
---buffer and saving it -- so it is labelled with the write command instead.
---@param kind string the section kind
---@param action string the action's name
---@return string? lhs nil when nothing is bound
local function key_for(kind, action)
  if action == "edit" then
    return ":w"
  end
  local mappings = config.values.mappings[TABLES[kind]] or {}
  local mapping = mappings[action]
  if not mapping or not mapping.lhs or mapping.lhs == "" then
    return nil
  end
  return keymap_help.pretty_lhs(mapping.lhs)
end

---Whether buttons are wanted, per `ui.section_buttons`.
---@return boolean true unless the option is explicitly false
function M.enabled()
  return config.values.ui.section_buttons ~= false
end

---The buttons one section offers.
---
---A button whose action has no key bound is dropped rather than drawn keyless: the
---key is the whole of how a reader without a mouse fires it.
---@param kind string one of `M.KINDS`' keys
---@param caps octo.ButtonCaps what the viewer may do to this section
---@return octo.Button[]
function M.rows(kind, caps)
  caps = caps or {}
  if not M.KINDS[kind] then
    return {}
  end

  local row = {}
  for _, entry in ipairs(VOCABULARY[kind] or {}) do
    if not entry.when or entry.when(caps) then
      local lhs = key_for(kind, entry.action)
      if lhs then
        row[#row + 1] = { label = entry.label, action = entry.action, lhs = lhs, hl = M.GROUP }
      end
    end
  end
  return row
end

---A button row as a `virt_lines` chunk list.
---
---Each button is one chunk so a click can be resolved to a button by counting display
---columns across the chunks, and the separators are chunks of their own so they are
---never mistaken for part of a label.
---@param row octo.Button[] the buttons, in the order they are drawn
---@return { [1]: string, [2]: string }[] chunks empty when there are no buttons
function M.line(row)
  local chunks = {}
  for index, button in ipairs(row or {}) do
    chunks[#chunks + 1] = { index == 1 and "  " or "  ", "Normal" }
    chunks[#chunks + 1] = { ("[ %s %s ]"):format(button.label, button.lhs), button.hl }
  end
  return chunks
end

return M
