---Renders the markdown in a picker preview rather than showing its source.
---
---The transform itself lives in `octo.ui.markdown`, which live octo buffers share.
---What is preview-specific stays here: the `picker_config` gate, the preview extmark
---namespace, and painting a body that begins partway down a buffer.
local config = require "octo.config"
local markdown = require "octo.ui.markdown"

local M = {}

M.BULLET = markdown.BULLET
M.MAX_HEADING_LEVEL = markdown.MAX_HEADING_LEVEL
M.conceal_spans = markdown.conceal_spans
M.available = markdown.available
M.start = markdown.start

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
  for _, span in ipairs(markdown.conceal_spans(lines)) do
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
  local started = markdown.start(bufnr)
  M.decorate(bufnr, first_line, lines)
  return started
end

return M
