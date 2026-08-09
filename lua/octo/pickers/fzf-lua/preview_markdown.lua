---Renders the markdown in a picker preview rather than showing its source.
---
---A preview buffer carries filetype `octo`, and `after/syntax/octo.vim` sources
---Vim's legacy regex markdown syntax into it. That syntax's `concealends` rules
---measure width without accounting for what conceal removes, so raising
---`conceallevel` over it makes fixed-column content ragged. `vim.treesitter.start`
---clears `b:current_syntax`, taking those rules with it, and replaces them with the
---`markdown`/`markdown_inline` queries — whose own `@conceal` captures hide emphasis
---delimiters, backticks and link targets at the right width.
---
---Treesitter is used directly rather than through a markdown rendering plugin: such
---a plugin attaches by filetype, forces its own `wrap` and `conceallevel` onto every
---window showing the buffer, and sizes headings and code blocks from `vim.o.columns`
---rather than the window's width, all of which fight a narrow preview float.
---
---What treesitter leaves visible is the block-level punctuation its shipped queries
---deliberately leave alone: ATX heading markers and list bullets. `conceal_spans` is
---the pure description of those, so the transform is asserted without a window.
local config = require "octo.config"

local M = {}

---The glyph a list bullet is shown as. Built with `nr2char` so a glyph that fails to
---survive transit is an error here rather than an empty conceal that silently eats
---the bullet.
M.BULLET = vim.fn.nr2char(0x2022)

---Greatest number of `#` characters that still opens an ATX heading.
M.MAX_HEADING_LEVEL = 6

---@class octo.MarkdownSpan
---@field row integer zero-based row within the lines handed to `conceal_spans`
---@field start_col integer zero-based byte column the span starts at
---@field end_col integer byte column the span ends at, exclusive
---@field replacement string what to show instead, empty to hide entirely

local namespace = vim.api.nvim_create_namespace "octo_preview_markdown"

---The extmark namespace this module owns.
---@return integer namespace passed to every extmark call made here
function M.namespace()
  return namespace
end

---Whether markdown rendering is wanted, per `picker_config.preview_render_markdown`.
---@return boolean true unless the option is explicitly false
function M.enabled()
  return config.values.picker_config.preview_render_markdown ~= false
end

---Whether both markdown treesitter parsers can be loaded.
---
---`markdown` alone highlights block structure; the inline delimiters that most of
---the rendering depends on live in `markdown_inline`, so both are required.
---@return boolean
function M.available()
  for _, lang in ipairs { "markdown", "markdown_inline" } do
    local ok, added = pcall(vim.treesitter.language.add, lang)
    if not ok or not added then
      return false
    end
  end
  return true
end

---The length of the fence a line opens or closes, zero when it is not a fence.
---@param line string one buffer line
---@return integer length number of fence characters, 0 when the line opens no fence
---@return string? char the fence character, nil when the line opens no fence
local function fence_at(line)
  local run = line:match "^%s*(```+)"
  if run then
    return #run, "`"
  end
  run = line:match "^%s*(~~~+)"
  if run then
    return #run, "~"
  end
  return 0, nil
end

---The span hiding an ATX heading's marker, if the line opens one.
---@param line string one buffer line
---@param row integer zero-based row of that line
---@return octo.MarkdownSpan? span nil when the line is not an ATX heading
local function heading_span(line, row)
  local prefix, hashes = line:match "^([%s>]*)(#+)%s"
  if not hashes or #hashes > M.MAX_HEADING_LEVEL then
    return nil
  end
  return { row = row, start_col = #prefix, end_col = #prefix + #hashes + 1, replacement = "" }
end

---The span replacing a list bullet with a glyph, if the line opens one.
---
---A thematic break is three or more of the same marker alone on the line, which a
---bullet test would otherwise claim; it is excluded before anything else.
---@param line string one buffer line
---@param row integer zero-based row of that line
---@return octo.MarkdownSpan? span nil when the line is not a bullet item
local function bullet_span(line, row)
  if line:match "^%s*([-*_])%s*%1%s*%1[%s%-*_]*$" then
    return nil
  end
  local indent = line:match "^(%s*)[-*+]%s"
  if not indent then
    return nil
  end
  return { row = row, start_col = #indent, end_col = #indent + 1, replacement = M.BULLET }
end

---Conceal spans for the block punctuation treesitter's markdown queries leave visible.
---
---Pure: it reads lines and returns a description. Lines inside a fenced code block
---produce nothing, so a shell comment is not mistaken for a heading.
---@param lines string[] body lines, in buffer order
---@return octo.MarkdownSpan[] spans in row order, then column order
function M.conceal_spans(lines)
  local spans = {}
  local fence_length, fence_char = 0, nil

  for index, line in ipairs(lines) do
    local length, char = fence_at(line)
    if fence_char then
      if char == fence_char and length >= fence_length then
        fence_length, fence_char = 0, nil
      end
    elseif length > 0 then
      fence_length, fence_char = length, char
    else
      local span = heading_span(line, index - 1) or bullet_span(line, index - 1)
      if span then
        table.insert(spans, span)
      end
    end
  end

  return spans
end

---Start markdown treesitter highlighting on a preview buffer.
---
---Idempotent: a buffer fzf-lua hands back for reuse may already be highlighted, and
---starting again would leave a second highlighter attached to it.
---@param bufnr integer buffer to highlight
---@return boolean started true when the buffer now has a markdown highlighter
function M.start(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or not M.available() then
    return false
  end
  if vim.treesitter.highlighter.active[bufnr] then
    return true
  end
  return pcall(vim.treesitter.start, bufnr, "markdown")
end

---Apply the conceal spans for a body to a preview buffer.
---@param bufnr integer buffer to decorate
---@param first_line integer zero-based buffer row the body's first line sits on
---@param lines string[] the body lines, in buffer order
---@return boolean applied false when rendering is off or the buffer is gone
function M.decorate(bufnr, first_line, lines)
  if not M.enabled() or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  for _, span in ipairs(M.conceal_spans(lines)) do
    pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace, first_line + span.row, span.start_col, {
      end_col = span.end_col,
      conceal = span.replacement,
    })
  end
  return true
end

---Render the markdown in a preview buffer: highlighting plus the conceal spans.
---@param bufnr integer buffer already painted by the writers
---@param first_line integer zero-based buffer row the body's first line sits on
---@param lines string[] the body lines, in buffer order
---@return boolean rendered false when rendering is off or unavailable
function M.render(bufnr, first_line, lines)
  if not M.enabled() then
    return false
  end
  local started = M.start(bufnr)
  M.decorate(bufnr, first_line, lines)
  return started
end

return M
