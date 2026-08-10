---The keys a context has, and how they are named wherever they are shown.
---
---Four surfaces need this and they share nothing but the formatting: review mode's
---winbar, an octo buffer's winbar, a comment popup's float footer, and an fzf header.
---What differs is the geometry and which mapping table is being read; what is the same
---is how an action is named, how a leader placeholder is resolved into a key the
---reader can actually press, and how a line is cut when there is not room for it.
local utils = require "octo.utils"

local M = {}

---The mark that says there was more to show than there was room for.
M.CUT = "…"

---The symbol that marks the keymap help section.
---
---Built with `nr2char` for the same reason the spinner frames are: a glyph that
---arrives as an empty string leaves a section that is nothing but a separator.
M.SYMBOL = vim.fn.nr2char(0x2328)

---The key that opens the keymap float in a buffer or a popup.
---
---`g?` rather than `?`, which is backwards-search in a buffer the reader can edit,
---and rather than `q`, which a popup already binds to close.
M.HELP_KEY = "g?"

---The key that opens the keymap float from a picker.
---
---`<C-g>` is free against every entry in `picker_config.mappings`.
M.PICKER_HELP_KEY = "<C-g>"

---An action's name as a bar labels it.
---
---The word `review` inside an action name is repeated noise on a surface that is
---already the review bar, and is short of room besides.
---@param action string the action's name, as the mapping config keys it
---@return string
function M.terse(action)
  local words = {}
  for word in action:gmatch "[^_]+" do
    if word ~= "review" then
      words[#words + 1] = word
    end
  end
  return table.concat(words, " ")
end

---A mapping's left-hand side as the reader has to type it.
---
---The config writes `<localleader>vs`; what the key actually is depends on the leader
---in force, and a bar that echoed the placeholder would be teaching a keystroke
---nobody can press.
---@param lhs string the left-hand side as the mapping config holds it
---@return string
function M.pretty_lhs(lhs)
  local resolved = lhs:gsub("<[Ll]ocal[Ll]eader>", function()
    return vim.g.maplocalleader or "\\"
  end)
  return (resolved:gsub("<[Ll]eader>", function()
    return vim.g.mapleader or "\\"
  end))
end

---Text cut to fit, with the mark where it was cut.
---
---Measured in display columns, because the leader and any key drawn through it can be
---more than one byte wide and a byte count would cut the line early.
---@param text string the text, however long it came out
---@param width integer columns available
---@return string
function M.truncate(text, width)
  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end

  local room = width - vim.fn.strdisplaywidth(M.CUT)
  if room < 1 then
    return vim.fn.strcharpart(text, 0, width)
  end

  local chars = vim.fn.strchars(text)
  while chars > 0 and vim.fn.strdisplaywidth(vim.fn.strcharpart(text, 0, chars)) > room do
    chars = chars - 1
  end
  return vim.fn.strcharpart(text, 0, chars) .. M.CUT
end

---The keys a mapping table has, in the order they should be drawn.
---
---Mirrors `utils.apply_mappings`' own test for whether a mapping was made, so no
---surface can ever advertise a key that nothing bound. Actions named in `order` come
---first, in that order; anything else follows, sorted, so a mapping added upstream
---still shows.
---@param mappings table<string, table> a mapping table from the config
---@param order string[] the actions to draw first, most useful first
---@param handlers table<string, function> the action handlers
---@return { action: string, lhs: string, label: string }[]
function M.entries_from(mappings, order, handlers)
  local listed, actions = {}, {}
  for _, action in ipairs(order or {}) do
    if mappings[action] and not listed[action] then
      actions[#actions + 1] = action
      listed[action] = true
    end
  end

  local rest = {}
  for action in pairs(mappings) do
    if not listed[action] then
      rest[#rest + 1] = action
    end
  end
  table.sort(rest)
  vim.list_extend(actions, rest)

  local entries = {}
  for _, action in ipairs(actions) do
    local mapping = mappings[action]
    if not utils.is_blank(mapping) and not utils.is_blank(mapping.lhs) and not utils.is_blank(handlers[action]) then
      entries[#entries + 1] = {
        action = action,
        lhs = M.pretty_lhs(mapping.lhs),
        label = M.terse(action),
      }
    end
  end
  return entries
end

---The keymap help section, set off from whatever is drawn beside it.
---
---A section of its own rather than another key on the end of the list: it is the one
---entry that is about the list itself, and it must survive being the last thing that
---fits.
---@return string
function M.section()
  return ("%s %s keys"):format(M.SYMBOL, M.HELP_KEY)
end

return M
