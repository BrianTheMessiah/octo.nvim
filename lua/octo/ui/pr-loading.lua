---What is on screen between picking something from a list and its buffer being painted.
---
---The fetch behind an `octo://` buffer is asynchronous, so the window is created empty
---and stays empty until the query answers. Without a sign of it the wait reads as an
---editor that has stopped rather than one that is working.
---
---It reports and never gates, the same rule `octo.ui.loading` follows: the float is
---opened with `enter = false` and `focusable = false`, so the cursor stays where the
---reader left it and every key still goes to the buffer underneath.
---
---`title` and `lines` are pure and are where the whole format lives, so the wording and
---the truncation are asserted without opening anything.
local config = require "octo.config"
local spinner = require "octo.ui.spinner"

local M = {}

---Height of the float, in rows: the title, then what is being waited on.
M.HEIGHT = 2

---Greatest width of the float, in columns.
M.MAX_WIDTH = 48

---Stacking order. Above fzf-lua's window, which defaults to 50 and puts its help
---window at 52, so the float is not hidden by the picker it was opened from.
M.ZINDEX = 60

local group = vim.api.nvim_create_augroup("OctoPrLoading", { clear = true })

local win ---@type integer?
local buf ---@type integer?
local timer ---@type uv.uv_timer_t?
local deadline ---@type uv.uv_timer_t?
local tick = 0
local heading = ""
local text = ""

---Whether the float is wanted, per `ui.pr_loading`.
---@return boolean true unless the option is explicitly false
function M.enabled()
  return config.values.ui.pr_loading ~= false
end

---What the float calls the thing being opened.
---
---A release is named by its tag and a repository has no id at all, so this cannot
---simply print a `#` and a number.
---@param repo string the `owner/name` the buffer belongs to
---@param kind string the octo node kind
---@param id string|integer|nil the number or tag, absent for a repository
---@return string
function M.title(repo, kind, id)
  if id == nil or id == "" then
    return repo
  end
  if kind == "release" then
    return ("%s %s"):format(repo, id)
  end
  return ("%s #%s"):format(repo, id)
end

---Text cut to fit, measured in display columns.
---@param body string
---@param width integer
---@return string
local function fit(body, width)
  body = body:gsub("[\n\r]", " ")
  if width < 1 then
    return ""
  end
  if vim.fn.strdisplaywidth(body) <= width then
    return body
  end
  while vim.fn.strdisplaywidth(body) > math.max(width - 1, 0) and body ~= "" do
    body = vim.fn.strcharpart(body, 0, vim.fn.strchars(body) - 1)
  end
  return body .. vim.fn.nr2char(0x2026)
end

---The float's content: the spinner and the title, then what is being waited on.
---
---Newlines are folded here rather than at the call site because `nvim_buf_set_lines`
---errors outright on a replacement containing one, and this is called from a timer
---every `INTERVAL_MS`: an uncaught newline would not fail once, it would fail on a loop.
---@param title string what is being opened
---@param message string what is being waited on
---@param count integer the animation tick
---@param width integer the float's inner width in columns
---@return string[] lines exactly two, neither wider than `width`
function M.lines(title, message, count, width)
  local prefix = " " .. spinner.frame_at(count) .. "  "
  local room = math.max(width - vim.fn.strdisplaywidth(prefix), 1)
  return {
    prefix .. fit(title, room),
    fit("    " .. message, width),
  }
end

---Whether the float is on screen, in the tabpage the reader is actually in.
---
---A float belongs to the tabpage it was created in, and `Layout:open` runs `tab split`. So
---a review that shows the float, opens its layout and then shows it again would, on a
---window-validity check alone, "update" a float stranded in the tabpage the reader has
---just left -- live, valid, and invisible. Asking about the current tabpage instead is
---what makes `M.show` reopen it where it can be seen.
---@return boolean
function M.is_open()
  if not (win ~= nil and vim.api.nvim_win_is_valid(win)) then
    return false
  end
  return vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage()
end

---The float's window.
---@return integer? win nil when nothing is shown
function M.window()
  return win
end

---The float's buffer.
---@return integer? buf nil when nothing is shown
function M.buffer()
  return buf
end

---Define the float's highlight groups.
---
---Links with `default = true`, so a colourscheme with an opinion keeps it, and
---re-applied on a colourscheme change because loading one clears every group.
function M.highlights()
  vim.api.nvim_set_hl(0, "OctoPrLoadingNormal", { link = "NormalFloat", default = true })
  vim.api.nvim_set_hl(0, "OctoPrLoadingBorder", { link = "FloatBorder", default = true })
end

---Write the current frame into the buffer.
local function draw()
  if not (M.is_open() and buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  local width = vim.api.nvim_win_get_width(win)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.lines(heading, text, tick, width))
  vim.bo[buf].modifiable = false
end

---Take the float off the screen and tear down both timers.
---
---Safe to call when nothing is showing, so every exit path can call it blindly.
function M.hide()
  spinner.stop(timer)
  spinner.stop(deadline)
  timer, deadline = nil, nil
  vim.api.nvim_clear_autocmds { group = group }
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
  win, buf = nil, nil
end

---Open the float and start the animation.
---@param self_width integer the float's width in columns
local function open(self_width)
  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "octo-pr-loading"

  local vim_height = vim.o.lines - vim.o.cmdheight

  win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = math.max(math.floor((vim_height - M.HEIGHT) / 2), 0),
    col = math.max(math.floor((vim.o.columns - self_width) / 2), 0),
    width = self_width,
    height = M.HEIGHT,
    style = "minimal",
    border = "rounded",
    focusable = false,
    zindex = M.ZINDEX,
    noautocmd = true,
  })
  vim.wo[win].winhighlight = "Normal:OctoPrLoadingNormal,FloatBorder:OctoPrLoadingBorder"

  -- Belt and braces against anything outside this module closing the float directly:
  -- without it the window vanishes and both timers keep ticking against a handle that
  -- is no longer valid. `M.hide` closes the window itself, which fires this same
  -- event; its own idempotency absorbs the reentry rather than looping.
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(win),
    callback = function()
      M.hide()
    end,
    desc = "Octo: take the loading float down with its window",
  })

  timer, deadline = spinner.start(function(count)
    tick = count
    vim.schedule(draw)
  end, function()
    vim.schedule(M.hide)
  end)
end

---Show the float for something being opened, or update it if it is already up.
---
---Called again with a different message while the float is up, it replaces the wording
---without reopening -- which is how a review reports moving from its query to its file
---fetch as one continuous float rather than two that flicker.
---@param repo string the `owner/name` the buffer belongs to
---@param kind string the octo node kind
---@param id string|integer|nil the number or tag
---@param message string? what is being waited on, default `fetching…`
function M.show(repo, kind, id, message)
  if not M.enabled() then
    return
  end
  heading = M.title(repo, kind, id)
  text = message or "fetching…"
  if not M.is_open() then
    -- `M.hide` first, because "not open" now includes "open in the tabpage we just left":
    -- that float is a live window and buffer, and opening over it without closing it would
    -- strand one per review.
    M.hide()
    tick = 0
    M.highlights()
    open(math.min(M.MAX_WIDTH, math.max(24, vim.o.columns - 4)))
  end
  draw()
end

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("OctoPrLoadingColors", { clear = true }),
  callback = function()
    M.highlights()
  end,
  desc = "Octo: keep the loading float's highlights after a colourscheme change",
})

return M
