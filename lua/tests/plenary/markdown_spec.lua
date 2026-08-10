---@diagnostic disable
local eq = assert.are.same

local markdown = require "octo.ui.markdown"
local preview = require "octo.pickers.fzf-lua.preview_markdown"

describe("octo.ui.markdown core:", function()
  it("hides an ATX heading marker and the space after it", function()
    eq({ { row = 0, start_col = 0, end_col = 3, replacement = "" } }, markdown.conceal_spans { "## Heading" })
  end)

  it("replaces a list bullet with a glyph rather than hiding it", function()
    eq({ { row = 0, start_col = 0, end_col = 1, replacement = markdown.BULLET } }, markdown.conceal_spans { "- item" })
  end)

  it("conceals nothing inside a fenced code block", function()
    eq({}, markdown.conceal_spans { "```sh", "# not a heading", "```" })
  end)

  it("is the one core the preview module uses, not a second copy of it", function()
    eq(true, rawequal(markdown.conceal_spans, preview.conceal_spans))
    eq(true, rawequal(markdown.start, preview.start))
    eq(markdown.BULLET, preview.BULLET)
  end)
end)

describe("octo.ui.markdown buffer regions:", function()
  ---A scratch buffer holding lines, wiped when the returned function is called.
  ---@param lines string[]
  ---@return integer bufnr
  ---@return fun() wipe
  local function scratch(lines)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    return bufnr, function()
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end

  ---The rows this module placed a conceal extmark on, in order.
  ---@param bufnr integer
  ---@return integer[] zero-based rows
  local function concealed_rows(bufnr)
    local rows = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bufnr, markdown.buffer_namespace(), 0, -1, {})) do
      rows[#rows + 1] = mark[2]
    end
    table.sort(rows)
    return rows
  end

  it("defaults ui.render_markdown to on", function()
    eq(true, require("octo.config").values.ui.render_markdown)
  end)

  it("conceals inside a region and leaves chrome outside it untouched", function()
    -- Row 0 is chrome that looks exactly like a bullet; only rows 2-3 are the body.
    local bufnr, wipe = scratch { "- not a body bullet", "", "# heading", "- real bullet" }

    markdown.render_regions(bufnr, { { first_line = 3, last_line = 4 } })
    local rows = concealed_rows(bufnr)

    wipe()
    eq({ 2, 3 }, rows)
  end)

  it("offsets spans by the region's own first line rather than the buffer's", function()
    local bufnr, wipe = scratch { "chrome", "chrome", "## body heading" }

    markdown.render_regions(bufnr, { { first_line = 3, last_line = 3 } })
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, markdown.buffer_namespace(), 0, -1, { details = true })
    local row, start_col, details = marks[1][2], marks[1][3], marks[1][4]

    wipe()
    eq(2, row)
    eq(0, start_col)
    eq(3, details.end_col)
  end)

  it("clears its previous extmarks so a repainted buffer does not accumulate them", function()
    local bufnr, wipe = scratch { "# heading" }

    markdown.render_regions(bufnr, { { first_line = 1, last_line = 1 } })
    markdown.render_regions(bufnr, { { first_line = 1, last_line = 1 } })
    local count = #vim.api.nvim_buf_get_extmarks(bufnr, markdown.buffer_namespace(), 0, -1, {})

    wipe()
    eq(1, count)
  end)

  it("uses a namespace of its own, never the preview module's", function()
    eq(false, markdown.buffer_namespace() == preview.namespace())
  end)

  it("clamps a region that runs past the end of the buffer", function()
    local bufnr, wipe = scratch { "# heading" }

    local ok = pcall(markdown.render_regions, bufnr, { { first_line = 1, last_line = 999 } })
    local rows = concealed_rows(bufnr)

    wipe()
    eq(true, ok)
    eq({ 0 }, rows)
  end)

  it("does nothing at all when the option is off", function()
    local config = require "octo.config"
    local original = config.values.ui.render_markdown
    config.values.ui.render_markdown = false
    local bufnr, wipe = scratch { "# heading" }

    markdown.render_regions(bufnr, { { first_line = 1, last_line = 1 } })
    local count = #vim.api.nvim_buf_get_extmarks(bufnr, markdown.buffer_namespace(), 0, -1, {})

    config.values.ui.render_markdown = original
    wipe()
    eq(0, count)
  end)

  it("refuses to touch a buffer that is no longer valid", function()
    local bufnr, wipe = scratch { "# heading" }
    wipe()

    eq(false, markdown.render_regions(bufnr, { { first_line = 1, last_line = 1 } }))
  end)
end)
