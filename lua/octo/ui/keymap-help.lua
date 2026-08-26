---The keys a context has, and how they are named wherever they are shown.
---
---Four surfaces need this and they share nothing but the formatting: review mode's
---winbar, an octo buffer's winbar, a comment popup's float footer, and an fzf header.
---What differs is the geometry and which mapping table is being read; what is the same
---is how an action is named, how a leader placeholder is resolved into a key the
---reader can actually press, and how a line is cut when there is not room for it.
local config = require "octo.config"
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

---What an action is called where its own name does not say what it does.
---
---A label is derived from the action's name, which works for `add_comment` and does not
---work for `review_start`: stripping `review` leaves `start`, and `start` beside `resume`
---in a pull request's key list says nothing about what either one starts. Asked directly:
---"what does start and resume mean here, please be more specific".
---
---What they are, from `reviews/init.lua`: `start` sends `addPullRequestReview` and opens
---the diff on a review that did not exist a moment ago; `resume` looks for the pending
---review you already have, and says "No pending reviews found for viewer" when there is
---none. So one of them makes a review and the other finds yours.
M.PHRASES = {
  review_start = "start a new review",
  review_resume = "reopen your pending review",
  review_submit = "submit your review",
  review_discard = "discard your pending review",
}

---An action's name as a bar labels it.
---
---`M.PHRASES` first, for the ones a derived name gets wrong. Otherwise the word `review`
---inside an action name is repeated noise on a surface that is already the review bar,
---and is short of room besides.
---@param action string the action's name, as the mapping config keys it
---@return string
function M.terse(action)
  if M.PHRASES[action] then
    return M.PHRASES[action]
  end
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

---The buffer variable a buffer's mapping kind is recorded under.
M.VARIABLE = "octo_keymap_help_kind"

---The highlight group the bar is drawn in.
M.GROUP = "OctoKeymapHelpBar"

---What a window's `winbar` is set to, so the bar is rebuilt on every redraw and
---follows the window's current width.
M.EXPRESSION = "%!v:lua.require'octo.ui.keymap-help'.winbar()"

---The order each buffer kind's keys are drawn in, most useful first.
---
---The bar is truncated to the window, so what comes first is what survives a narrow
---one. Actions the config has that are not named here are drawn after these, sorted,
---so a mapping added upstream still shows.
M.ORDER = {
  issue = {
    "add_comment",
    "edit_comment",
    "add_reply",
    "react_thumbs_up",
    "close_issue",
    "reload",
    "open_in_browser",
    "close_buffer",
  },
  -- `review_start` first, and that is the whole of a reported gap rather than a preference. It
  -- was already in this list -- every mapping the config has that is not named here is appended,
  -- sorted -- but 42nd out of 47, which on a truncated bar is never and in the float is a
  -- haystack. Starting a review is the thing a pull request buffer is opened FOR.
  pull = {
    "review_start",
    "review_resume",
    "add_comment",
    "edit_comment",
    "add_reply",
    "checkout_pr",
    "list_changed_files",
    "merge_pr",
    "reload",
    "open_in_browser",
    "close_buffer",
  },
  discussion = {
    "add_comment",
    "edit_comment",
    "add_reply",
    "react_thumbs_up",
    "reload",
    "open_in_browser",
    "close_buffer",
  },
  -- A review thread had no order at all, so its keys were drawn alphabetically -- which put
  -- `add_suggestion` third and `resolve_thread` twentieth on the one surface where resolving is
  -- the point. These are what a reader does IN a thread, in the order they do them.
  review_thread = {
    "add_reply",
    "edit_comment",
    "add_suggestion",
    "resolve_thread",
    "unresolve_thread",
    "select_next_entry",
    "select_prev_entry",
    "close_review_tab",
  },
  repo = { "reload", "open_in_browser", "copy_url", "close_buffer" },
  release = { "reload", "open_in_browser", "copy_url", "close_buffer" },
}

---How a buffer kind is named on the bar.
M.LABELS = {
  issue = "issue",
  pull = "pull",
  discussion = "discussion",
  repo = "repo",
  release = "release",
  comment_popup = "comment",
  picker = "picker",
}

---The `config.values.mappings` key a buffer kind's keys actually sit under.
---
---`OctoBuffer.kind` is not that key: a pull request buffer's kind is `pull` and its
---mappings are `mappings.pull_request`. `OctoBuffer:apply_mappings` makes the same
---translation to bind them; read the kind straight instead and the bar reports no keys
---for the one buffer this surface was built for. Kinds absent here are their own key.
M.CONFIG_KEY = {
  pull = "pull_request",
  reviewthread = "review_thread",
}

---The keys a surface binds in code rather than reading from the mapping config.
---
---A comment popup binds its own keys in `octo.ui.comment-popup`, so there is no
---`config.values.mappings` table to build entries from and the float would otherwise
---have nothing to show.
M.LITERAL = {
  comment_popup = {
    { action = "submit", lhs = "<C-s>", label = "send this comment" },
    { action = "submit_leader", lhs = "<leader>op", label = "send this comment" },
    { action = "cancel", lhs = "q", label = "close, keeping a draft" },
    { action = "cancel_ctrl", lhs = "<C-c>", label = "close, keeping a draft" },
  },
}

---The keys one kind has, in the order they are drawn.
---@param kind string a key of `M.ORDER`, or any mappings table name
---@param handlers table<string, function>|nil the action handlers; octo's own when omitted
---@return { action: string, lhs: string, label: string }[]
function M.entries(kind, handlers)
  if M.LITERAL[kind] then
    local entries = {}
    for _, entry in ipairs(M.LITERAL[kind]) do
      entries[#entries + 1] = {
        action = entry.action,
        lhs = M.pretty_lhs(entry.lhs),
        label = entry.label,
      }
    end
    return entries
  end
  if kind == "picker" then
    local entries = {}
    for action, mapping in pairs(config.values.picker_config.mappings or {}) do
      if not utils.is_blank(mapping) and not utils.is_blank(mapping.lhs) then
        entries[#entries + 1] = {
          action = action,
          lhs = M.pretty_lhs(mapping.lhs),
          label = mapping.desc or M.terse(action),
        }
      end
    end
    table.sort(entries, function(a, b)
      return a.action < b.action
    end)
    return entries
  end
  handlers = handlers or require "octo.mappings"
  local mappings = config.values.mappings[M.CONFIG_KEY[kind] or kind] or {}
  return M.entries_from(mappings, M.ORDER[kind] or {}, handlers)
end

---The surfaces a reviewer meets a pending comment on.
---
---All three, because the sequence can be started from any of them: the diff is where a
---comment is added, a thread is where one is replied to, and the submit window is the step
---people are looking for when they go hunting for the help in the first place.
M.NOTED = {
  review_diff = true,
  review_thread = true,
  submit_win = true,
}

---A configured mapping's key, drawn the way the reader has to type it.
---@param group string the `config.values.mappings` group
---@param action string the action within it
---@return string|nil nil when nothing is bound
local function bound(group, action)
  local mapping = (config.values.mappings[group] or {})[action]
  local lhs = type(mapping) == "table" and mapping.lhs or nil
  if lhs == nil or lhs == "" then
    return nil
  end
  return M.pretty_lhs(lhs)
end

---What a list of keys cannot say on its own.
---
---A review comment is *pending*. Writing the buffer records it locally; it reaches GitHub,
---and the author, only when the review itself is submitted. That is two steps, and the key
---list cannot express it -- both steps read as ordinary independent keys, so stopping
---after the first looks finished and is the mistake the list invites.
---
---The keys are read from the configuration rather than written out here, so a rebound key
---is named correctly and a note can never drift from what is actually bound.
---@param kind string the mapping kind being described
---@return string[] lines empty for a kind with nothing extra to say
function M.note_lines(kind)
  if not M.NOTED[kind] then
    return {}
  end

  local add = bound("review_diff", "add_review_comment")
  local reply = bound("review_thread", "add_reply")
  local submit = bound("review_diff", "submit_review")
  local approve = bound("submit_win", "approve_review")
  local comment = bound("submit_win", "comment_review")
  local request = bound("submit_win", "request_changes")

  local verdicts = {}
  for _, pair in ipairs { { approve, "approve" }, { comment, "comment" }, { request, "request changes" } } do
    if pair[1] then
      verdicts[#verdicts + 1] = ("%s %s"):format(pair[1], pair[2])
    end
  end

  -- Appended one at a time rather than built as a constructor with `nil` holes in it,
  -- which would leave `#lines` undefined.
  local lines = { "", " a comment is pending until the review is submitted" }
  local step = 0
  local function say(text)
    step = step + 1
    lines[#lines + 1] = (" %d. %s"):format(step, text)
  end

  local start = add or reply
  if start then
    say(("%s writes it, and it stays on this machine"):format(start))
  end
  if submit then
    say(("%s opens the submit window"):format(submit))
  end
  if #verdicts > 0 then
    say(table.concat(verdicts, " · "))
  end
  return lines
end

---The float's content: every key a kind has, one to a line, and what the keys leave out.
---@param kind string the mapping kind to describe
---@param handlers table<string, function>|nil the action handlers; octo's own when omitted
---@return string[] lines at least one, never empty
function M.float_lines(kind, handlers)
  local entries = M.entries(kind, handlers)
  if #entries == 0 then
    return { (" no keys mapped for %s"):format(kind) }
  end

  local widest = 0
  for _, entry in ipairs(entries) do
    widest = math.max(widest, vim.fn.strdisplaywidth(entry.lhs))
  end

  local lines = {}
  for _, entry in ipairs(entries) do
    local pad = string.rep(" ", widest - vim.fn.strdisplaywidth(entry.lhs))
    lines[#lines + 1] = (" %s%s   %s"):format(entry.lhs, pad, entry.label)
  end

  -- Below the keys, never instead of them: the note explains a sequence the keys are part
  -- of, so it reads as a footnote to the list rather than a replacement for it.
  vim.list_extend(lines, M.note_lines(kind))
  return lines
end

---Open a float listing every key a kind has.
---
---Takes the cursor, unlike everything else octo floats: it is read, scrolled and
---dismissed, so it is the one surface where the keys should go to the float itself.
---@param kind string the mapping kind to describe
---@return integer winid
---@return integer bufnr
function M.float(kind)
  local lines = M.float_lines(kind)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = "octo-keymap-help"
  vim.bo[bufnr].bufhidden = "wipe"

  local widest = 0
  for _, line in ipairs(lines) do
    widest = math.max(widest, vim.fn.strdisplaywidth(line))
  end

  local vim_height = vim.o.lines - vim.o.cmdheight
  local width = math.min(widest + 2, math.max(vim.o.columns - 8, 20))
  local height = math.min(#lines, math.max(vim_height - 6, 3))

  local winid = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    row = math.max(math.floor((vim_height - height) / 2), 0),
    col = math.max(math.floor((vim.o.columns - width) / 2), 0),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = (" %s  %s keys "):format(M.SYMBOL, M.LABELS[kind] or kind),
    title_pos = "center",
    zindex = 70,
  })

  for _, lhs in ipairs { "q", "<Esc>", M.HELP_KEY } do
    vim.keymap.set("n", lhs, function()
      pcall(vim.api.nvim_win_close, winid, true)
    end, { buffer = bufnr, silent = true, noremap = true, desc = "Octo: close the keymap help" })
  end

  return winid, bufnr
end

---The keys that fit, joined, each one drawn whole.
---
---Stops at the first key too wide to finish rather than cutting through one, because
---half a label reads as a different action.
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

---The bar's single line for one buffer kind.
---
---The help section is reserved out of the width before the keys are laid out, and it
---is the last thing cut, not the first: while the section itself still fits, only the
---label ahead of it gives up width, truncated down to make room. Only once the section
---alone would not fit does its own tail start to go -- `M.truncate` cuts from the end,
---and the symbol sits at the section's front, so the symbol is the last thing lost
---rather than the first thing dropped.
---@param kind string the mapping kind to describe
---@param width integer columns available; clamped to zero if negative
---@param handlers table<string, function>|nil the action handlers; octo's own when omitted
---@return string a statusline expression with every percent escaped, never wider than width
function M.bar_line(kind, width, handlers)
  width = math.max(width, 0)
  local section = ("  %s %s"):format(vim.fn.nr2char(0x2502), M.section())
  local opening = (" %s   "):format(M.LABELS[kind] or kind)
  local section_width = vim.fn.strdisplaywidth(section)
  local reserved = vim.fn.strdisplaywidth(opening) + section_width

  if width <= section_width then
    return (M.truncate(section, width):gsub("%%", "%%%%"))
  end

  if width <= reserved then
    return ((M.truncate(opening, width - section_width) .. section):gsub("%%", "%%%%"))
  end

  local parts = {}
  for _, entry in ipairs(M.entries(kind, handlers)) do
    parts[#parts + 1] = ("%s %s"):format(entry.lhs, entry.label)
  end
  if #parts == 0 then
    parts[1] = "no keys mapped"
  end

  return ((opening .. keys_that_fit(parts, width - reserved) .. section):gsub("%%", "%%%%"))
end

---Records which mapping kind a buffer's keys were bound from.
---@param bufnr integer the buffer the mappings were applied to
---@param kind string the mapping kind they came from
function M.remember(bufnr, kind)
  if M.LABELS[kind] and vim.api.nvim_buf_is_valid(bufnr) then
    vim.b[bufnr][M.VARIABLE] = kind
  end
end

---The mapping kind a buffer's keys came from, if it has one.
---@param bufnr integer the buffer to ask about
---@return string|nil kind a key of `M.LABELS`
function M.kind(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  local kind = vim.b[bufnr][M.VARIABLE]
  return M.LABELS[kind] and kind or nil
end

---The bar as the window it hangs on redraws it.
---@return string a winbar expression, empty when there is no kind to describe
function M.winbar()
  local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then
    return ""
  end

  local kind = M.kind(vim.api.nvim_win_get_buf(win))
  if not kind then
    return ""
  end

  return ("%%#%s#%s"):format(M.GROUP, M.bar_line(kind, vim.api.nvim_win_get_width(win)))
end

---Dims the bar, unless something has already said how it should look.
---
---Emptiness is the test rather than existence, because naming a group in a statusline
---expression brings it into existence with nothing in it.
function M.highlight()
  if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = M.GROUP })) then
    vim.api.nvim_set_hl(0, M.GROUP, { link = "Comment" })
  end
end

---Puts the bar on one window, or takes it off, according to what that window is showing.
---
---The bar belongs to the BUFFER and the winbar belongs to the window, and this is what
---reconciles the two. It only ever clears a winbar that is this module's own expression,
---so barbecue's breadcrumb, the switchboard's hint and anything else drawn up there is
---left alone.
---@param win integer the window to reconcile
---@return boolean dressed whether the window came away wearing the bar
function M.dress(win)
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end
  local current = vim.api.nvim_get_option_value("winbar", { win = win, scope = "local" })
  if M.kind(vim.api.nvim_win_get_buf(win)) then
    M.highlight()
    if current ~= M.EXPRESSION then
      vim.api.nvim_set_option_value("winbar", M.EXPRESSION, { win = win, scope = "local" })
    end
    return true
  end
  if current == M.EXPRESSION then
    vim.api.nvim_set_option_value("winbar", "", { win = win, scope = "local" })
  end
  return false
end

---The events after which a window is reconciled with what it is showing.
M.FOLLOW_EVENTS = { "BufWinEnter", "BufEnter", "WinEnter", "WinNew" }

---The augroup holding the follower, so registering it twice replaces it.
M.FOLLOW_GROUP = "octo_keymap_help_winbar"

---Follow octo buffers between windows, so the bar is wherever one is being read.
---@return nil
function M.follow()
  local group = vim.api.nvim_create_augroup(M.FOLLOW_GROUP, { clear = true })
  vim.api.nvim_create_autocmd(M.FOLLOW_EVENTS, {
    group = group,
    callback = function()
      M.dress(vim.api.nvim_get_current_win())
    end,
    desc = "Octo: keep the keys bar on whichever window is showing an octo buffer",
  })
end

---Binds the key that opens the float, and starts the bar following the buffer.
---
---The bar used to be hung on `vim.api.nvim_get_current_win()` here and left there. A
---buffer is configured when GitHub answers, not when the reader looks at it, so the
---window current at that moment is frequently not the one the pull request ends up in --
---measured: the window the reader was sitting in got the bar, and the window that then
---showed the pull request got nothing, which is a pull request with no `g?` hint above
---it. `win` is still honoured, but only if it is really showing this buffer.
---@param win integer the window the caller believes is showing the buffer
---@param bufnr integer the buffer whose kind the bar describes
---@param kind string the mapping kind
function M.attach(win, bufnr, kind)
  M.remember(bufnr, kind)
  if not M.LABELS[kind] then
    return
  end
  vim.keymap.set("n", M.HELP_KEY, function()
    M.float(kind)
  end, { buffer = bufnr, silent = true, noremap = true, desc = "Octo: show the keys this buffer has" })

  M.follow()
  for _, showing in ipairs(vim.fn.win_findbuf(bufnr)) do
    M.dress(showing)
  end
  if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
    M.dress(win)
  end
end

return M
