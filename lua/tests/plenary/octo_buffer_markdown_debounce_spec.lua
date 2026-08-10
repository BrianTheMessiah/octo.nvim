---@diagnostic disable
local OctoBuffer = require("octo.model.octo-buffer").OctoBuffer
local constants = require "octo.constants"
local eq = assert.are.same

describe("OctoBuffer markdown debounce wiring:", function()
  ---An OctoBuffer over a real scratch buffer, configured once.
  ---@return OctoBuffer buffer
  ---@return integer bufnr
  local function configured_buffer()
    local bufnr = vim.api.nvim_create_buf(false, true)
    local buffer = OctoBuffer:new {
      bufnr = bufnr,
      number = 1,
      repo = "owner/name",
      node = {},
      kind = "issue",
      commentsMetadata = {},
      threadsMetadata = {},
    }
    buffer:configure()
    return buffer, bufnr
  end

  ---Counts distinct autocmd registrations (by id, not by event -- a single
  ---registration for {"TextChanged", "TextChangedI"} legitimately produces two
  ---entries, one per event, from nvim_get_autocmds) whose desc contains
  ---desc_pattern.
  ---@param bufnr integer
  ---@param desc_pattern string plain substring to match against each autocmd's desc
  ---@return integer count of distinct buffer-local autocmd ids
  local function count_autocmds(bufnr, desc_pattern)
    local ids = {}
    for _, entry in ipairs(vim.api.nvim_get_autocmds { buffer = bufnr }) do
      if entry.desc and entry.desc:find(desc_pattern, 1, true) then
        ids[entry.id] = true
      end
    end
    return vim.tbl_count(ids)
  end

  it("registers exactly one debounce autocmd no matter how many times configure() runs", function()
    local buffer, bufnr = configured_buffer()

    -- BufEnter re-invokes configure() on the same already-existing OctoBuffer every
    -- time its window is re-entered (see lua/octo/init.lua configure_octo_buffer),
    -- so this loop is simulating ordinary window switching, not a contrived case.
    buffer:configure()
    buffer:configure()

    local count = count_autocmds(bufnr, "keep the rendered markdown current")
    vim.api.nvim_buf_delete(bufnr, { force = true })

    eq(1, count)
  end)

  it("registers exactly one teardown autocmd no matter how many times configure() runs", function()
    local buffer, bufnr = configured_buffer()

    buffer:configure()
    buffer:configure()

    local count = count_autocmds(bufnr, "stop the markdown debounce timer")
    vim.api.nvim_buf_delete(bufnr, { force = true })

    eq(1, count)
  end)

  it("stops and releases the debounce timer when the buffer is wiped out", function()
    local buffer, bufnr = configured_buffer()

    buffer:schedule_render_markdown()
    assert.is_not_nil(buffer.markdown_timer)

    vim.api.nvim_buf_delete(bufnr, { force = true })

    eq(nil, buffer.markdown_timer)
  end)

  it("clears ready on teardown so nothing else tries to render into the dead buffer", function()
    local buffer, bufnr = configured_buffer()
    buffer.ready = true

    vim.api.nvim_buf_delete(bufnr, { force = true })

    eq(false, buffer.ready)
  end)

  it("reuses one timer across repeated edits rather than allocating one per keystroke", function()
    local buffer, bufnr = configured_buffer()

    buffer:schedule_render_markdown()
    local first_timer = buffer.markdown_timer
    buffer:schedule_render_markdown()
    local second_timer = buffer.markdown_timer

    buffer:stop_markdown_timer()
    vim.api.nvim_buf_delete(bufnr, { force = true })

    eq(true, first_timer == second_timer)
  end)

  it("render_markdown raises nothing when called against a buffer that is no longer valid", function()
    local buffer, bufnr = configured_buffer()
    -- markdown_regions() only ever touches the API if there is metadata to read;
    -- without a real extmark this test would pass vacuously, without exercising
    -- the actual crash path at all. Give the body a real extmark, the way
    -- render_issue/render_repo/etc. would, so markdown_regions() actually calls
    -- nvim_buf_get_extmark_by_id.
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "body text" })
    buffer.bodyMetadata.extmark = vim.api.nvim_buf_set_extmark(bufnr, constants.OCTO_COMMENT_NS, 0, 0, {})
    vim.api.nvim_buf_delete(bufnr, { force = true })

    -- Simulates a debounced callback that lands after teardown despite the
    -- BufWipeout handler: render_markdown's own validity guard must still hold
    -- even if `ready` were never reset (it evaluates markdown_regions() as an
    -- argument to markdown.render_regions, ahead of that function's own guard,
    -- so this check cannot be left to render_regions alone).
    buffer.ready = true

    local ok = pcall(function()
      buffer:render_markdown()
    end)

    eq(true, ok)
  end)

  it("an edit followed immediately by wiping the buffer raises nothing once the debounce fires", function()
    local buffer, bufnr = configured_buffer()

    -- Simulates typing (TextChangedI schedules the debounce timer) immediately
    -- followed by closing the buffer inside the 150ms window -- the exact
    -- sequence the reviewer reproduced the crash with.
    buffer:schedule_render_markdown()
    vim.api.nvim_buf_delete(bufnr, { force = true })

    -- The BufWipeout handler stops the timer synchronously, so pumping the
    -- event loop past the debounce delay must not run render_markdown again.
    vim.wait(250, function()
      return false
    end)

    eq(nil, buffer.markdown_timer)
  end)
end)
