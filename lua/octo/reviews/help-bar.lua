local config = require "octo.config"
local utils = require "octo.utils"

local M = {}

--- The short name each review context wears on the bar.
---
--- One word, so the keys keep the rest of the line. The four kinds are exactly
--- the ones review mode calls `utils.apply_mappings` with.
M.LABELS = {
  review_diff = "diff",
  review_thread = "thread",
  file_panel = "files",
  submit_win = "submit",
}

--- The order each context's keys are drawn in, most useful first.
---
--- The bar is truncated to the window it is drawn on, so what comes first is
--- what survives a narrow window. Actions the config has that are not named
--- here are drawn after these, sorted, so a mapping added upstream still shows.
M.ORDER = {
  review_diff = {
    "submit_review",
    "discard_review",
    "add_review_comment",
    "add_review_suggestion",
    "next_thread",
    "prev_thread",
    "toggle_viewed",
    "select_next_entry",
    "select_prev_entry",
    "select_next_unviewed_entry",
    "select_prev_unviewed_entry",
    "focus_files",
    "toggle_files",
    "review_commits",
    "goto_file",
    "copy_sha",
    "select_first_entry",
    "select_last_entry",
    "close_review_tab",
  },
  review_thread = {
    "add_comment",
    "add_reply",
    "add_suggestion",
    "resolve_thread",
    "unresolve_thread",
    "delete_comment",
    "next_comment",
    "prev_comment",
    "comment_edits",
    "reference_in_new_issue",
    "goto_issue",
    "select_next_entry",
    "select_prev_entry",
    "select_next_unviewed_entry",
    "select_prev_unviewed_entry",
    "select_first_entry",
    "select_last_entry",
    "close_review_tab",
  },
  file_panel = {
    "select_entry",
    "next_entry",
    "prev_entry",
    "toggle_viewed",
    "submit_review",
    "discard_review",
    "refresh_files",
    "select_next_unviewed_entry",
    "select_prev_unviewed_entry",
    "toggle_files",
    "focus_files",
    "review_commits",
    "select_next_entry",
    "select_prev_entry",
    "select_first_entry",
    "select_last_entry",
    "close_review_tab",
  },
  submit_win = {
    "approve_review",
    "comment_review",
    "request_changes",
    "close_review_tab",
  },
}

--- An action's name as the bar labels it.
---
--- The whole bar is the review bar, so the word `review` inside an action name
--- is repeated noise on the one surface short of room.
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

--- A mapping's left-hand side as the reader has to type it.
---
--- The config writes `<localleader>vs`; what the key actually is depends on the
--- leader in force, and a bar that echoed the placeholder would be teaching a
--- keystroke nobody can press.
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

--- The action names of one context in the order the bar draws them.
---@param kind string the review kind, one of `M.LABELS`' keys
---@param mappings table<string, table> the kind's mapping table from the config
---@return string[]
local function ordered_actions(kind, mappings)
  local actions, listed = {}, {}
  for _, action in ipairs(M.ORDER[kind] or {}) do
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
  return actions
end

--- The keys one review context has, in the order the bar draws them.
---
--- Mirrors `utils.apply_mappings`' own test for whether a mapping was made, so
--- the bar can never advertise a key that nothing bound.
---@param kind string the review kind, one of `M.LABELS`' keys
---@param handlers table<string, function>|nil the action handlers; octo's own when omitted
---@return { action: string, lhs: string, label: string }[]
function M.entries(kind, handlers)
  handlers = handlers or require "octo.mappings"
  local mappings = config.values.mappings[kind] or {}

  local entries = {}
  for _, action in ipairs(ordered_actions(kind, mappings)) do
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

--- The buffer variable a review buffer's context is recorded under.
M.VARIABLE = "octo_review_help_kind"

--- The highlight group the whole bar is drawn in.
M.GROUP = "OctoReviewHelpBar"

--- What a window's `winbar` is set to, so the bar is rebuilt on every redraw
--- and follows both the focused context and the window's current width.
M.EXPRESSION = "%!v:lua.require'octo.reviews.help-bar'.winbar()"

--- Records which review context a buffer's keys were bound from.
---
--- Called where octo applies the mappings, so the bar and the keys are read off
--- the same `kind` and cannot drift apart. Contexts outside review mode are
--- ignored: the bar has nothing to say about them.
---@param bufnr integer the buffer the mappings were applied to
---@param kind string the mapping kind they came from
function M.remember(bufnr, kind)
  if M.LABELS[kind] and vim.api.nvim_buf_is_valid(bufnr) then
    vim.b[bufnr][M.VARIABLE] = kind
  end
end

--- The review context a buffer's keys came from, if it has one.
---@param bufnr integer the buffer to ask about
---@return string|nil kind one of `M.LABELS`' keys
function M.kind(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  local kind = vim.b[bufnr][M.VARIABLE]
  return M.LABELS[kind] and kind or nil
end

--- Text cut to fit, with a mark where it was cut.
---
--- Measured in display columns, because the leader and any key drawn through it
--- can be more than one byte wide and a byte count would cut the line early.
---@param text string the finished line, however long it came out
---@param width integer columns available
---@return string
function M.truncate(text, width)
  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end

  local mark = "…"
  local room = width - vim.fn.strdisplaywidth(mark)
  if room < 1 then
    return vim.fn.strcharpart(text, 0, width)
  end

  local chars = vim.fn.strchars(text)
  while chars > 0 and vim.fn.strdisplaywidth(vim.fn.strcharpart(text, 0, chars)) > room do
    chars = chars - 1
  end
  return vim.fn.strcharpart(text, 0, chars) .. mark
end

--- The bar's single line for one review context.
---
--- Pure, so the wording, the ordering and the truncation are all asserted
--- without opening a window.
---@param kind string the review kind, one of `M.LABELS`' keys
---@param width integer columns available
---@param handlers table<string, function>|nil the action handlers; octo's own when omitted
---@return string a statusline expression with every percent escaped
function M.line(kind, width, handlers)
  local parts = {}
  for _, entry in ipairs(M.entries(kind, handlers)) do
    parts[#parts + 1] = ("%s %s"):format(entry.lhs, entry.label)
  end

  if #parts == 0 then
    parts[1] = "no keys mapped"
  end

  local text = (" %s   %s"):format(M.LABELS[kind] or kind, table.concat(parts, "  "))
  return (M.truncate(text, width):gsub("%%", "%%%%"))
end

--- The bar as the window it hangs on redraws it.
---
--- The context comes from the window in focus rather than from the window the
--- bar is drawn on, so one bar at the foot of the review serves the diff, the
--- thread and the submit window as the reviewer moves between them. When focus
--- has left review mode entirely it falls back to the bar's own window, whose
--- keys are true wherever the cursor is.
---@return string a winbar expression, empty when there is no review context to describe
function M.winbar()
  local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then
    return ""
  end

  local kind = M.kind(vim.api.nvim_get_current_buf()) or M.kind(vim.api.nvim_win_get_buf(win))
  if not kind then
    return ""
  end

  return ("%%#%s#%s"):format(M.GROUP, M.line(kind, vim.api.nvim_win_get_width(win)))
end

--- Dims the bar, unless something has already said how it should look.
---
--- Defined here rather than in `octo.ui.colors`, which skips any group that
--- already exists -- and naming a group in a statusline expression brings it
--- into existence with nothing in it, so a group left to that setup renders as
--- plain bold `WinBar` text. Emptiness is the test rather than existence, so
--- calling this twice is free and a colourscheme's own definition still wins.
function M.highlight()
  if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = M.GROUP })) then
    vim.api.nvim_set_hl(0, M.GROUP, { link = "Comment" })
  end
end

--- Hangs the bar on a window.
---
--- A window option, so the bar goes when the window goes and an abandoned
--- review leaves nothing to clean up. `winbar` is global-local, and the local
--- scope is named rather than left to a default so the global value stays empty
--- and no window outside the review inherits a bar.
---@param win integer the window to draw the bar on
function M.attach(win)
  if vim.api.nvim_win_is_valid(win) then
    M.highlight()
    vim.api.nvim_set_option_value("winbar", M.EXPRESSION, { win = win, scope = "local" })
  end
end

return M
