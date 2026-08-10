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
