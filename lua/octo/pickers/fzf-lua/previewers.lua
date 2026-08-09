---@diagnostic disable
local OctoBuffer = require("octo.model.octo-buffer").OctoBuffer
local notifications = require "octo.notifications"
local builtin = require "fzf-lua.previewer.builtin"
local gh = require "octo.gh"
local headers = require "octo.gh.headers"
local graphql = require "octo.gh.graphql"
local queries = require "octo.gh.queries"
local utils = require "octo.utils"
local writers = require "octo.ui.writers"
local config = require "octo.config"
local html = require "octo.ui.html"
local preview_cache = require "octo.pickers.fzf-lua.preview_cache"
local preview_markdown = require "octo.pickers.fzf-lua.preview_markdown"
local preview_prefetch = require "octo.pickers.fzf-lua.preview_prefetch"

local M = {}

---Inherit from the "buffer_or_file" previewer
---@class octo.fzf-lua.Previewer : fzf-lua.previewer.BufferOrFile
M.bufferPreviewer = builtin.buffer_or_file:extend()

function M.bufferPreviewer:new(o, opts, fzf_win)
  M.bufferPreviewer.super.new(self, o, opts, fzf_win)
  setmetatable(self, M.bufferPreviewer)
  -- self.title = true
  return self
end

function M.bufferPreviewer:parse_entry(entry_str)
  -- Assume an arbitrary entry in the format of 'file:line'
  local path, line = entry_str:match "([^:]+):?(.*)"
  return {
    path = path,
    line = tonumber(line) or 1,
    col = 1,
  }
end

---Whether this previewer's content is prose that should soft-wrap. Diffs, patches,
---review-thread snippets and source listings leave this false so their column
---alignment survives.
M.bufferPreviewer.octo_wrap = false

---Whether this previewer renders markdown, and so needs conceal turned on. Only the
---previewers that start a markdown highlighter set this: raising `conceallevel` over
---the legacy regex syntax alone is what makes fixed-column content ragged.
M.bufferPreviewer.octo_conceal = false

---Whether prose previewers should soft-wrap, per `picker_config.preview_wrap`.
---@return boolean true when long body lines should be wrapped rather than clipped
function M.wrap_prose()
  return config.values.picker_config.preview_wrap ~= false
end

---Whether preview bodies should have their markdown rendered.
---@return boolean true when it is both wanted and the treesitter parsers are present
function M.render_markdown()
  return preview_markdown.enabled() and preview_markdown.available()
end

---Window options for an octo preview: never numbered, wrapped only for prose, and
---concealing only where a markdown highlighter supplies the conceal ranges.
---@return table winopts merged over the previewer's own `winopts`
function M.bufferPreviewer:gen_winopts()
  local new_winopts = {
    wrap = self.octo_wrap,
    number = false,
    conceallevel = self.octo_conceal and 2 or 0,
    concealcursor = self.octo_conceal and "nvic" or "",
  }
  return vim.tbl_extend("force", self.winopts, new_winopts)
end

function M.bufferPreviewer:update_border(title)
  self.win:update_preview_title(title)
  self.win:update_preview_scrollbar()
end

---The GraphQL query that fetches everything a preview renders for one item.
---@param kind string octo entry kind, "issue" or "pull_request"
---@param owner string repository owner
---@param name string repository name
---@param number string|integer the issue or pull request number
---@return string? query nil for a kind that has no preview query
local function preview_query(kind, owner, name, number)
  if kind == "issue" then
    return graphql("issue_query", owner, name, number, _G.octo_pv2_fragment)
  elseif kind == "pull_request" then
    return graphql("pull_request_query", owner, name, number, _G.octo_pv2_fragment)
  end
end

---Pull the issue or pull request node out of a decoded preview response.
---@param kind string octo entry kind, "issue" or "pull_request"
---@param output string raw JSON returned by `gh api graphql`
---@return table? node nil when the response cannot be decoded or holds no node
local function decode_preview(kind, output)
  local ok, result = pcall(vim.json.decode, output)
  if not ok or type(result) ~= "table" or not result.data or not result.data.repository then
    return nil
  end
  if kind == "issue" then
    return result.data.repository.issue
  elseif kind == "pull_request" then
    return result.data.repository.pullRequest
  end
end

---Start one preview fetch. Writes nothing to any buffer or window: it decodes the
---response and hands the payload to `done`, which is what makes a completion that
---outlives its picker harmless.
---@param kind string octo entry kind, "issue" or "pull_request"
---@param repo string "owner/name" the item belongs to
---@param number string|integer the issue or pull request number
---@param done fun(payload: table?) called with the decoded node, or nil on failure
local function fetch_preview(kind, repo, number, done)
  local owner, name = utils.split_repo(repo)
  local query = preview_query(kind, owner, name, number)
  if not query then
    done(nil)
    return
  end
  gh.api.graphql {
    f = { query = query },
    opts = {
      cb = function(output, stderr)
        if stderr and not utils.is_blank(stderr) then
          done(nil)
        else
          done(decode_preview(kind, output))
        end
      end,
    },
  }
end

---A shallow copy of a payload whose body has had its inline HTML rewritten as
---markdown. The cached payload itself is never touched, so what the cache holds
---stays the raw response and the transform is derived per paint.
---@param obj table decoded issue or pull request node
---@return table obj to hand to the writers
local function with_rendered_body(obj)
  if config.values.picker_config.preview_render_html == false then
    return obj
  end
  return vim.tbl_extend("keep", { body = html.to_markdown(obj.body) }, obj)
end

---Paint a fetched preview payload into a buffer.
---@param bufnr integer buffer to write into, already validated by the caller
---@param kind string octo entry kind, "issue" or "pull_request"
---@param number string|integer the issue or pull request number, used for the state line
---@param obj table decoded issue or pull request node
local function render_preview(bufnr, kind, number, obj)
  local state = utils.get_displayed_state(kind == "issue", obj.state, obj.stateReason)

  writers.write_title(bufnr, obj.title, 1)
  writers.write_details(bufnr, obj, false, true)

  local body_first = vim.api.nvim_buf_line_count(bufnr)
  writers.write_body(bufnr, with_rendered_body(obj))
  local body_lines = vim.api.nvim_buf_get_lines(bufnr, body_first, -1, false)

  writers.write_state(bufnr, state:upper(), number)
  local reactions_line = vim.api.nvim_buf_line_count(bufnr) - 1
  writers.write_block(bufnr, { "", "" }, reactions_line)
  writers.write_reactions(bufnr, obj.reactionGroups, reactions_line)
  vim.bo[bufnr].filetype = "octo"
  preview_markdown.render(bufnr, body_first, body_lines)
end

---Previewer for a list of issues or pull requests.
---@param formatted_issues table<string, table> entry keyed by its entry string
---@param order? string[] entry strings in list order; enables prefetching ahead of the cursor
---@return octo.fzf-lua.Previewer
function M.issue(formatted_issues, order)
  ---@type octo.fzf-lua.Previewer
  local previewer = M.bufferPreviewer:extend()
  previewer.octo_wrap = M.wrap_prose()
  previewer.octo_conceal = M.render_markdown()

  function previewer:new(o, opts, fzf_win)
    M.bufferPreviewer.super.new(self, o, opts, fzf_win)
    self.title = "Issues"
    setmetatable(self, previewer)
    return self
  end

  local cache = preview_cache.new()
  local positions ---@type table<string, integer>?
  local previous_position ---@type integer?

  ---Warm the cache for the entries just beyond the cursor, in its direction of
  ---travel. Warming writes only to the cache, never to a buffer or a window.
  ---@param entry_str string the entry now under the cursor
  local function warm_neighbours(entry_str)
    local window = preview_prefetch.window()
    if window == 0 or not order or #order == 0 then
      return
    end
    if not positions or vim.tbl_count(positions) ~= #order then
      positions = preview_prefetch.positions_of(order)
    end
    local from = positions[entry_str]
    if not from then
      return
    end
    for _, target in ipairs(preview_prefetch.targets(order, from, previous_position, window)) do
      local neighbour = formatted_issues[target]
      if neighbour then
        local key = preview_cache.key(neighbour.kind, neighbour.repo, neighbour.value)
        cache:request(key, function(done)
          fetch_preview(neighbour.kind, neighbour.repo, neighbour.value, done)
        end)
      end
    end
    previous_position = from
  end

  function previewer:close(do_not_clear_cache)
    cache:abandon()
    return previewer.super.close(self, do_not_clear_cache)
  end

  function previewer:populate_preview_buf(entry_str)
    local tmpbuf = self:get_tmp_buffer()
    local entry = formatted_issues[entry_str]
    local key = preview_cache.key(entry.kind, entry.repo, entry.value)
    self.octo_preview_key = key

    local cached = cache:get(key)
    if cached then
      render_preview(tmpbuf, entry.kind, entry.value, cached)
    else
      cache:request(key, function(done)
        fetch_preview(entry.kind, entry.repo, entry.value, done)
      end, function(payload)
        if self.octo_preview_key == key and self.preview_bufnr == tmpbuf and vim.api.nvim_buf_is_valid(tmpbuf) then
          render_preview(tmpbuf, entry.kind, entry.value, payload)
        end
      end)
    end

    self:set_preview_buf(tmpbuf)
    self:update_border(entry.ordinal)
    warm_neighbours(entry_str)
  end

  return previewer
end

function M.search()
  ---@type octo.fzf-lua.Previewer
  local previewer = M.bufferPreviewer:extend()
  previewer.octo_wrap = M.wrap_prose()
  previewer.octo_conceal = M.render_markdown()

  function previewer:new(o, opts, fzf_win)
    M.bufferPreviewer.super.new(self, o, opts, fzf_win)
    self.title = "Issues"
    setmetatable(self, previewer)
    return self
  end

  local cache = preview_cache.new()

  function previewer:close(do_not_clear_cache)
    cache:abandon()
    return previewer.super.close(self, do_not_clear_cache)
  end

  function previewer:populate_preview_buf(entry_str)
    local tmpbuf = self:get_tmp_buffer()
    local match = string.gmatch(entry_str, "[^%s]+")
    local kind = match()
    local owner = match()
    local name = match()
    local number = tonumber(match())
    local repo = string.format("%s/%s", owner, name)
    local key = preview_cache.key(kind, repo, number)
    self.octo_preview_key = key

    local cached = cache:get(key)
    if cached then
      render_preview(tmpbuf, kind, number, cached)
    else
      cache:request(key, function(done)
        fetch_preview(kind, repo, number, done)
      end, function(payload)
        if self.octo_preview_key == key and self.preview_bufnr == tmpbuf and vim.api.nvim_buf_is_valid(tmpbuf) then
          render_preview(tmpbuf, kind, number, payload)
        end
      end)
    end

    self:set_preview_buf(tmpbuf)
    self.win:update_preview_scrollbar()
  end

  return previewer
end

function M.commit(formatted_commits, repo)
  ---@type octo.fzf-lua.Previewer
  local previewer = M.bufferPreviewer:extend()

  function previewer:new(o, opts, fzf_win)
    M.bufferPreviewer.super.new(self, o, opts, fzf_win)
    setmetatable(self, previewer)
    return self
  end

  function previewer:populate_preview_buf(entry_str)
    local tmpbuf = self:get_tmp_buffer()
    local entry = formatted_commits[entry_str]

    local lines = {}
    vim.list_extend(lines, { string.format("Commit: %s", entry.value) })
    vim.list_extend(lines, { string.format("Author: %s", entry.author) })
    vim.list_extend(lines, { string.format("Date: %s", entry.date) })
    vim.list_extend(lines, { "" })
    vim.list_extend(lines, vim.split(entry.msg, "\n"))
    vim.list_extend(lines, { "" })

    vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, lines)
    vim.bo[tmpbuf].filetype = "git"
    vim.api.nvim_buf_add_highlight(tmpbuf, -1, "OctoDetailsLabel", 0, 0, string.len "Commit:")
    vim.api.nvim_buf_add_highlight(tmpbuf, -1, "OctoDetailsLabel", 1, 0, string.len "Author:")
    vim.api.nvim_buf_add_highlight(tmpbuf, -1, "OctoDetailsLabel", 2, 0, string.len "Date:")

    local url = string.format("/repos/%s/commits/%s", repo, entry.value)
    local cmd = table.concat({ "gh", "api", "--paginate", url, "-H", headers.diff }, " ")
    local proc = io.popen(cmd, "r")
    local output ---@type string
    if proc ~= nil then
      output = proc:read "*a"
      proc:close()
    else
      output = "Failed to read from " .. url
    end

    vim.api.nvim_buf_set_lines(tmpbuf, #lines, -1, false, vim.split(output, "\n"))

    self:set_preview_buf(tmpbuf)
    self:update_border(entry.ordinal)
  end

  return previewer
end

function M.changed_files(formatted_files)
  ---@type octo.fzf-lua.Previewer
  local previewer = M.bufferPreviewer:extend()

  function previewer:new(o, opts, fzf_win)
    M.bufferPreviewer.super.new(self, o, opts, fzf_win)
    setmetatable(self, previewer)
    return self
  end

  function previewer:populate_preview_buf(entry_str)
    local tmpbuf = self:get_tmp_buffer()
    local entry = formatted_files[entry_str]

    local diff = entry.change.patch
    if diff then
      vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, vim.split(diff, "\n"))
      vim.bo[tmpbuf].filetype = "git"
    end

    self:set_preview_buf(tmpbuf)
    self:update_border(entry.ordinal)
  end

  return previewer
end

function M.review_thread(formatted_threads)
  ---@type octo.fzf-lua.Previewer
  local previewer = M.bufferPreviewer:extend()

  function previewer:new(o, opts, fzf_win)
    M.bufferPreviewer.super.new(self, o, opts, fzf_win)
    setmetatable(self, previewer)
    return self
  end

  function previewer:populate_preview_buf(entry_str)
    local tmpbuf = self:get_tmp_buffer()
    local entry = formatted_threads[entry_str]

    local buffer = OctoBuffer:new {
      bufnr = tmpbuf,
    }
    buffer:configure()
    buffer:render_threads { entry.thread }
    vim.api.nvim_buf_call(tmpbuf, function()
      vim.cmd [[setlocal foldmethod=manual]]
      vim.cmd [[normal! zR]]
    end)

    self:set_preview_buf(tmpbuf)
    self:update_border(entry.ordinal)
  end

  return previewer
end

function M.gist(formatted_gists)
  ---@type octo.fzf-lua.Previewer
  local previewer = M.bufferPreviewer:extend()

  function previewer:new(o, opts, fzf_win)
    M.bufferPreviewer.super.new(self, o, opts, fzf_win)
    setmetatable(self, previewer)
    return self
  end

  function previewer:populate_preview_buf(entry_str)
    local tmpbuf = self:get_tmp_buffer()

    local entry = formatted_gists[entry_str]

    local file = entry.gist.files[1]
    if file.text then
      vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, vim.split(file.text, "\n"))
    else
      vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, entry.gist.description)
    end
    vim.api.nvim_buf_call(tmpbuf, function()
      pcall(vim.cmd, "set filetype=" .. string.gsub(file.extension, "\\.", ""))
    end)

    self:set_preview_buf(tmpbuf)
    self:update_border(entry.gist.description)
  end

  return previewer
end

function M.repo(formatted_repos)
  ---@type octo.fzf-lua.Previewer
  local previewer = M.bufferPreviewer:extend()

  function previewer:new(o, opts, fzf_win)
    M.bufferPreviewer.super.new(self, o, opts, fzf_win)
    setmetatable(self, previewer)
    return self
  end

  function previewer:populate_preview_buf(entry_str)
    local tmpbuf = self:get_tmp_buffer()
    local entry = formatted_repos[entry_str]

    local buffer = OctoBuffer:new {
      bufnr = tmpbuf,
    }
    buffer:configure()
    local repo_name_owner = vim.split(entry_str, " ")[1]
    local owner, name = utils.split_repo(repo_name_owner)

    local function cb(output, _)
      -- when the entry changes `preview_bufnr` will also change (due to `set_preview_buf`)
      -- and `tmpbuf` within this context is already cleared and invalidated
      if self.preview_bufnr == tmpbuf and vim.api.nvim_buf_is_valid(tmpbuf) then
        local resp = vim.json.decode(output)
        buffer.node = resp.data.repository
        buffer.kind = "repo"
        buffer:render_repo()
      end
    end
    gh.api.graphql {
      query = queries.repository,
      f = { owner = owner, name = name },
      paginate = true,
      jq = ".",
      opts = { cb = cb },
    }
    self:set_preview_buf(tmpbuf)

    ---@type string, string
    local stargazer, fork
    if config.values.picker_config.use_emojis then
      stargazer = string.format("💫: %s", entry.repo.stargazerCount)
      fork = string.format("🔱: %s", entry.repo.forkCount)
    else
      stargazer = string.format("s: %s", entry.repo.stargazerCount)
      fork = string.format("f: %s", entry.repo.forkCount)
    end
    self:update_border(string.format("%s (%s, %s)", repo_name_owner, stargazer, fork))
  end

  return previewer
end

function M.issue_template(formatted_templates)
  ---@type octo.fzf-lua.Previewer
  local previewer = M.bufferPreviewer:extend()
  previewer.octo_wrap = M.wrap_prose()

  function previewer:new(o, opts, fzf_win)
    M.bufferPreviewer.super.new(self, o, opts, fzf_win)
    setmetatable(self, previewer)
    return self
  end

  function previewer:populate_preview_buf(entry_str)
    local tmpbuf = self:get_tmp_buffer()
    local entry = formatted_templates[entry_str]
    local template = entry.template.body

    if template then
      vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, vim.split(template, "\n"))
      vim.bo[tmpbuf].filetype = "markdown"
    end

    self:set_preview_buf(tmpbuf)
    self:update_border(entry.value)
    self.win:update_preview_scrollbar()
  end

  return previewer
end

---@param formatted_notifications table<string, octo.NotificationEntry>
---@param cached_notification_infos table<string, any>
---@return fzf-lua.previewer.BufferOrFile
function M.notifications(formatted_notifications, cached_notification_infos)
  local previewer = M.bufferPreviewer:extend() ---@type fzf-lua.previewer.BufferOrFile
  previewer.octo_wrap = M.wrap_prose()

  function previewer:new(o, opts, fzf_win)
    M.bufferPreviewer.super.new(self, o, opts, fzf_win)
    setmetatable(self, previewer)
    return self
  end

  function previewer:populate_preview_buf(entry_str)
    local tmpbuf = self:get_tmp_buffer() ---@type integer
    local entry = formatted_notifications[entry_str]
    local number = entry.value ---@type string
    local owner, name = utils.split_repo(entry.repo)
    local kind = entry.kind
    local preview = notifications.get_preview_fn(kind)
    local cached_notification = cached_notification_infos[entry.ordinal]

    if cached_notification then
      preview(cached_notification, tmpbuf)
    end

    notifications.fetch_preview(owner, name, number, kind, function(obj)
      cached_notification_infos[entry.ordinal] = obj
      if self.preview_bufnr == tmpbuf and vim.api.nvim_buf_is_valid(tmpbuf) then
        preview(obj, tmpbuf)
      end
    end)
    self:set_preview_buf(tmpbuf)
    self:update_border(entry.value)
    self.win:update_preview_scrollbar()
  end

  return previewer
end

return M
