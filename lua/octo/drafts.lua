local M = {}

---The directory drafts live in, created on demand.
---@return string path
function M.root()
  local dir = vim.fs.joinpath(vim.fn.stdpath "state", "octo-drafts")
  vim.fn.mkdir(dir, "p")
  return dir
end

---Escapes one field so that no two distinct inputs can collide.
---
---Every character outside [A-Za-z0-9] becomes "-" plus two hex digits. That makes
---the encoding reversible, which is what a plain gsub to "_" was not: it mapped
---"/" and ":" onto the same byte, so two different thread ids produced one
---filename and one draft silently overwrote the other.
---@param field string
---@return string encoded
local function encode_field(field)
  return (field:gsub("[^%w]", function(c)
    return ("-%02X"):format(c:byte())
  end))
end

---Builds a filesystem-safe key identifying one draft.
---
---Each of the three fields is escaped independently by encode_field and joined
---with "_", which cannot appear inside an encoded field (it encodes to "-5F").
---That keeps a repo slug or GraphQL node id containing "/" or ":" from escaping
---the drafts directory, and keeps two different inputs from colliding.
---@param repo string owner/name slug
---@param kind string comment kind, e.g. "IssueComment"
---@param thread_id string|nil thread or comment id, nil for a top-level comment
---@return string key
function M.key(repo, kind, thread_id)
  return table.concat({
    encode_field(repo),
    encode_field(kind),
    encode_field(thread_id or "root"),
  }, "_")
end

---@param key string
---@return string path
local function path_for(key)
  return vim.fs.joinpath(M.root(), key)
end

---Writes draft text, replacing any previous text for this key.
---@param key string
---@param text string
---@return nil
function M.save(key, text)
  local fd = assert(vim.uv.fs_open(path_for(key), "w", 420)) -- 0644
  vim.uv.fs_write(fd, text)
  vim.uv.fs_close(fd)
end

---Reads draft text.
---@param key string
---@return string|nil text nil when no draft is stored
function M.load(key)
  local path = path_for(key)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return nil
  end
  local fd = assert(vim.uv.fs_open(path, "r", 420))
  local text = vim.uv.fs_read(fd, stat.size, 0)
  vim.uv.fs_close(fd)
  return text
end

---Removes a draft. Absent drafts are not an error.
---@param key string
---@return nil
function M.discard(key)
  vim.uv.fs_unlink(path_for(key))
end

---Removes drafts last modified more than `max_age_days` ago.
---@param max_age_days number
---@return integer removed how many drafts were deleted
function M.sweep(max_age_days)
  local dir = vim.fs.joinpath(vim.fn.stdpath "state", "octo-drafts")
  if not vim.uv.fs_stat(dir) then
    return 0
  end
  local cutoff = os.time() - (max_age_days * 24 * 60 * 60)
  local removed = 0
  for name, kind in vim.fs.dir(dir) do
    if kind == "file" then
      local path = vim.fs.joinpath(dir, name)
      local stat = vim.uv.fs_stat(path)
      if stat and stat.mtime.sec < cutoff then
        vim.uv.fs_unlink(path)
        removed = removed + 1
      end
    end
  end
  return removed
end

return M
