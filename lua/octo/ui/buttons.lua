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

---@class octo.ButtonSection
---@field kind string one of `M.KINDS`' keys
---@field last_line integer 1-based buffer line the row is drawn below
---@field caps octo.ButtonCaps what the viewer may do to this section

local namespace = vim.api.nvim_create_namespace "octo_buttons"

---The extmark namespace the button rows are drawn in.
---@return integer
function M.namespace()
  return namespace
end

---What each drawn row holds, keyed by buffer then by the row's zero-based anchor.
---
---Kept so a click can be resolved without rebuilding the vocabulary: the chunks are
---what was actually drawn, and the columns must be measured against those rather than
---against what `rows` would return now.
---@type table<integer, table<integer, { chunks: table, row: octo.Button[] }>>
local drawn = {}

---Draw a button row under each section.
---@param bufnr integer the octo buffer
---@param sections octo.ButtonSection[] the sections to draw under
---@return boolean drawn false when buttons are off or the buffer is gone
function M.render(bufnr, sections)
  if not M.enabled() or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  drawn[bufnr] = {}

  local total = vim.api.nvim_buf_line_count(bufnr)
  for _, section in ipairs(sections or {}) do
    local anchor = (section.last_line or 0) - 1
    if anchor >= 0 and anchor < total then
      local row = M.rows(section.kind, section.caps)
      local chunks = M.line(row)
      if #chunks > 0 then
        local ok = pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace, anchor, 0, {
          virt_lines = { chunks },
          virt_lines_above = false,
        })
        if ok then
          drawn[bufnr][anchor] = { chunks = chunks, row = row }
        end
      end
    end
  end

  return true
end

---The button a display column falls inside.
---
---Measured in display columns across the chunks in order, because a label can hold a
---glyph wider than one cell and a byte count would find the wrong button. The row the
---chunks were drawn from is passed in rather than rebuilt, because `rows` reads the
---live config and a mapping changed since the draw would return a different set.
---@param chunks { [1]: string, [2]: string }[] the chunks as drawn
---@param column integer zero-based display column within the virtual line
---@param row octo.Button[]|nil the buttons those chunks were drawn from
---@return octo.Button? button nil when the column is in a gap or past the end
function M.hit(chunks, column, row)
  local at = 0
  local index = 0
  for _, chunk in ipairs(chunks or {}) do
    local width = vim.fn.strdisplaywidth(chunk[1])
    if chunk[2] ~= "Normal" then
      index = index + 1
      if column >= at and column < at + width then
        return row and row[index] or { index = index }
      end
    end
    at = at + width
  end
  return nil
end

---Fire the button under the mouse.
---
---A `virt_lines` row has no buffer position of its own, so the row is found by
---subtracting the anchor line's screen row from the click's: `getmousepos` reports the
---nearest real line, which for a click on a virtual line is the line it hangs from.
function M.click()
  local pos = vim.fn.getmousepos()
  local win, bufnr = pos.winid, vim.api.nvim_win_get_buf(pos.winid)
  local rows = drawn[bufnr]
  if not rows or pos.line < 1 then
    return
  end

  local anchor = pos.line - 1
  local entry = rows[anchor]
  if not entry then
    return
  end

  local anchor_screen = vim.fn.screenpos(win, pos.line, 1)
  if anchor_screen.row == 0 or pos.screenrow <= anchor_screen.row then
    return
  end

  local target = M.hit(entry.chunks, pos.wincol - 1, entry.row)
  if not target then
    return
  end

  local handlers = require "octo.mappings"
  local handler = handlers[target.action]
  if type(handler) == "function" then
    vim.api.nvim_win_set_cursor(win, { pos.line, 0 })
    handler()
  end
end

return M
