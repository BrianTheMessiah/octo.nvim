local fzf = require "fzf-lua"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"

local M = {}

---The repository stand-in meaning "do not narrow at all". Every GitHub
---`nameWithOwner` contains a slash, so this can never be mistaken for one.
M.ALL = "*"

---@class octo.RepoScopeItem
---@field repo string the `nameWithOwner` the pull request lives in
---@field line string the line the list showed for that pull request

---@class octo.RepoScopeRow
---@field repo string a `nameWithOwner`, or `M.ALL` for the widening row
---@field label string the repository name, padded to the width of the left column
---@field count string the number of pull requests, padded to the width of the right column

---Pads a string on the right to a column width, measured the way a terminal
---measures it rather than in bytes, so a name carrying a multi-cell glyph still
---leaves the next column where it belongs.
---@param text string the string to pad
---@param width integer the column width to fill
---@return string padded the string followed by enough spaces to reach `width`
local function pad_right(text, width)
  return text .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(text)))
end

---Pads a string on the left to a column width, measured the way a terminal
---measures it, so counts of different lengths end on the same column.
---@param text string the string to pad
---@param width integer the column width to fill
---@return string padded enough spaces to reach `width`, followed by the string
local function pad_left(text, width)
  return string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(text))) .. text
end

---How many of the loaded pull requests each repository holds.
---@param items octo.RepoScopeItem[] every pull request the list has loaded
---@return table<string, integer> counts `nameWithOwner` to number of pull requests
function M.counts(items)
  local counts = {}
  for _, item in ipairs(items) do
    counts[item.repo] = (counts[item.repo] or 0) + 1
  end
  return counts
end

---The repositories in the order the picker lists them: the ones holding the most
---pull requests first, ties broken by name so the order never wobbles between
---two presses of the same key.
---@param counts table<string, integer> `nameWithOwner` to number of pull requests
---@return { repo: string, count: integer }[] ranked one entry per repository, in display order
function M.ranked(counts)
  local ranked = {}
  for repo, count in pairs(counts) do
    ranked[#ranked + 1] = { repo = repo, count = count }
  end
  table.sort(ranked, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    return a.repo < b.repo
  end)
  return ranked
end

---Whether repository names have to keep their owner to stay unambiguous. A list
---confined to one organisation reads better as `service.core`; as soon as it
---spans two, the owner is the only thing telling two same-named repositories
---apart.
---@param ranked { repo: string, count: integer }[] the repositories being listed
---@return boolean qualify true when every name must keep its `owner/` prefix
function M.needs_owner(ranked)
  local owner
  for _, item in ipairs(ranked) do
    local this_owner = item.repo:match "^([^/]+)/"
    if owner and this_owner ~= owner then
      return true
    end
    owner = this_owner
  end
  return false
end

---The name shown for one repository.
---@param repo string a `nameWithOwner`
---@param qualify boolean keep the `owner/` prefix when true, drop it when false
---@return string label the name as the picker shows it
function M.label(repo, qualify)
  if qualify then
    return repo
  end
  return repo:match "/([^/]+)$" or repo
end

---The total number of pull requests loaded, which is what the widening row
---offers to go back to.
---@param ranked { repo: string, count: integer }[] the repositories being listed
---@return integer total the sum of every repository's count
function M.total(ranked)
  local total = 0
  for _, item in ipairs(ranked) do
    total = total + item.count
  end
  return total
end

---The rows of the repository picker: one per repository present among the loaded
---pull requests, headed by the row that widens back to all of them. Nothing here
---asks GitHub anything; the counts come from the lines the list already holds.
---@param items octo.RepoScopeItem[] every pull request the list has loaded
---@return octo.RepoScopeRow[] rows in display order, both columns padded to align
function M.rows(items)
  local ranked = M.ranked(M.counts(items))
  if #ranked == 0 then
    return {}
  end

  local qualify = M.needs_owner(ranked)
  local pending = { { repo = M.ALL, label = "every repository", count = M.total(ranked) } }
  for _, item in ipairs(ranked) do
    pending[#pending + 1] = { repo = item.repo, label = M.label(item.repo, qualify), count = item.count }
  end

  local label_width, count_width = 0, 0
  for _, row in ipairs(pending) do
    label_width = math.max(label_width, vim.fn.strdisplaywidth(row.label))
    count_width = math.max(count_width, vim.fn.strdisplaywidth(tostring(row.count)))
  end

  local rows = {}
  for _, row in ipairs(pending) do
    rows[#rows + 1] = {
      repo = row.repo,
      label = pad_right(row.label, label_width),
      count = pad_left(tostring(row.count), count_width),
    }
  end
  return rows
end

---The plain text of a row, which is what fzf hands back when the row is chosen.
---@param row octo.RepoScopeRow a row from `M.rows`
---@return string line the row with no colouring in it
function M.line(row)
  return row.label .. "  " .. row.count
end

---The row as the picker draws it: the same text as `M.line`, with the count
---dimmed so the eye lands on the names.
---@param row octo.RepoScopeRow a row from `M.rows`
---@return string display the row with its count coloured
function M.display(row)
  return row.label .. "  " .. fzf.utils.ansi_from_hl("Comment", row.count)
end

---The loaded pull requests belonging to one repository, in the order the list
---loaded them.
---@param items octo.RepoScopeItem[] every pull request the list has loaded
---@param repo string a `nameWithOwner`, or `M.ALL` to keep all of them
---@return octo.RepoScopeItem[] kept the matching items, sharing the originals
function M.keep(items, repo)
  if repo == M.ALL then
    return vim.list_slice(items)
  end

  local kept = {}
  for _, item in ipairs(items) do
    if item.repo == repo then
      kept[#kept + 1] = item
    end
  end
  return kept
end

---The prompt title a narrowed list carries, so which repository the list is
---confined to is visible without reading the rows.
---@param title string|nil the prompt title the unfiltered list was opened with
---@param repo string a `nameWithOwner`, or `M.ALL` for the unfiltered list
---@return string|nil prompt_title the repository, or the original title when not narrowed
function M.prompt(title, repo)
  if repo == M.ALL then
    return title
  end
  return repo
end

---What the narrowing key reports in a list that holds one repository and can hold
---no other, because the repository was fixed before the list was asked for. It
---names the repository, so the absence of anything to choose is accounted for,
---and it names the search that spans repositories, so the key points somewhere
---even where it cannot narrow.
---@param repo string the `nameWithOwner` the list is confined to
---@param lhs string the pressed key, written as a mapping writes it
---@return string message the whole of what the press reports
function M.pinned_message(repo, lhs)
  local reason = ("%s is the only repository in this list, so %s has nothing to narrow."):format(repo, lhs)
  local owner = repo:match "^([^/]+)/"
  if not owner then
    return reason
  end
  return ("%s For pull requests across repositories, run :Octo search is:pr is:open org:%s."):format(reason, owner)
end

---Opens the second picker: the repositories present among the pull requests
---already loaded, with how many each holds. Choosing one calls back with its
---`nameWithOwner`; choosing the first row calls back with `M.ALL`.
---@param items octo.RepoScopeItem[] every pull request the list has loaded
---@param choose fun(repo: string) called with the chosen `nameWithOwner`, or `M.ALL`
---@return nil
function M.open(items, choose)
  local rows = M.rows(items)
  if #rows == 0 then
    return
  end

  local lines, by_line = {}, {}
  for _, row in ipairs(rows) do
    by_line[M.line(row)] = row.repo
    lines[#lines + 1] = M.display(row)
  end

  fzf.fzf_exec(lines, {
    prompt = picker_utils.get_prompt "repository",
    fzf_opts = {
      ["--no-multi"] = "",
      ["--info"] = "default",
    },
    winopts = {
      title = "Repositories",
      title_pos = "center",
    },
    actions = {
      ["default"] = function(selected)
        local repo = selected and by_line[selected[1]]
        if repo then
          choose(repo)
        end
      end,
    },
  })
end

return M
