---@diagnostic disable
local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"
local new_pull_request = require "octo.pickers.fzf-lua.new_pull_request"
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local queries = require "octo.gh.queries"
local octo_config = require "octo.config"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local repo_scope = require "octo.pickers.fzf-lua.pickers.repo_scope"
local utils = require "octo.utils"
local previewers = require "octo.pickers.fzf-lua.previewers"

local M = {}

---@param fzf_cb fzf-lua.fzfCb
---@param issue table
---@param max_id_length integer
---@param formatted_issues table<string, table> entry.ordinal -> entry
---@param snapshot octo.RepoScopeItem[] collects the repository and line of every entry shown
local function handle_entry(fzf_cb, issue, max_id_length, formatted_issues, snapshot)
  local entry = entry_maker.gen_from_issue(issue)
  if entry ~= nil then
    local owner, name = utils.split_repo(entry.repo)
    local raw_number = picker_utils.pad_string(entry.obj.number, max_id_length)
    local number = fzf.utils.ansi_from_hl("Comment", raw_number)
    local ordinal_entry = string.format("%s %s %s %s %s", entry.kind, owner, name, raw_number, entry.obj.title)
    local string_entry = string.format("%s %s %s %s %s", entry.kind, owner, name, number, entry.obj.title)
    formatted_issues[ordinal_entry] = entry
    snapshot[#snapshot + 1] = { repo = entry.repo, line = string_entry }
    fzf_cb(string_entry)
  end
end

---Empties the snapshot in place, so the narrowing action -- which was handed this
---very table when the picker opened -- sees the results of the query now on
---screen rather than the ones it was created with.
---@param snapshot octo.RepoScopeItem[] the snapshot to empty
---@return nil
function M.reset(snapshot)
  for i = #snapshot, 1, -1 do
    snapshot[i] = nil
  end
end

---The fzf options the searched list and every repository-scoped list share, so a
---narrowed list looks and types exactly like the list it was narrowed from.
---@return table fzf_opts the options to hand fzf
function M.list_fzf_opts()
  return {
    ["--info"] = "default",
    ["--delimiter"] = " ",
    ["--with-nth"] = "4..",
  }
end

---The actions both lists carry: octo's usual open, browse and copy keys, plus the
---key that narrows the pull requests already loaded down to one repository.
---@param formatted_items table<string, table> entry.ordinal -> entry
---@param snapshot octo.RepoScopeItem[] every pull request the list has loaded
---@param narrow fun(repo: string) reopens the list confined to one repository
---@return table<string, function> actions keyed by fzf key
function M.list_actions(formatted_items, snapshot, narrow)
  local cfg = octo_config.values
  return vim.tbl_extend("force", fzf_actions.common_open_actions(formatted_items), {
    [utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.filter_repo.lhs)] = function()
      vim.schedule(function()
        repo_scope.open(snapshot, narrow)
      end)
    end,
  })
end

---The lines a narrowed list is built from: the ones the previous list already
---streamed, kept as they were rather than fetched again.
---@param snapshot octo.RepoScopeItem[] every pull request the list has loaded
---@param repo string a `nameWithOwner`, or `repo_scope.ALL` for every loaded line
---@return string[] lines ready to hand fzf, in the order they were loaded
function M.scoped_lines(snapshot, repo)
  local lines = {}
  for _, item in ipairs(repo_scope.keep(snapshot, repo)) do
    lines[#lines + 1] = item.line
  end
  return lines
end

---Reopens the loaded pull requests confined to one repository. GitHub is not
---asked for anything: every line, every entry and the previewer's field layout
---come from what the searched list already had in hand.
---@param snapshot octo.RepoScopeItem[] every pull request the list has loaded
---@param formatted_items table<string, table> entry.ordinal -> entry, shared with the searched list
---@param prompt_title string|nil the prompt title the searched list was opened with
---@param repo string a `nameWithOwner`, or `repo_scope.ALL` to widen back
---@return nil
function M.open_scoped(snapshot, formatted_items, prompt_title, repo)
  local function narrow(next_repo)
    M.open_scoped(snapshot, formatted_items, prompt_title, next_repo)
  end

  fzf.fzf_exec(new_pull_request.prepend(M.scoped_lines(snapshot, repo)), {
    prompt = picker_utils.get_prompt(repo_scope.prompt(prompt_title, repo)),
    previewer = previewers.search(formatted_items),
    fzf_opts = M.list_fzf_opts(),
    actions = M.list_actions(formatted_items, snapshot, narrow),
  })
end

---Opens the fzf-lua search picker.
---@param opts? table `prompt`, `prompt_title`, `type`
function M.picker(opts)
  opts = opts or {}
  opts.type = opts.type or "ISSUE"

  local formatted_items = {} ---@type table<string, table> entry.ordinal -> entry
  local snapshot = {} ---@type octo.RepoScopeItem[] every line the results now on screen hold

  ---@type fzf-lua.shell.data2
  local function contents(args)
    local query = args[1] or ""

    return coroutine.wrap(
      ---@param fzf_cb fzf-lua.fzfCb
      function(fzf_cb)
        local co = coroutine.running()

        -- Emitted before any early return: a query that matches nothing, or no query at
        -- all, still carries the row -- which is the moment it is most wanted, since a
        -- list that is empty because you have opened nothing is a list you came to in
        -- order to open one.
        if new_pull_request.enabled() then
          fzf_cb(new_pull_request.line())
        end

        if not opts.prompt and utils.is_blank(query) then
          fzf_cb()
          return
        end

        if type(opts.prompt) == "string" then
          opts.prompt = { opts.prompt }
        end

        M.reset(snapshot)

        for _, val in ipairs(opts.prompt) do
          local _prompt = query
          if val then
            _prompt = string.format("%s %s", val, _prompt)
          end
          local output ---@type string
          gh.api.graphql {
            query = queries.search,
            jq = ".data.search.nodes",
            fields = { prompt = _prompt, type = opts.type },
            opts = {
              cb = gh.create_callback {
                success = function(stdout)
                  output = stdout
                  coroutine.resume(co)
                end,
                failure = function(stderr)
                  utils.error(stderr)
                  coroutine.resume(co)
                end,
              },
            },
          }
          coroutine.yield()

          if utils.is_blank(output) then
            fzf_cb()
            return
          end

          local issues = vim.json.decode(output)

          local max_id_length = 1
          for _, issue in ipairs(issues) do
            local s = tostring(issue.number)
            if #s > max_id_length then
              max_id_length = #s
            end
          end

          for _, issue in ipairs(issues) do
            handle_entry(fzf_cb, issue, max_id_length, formatted_items, snapshot)
          end
        end

        fzf_cb()
      end
    )
  end

  local function narrow(repo)
    M.open_scoped(snapshot, formatted_items, opts.prompt_title, repo)
  end

  -- TODO this is still not as fast as I would like.
  fzf.fzf_live(contents, {
    prompt = picker_utils.get_prompt(opts.prompt_title),
    exec_empty_query = true,
    previewer = previewers.search(formatted_items),
    query_delay = 500,
    fzf_opts = M.list_fzf_opts(),
    actions = M.list_actions(formatted_items, snapshot, narrow),
  })
end

setmetatable(M, {
  __call = function(_, opts)
    return M.picker(opts)
  end,
})

return M
