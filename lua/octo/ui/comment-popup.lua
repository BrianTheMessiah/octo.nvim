local drafts = require "octo.drafts"
local utils = require "octo.utils"
local window = require "octo.ui.window"

local M = {}

---The line separating read-only context from the editable compose region.
M.COMPOSE_MARK = "───────────────────────── your comment ─────────────────────────"

---Per-buffer state for open popups, keyed by bufnr.
---@type table<integer, table>
local state = {}

---Milliseconds of typing quiet before a draft is written to disk.
local PERSIST_DELAY_MS = 300

---The first line of the compose region, 1-indexed.
---@param bufnr integer
---@return integer line
local function compose_start(bufnr)
  return state[bufnr].context_height + 1
end

---The composed comment text, excluding context and separator.
---@param bufnr integer
---@return string body
function M.body(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, compose_start(bufnr) - 1, -1, false)
  return table.concat(lines, "\n")
end

---Writes the current body to the draft store, or clears it when blank.
---@param bufnr integer
---@return nil
local function persist(bufnr)
  local entry = state[bufnr]
  if not entry or not entry.draft_key then
    return
  end
  local body = M.body(bufnr)
  if utils.is_blank(vim.trim(body)) then
    drafts.discard(entry.draft_key)
  else
    drafts.save(entry.draft_key, body)
  end
end

---Stops and releases a popup's debounce timer, if it has one.
---@param entry table|nil
---@return nil
local function stop_timer(entry)
  if not entry or not entry.timer then
    return
  end
  entry.timer:stop()
  if not entry.timer:is_closing() then
    entry.timer:close()
  end
  entry.timer = nil
end

---Restarts a per-buffer timer that writes the draft once typing pauses.
---
---submit and cancel persist immediately instead of going through this timer,
---so a debounced write can only ever coalesce keystrokes, never delay the
---writes that matter for correctness.
---@param bufnr integer
---@return nil
local function schedule_persist(bufnr)
  local entry = state[bufnr]
  if not entry then
    return
  end
  if not entry.timer then
    entry.timer = assert(vim.uv.new_timer())
  end
  entry.timer:stop()
  entry.timer:start(
    PERSIST_DELAY_MS,
    0,
    vim.schedule_wrap(function()
      persist(bufnr)
    end)
  )
end

---Closes the popup and forgets its state.
---@param bufnr integer
---@return nil
local function teardown(bufnr)
  local entry = state[bufnr]
  state[bufnr] = nil
  stop_timer(entry)
  if entry and entry.winid then
    window.try_close_wins(entry.winid)
  end
end

---Sends the composed comment. Blank bodies are refused without calling back.
---
---A `submitting` flag on the entry blocks re-entry: without it, pressing a
---submit key twice before an async on_submit resolves would fire it twice
---and could create a duplicate comment upstream. The flag is cleared on
---failure so a retry is possible, and is implicitly cleared on success
---because teardown discards the whole entry.
---@param bufnr integer
---@return nil
function M.submit(bufnr)
  local entry = state[bufnr]
  if not entry or entry.submitting then
    return
  end
  local body = M.body(bufnr)
  if utils.is_blank(vim.trim(body)) then
    utils.error "Nothing to submit: the comment is empty"
    return
  end
  persist(bufnr)
  entry.submitting = true
  entry.on_submit(body, function(ok, err)
    if not ok then
      entry.submitting = false
      utils.error(err or "Failed to submit comment")
      return
    end
    if entry.draft_key then
      drafts.discard(entry.draft_key)
    end
    teardown(bufnr)
  end)
end

---Closes without sending, keeping whatever was typed as a draft.
---@param bufnr integer
---@return nil
function M.cancel(bufnr)
  persist(bufnr)
  teardown(bufnr)
end

---Options accepted by M.open.
---@class octo.CommentPopupOpts
---@field target table classification of what is being replied to, from classify_comment_target
---@field context? string[] read-only lines shown above the compose region
---@field draft_key? string key into the draft store; nil disables draft persistence
---@field on_submit fun(body: string, done: fun(ok: boolean, err: string|nil)) called on submit with the composed body
---@field title? string floating window header

---Opens a compose popup.
---@param opts octo.CommentPopupOpts
---@return integer winid
---@return integer bufnr
function M.open(opts)
  local context = opts.context or {}
  local content = {}
  for _, line in ipairs(context) do
    table.insert(content, line)
  end
  if #context > 0 then
    table.insert(content, M.COMPOSE_MARK)
  end

  local restored = opts.draft_key and drafts.load(opts.draft_key) or nil
  local body_lines = restored and vim.split(restored, "\n") or { "" }
  for _, line in ipairs(body_lines) do
    table.insert(content, line)
  end

  local winid, bufnr = window.create_centered_float {
    header = opts.title or "Comment",
    content = content,
    enter = true,
  }

  state[bufnr] = {
    winid = winid,
    draft_key = opts.draft_key,
    on_submit = opts.on_submit,
    target = opts.target,
    context_height = #context > 0 and #context + 1 or 0,
  }

  vim.bo[bufnr].filetype = "octo_comment"
  vim.bo[bufnr].modifiable = true

  -- Closing the popup's window must also dispose of its buffer. create_centered_float
  -- leaves bufhidden at nvim_create_buf's default of "hide", so a window-only close
  -- (:q!, nvim_win_close) fires no BufDelete/BufWipeout and the state entry, its
  -- on_submit closure and its debounce timer all leak. "wipe" makes the window close
  -- fire BufWipeout, which the autocommand below already handles. Verified: the
  -- buffer's lines are still readable inside that BufWipeout callback, so persisting
  -- there does not race the wipe.
  vim.bo[bufnr].bufhidden = "wipe"

  local map_opts = { buffer = bufnr, silent = true, noremap = true }

  -- Both submit keys are bound buffer-locally, and `<leader>op` must be among
  -- them even though switchboard installs a global `\op`: that global runs
  -- `:Octo submit`, which would call save_buffer() on this scratch buffer rather
  -- than sending the comment. A buffer-local mapping shadows it.
  for _, lhs in ipairs { "<leader>op", "<C-s>" } do
    vim.keymap.set({ "n", "i" }, lhs, function()
      M.submit(bufnr)
    end, vim.tbl_extend("force", map_opts, { desc = "Octo: submit this comment" }))
  end

  vim.keymap.set("n", "q", function()
    M.cancel(bufnr)
  end, vim.tbl_extend("force", map_opts, { desc = "Octo: close, keeping a draft" }))

  vim.keymap.set("n", "<C-c>", function()
    M.cancel(bufnr)
  end, vim.tbl_extend("force", map_opts, { desc = "Octo: close, keeping a draft" }))

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = bufnr,
    desc = "Octo: keep the comment draft on disk, debounced",
    callback = function()
      schedule_persist(bufnr)
    end,
  })

  -- Reached when the popup is closed by a route of its own -- :bd, :bwipeout!,
  -- :q!, or external code -- rather than through submit or cancel. Persist
  -- first, then forget: teardown would try to close a window that may already
  -- be gone, and the debounce timer must not be left running against a dead
  -- buffer.
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    buffer = bufnr,
    once = true,
    desc = "Octo: keep the draft and forget the popup when its buffer goes away",
    callback = function()
      pcall(persist, bufnr)
      stop_timer(state[bufnr])
      state[bufnr] = nil
    end,
  })

  vim.api.nvim_win_set_cursor(winid, { #content, 0 })
  return winid, bufnr
end

return M
