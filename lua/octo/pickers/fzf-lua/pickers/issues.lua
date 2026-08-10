---@diagnostic disable
local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"
local entry_maker = require "octo.pickers.fzf-lua.entry_maker"
local fzf = require "fzf-lua"
local gh = require "octo.gh"
local graphql = require "octo.gh.graphql"
local queries = require "octo.gh.queries"
local octo_config = require "octo.config"
local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local previewers = require "octo.pickers.fzf-lua.previewers"
local utils = require "octo.utils"

local M = {}

---The fzf options every issue list carries.
---
---Pulled out of `M.picker` so a test can see the exact header the picker hands
---`fzf.fzf_exec`, rather than the shared builder in isolation.
---@return table fzf_opts the options to hand fzf
function M.fzf_opts()
  return {
    ["--no-multi"] = "", -- TODO this can support multi, maybe.
    ["--header"] = picker_utils.help_header(),
    ["--info"] = "default",
  }
end

---The actions the issue list carries.
---
---With a `cb`, the picker was opened to choose one issue for a caller (e.g. linking
---a related issue), so `default` hands that issue straight to `cb` and none of the
---usual open/browse/copy keys apply. Without one, the shared open/browse/copy keys
---carry the list as normal. Either way this task's own help key is merged in last,
---so both callers of this picker keep a working keymap float.
---
---Pulled out of `M.picker` so a test can see the exact actions table the picker
---hands `fzf.fzf_exec`, rather than asserting against a rebuilt copy.
---@param formatted_issues table<string, table> entry.ordinal -> entry
---@param cb fun(entry: table)|nil the callback that receives the chosen entry, if any
---@return table<string, function> actions keyed by fzf key
function M.list_actions(formatted_issues, cb)
  if cb then
    return vim.tbl_extend("force", {
      ["default"] = function(selected)
        cb(formatted_issues[selected[1]])
      end,
    }, fzf_actions.help_action())
  end
  return vim.tbl_extend("force", fzf_actions.common_open_actions(formatted_issues), fzf_actions.help_action())
end

---Opens the fzf-lua issue picker.
---@param opts? table `repo`, `window_title`, `prompt_title`, `states`, `cb`
function M.picker(opts)
  opts = opts or {}
  if not opts.states then
    opts.states = { "OPEN" }
  end

  local repo = utils.pop_key(opts, "repo")
  if utils.is_blank(repo) then
    repo = utils.get_remote_name()
  end

  if not repo then
    utils.error "Cannot find repo"
    return
  end

  local owner, name = utils.split_repo(repo)

  local window_title = utils.pop_key(opts, "window_title") or "Issues"
  local prompt_title = utils.pop_key(opts, "prompt_title")
  local cb = utils.pop_key(opts, "cb")

  local formatted_issues = {} ---@type table<string, table> entry.ordinal -> entry
  local issue_order = {} ---@type string[] entry.ordinal in list order

  local function get_contents(fzf_cb)
    gh.api.graphql {
      query = queries.issues,
      F = {
        owner = owner,
        name = name,
        filter_by = opts,
        order_by = octo_config.values.issues.order_by,
      },
      paginate = true,
      jq = ".",
      opts = {
        stream_cb = function(data, err)
          if err and not utils.is_blank(err) then
            utils.error(err)
            fzf_cb()
          elseif data then
            local resp = utils.aggregate_pages(data, "data.repository.issues.nodes")
            local issues = resp.data.repository.issues.nodes

            for _, issue in ipairs(issues) do
              local entry = entry_maker.gen_from_issue(issue)

              if entry ~= nil then
                formatted_issues[entry.ordinal] = entry
                table.insert(issue_order, entry.ordinal)
                local prefix = fzf.utils.ansi_from_hl("Comment", entry.value)
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
    previewer = previewers.issue(formatted_issues, issue_order),
    fzf_opts = M.fzf_opts(),
    winopts = {
      title = window_title,
      title_pos = "center",
    },
    actions = M.list_actions(formatted_issues, cb),
  })
end

setmetatable(M, {
  __call = function(_, opts)
    return M.picker(opts)
  end,
})

return M
