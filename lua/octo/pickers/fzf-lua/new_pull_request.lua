---A row at the top of every search picker that opens a NEW pull request.
---
---A list of pull requests is exactly where somebody decides to open one, and until this
---existed there was no way to from there -- the pickers only ever opened what GitHub
---already had. The alternative, a separate list built outside octo, loses the previewer,
---the markdown rendering, the preview warmer's loading indicator and the fzf options, so
---the row belongs here where all of that already works.
---
---Off unless an action is set. A row that opens nothing is worse than no row, so the
---picker only grows one once something has been wired to it:
---
---    require("octo.pickers.fzf-lua.new_pull_request").set_action(function()
---      require("my_config.pull_request_form").open()
---    end)
---
---A setter rather than a `picker_config` key because the value is a function: it belongs
---to whatever the user wants opening, not to octo's serialisable configuration.
local M = {}

---The first field of the row's line, and the only thing that identifies it.
---
---The *kind* rather than the label, because a title is arbitrary text from GitHub: a pull
---request actually called "open a new pull request" must not be mistaken for this row.
M.KIND = "octo_new_pull_request"

---What the row reads as in the list.
M.LABEL = "＋ open a new pull request"

---@type function|nil
local action = nil

---Sets what the row opens, or clears it with `nil`.
---@param fn function|nil
---@return nil
function M.set_action(fn) action = fn end

---Whether there is anything for the row to open.
---@return boolean
function M.enabled() return type(action) == "function" end

---The row's line, in the shape every other line in these lists has.
---
---A real entry is `"<kind> <owner> <name> <number> <title>"`, and the lists run with
---`--delimiter " " --with-nth 4..`, so fzf shows from the fourth field on. The two
---placeholder fields are what put the label in that visible range; they are dots rather
---than empty strings because an empty field between two delimiters shifts every column
---after it.
---@return string
function M.line() return ("%s . . %s"):format(M.KIND, M.LABEL) end

---Whether a chosen line is this row rather than a pull request.
---@param entry string|nil the line fzf handed back
---@return boolean
function M.is(entry)
  if type(entry) ~= "string" then
    return false
  end
  return entry:sub(1, #M.KIND + 1) == M.KIND .. " "
end

---The lines with the row in front, when there is one to put there.
---@param lines string[]
---@return string[]
function M.prepend(lines)
  if not M.enabled() then
    return lines
  end

  local with_row = { M.line() }
  for _, line in ipairs(lines) do
    with_row[#with_row + 1] = line
  end
  return with_row
end

---What the preview pane shows while the row is under the cursor.
---
---Its own lines rather than a lookup. `previewers.search` splits an entry into
---kind/owner/name/number and formats a cache key from them; this row's fourth field is
---not a number, so the key comes out as `octo_new_pull_request:./.:nil` -- measured, and
---it does NOT raise, which is the trap. Unguarded it misses the cache and fires a GraphQL
---request for a repository and number that do not exist, on every move onto the row.
---@return string[]
function M.preview_lines()
  return {
    M.LABEL,
    "",
    "Opens a new pull request from the branch you are on,",
    "rather than one that already exists on GitHub.",
  }
end

---Opens whatever was set.
---
---Scheduled, because fzf-lua is still tearing its own window down when an action runs and
---a float opened inside that teardown is closed along with it -- the same reason
---`fzf_actions.help_action` schedules.
---@return nil
function M.run()
  if not M.enabled() then
    return
  end
  vim.schedule(function() action() end)
end

return M
