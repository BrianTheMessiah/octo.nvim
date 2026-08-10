---The animation and the timers behind anything octo shows while it is waiting.
---
---Two surfaces need this: the corner strip that reports preview warming, and the
---centered float that covers the wait between picking a pull request and its buffer
---being painted. They differ entirely in geometry and wording and not at all in how
---they animate, so this is the half they share.
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

---The hard ceiling. Nothing else guarantees a float comes down: a request that never
---answers produces no completion, and without this a spinner would outlive whatever
---it was reporting on.
M.TIMEOUT_MS = 120000

---The spinner frame for a tick.
---@param count integer the animation tick, of any sign
---@return string frame one frame from `M.FRAMES`
function M.frame_at(count)
  return M.FRAMES[(count - 1) % #M.FRAMES + 1]
end

---Stop and close a timer.
---
---Closing matters as much as stopping: a stopped but unclosed timer leaks, and this
---runs on every hide. Safe on nil and safe twice, so every exit path can call it
---blindly.
---@param handle uv.uv_timer_t? a libuv timer
function M.stop(handle)
  if handle and not handle:is_closing() then
    handle:stop()
    handle:close()
  end
end

---Start the animation timer and the deadline timer.
---
---Both callbacks run on the libuv loop, so a caller touching the editor from either
---must wrap its own work in `vim.schedule`; the tick count is passed in rather than
---held here so a caller can draw from it without keeping its own counter in step.
---@param on_tick fun(tick: integer) called every `INTERVAL_MS` with the tick count
---@param on_deadline fun() called once, `TIMEOUT_MS` after the start
---@return uv.uv_timer_t animation the repeating timer
---@return uv.uv_timer_t deadline the one-shot timer
function M.start(on_tick, on_deadline)
  local tick = 0
  local animation = assert(vim.uv.new_timer())
  animation:start(M.INTERVAL_MS, M.INTERVAL_MS, function()
    tick = tick + 1
    on_tick(tick)
  end)

  local deadline = assert(vim.uv.new_timer())
  deadline:start(M.TIMEOUT_MS, 0, function()
    on_deadline()
  end)

  return animation, deadline
end

return M
