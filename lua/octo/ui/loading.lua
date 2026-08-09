---What is on screen while a picker's previews are being warmed.
---
---Opening a list is silent until a preview is asked for: the whole list is being
---fetched behind the picker, and without a sign of it a wait reads as an editor that
---has stopped rather than one that is working.
---
---It reports and never gates. The float is opened with `enter = false` and
---`focusable = false`, so the picker keeps the cursor and every key still goes to it;
---a list can be picked from the moment it appears, warm or not.
---
---`lines` and `message` are pure and are where the whole format lives, so the wording
---and the truncation are asserted without opening anything.
local config = require "octo.config"

local M = {}

---Spinner frames. Built with `nr2char` rather than pasted in literally: a glyph that
---arrives as an empty string animates nothing, which is indistinguishable from a
---frozen editor.
M.FRAMES = {
  vim.fn.nr2char(0x280B),
  vim.fn.nr2char(0x2819),
  vim.fn.nr2char(0x2839),
  vim.fn.nr2char(0x2838),
  vim.fn.nr2char(0x283C),
  vim.fn.nr2char(0x2834),
  vim.fn.nr2char(0x2826),
  vim.fn.nr2char(0x2827),
  vim.fn.nr2char(0x2807),
  vim.fn.nr2char(0x280F),
}

---How often the spinner advances.
M.INTERVAL_MS = 80

---The hard ceiling. Nothing else guarantees the float comes down: a request that never
---answers produces no completion, and without this the spinner would outlive the
---picker.
M.TIMEOUT_MS = 120000

---Height of the float, in rows.
M.HEIGHT = 1

---Greatest width of the float, in columns.
M.MAX_WIDTH = 34

---Stacking order. Above fzf-lua's window, which defaults to 50 and puts its help
---window at 52, so the strip is not hidden by the picker it reports on.
M.ZINDEX = 60

local group = vim.api.nvim_create_augroup("OctoPreviewLoading", { clear = true })

local win ---@type integer?
local buf ---@type integer?
local timer ---@type uv.uv_timer_t?
local deadline ---@type uv.uv_timer_t?
local tick = 0
local text = ""

---Whether the loading strip is wanted, per `picker_config.preview_loading`.
---@return boolean true unless the option is explicitly false
function M.enabled()
  return config.values.picker_config.preview_loading ~= false
end

---The spinner frame for a tick.
---@param count integer the animation tick, of any sign
---@return string frame one frame from `M.FRAMES`
function M.frame_at(count)
  return M.FRAMES[(count - 1) % #M.FRAMES + 1]
end

---What the strip says about the warming.
---@param completed integer previews warmed so far
---@param total integer previews asked for
---@return string message for `M.lines`
function M.message(completed, total)
  return string.format("%d/%d previews warm", completed, total)
end

---The float's content: the spinner then the message, cut to the width.
---
---Newlines are folded here rather than at the call site because
---`nvim_buf_set_lines` errors outright on a replacement containing one, and this is
---called from a timer every `INTERVAL_MS`: an uncaught newline would not fail once, it
---would fail on a loop.
---@param message string what is being waited on
---@param count integer the animation tick
---@param width integer the float's inner width in columns
---@return string[] lines exactly one, never wider than `width`
function M.lines(message, count, width)
  local prefix = " " .. M.frame_at(count) .. "  "
  local room = math.max(width - vim.fn.strdisplaywidth(prefix), 1)
  local body = message:gsub("[\n\r]", " ")
  if vim.fn.strdisplaywidth(body) > room then
    while vim.fn.strdisplaywidth(body) > math.max(room - 1, 0) and body ~= "" do
      body = vim.fn.strcharpart(body, 0, vim.fn.strchars(body) - 1)
    end
    body = body .. vim.fn.nr2char(0x2026)
  end
  return { prefix .. body }
end

---Whether the strip is on screen.
---@return boolean
function M.is_open()
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

---The strip's window, for tests and for callers that need its geometry.
---@return integer? win nil when nothing is shown
function M.window()
  return win
end

---The strip's buffer.
---@return integer? buf nil when nothing is shown
function M.buffer()
  return buf
end

---Define the strip's highlight groups.
---
---Links with `default = true`, so a colourscheme with an opinion keeps it, and
---re-applied on a colourscheme change because loading one clears every group: a group
---defined once at startup survives by name and loses its colour.
function M.highlights()
  vim.api.nvim_set_hl(0, "OctoPreviewLoadingNormal", { link = "NormalFloat", default = true })
  vim.api.nvim_set_hl(0, "OctoPreviewLoadingBorder", { link = "FloatBorder", default = true })
end

---Stop and close a timer. Closing matters as much as stopping: a stopped but unclosed
---timer leaks, and this runs on every hide.
---@param handle uv.uv_timer_t? a libuv timer
local function stop(handle)
  if handle and not handle:is_closing() then
    handle:stop()
    handle:close()
  end
end

---Write the current frame and message into the buffer.
---
---Re-validates both handles before touching either: the timer runs off the main loop
---and the picker may have closed since it was scheduled.
local function draw()
  if not (M.is_open() and buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  local width = vim.api.nvim_win_get_width(win)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.lines(text, tick, width))
  vim.bo[buf].modifiable = false
end

---Take the strip off the screen and tear down both timers.
---
---Safe to call when nothing is showing, so every exit path can call it blindly.
function M.hide()
  stop(timer)
  stop(deadline)
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
---@return nil
local function open(self_width)
  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "octo-preview-loading"

  win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = math.max(vim.o.lines - vim.o.cmdheight - M.HEIGHT - 2, 0),
    col = math.max(vim.o.columns - self_width - 2, 0),
    width = self_width,
    height = M.HEIGHT,
    style = "minimal",
    border = "rounded",
    focusable = false,
    zindex = M.ZINDEX,
    noautocmd = true,
  })
  vim.wo[win].winhighlight = "Normal:OctoPreviewLoadingNormal,FloatBorder:OctoPreviewLoadingBorder"

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
    desc = "Octo: take the preview loading strip down with its window",
  })

  timer = vim.uv.new_timer()
  timer:start(M.INTERVAL_MS, M.INTERVAL_MS, function()
    tick = tick + 1
    vim.schedule(draw)
  end)

  deadline = vim.uv.new_timer()
  deadline:start(M.TIMEOUT_MS, 0, function()
    vim.schedule(M.hide)
  end)
end

---Show the strip, or update it if it is already up.
---@param completed integer previews warmed so far
---@param total integer previews asked for
function M.show(completed, total)
  if not M.enabled() then
    return
  end
  text = M.message(completed, total)
  if not M.is_open() then
    tick = 0
    M.highlights()
    open(math.min(M.MAX_WIDTH, math.max(20, vim.o.columns - 4)))
  end
  draw()
end

---Report progress, showing the strip while there is warming left and taking it down
---once there is not.
---@param completed integer previews warmed so far
---@param total integer previews asked for
function M.update(completed, total)
  if total <= 0 or completed >= total then
    M.hide()
    return
  end
  M.show(completed, total)
end

---Take the strip down for a warm that never started, or one whose picker has closed.
---
---Safe to call when nothing is showing, so a caller need not check first.
function M.abandon()
  M.hide()
end

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("OctoPreviewLoadingColors", { clear = true }),
  callback = function()
    M.highlights()
  end,
  desc = "Octo: keep the preview loading strip's highlights after a colourscheme change",
})

return M
