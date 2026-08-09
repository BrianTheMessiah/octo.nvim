---@diagnostic disable
local eq = assert.are.same

local config = require "octo.config"
local md = require "octo.pickers.fzf-lua.preview_markdown"

---Run a function with `picker_config.preview_render_markdown` temporarily set.
---@param value any the value to install for the duration of the call
---@param fn fun() body to run under that setting
local function with_render(value, fn)
  local previous = config.values.picker_config.preview_render_markdown
  config.values.picker_config.preview_render_markdown = value
  local ok, err = pcall(fn)
  config.values.picker_config.preview_render_markdown = previous
  assert(ok, err)
end

---The conceal span covering a given row, if there is exactly one.
---@param spans octo.MarkdownSpan[] spans returned by `conceal_spans`
---@param row integer zero-based row to look for
---@return octo.MarkdownSpan[] spans on that row, in column order
local function on_row(spans, row)
  local found = {}
  for _, span in ipairs(spans) do
    if span.row == row then
      table.insert(found, span)
    end
  end
  return found
end

describe("octo preview markdown:", function()
  it("defaults picker_config.preview_render_markdown to on", function()
    eq(true, config.get_default_values().picker_config.preview_render_markdown)
  end)

  it("reports whether the markdown treesitter parsers can be loaded", function()
    eq("boolean", type(md.available()))
  end)

  it("hides an ATX heading marker and the space after it", function()
    local spans = md.conceal_spans { "# Heading one" }
    eq({ { row = 0, start_col = 0, end_col = 2, replacement = "" } }, spans)
  end)

  it("hides a deeper heading marker up to six levels", function()
    eq(4, md.conceal_spans({ "### What" })[1].end_col)
    eq(7, md.conceal_spans({ "###### Deep" })[1].end_col)
    eq({}, md.conceal_spans { "####### Not a heading" })
  end)

  it("leaves a hash that starts no heading alone", function()
    eq({}, md.conceal_spans { "#hashtag is not a heading" })
    eq({}, md.conceal_spans { "issue #123 was fixed" })
  end)

  it("keeps a blockquote marker and hides only the heading inside it", function()
    local spans = md.conceal_spans { "> ## v3.1.5" }
    eq({ { row = 0, start_col = 2, end_col = 5, replacement = "" } }, spans)
  end)

  it("replaces a list bullet with a glyph rather than hiding it", function()
    local spans = md.conceal_spans { "- bullet one" }
    eq(1, #spans)
    eq(0, spans[1].start_col)
    eq(1, spans[1].end_col)
    assert.is_true(spans[1].replacement ~= "", "the bullet glyph must not be empty")
  end)

  it("keeps a nested bullet at its own indent", function()
    local spans = md.conceal_spans { "    - nested" }
    eq({ 4, 5 }, { spans[1].start_col, spans[1].end_col })
  end)

  it("treats an asterisk and a plus as bullets too", function()
    eq(1, #md.conceal_spans { "* star" })
    eq(1, #md.conceal_spans { "+ plus" })
  end)

  it("leaves a thematic break alone rather than reading it as a bullet", function()
    eq({}, md.conceal_spans { "---" })
    eq({}, md.conceal_spans { "***" })
  end)

  it("leaves a spaced thematic break alone, which does look like a bullet", function()
    eq({}, md.conceal_spans { "- - -" })
    eq({}, md.conceal_spans { "* * *" })
    eq({}, md.conceal_spans { "- - - -" })
  end)

  it("leaves a hyphen inside prose alone", function()
    eq({}, md.conceal_spans { "a well-known case" })
    eq({}, md.conceal_spans { "the range 3-5 applies" })
  end)

  it("conceals nothing inside a fenced code block", function()
    local spans = md.conceal_spans {
      "before",
      "```bash",
      "# not a heading, a shell comment",
      "- not a bullet",
      "```",
      "# a real heading",
    }
    eq({}, on_row(spans, 2))
    eq({}, on_row(spans, 3))
    eq(1, #on_row(spans, 5))
  end)

  it("closes a fence only on a fence of at least the opening length", function()
    local spans = md.conceal_spans {
      "````",
      "```",
      "# still inside the longer fence",
      "````",
      "# outside now",
    }
    eq({}, on_row(spans, 2))
    eq(1, #on_row(spans, 4))
  end)

  it("treats a tilde fence the same as a backtick fence", function()
    local spans = md.conceal_spans {
      "~~~",
      "# inside",
      "~~~",
      "# outside",
    }
    eq({}, on_row(spans, 1))
    eq(1, #on_row(spans, 3))
  end)

  it("returns spans for every row that needs one, in row order", function()
    local spans = md.conceal_spans {
      "# One",
      "plain prose",
      "- item",
      "## Two",
    }
    eq({ 0, 2, 3 }, { spans[1].row, spans[2].row, spans[3].row })
  end)

  it("handles an empty body without error", function()
    eq({}, md.conceal_spans {})
    eq({}, md.conceal_spans { "" })
  end)

  it("starts markdown highlighting on a buffer whose filetype is octo", function()
    if not md.available() then
      return
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# Heading", "Some **bold** text" })
    vim.bo[buf].filetype = "octo"

    eq(true, md.start(buf))
    eq(true, vim.treesitter.highlighter.active[buf] ~= nil)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("clears the legacy regex syntax that would otherwise conceal against its own width", function()
    if not md.available() then
      return
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "| a | b |", "| --- | --- |", "| **x** | y |" })
    vim.bo[buf].filetype = "octo"
    vim.b[buf].current_syntax = "octo"

    md.start(buf)
    eq(nil, vim.b[buf].current_syntax)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("starts a highlighter once only, however often a reused buffer is repainted", function()
    if not md.available() then
      return
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# Heading" })
    vim.bo[buf].filetype = "octo"

    local original = vim.treesitter.start
    local starts = 0
    vim.treesitter.start = function(...)
      starts = starts + 1
      return original(...)
    end
    local ok, err = pcall(function()
      eq(true, md.start(buf))
      eq(true, md.start(buf))
      eq(true, md.start(buf))
    end)
    vim.treesitter.start = original
    assert(ok, err)

    eq(1, starts)
    eq(true, vim.treesitter.highlighter.active[buf] ~= nil)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("refuses to touch a buffer that is no longer valid", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_delete(buf, { force = true })
    eq(false, md.start(buf))
  end)

  it("does nothing at all when the option is off", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# Heading" })
    vim.bo[buf].filetype = "octo"

    with_render(false, function()
      eq(false, md.decorate(buf, 0, { "# Heading" }))
      eq(0, #vim.api.nvim_buf_get_extmarks(buf, md.namespace(), 0, -1, {}))
    end)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("places its conceal extmarks in its own namespace, offset past the body's first line", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "title", "", "# Heading", "- item" })
    vim.bo[buf].filetype = "octo"

    with_render(true, function()
      eq(true, md.decorate(buf, 2, { "# Heading", "- item" }))
      local marks = vim.api.nvim_buf_get_extmarks(buf, md.namespace(), 0, -1, { details = true })
      eq(2, #marks)
      eq(2, marks[1][2])
      eq(3, marks[2][2])
      eq("", marks[1][4].conceal)
    end)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("clears its previous extmarks so a repainted buffer does not accumulate them", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "# Heading", "- item" })
    vim.bo[buf].filetype = "octo"

    with_render(true, function()
      md.decorate(buf, 0, { "# Heading", "- item" })
      md.decorate(buf, 0, { "# Heading", "- item" })
      eq(2, #vim.api.nvim_buf_get_extmarks(buf, md.namespace(), 0, -1, {}))
    end)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
