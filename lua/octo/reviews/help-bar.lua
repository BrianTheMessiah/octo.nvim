local config = require "octo.config"
local keymap_help = require "octo.ui.keymap-help"

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

M.CUT = keymap_help.CUT
M.terse = keymap_help.terse
M.pretty_lhs = keymap_help.pretty_lhs
M.truncate = keymap_help.truncate

--- The keys one review context has, in the order the bar draws them.
---@param kind string the review kind, one of `M.LABELS`' keys
---@param handlers table<string, function>|nil the action handlers; octo's own when omitted
---@return { action: string, lhs: string, label: string }[]
function M.entries(kind, handlers)
  handlers = handlers or require "octo.mappings"
  return keymap_help.entries_from(config.values.mappings[kind] or {}, M.ORDER[kind] or {}, handlers)
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

--- The keys that fit, joined, each one drawn whole.
---
--- Stops at the first key too wide to finish rather than cutting through one,
--- because half a label reads as a different action. Grown one key at a time so
--- the columns are counted once per key rather than once per character of a line
--- most of which is about to be thrown away -- this runs on every redraw.
---@param parts string[] each key with its label, in the order they are drawn
---@param width integer columns available for the keys
---@return string
local function keys_that_fit(parts, width)
  local separator = "  "
  local tail = #separator + vim.fn.strdisplaywidth(M.CUT)
  local kept, used = {}, 0

  for _, part in ipairs(parts) do
    local cost = vim.fn.strdisplaywidth(part) + (#kept > 0 and #separator or 0)
    if used + cost > width then
      while #kept > 0 and used + tail > width do
        local dropped = table.remove(kept)
        used = used - vim.fn.strdisplaywidth(dropped) - (#kept > 0 and #separator or 0)
      end
      if #kept == 0 then
        return M.truncate(parts[1], width)
      end
      return table.concat(kept, separator) .. separator .. M.CUT
    end
    kept[#kept + 1] = part
    used = used + cost
  end

  return table.concat(kept, separator)
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

  local opening = (" %s   "):format(M.LABELS[kind] or kind)
  local room = width - vim.fn.strdisplaywidth(opening)
  if room < 1 then
    return (M.truncate(opening, width):gsub("%%", "%%%%"))
  end

  return ((opening .. keys_that_fit(parts, room)):gsub("%%", "%%%%"))
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
