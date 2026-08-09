---@diagnostic disable
local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local queries = require "octo.gh.queries"
local graphql = require "octo.gh.graphql"
local octo_config = require "octo.config"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local previewers = require "octo.pickers.fzf-lua.previewers"
local utils = require "octo.utils"

local M = {}

local function checkout_pull_request(entry)
  utils.checkout_pr(entry.obj.number)
end

local function not_implemented()
  utils.error "Not implemented yet"
end

---Builds the GraphQL query backing the PR picker.
---
---Without an author the repository connection is used, as before. With one the
---search API is used instead: `repository.pullRequests` has no author argument
---(see queries.lua) and GitHub does not offer one, so author filtering has to go
---through search. Both paths feed entry_maker.gen_from_issue, so entries,
---previewer and actions are identical either way.
---@param opts table the picker's options; `author` and `states` are read here
---@param owner string repository owner
---@param name string repository name
---@return string query the GraphQL document
---@return table fields the variables to send
---@return string jq the path to the node list in the response
function M.build_query(opts, owner, name)
  local cfg = octo_config.values
  if utils.is_blank(opts.author) then
    return queries.pull_requests, {
      owner = owner,
      name = name,
      base_ref_name = opts.BaseRefName,
      head_ref_name = opts.HeadRefName,
      labels = opts.labels,
      states = opts.states,
      order_by = cfg.pull_requests.order_by,
    }, ".data.repository.pullRequests.nodes"
  end

  local author = opts.author == "@me" and vim.g.octo_viewer or opts.author
  local parts = { ("repo:%s/%s"):format(owner, name), "is:pr" }
  if opts.states and #opts.states == 1 then
    table.insert(parts, "is:" .. string.lower(opts.states[1]))
  end
  table.insert(parts, "author:" .. author)

  return queries.search, { prompt = table.concat(parts, " "), type = "ISSUE" }, ".data.search.nodes"
end

---Opens the fzf-lua PR picker.
---@param opts? table `repo`, `window_title`, `prompt_title`, `author`, `states`,
---  `BaseRefName`, `HeadRefName`, `labels`, `cb`
function M.picker(opts)
  opts = opts or {}
  if not opts.states then
    opts.states = { "OPEN" }
  end

  if opts.cb ~= nil then
    not_implemented()
    return
  end

  local requested_repo = opts.repo
  local requested_prompt_title = opts.prompt_title

  local repo = utils.pop_key(opts, "repo")
  if utils.is_blank(repo) then
    repo = utils.get_remote_name()
  end
  if not repo then
    utils.error "Cannot find repo"
    return
  end

  local owner, name = utils.split_repo(repo)
  local cfg = octo_config.values

  local window_title = utils.pop_key(opts, "window_title") or "Pull Requests"
  local prompt_title = utils.pop_key(opts, "prompt_title")

  local formatted_pulls = {} ---@type table<string, table> entry.ordinal -> entry
  local pull_order = {} ---@type string[] entry.ordinal in list order

  local function get_contents(fzf_cb)
    local query, fields, jq = M.build_query(opts, owner, name)
    local is_repository_query = query == queries.pull_requests
    local key = jq:sub(2) -- strip the leading "." to match utils.get_nested_prop's dotted path

    gh.api.graphql {
      query = query,
      F = fields,
      paginate = is_repository_query,
      jq = ".",
      opts = {
        stream_cb = function(data, err)
          if err and not utils.is_blank(err) then
            utils.error(err)
            fzf_cb()
          elseif data then
            local pull_requests
            if is_repository_query then
              local resp = utils.aggregate_pages(data, key)
              pull_requests = utils.get_nested_prop(resp, key)
            else
              pull_requests = utils.get_nested_prop(vim.json.decode(data), key)
            end

            for _, pull in ipairs(pull_requests) do
              local entry = entry_maker.gen_from_issue(pull)

              if entry ~= nil then
                formatted_pulls[entry.ordinal] = entry
                table.insert(pull_order, entry.ordinal)
                local highlight
                if entry.obj.isDraft then
                  highlight = "OctoSymbol"
                else
                  highlight = "OctoStateOpen"
                end
                local prefix = fzf.utils.ansi_from_hl(highlight, entry.value)
                fzf_cb(prefix .. " " .. entry.obj.title)
              end
            end
          end
        end,
        cb = function()
          fzf_cb()
        end,
      },
    }
  end

  fzf.fzf_exec(get_contents, {
    prompt = picker_utils.get_prompt(prompt_title),
    previewer = previewers.issue(formatted_pulls, pull_order),
    fzf_opts = {
      ["--no-multi"] = "", -- TODO this can support multi, maybe.
      ["--info"] = "default",
    },
    winopts = {
      title = window_title,
      title_pos = "center",
    },
    actions = vim.tbl_extend("force", fzf_actions.common_open_actions(formatted_pulls), {
      [utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.checkout_pr.lhs)] = function(selected)
        local entry = formatted_pulls[selected[1]]
        checkout_pull_request(entry)
      end,
      [utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.filter_mine.lhs)] = function()
        local next_opts = vim.tbl_extend("force", opts, {
          repo = requested_repo,
          prompt_title = requested_prompt_title,
          author = "@me",
          window_title = "My Pull Requests",
        })
        vim.schedule(function()
          M.picker(next_opts)
        end)
      end,
      [utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.filter_all.lhs)] = function()
        local next_opts = vim.tbl_extend("force", opts, {
          repo = requested_repo,
          prompt_title = requested_prompt_title,
          window_title = "Pull Requests",
        })
        next_opts.author = nil
        vim.schedule(function()
          M.picker(next_opts)
        end)
      end,
    }),
  })
end

setmetatable(M, {
  __call = function(_, opts)
    return M.picker(opts)
  end,
})

return M
