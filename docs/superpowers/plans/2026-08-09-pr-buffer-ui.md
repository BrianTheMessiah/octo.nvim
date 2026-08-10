# PR Buffer UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give octo buffers rendered markdown, a loading float on the list-to-buffer transition, a keymap helper reachable from popups, buffers and fzf, and per-section action buttons.

**Architecture:** Three existing modules each hand their generic half to a new module and delegate, so there is one `conceal_spans`, one spinner and one `terse()`. Two further new modules (`ui/buttons.lua`, `ui/pr-loading.lua`) build on those cores. Every new surface is gated by a config value defaulting true, and every pure function is asserted headlessly without opening a window.

**Tech Stack:** Lua, Neovim 0.12.4 API (extmarks, `virt_lines`, treesitter, float `footer`), plenary.busted, fzf-lua.

## Global Constraints

- Worktree: `/home/brianthemessiah/src/octo.nvim-prui`, branch `feat/pr-buffer-ui`, off `master` (23328a9). Run every command from that directory.
- Test dependencies are siblings of the worktree: `../plenary.nvim` (symlinked to `~/.local/share/nvim/lazy/plenary.nvim`) and `../fzf-lua`. Both already exist.
- Run one spec: `nvim --headless --noplugin -u lua/tests/minimal_init.vim -c "PlenaryBustedFile lua/tests/plenary/<name>_spec.lua"`
- Run the suite: `nvim --headless --noplugin -u lua/tests/minimal_init.vim -c "PlenaryBustedDirectory lua/tests/plenary/ {minimal_init = 'lua/tests/minimal_init.vim'}"`
- Typecheck: `make check`. Format: `make format`.
- Specs open with `---@diagnostic disable` and `local eq = assert.are.same`, matching `lua/tests/plenary/review_help_bar_spec.lua`.
- Every new config value goes under `ui`, defaults to `true`, gets a `validate_type` line in `config.lua`'s `ui` block, and gets a row in `doc/octo.txt`.
- Use long-form flags in shell commands (`--message`, not `-m`). Where no long form exists (`git worktree add -b`), the short form is fine.
- Extmark writes stay inside `pcall`. Nothing in this plan may raise into a buffer render.
- Never clear a namespace you do not own. `octo_preview_markdown`, `octo_buffer_markdown` and `octo_buttons` are three distinct namespaces.

---

### Task 1: Extract the markdown core

Pure refactor. `preview_markdown.lua` keeps its public surface and its behaviour; the block-punctuation logic moves somewhere a live buffer can also reach it.

**Files:**
- Create: `lua/octo/ui/markdown.lua`
- Modify: `lua/octo/pickers/fzf-lua/preview_markdown.lua` (whole file)
- Test: `lua/tests/plenary/markdown_spec.lua`

**Interfaces:**
- Consumes: nothing.
- Produces: `octo.ui.markdown` exposing `BULLET: string`, `MAX_HEADING_LEVEL: integer`, `conceal_spans(lines: string[]): octo.MarkdownSpan[]`, `available(): boolean`, `start(bufnr: integer): boolean`. `octo.pickers.fzf-lua.preview_markdown` keeps `BULLET`, `MAX_HEADING_LEVEL`, `conceal_spans`, `available`, `start`, `namespace`, `enabled`, `decorate`, `render` unchanged.

- [ ] **Step 1: Write the failing test**

Create `lua/tests/plenary/markdown_spec.lua`:

```lua
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/markdown_spec.lua"
```

Expected: FAIL — `module 'octo.ui.markdown' not found`.

- [ ] **Step 3: Create the core module**

Create `lua/octo/ui/markdown.lua`. Move the docstring paragraphs about treesitter versus legacy syntax across from `preview_markdown.lua`, since they explain this code:

```lua
---The markdown rendering octo shares between picker previews and live buffers.
---
---A buffer carrying filetype `octo` has `after/syntax/octo.vim` source Vim's legacy
---regex markdown syntax into it. That syntax's `concealends` rules measure width
---without accounting for what conceal removes, so the `conceallevel = 2` octo already
---sets over it makes fixed-column content ragged. `vim.treesitter.start` clears
---`b:current_syntax`, taking those rules with it, and replaces them with the
---`markdown`/`markdown_inline` queries -- whose own `@conceal` captures hide emphasis
---delimiters, backticks and link targets at the right width. The emoji conceals in
---`after/syntax/octo.vim` are window-local `matchadd` calls, not buffer syntax, so they
---survive this untouched.
---
---What treesitter leaves visible is the block-level punctuation its shipped queries
---deliberately leave alone: ATX heading markers and list bullets. `conceal_spans` is
---the pure description of those, so the transform is asserted without a window.
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

---Start markdown treesitter highlighting on a buffer.
---
---Idempotent: a buffer that is repainted, or one fzf-lua hands back for reuse, may
---already be highlighted, and starting again would leave a second highlighter attached.
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

return M
```

- [ ] **Step 4: Make the preview module delegate**

Replace `lua/octo/pickers/fzf-lua/preview_markdown.lua` entirely:

```lua
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
```

- [ ] **Step 5: Run both specs to verify they pass**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/markdown_spec.lua"
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/preview_markdown_spec.lua"
```

Expected: both PASS. `preview_markdown_spec.lua` is not edited — it passing unchanged is the proof the refactor kept behaviour.

- [ ] **Step 6: Commit**

```bash
git add lua/octo/ui/markdown.lua lua/octo/pickers/fzf-lua/preview_markdown.lua lua/tests/plenary/markdown_spec.lua
git commit --message "refactor(markdown): the conceal core moves where a live buffer can reach it"
```

---

### Task 2: Render markdown in octo buffers

**Files:**
- Modify: `lua/octo/ui/markdown.lua` (append region rendering)
- Modify: `lua/octo/model/octo-buffer.lua` (`render_repo`, `render_release`, `render_discussion`, `render_issue`, new methods)
- Modify: `lua/octo/config.lua:308-313` (defaults) and `:906-910` (validation)
- Modify: `doc/octo.txt`
- Test: `lua/tests/plenary/markdown_spec.lua` (append)

**Interfaces:**
- Consumes: `markdown.conceal_spans`, `markdown.start` from Task 1.
- Produces: `markdown.buffer_namespace(): integer`, `markdown.enabled_in_buffer(): boolean`, `markdown.render_regions(bufnr: integer, regions: octo.MarkdownRegion[]): boolean` where `octo.MarkdownRegion` is `{ first_line: integer, last_line: integer }` with **1-based inclusive** buffer lines. `OctoBuffer:markdown_regions(): octo.MarkdownRegion[]` and `OctoBuffer:render_markdown(): nil`. Config value `ui.render_markdown: boolean`.

- [ ] **Step 1: Write the failing test**

Append to `lua/tests/plenary/markdown_spec.lua`:

```lua
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
```

- [ ] **Step 2: Run test to verify it fails**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/markdown_spec.lua"
```

Expected: FAIL — `attempt to call field 'buffer_namespace' (a nil value)`, and the defaults test fails on `ui.render_markdown` being nil.

- [ ] **Step 3: Add the config value**

In `lua/octo/config.lua`, in the `ui` defaults block (currently lines 308-313), add the line after `conceallevel`:

```lua
    ui = {
      conceallevel = 2, -- conceallevel for octo buffers
      render_markdown = true, -- render the markdown in bodies and comments rather than showing its source
      use_signcolumn = false, -- show "modified" marks on the sign column
      use_statuscolumn = true, -- show "modified" marks on the status column
      use_foldtext = true,
    },
```

In the `OctoConfigUi` class annotation (currently line 78-82), add:

```lua
---@field render_markdown boolean
```

In the validation block (currently lines 906-910), add:

```lua
      validate_type(config.ui.render_markdown, "ui.render_markdown", "boolean")
```

- [ ] **Step 4: Add region rendering to the core module**

Append to `lua/octo/ui/markdown.lua`, before `return M`:

```lua
local config = require "octo.config"

---@class octo.MarkdownRegion
---@field first_line integer 1-based first buffer line of the region, inclusive
---@field last_line integer 1-based last buffer line of the region, inclusive

---The extmark namespace live buffers are decorated in.
---
---Deliberately not the preview module's: a preview buffer and a live buffer are never
---the same buffer, but sharing a namespace would mean either one's clear wiped the
---other's marks if that ever stopped being true.
local buffer_namespace = vim.api.nvim_create_namespace "octo_buffer_markdown"

---The extmark namespace live buffer rendering owns.
---@return integer
function M.buffer_namespace()
  return buffer_namespace
end

---Whether rendering in live octo buffers is wanted, per `ui.render_markdown`.
---@return boolean true unless the option is explicitly false
function M.enabled_in_buffer()
  return config.values.ui.render_markdown ~= false
end

---Render the markdown in a live octo buffer.
---
---Highlighting is started buffer-wide, because treesitter's inline conceal captures
---cannot be region-gated cheaply and octo's own colours are extmarks at priority 4096
---against treesitter's 100, so they draw over it rather than being lost to it. The
---block-punctuation conceals are region-scoped, because octo chrome is full of lines
---opening with `-` or `#` that are not markdown and must not be redrawn as though
---they were.
---@param bufnr integer the octo buffer
---@param regions octo.MarkdownRegion[] the body and comment extents, 1-based inclusive
---@return boolean rendered false when rendering is off, unavailable, or the buffer is gone
function M.render_regions(bufnr, regions)
  if not M.enabled_in_buffer() or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local started = M.start(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, buffer_namespace, 0, -1)

  local total = vim.api.nvim_buf_line_count(bufnr)
  for _, region in ipairs(regions or {}) do
    local first = math.max(region.first_line or 1, 1)
    local last = math.min(region.last_line or 0, total)
    if last >= first then
      local lines = vim.api.nvim_buf_get_lines(bufnr, first - 1, last, false)
      for _, span in ipairs(M.conceal_spans(lines)) do
        pcall(vim.api.nvim_buf_set_extmark, bufnr, buffer_namespace, first - 1 + span.row, span.start_col, {
          end_col = span.end_col,
          conceal = span.replacement,
        })
      end
    end
  end

  return started
end
```

- [ ] **Step 5: Run test to verify it passes**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/markdown_spec.lua"
```

Expected: PASS.

- [ ] **Step 6: Wire it into OctoBuffer**

In `lua/octo/model/octo-buffer.lua`, add to the requires at the top:

```lua
local markdown = require "octo.ui.markdown"
```

Add these two methods immediately after `OctoBuffer:update_metadata` (currently ends around line 1001):

```lua
---The body and comment extents markdown may be rendered over.
---
---Read straight off each metadata's extmark rather than from `startLine`/`endLine`,
---which `update_metadata` only fills in for issues, pull requests and discussions --
---a release's body is written through the same `write_body_agnostic` and has an
---extmark just the same. Reading the mark keeps this kind-agnostic and free of any
---ordering dependency on `update_metadata` having run first.
---@return octo.MarkdownRegion[] regions in buffer order, 1-based inclusive
function OctoBuffer:markdown_regions()
  local regions = {}

  ---@param metadata BodyMetadata|CommentMetadata|nil
  local function add(metadata)
    if not metadata or not metadata.extmark then
      return
    end
    local mark =
      vim.api.nvim_buf_get_extmark_by_id(self.bufnr, constants.OCTO_COMMENT_NS, metadata.extmark, { details = true })
    if vim.tbl_isempty(mark) then
      return
    end
    local first, last = utils.get_extmark_region(self.bufnr, mark)
    if first and last and last >= first then
      regions[#regions + 1] = { first_line = first, last_line = last }
    end
  end

  add(self.bodyMetadata)
  for _, metadata in ipairs(self.commentsMetadata or {}) do
    add(metadata)
  end

  return regions
end

---Renders the markdown in this buffer's bodies and comments.
---
---Safe to call on a buffer that is not ready: there are no regions yet, so it does
---nothing rather than half-rendering a buffer mid-paint.
function OctoBuffer:render_markdown()
  if not self.ready then
    return
  end
  markdown.render_regions(self.bufnr, self:markdown_regions())
end
```

Then call it at the end of each render method, immediately **after** `self.ready = true` (it reads `self.ready`, so it must come after):

- `render_repo` — after `self.ready = true`
- `render_release` — after `self.ready = true`
- `render_discussion` — after `self.ready = true`
- `render_issue` — after `self.ready = true`

Each call is the same line:

```lua
  self:render_markdown()
```

- [ ] **Step 7: Keep it current as the reader types**

In `lua/octo/model/octo-buffer.lua`, inside `OctoBuffer:configure()`, after the `vim.api.nvim_buf_call` block and before `self:apply_mappings()`, add:

```lua
  -- Conceal extmarks shift with edits on their own, so this is only ever about
  -- markdown the reader has just *typed*: a `**` that has no span yet. Debounced,
  -- because it runs a treesitter-free line scan over every body and comment and
  -- TextChangedI fires on every keystroke.
  local pending ---@type uv.uv_timer_t?
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = self.bufnr,
    desc = "Octo: keep the rendered markdown current as the buffer is edited",
    callback = function()
      if pending then
        pending:stop()
        if not pending:is_closing() then
          pending:close()
        end
      end
      pending = assert(vim.uv.new_timer())
      pending:start(
        150,
        0,
        vim.schedule_wrap(function()
          pending = nil
          self:render_markdown()
        end)
      )
    end,
  })
```

- [ ] **Step 8: Document the option**

In `doc/octo.txt`, find the `ui` configuration block and add a row alongside `conceallevel`:

```
        render_markdown                 boolean (default: true)
            Render the markdown in bodies and comments rather than showing
            its source. The line the cursor is on always shows its source,
            so text stays editable.
```

- [ ] **Step 9: Run the whole suite and typecheck**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedDirectory lua/tests/plenary/ {minimal_init = 'lua/tests/minimal_init.vim'}"
make check
```

Expected: every spec passes, `make check` reports nothing new.

- [ ] **Step 10: Commit**

```bash
git add lua/octo/ui/markdown.lua lua/octo/model/octo-buffer.lua lua/octo/config.lua doc/octo.txt lua/tests/plenary/markdown_spec.lua
git commit --message "feat(markdown): octo buffers render their bodies and comments instead of showing the source"
```

---

### Task 3: Extract the spinner core

Pure refactor, same shape as Task 1. `loading.lua` keeps its corner-strip geometry and its `preview_loading` gate; the frames and the timer lifecycle move somewhere a second float can share them.

**Files:**
- Create: `lua/octo/ui/spinner.lua`
- Modify: `lua/octo/ui/loading.lua:20-57` and its `open`/`hide` internals
- Test: `lua/tests/plenary/spinner_spec.lua`

**Interfaces:**
- Consumes: nothing.
- Produces: `octo.ui.spinner` exposing `FRAMES: string[]`, `INTERVAL_MS: integer`, `TIMEOUT_MS: integer`, `frame_at(count: integer): string`, `stop(handle: uv.uv_timer_t?): nil`, `start(on_tick: fun(tick: integer), on_deadline: fun()): uv.uv_timer_t, uv.uv_timer_t` returning the animation timer and the deadline timer. `octo.ui.loading` keeps `FRAMES`, `INTERVAL_MS`, `TIMEOUT_MS`, `frame_at` and every other public name unchanged.

- [ ] **Step 1: Write the failing test**

Create `lua/tests/plenary/spinner_spec.lua`:

```lua
---@diagnostic disable
local eq = assert.are.same

local spinner = require "octo.ui.spinner"
local loading = require "octo.ui.loading"

describe("octo.ui.spinner:", function()
  it("has frames that are all non-empty", function()
    for _, frame in ipairs(spinner.FRAMES) do
      eq(true, frame ~= "" and frame ~= nil)
    end
  end)

  it("advances through the frames and wraps round", function()
    eq(spinner.FRAMES[1], spinner.frame_at(1))
    eq(spinner.FRAMES[#spinner.FRAMES], spinner.frame_at(#spinner.FRAMES))
    eq(spinner.FRAMES[1], spinner.frame_at(#spinner.FRAMES + 1))
  end)

  it("indexes no frame off the end for a zero or negative tick", function()
    eq(true, spinner.frame_at(0) ~= nil)
    eq(true, spinner.frame_at(-7) ~= nil)
  end)

  it("is the one core the loading strip uses, not a second copy of it", function()
    eq(true, rawequal(spinner.frame_at, loading.frame_at))
    eq(spinner.FRAMES, loading.FRAMES)
    eq(spinner.INTERVAL_MS, loading.INTERVAL_MS)
    eq(spinner.TIMEOUT_MS, loading.TIMEOUT_MS)
  end)

  it("stopping a nil handle is harmless", function()
    eq(true, pcall(spinner.stop, nil))
  end)

  it("stopping the same handle twice is harmless", function()
    local timer = assert(vim.uv.new_timer())
    spinner.stop(timer)
    eq(true, pcall(spinner.stop, timer))
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/spinner_spec.lua"
```

Expected: FAIL — `module 'octo.ui.spinner' not found`.

- [ ] **Step 3: Create the spinner core**

Create `lua/octo/ui/spinner.lua`:

```lua
---The animation and the timers behind anything octo shows while it is waiting.
---
---Two surfaces need this: the corner strip that reports preview warming, and the
---centered float that covers the wait between picking a pull request and its buffer
---being painted. They differ entirely in geometry and wording and not at all in how
---they animate, so this is the half they share.
local M = {}

---Spinner frames. Built with `nr2char` rather than pasted in literally: a glyph that
---arrives as an empty string animates nothing, which is indistinguishable from a
---frozen editor.
M.FRAMES = {
  vim.fn.nr2char(0x280B),
  vim.fn.nr2char(0x2819),
  vim.fn.nr2char(0x2839),
  vim.fn.nr2char(0x2838),
  vim.fn.nr2char(0x283C),
  vim.fn.nr2char(0x2834),
  vim.fn.nr2char(0x2826),
  vim.fn.nr2char(0x2827),
  vim.fn.nr2char(0x2807),
  vim.fn.nr2char(0x280F),
}

---How often the spinner advances.
M.INTERVAL_MS = 80

---The hard ceiling. Nothing else guarantees a float comes down: a request that never
---answers produces no completion, and without this a spinner would outlive whatever
---it was reporting on.
M.TIMEOUT_MS = 120000

---The spinner frame for a tick.
---@param count integer the animation tick, of any sign
---@return string frame one frame from `M.FRAMES`
function M.frame_at(count)
  return M.FRAMES[(count - 1) % #M.FRAMES + 1]
end

---Stop and close a timer.
---
---Closing matters as much as stopping: a stopped but unclosed timer leaks, and this
---runs on every hide. Safe on nil and safe twice, so every exit path can call it
---blindly.
---@param handle uv.uv_timer_t? a libuv timer
function M.stop(handle)
  if handle and not handle:is_closing() then
    handle:stop()
    handle:close()
  end
end

---Start the animation timer and the deadline timer.
---
---Both callbacks run on the libuv loop, so a caller touching the editor from either
---must wrap its own work in `vim.schedule`; the tick count is passed in rather than
---held here so a caller can draw from it without keeping its own counter in step.
---@param on_tick fun(tick: integer) called every `INTERVAL_MS` with the tick count
---@param on_deadline fun() called once, `TIMEOUT_MS` after the start
---@return uv.uv_timer_t animation the repeating timer
---@return uv.uv_timer_t deadline the one-shot timer
function M.start(on_tick, on_deadline)
  local tick = 0
  local animation = assert(vim.uv.new_timer())
  animation:start(M.INTERVAL_MS, M.INTERVAL_MS, function()
    tick = tick + 1
    on_tick(tick)
  end)

  local deadline = assert(vim.uv.new_timer())
  deadline:start(M.TIMEOUT_MS, 0, function()
    on_deadline()
  end)

  return animation, deadline
end

return M
```

- [ ] **Step 4: Make the loading strip delegate**

In `lua/octo/ui/loading.lua`, add the require at the top beside `local config = require "octo.config"`:

```lua
local spinner = require "octo.ui.spinner"
```

Replace the `M.FRAMES` table, `M.INTERVAL_MS`, `M.TIMEOUT_MS` and `M.frame_at` definitions (currently lines 17-34 and 66-71) with:

```lua
M.FRAMES = spinner.FRAMES
M.INTERVAL_MS = spinner.INTERVAL_MS
M.TIMEOUT_MS = spinner.TIMEOUT_MS
M.frame_at = spinner.frame_at
```

Delete the module-local `stop` function (currently lines 132-140) and replace its two call sites in `M.hide` with `spinner.stop`:

```lua
function M.hide()
  spinner.stop(timer)
  spinner.stop(deadline)
  timer, deadline = nil, nil
```

Replace the timer setup at the end of `open` (currently lines 207-216) with:

```lua
  timer, deadline = spinner.start(function(count)
    tick = count
    vim.schedule(draw)
  end, function()
    vim.schedule(M.hide)
  end)
```

- [ ] **Step 5: Run both specs to verify they pass**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/spinner_spec.lua"
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/preview_loading_spec.lua"
```

Expected: both PASS. `preview_loading_spec.lua` is not edited.

- [ ] **Step 6: Commit**

```bash
git add lua/octo/ui/spinner.lua lua/octo/ui/loading.lua lua/tests/plenary/spinner_spec.lua
git commit --message "refactor(loading): the frames and the timers move where a second float can share them"
```

---

### Task 4: A loading float on the list-to-buffer transition

**Files:**
- Create: `lua/octo/ui/pr-loading.lua`
- Modify: `lua/octo/init.lua:107-163` (`M.load_buffer`)
- Modify: `lua/octo/config.lua` (defaults and validation)
- Modify: `doc/octo.txt`
- Test: `lua/tests/plenary/pr_loading_spec.lua`

**Interfaces:**
- Consumes: `spinner.FRAMES`, `spinner.frame_at`, `spinner.start`, `spinner.stop` from Task 3.
- Produces: `octo.ui.pr-loading` exposing `enabled(): boolean`, `title(repo: string, kind: string, id: string|integer): string`, `lines(title: string, message: string, count: integer, width: integer): string[]`, `show(repo, kind, id): nil`, `hide(): nil`, `is_open(): boolean`, `window(): integer?`, `buffer(): integer?`, `HEIGHT: integer`, `MAX_WIDTH: integer`, `ZINDEX: integer`. Config value `ui.pr_loading: boolean`.

- [ ] **Step 1: Write the failing test**

Create `lua/tests/plenary/pr_loading_spec.lua`:

```lua
---@diagnostic disable
local eq = assert.are.same

local pr_loading = require "octo.ui.pr-loading"
local config = require "octo.config"

describe("octo pr loading:", function()
  after_each(function()
    pr_loading.hide()
  end)

  it("defaults ui.pr_loading to on", function()
    eq(true, config.values.ui.pr_loading)
  end)

  it("names what is being opened, so the float says which one", function()
    eq("pwntester/octo.nvim #123", pr_loading.title("pwntester/octo.nvim", "pull", 123))
  end)

  it("names a release by its tag rather than a number", function()
    eq("pwntester/octo.nvim v1.2.0", pr_loading.title("pwntester/octo.nvim", "release", "v1.2.0"))
  end)

  it("names a repository without an id at all", function()
    eq("pwntester/octo.nvim", pr_loading.title("pwntester/octo.nvim", "repo", nil))
  end)

  it("returns two lines, neither wider than the width given", function()
    local lines = pr_loading.lines("pwntester/octo.nvim #123", "fetching", 1, 30)
    eq(2, #lines)
    for _, line in ipairs(lines) do
      eq(true, vim.fn.strdisplaywidth(line) <= 30)
    end
  end)

  it("truncates a long title rather than overflowing", function()
    local lines = pr_loading.lines(string.rep("x", 200), "fetching", 1, 20)
    eq(true, vim.fn.strdisplaywidth(lines[1]) <= 20)
  end)

  it("folds a newline out, which nvim_buf_set_lines would reject", function()
    local lines = pr_loading.lines("a\nb", "c\nd", 1, 40)
    for _, line in ipairs(lines) do
      eq(nil, line:find "\n")
    end
  end)

  it("opens nothing and reports closed before it is shown", function()
    eq(false, pr_loading.is_open())
    eq(nil, pr_loading.window())
  end)

  it("opens a non-focusable float that does not take the cursor", function()
    local before = vim.api.nvim_get_current_win()

    pr_loading.show("pwntester/octo.nvim", "pull", 123)

    eq(true, pr_loading.is_open())
    eq(before, vim.api.nvim_get_current_win())
    eq(false, vim.api.nvim_win_get_config(pr_loading.window()).focusable)
  end)

  it("showing twice reuses the one window rather than stacking floats", function()
    pr_loading.show("pwntester/octo.nvim", "pull", 123)
    local first = pr_loading.window()
    pr_loading.show("pwntester/octo.nvim", "pull", 456)

    eq(first, pr_loading.window())
  end)

  it("closes the window and deletes its buffer on hide", function()
    pr_loading.show("pwntester/octo.nvim", "pull", 123)
    local win, buf = pr_loading.window(), pr_loading.buffer()

    pr_loading.hide()

    eq(false, vim.api.nvim_win_is_valid(win))
    eq(false, vim.api.nvim_buf_is_valid(buf))
    eq(false, pr_loading.is_open())
  end)

  it("hiding when nothing is shown is harmless", function()
    eq(true, pcall(pr_loading.hide))
    eq(true, pcall(pr_loading.hide))
  end)

  it("tears itself down when its window is closed behind its back", function()
    pr_loading.show("pwntester/octo.nvim", "pull", 123)
    local win = pr_loading.window()

    vim.api.nvim_win_close(win, true)

    eq(false, pr_loading.is_open())
  end)

  it("shows nothing at all when the option is off", function()
    local original = config.values.ui.pr_loading
    config.values.ui.pr_loading = false

    pr_loading.show("pwntester/octo.nvim", "pull", 123)
    local open = pr_loading.is_open()

    config.values.ui.pr_loading = original
    eq(false, open)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/pr_loading_spec.lua"
```

Expected: FAIL — `module 'octo.ui.pr-loading' not found`.

- [ ] **Step 3: Add the config value**

In `lua/octo/config.lua`, add to the `ui` defaults after `render_markdown`:

```lua
      pr_loading = true, -- show a loading float while a picked issue or pull request is fetched
```

Add to the `OctoConfigUi` class annotation:

```lua
---@field pr_loading boolean
```

Add to the `ui` validation block:

```lua
      validate_type(config.ui.pr_loading, "ui.pr_loading", "boolean")
```

- [ ] **Step 4: Create the loading float**

Create `lua/octo/ui/pr-loading.lua`:

```lua
---What is on screen between picking something from a list and its buffer being painted.
---
---The fetch behind an `octo://` buffer is asynchronous, so the window is created empty
---and stays empty until the query answers. Without a sign of it the wait reads as an
---editor that has stopped rather than one that is working.
---
---It reports and never gates, the same rule `octo.ui.loading` follows: the float is
---opened with `enter = false` and `focusable = false`, so the cursor stays where the
---reader left it and every key still goes to the buffer underneath.
---
---`title` and `lines` are pure and are where the whole format lives, so the wording and
---the truncation are asserted without opening anything.
local config = require "octo.config"
local spinner = require "octo.ui.spinner"

local M = {}

---Height of the float, in rows: the title, then what is being waited on.
M.HEIGHT = 2

---Greatest width of the float, in columns.
M.MAX_WIDTH = 48

---Stacking order. Above fzf-lua's window, which defaults to 50 and puts its help
---window at 52, so the float is not hidden by the picker it was opened from.
M.ZINDEX = 60

local group = vim.api.nvim_create_augroup("OctoPrLoading", { clear = true })

local win ---@type integer?
local buf ---@type integer?
local timer ---@type uv.uv_timer_t?
local deadline ---@type uv.uv_timer_t?
local tick = 0
local heading = ""
local text = ""

---Whether the float is wanted, per `ui.pr_loading`.
---@return boolean true unless the option is explicitly false
function M.enabled()
  return config.values.ui.pr_loading ~= false
end

---What the float calls the thing being opened.
---
---A release is named by its tag and a repository has no id at all, so this cannot
---simply print a `#` and a number.
---@param repo string the `owner/name` the buffer belongs to
---@param kind string the octo node kind
---@param id string|integer|nil the number or tag, absent for a repository
---@return string
function M.title(repo, kind, id)
  if id == nil or id == "" then
    return repo
  end
  if kind == "release" then
    return ("%s %s"):format(repo, id)
  end
  return ("%s #%s"):format(repo, id)
end

---Text cut to fit, measured in display columns.
---@param body string
---@param width integer
---@return string
local function fit(body, width)
  body = body:gsub("[\n\r]", " ")
  if width < 1 then
    return ""
  end
  if vim.fn.strdisplaywidth(body) <= width then
    return body
  end
  while vim.fn.strdisplaywidth(body) > math.max(width - 1, 0) and body ~= "" do
    body = vim.fn.strcharpart(body, 0, vim.fn.strchars(body) - 1)
  end
  return body .. vim.fn.nr2char(0x2026)
end

---The float's content: the spinner and the title, then what is being waited on.
---
---Newlines are folded here rather than at the call site because `nvim_buf_set_lines`
---errors outright on a replacement containing one, and this is called from a timer
---every `INTERVAL_MS`: an uncaught newline would not fail once, it would fail on a loop.
---@param title string what is being opened
---@param message string what is being waited on
---@param count integer the animation tick
---@param width integer the float's inner width in columns
---@return string[] lines exactly two, neither wider than `width`
function M.lines(title, message, count, width)
  local prefix = " " .. spinner.frame_at(count) .. "  "
  local room = math.max(width - vim.fn.strdisplaywidth(prefix), 1)
  return {
    prefix .. fit(title, room),
    fit("    " .. message, width),
  }
end

---Whether the float is on screen.
---@return boolean
function M.is_open()
  return win ~= nil and vim.api.nvim_win_is_valid(win)
end

---The float's window.
---@return integer? win nil when nothing is shown
function M.window()
  return win
end

---The float's buffer.
---@return integer? buf nil when nothing is shown
function M.buffer()
  return buf
end

---Define the float's highlight groups.
---
---Links with `default = true`, so a colourscheme with an opinion keeps it, and
---re-applied on a colourscheme change because loading one clears every group.
function M.highlights()
  vim.api.nvim_set_hl(0, "OctoPrLoadingNormal", { link = "NormalFloat", default = true })
  vim.api.nvim_set_hl(0, "OctoPrLoadingBorder", { link = "FloatBorder", default = true })
end

---Write the current frame into the buffer.
local function draw()
  if not (M.is_open() and buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  local width = vim.api.nvim_win_get_width(win)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.lines(heading, text, tick, width))
  vim.bo[buf].modifiable = false
end

---Take the float off the screen and tear down both timers.
---
---Safe to call when nothing is showing, so every exit path can call it blindly.
function M.hide()
  spinner.stop(timer)
  spinner.stop(deadline)
  timer, deadline = nil, nil
  vim.api.nvim_clear_autocmds { group = group }
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
  win, buf = nil, nil
end

---Open the float and start the animation.
---@param self_width integer the float's width in columns
local function open(self_width)
  buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "octo-pr-loading"

  local vim_height = vim.o.lines - vim.o.cmdheight

  win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = math.max(math.floor((vim_height - M.HEIGHT) / 2), 0),
    col = math.max(math.floor((vim.o.columns - self_width) / 2), 0),
    width = self_width,
    height = M.HEIGHT,
    style = "minimal",
    border = "rounded",
    focusable = false,
    zindex = M.ZINDEX,
    noautocmd = true,
  })
  vim.wo[win].winhighlight = "Normal:OctoPrLoadingNormal,FloatBorder:OctoPrLoadingBorder"

  -- Belt and braces against anything outside this module closing the float directly:
  -- without it the window vanishes and both timers keep ticking against a handle that
  -- is no longer valid. `M.hide` closes the window itself, which fires this same
  -- event; its own idempotency absorbs the reentry rather than looping.
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(win),
    callback = function()
      M.hide()
    end,
    desc = "Octo: take the loading float down with its window",
  })

  timer, deadline = spinner.start(function(count)
    tick = count
    vim.schedule(draw)
  end, function()
    vim.schedule(M.hide)
  end)
end

---Show the float for something being opened, or update it if it is already up.
---@param repo string the `owner/name` the buffer belongs to
---@param kind string the octo node kind
---@param id string|integer|nil the number or tag
function M.show(repo, kind, id)
  if not M.enabled() then
    return
  end
  heading = M.title(repo, kind, id)
  text = "fetching…"
  if not M.is_open() then
    tick = 0
    M.highlights()
    open(math.min(M.MAX_WIDTH, math.max(24, vim.o.columns - 4)))
  end
  draw()
end

vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("OctoPrLoadingColors", { clear = true }),
  callback = function()
    M.highlights()
  end,
  desc = "Octo: keep the loading float's highlights after a colourscheme change",
})

return M
```

- [ ] **Step 5: Run test to verify it passes**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/pr_loading_spec.lua"
```

Expected: PASS.

- [ ] **Step 6: Hook it into the buffer load**

In `lua/octo/init.lua`, add to the requires at the top:

```lua
local pr_loading = require "octo.ui.pr-loading"
```

In `M.load_buffer`, show the float once the target has been parsed and hide it on every exit from the callback. The parse failure path must not leave a float up, so `show` comes after it. Replace the body from the `M.load(...)` call onwards:

```lua
  pr_loading.show(repo, kind, id)

  M.load(repo, kind, id, hostname, function(obj)
    pr_loading.hide()

    if is_stale_target() then
      return
    end

    local should_restore_cursor = vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr

    vim.api.nvim_buf_call(bufnr, function()
      M.create_buffer(kind, obj, repo, false, hostname)

      if should_restore_cursor then
        -- get size of newly created buffer
        local lines = vim.api.nvim_buf_line_count(bufnr)

        -- One to the left
        local new_cursor_pos = {
          math.min(cursor_pos[1], lines),
          math.max(0, cursor_pos[2] - 1),
        }
        pcall(vim.api.nvim_win_set_cursor, winid, new_cursor_pos)
      end

      if opts.verbose then
        utils.info(string.format("Loaded %s/%s/%d", repo, kind, id))
      end
    end)
  end)
```

`M.load`'s own error paths call `utils.print_err` and never invoke the callback, so add a hide there too. In `M.load`, find each `utils.print_err` call inside a failure branch and precede it with:

```lua
        pr_loading.hide()
```

The deadline timer is the backstop for any path that still slips through.

- [ ] **Step 7: Document the option**

In `doc/octo.txt`, in the `ui` block, add:

```
        pr_loading                      boolean (default: true)
            Show a loading float while a picked issue, pull request or
            discussion is fetched. It reports only; the cursor and every
            key still go to the buffer underneath.
```

- [ ] **Step 8: Run the whole suite and typecheck**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedDirectory lua/tests/plenary/ {minimal_init = 'lua/tests/minimal_init.vim'}"
make check
```

Expected: every spec passes.

- [ ] **Step 9: Commit**

```bash
git add lua/octo/ui/pr-loading.lua lua/octo/init.lua lua/octo/config.lua doc/octo.txt lua/tests/plenary/pr_loading_spec.lua
git commit --message "feat(loading): a float covers the wait between picking a pull request and its buffer"
```

---

### Task 5: Extract the keymap help core

Pure refactor. `help-bar.lua` keeps its review-specific `LABELS`, `ORDER`, `winbar` and `attach`; the formatters every other surface needs move out.

**Files:**
- Create: `lua/octo/ui/keymap-help.lua`
- Modify: `lua/octo/reviews/help-bar.lua` (delegate `terse`, `pretty_lhs`, `truncate`, `CUT`, and the entry building)
- Test: `lua/tests/plenary/keymap_help_spec.lua`

**Interfaces:**
- Consumes: nothing.
- Produces: `octo.ui.keymap-help` exposing `CUT: string`, `SYMBOL: string`, `HELP_KEY: string`, `PICKER_HELP_KEY: string`, `terse(action: string): string`, `pretty_lhs(lhs: string): string`, `truncate(text: string, width: integer): string`, `entries_from(mappings: table<string, table>, order: string[], handlers: table): { action: string, lhs: string, label: string }[]`, `section(): string`. `octo.reviews.help-bar` keeps every public name it has now.

- [ ] **Step 1: Write the failing test**

Create `lua/tests/plenary/keymap_help_spec.lua`:

```lua
---@diagnostic disable
local eq = assert.are.same

local keymap_help = require "octo.ui.keymap-help"
local help_bar = require "octo.reviews.help-bar"

describe("octo.ui.keymap-help core:", function()
  it("drops the word review from an action name, which the bar repeats otherwise", function()
    eq("submit", keymap_help.terse "submit_review")
    eq("add comment", keymap_help.terse "add_comment")
  end)

  it("resolves a localleader placeholder to the key the reader has to press", function()
    local original = vim.g.maplocalleader
    vim.g.maplocalleader = ","

    local resolved = keymap_help.pretty_lhs "<localleader>ca"

    vim.g.maplocalleader = original
    eq(",ca", resolved)
  end)

  it("cuts text to the width, marking where it was cut", function()
    eq(true, vim.fn.strdisplaywidth(keymap_help.truncate(string.rep("x", 80), 10)) <= 10)
    eq("short", keymap_help.truncate("short", 40))
  end)

  it("builds entries only for actions that have both a mapping and a handler", function()
    local mappings = {
      real = { lhs = "<localleader>a", desc = "real" },
      unbound = { lhs = "", desc = "no key" },
      unhandled = { lhs = "<localleader>b", desc = "no handler" },
    }
    local handlers = { real = function() end, unbound = function() end }

    local entries = keymap_help.entries_from(mappings, { "real", "unbound", "unhandled" }, handlers)

    eq(1, #entries)
    eq("real", entries[1].action)
  end)

  it("draws ordered actions first and any others after them, sorted", function()
    local mappings = {
      zebra = { lhs = "<localleader>z", desc = "z" },
      apple = { lhs = "<localleader>a", desc = "a" },
      first = { lhs = "<localleader>f", desc = "f" },
    }
    local handlers = { zebra = function() end, apple = function() end, first = function() end }

    local entries = keymap_help.entries_from(mappings, { "first" }, handlers)

    eq({ "first", "apple", "zebra" }, vim.tbl_map(function(entry)
      return entry.action
    end, entries))
  end)

  it("has a symbol that is not empty, so the section is never a bare separator", function()
    eq(true, keymap_help.SYMBOL ~= "" and keymap_help.SYMBOL ~= nil)
  end)

  it("puts the symbol and the key in a section of its own", function()
    local section = keymap_help.section()

    eq(true, section:find(keymap_help.SYMBOL, 1, true) ~= nil)
    eq(true, section:find(keymap_help.HELP_KEY, 1, true) ~= nil)
  end)

  it("is the one core the review bar uses, not a second copy of it", function()
    eq(true, rawequal(keymap_help.terse, help_bar.terse))
    eq(true, rawequal(keymap_help.pretty_lhs, help_bar.pretty_lhs))
    eq(true, rawequal(keymap_help.truncate, help_bar.truncate))
    eq(keymap_help.CUT, help_bar.CUT)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/keymap_help_spec.lua"
```

Expected: FAIL — `module 'octo.ui.keymap-help' not found`.

- [ ] **Step 3: Create the core module**

Create `lua/octo/ui/keymap-help.lua`:

```lua
---The keys a context has, and how they are named wherever they are shown.
---
---Four surfaces need this and they share nothing but the formatting: review mode's
---winbar, an octo buffer's winbar, a comment popup's float footer, and an fzf header.
---What differs is the geometry and which mapping table is being read; what is the same
---is how an action is named, how a leader placeholder is resolved into a key the
---reader can actually press, and how a line is cut when there is not room for it.
local utils = require "octo.utils"

local M = {}

---The mark that says there was more to show than there was room for.
M.CUT = "…"

---The symbol that marks the keymap help section.
---
---Built with `nr2char` for the same reason the spinner frames are: a glyph that
---arrives as an empty string leaves a section that is nothing but a separator.
M.SYMBOL = vim.fn.nr2char(0x2328)

---The key that opens the keymap float in a buffer or a popup.
---
---`g?` rather than `?`, which is backwards-search in a buffer the reader can edit,
---and rather than `q`, which a popup already binds to close.
M.HELP_KEY = "g?"

---The key that opens the keymap float from a picker.
---
---`<C-g>` is free against every entry in `picker_config.mappings`.
M.PICKER_HELP_KEY = "<C-g>"

---An action's name as a bar labels it.
---
---The word `review` inside an action name is repeated noise on a surface that is
---already the review bar, and is short of room besides.
---@param action string the action's name, as the mapping config keys it
---@return string
function M.terse(action)
  local words = {}
  for word in action:gmatch "[^_]+" do
    if word ~= "review" then
      words[#words + 1] = word
    end
  end
  return table.concat(words, " ")
end

---A mapping's left-hand side as the reader has to type it.
---
---The config writes `<localleader>vs`; what the key actually is depends on the leader
---in force, and a bar that echoed the placeholder would be teaching a keystroke
---nobody can press.
---@param lhs string the left-hand side as the mapping config holds it
---@return string
function M.pretty_lhs(lhs)
  local resolved = lhs:gsub("<[Ll]ocal[Ll]eader>", function()
    return vim.g.maplocalleader or "\\"
  end)
  return (resolved:gsub("<[Ll]eader>", function()
    return vim.g.mapleader or "\\"
  end))
end

---Text cut to fit, with the mark where it was cut.
---
---Measured in display columns, because the leader and any key drawn through it can be
---more than one byte wide and a byte count would cut the line early.
---@param text string the text, however long it came out
---@param width integer columns available
---@return string
function M.truncate(text, width)
  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end

  local room = width - vim.fn.strdisplaywidth(M.CUT)
  if room < 1 then
    return vim.fn.strcharpart(text, 0, width)
  end

  local chars = vim.fn.strchars(text)
  while chars > 0 and vim.fn.strdisplaywidth(vim.fn.strcharpart(text, 0, chars)) > room do
    chars = chars - 1
  end
  return vim.fn.strcharpart(text, 0, chars) .. M.CUT
end

---The keys a mapping table has, in the order they should be drawn.
---
---Mirrors `utils.apply_mappings`' own test for whether a mapping was made, so no
---surface can ever advertise a key that nothing bound. Actions named in `order` come
---first, in that order; anything else follows, sorted, so a mapping added upstream
---still shows.
---@param mappings table<string, table> a mapping table from the config
---@param order string[] the actions to draw first, most useful first
---@param handlers table<string, function> the action handlers
---@return { action: string, lhs: string, label: string }[]
function M.entries_from(mappings, order, handlers)
  local listed, actions = {}, {}
  for _, action in ipairs(order or {}) do
    if mappings[action] and not listed[action] then
      actions[#actions + 1] = action
      listed[action] = true
    end
  end

  local rest = {}
  for action in pairs(mappings) do
    if not listed[action] then
      rest[#rest + 1] = action
    end
  end
  table.sort(rest)
  vim.list_extend(actions, rest)

  local entries = {}
  for _, action in ipairs(actions) do
    local mapping = mappings[action]
    if not utils.is_blank(mapping) and not utils.is_blank(mapping.lhs) and not utils.is_blank(handlers[action]) then
      entries[#entries + 1] = {
        action = action,
        lhs = M.pretty_lhs(mapping.lhs),
        label = M.terse(action),
      }
    end
  end
  return entries
end

---The keymap help section, set off from whatever is drawn beside it.
---
---A section of its own rather than another key on the end of the list: it is the one
---entry that is about the list itself, and it must survive being the last thing that
---fits.
---@return string
function M.section()
  return ("%s %s keys"):format(M.SYMBOL, M.HELP_KEY)
end

return M
```

- [ ] **Step 4: Make the review bar delegate**

In `lua/octo/reviews/help-bar.lua`, add the require:

```lua
local keymap_help = require "octo.ui.keymap-help"
```

Replace the `M.terse`, `M.pretty_lhs`, `M.CUT` and `M.truncate` definitions with:

```lua
M.CUT = keymap_help.CUT
M.terse = keymap_help.terse
M.pretty_lhs = keymap_help.pretty_lhs
M.truncate = keymap_help.truncate
```

Delete the module-local `ordered_actions` function and replace `M.entries` with:

```lua
--- The keys one review context has, in the order the bar draws them.
---@param kind string the review kind, one of `M.LABELS`' keys
---@param handlers table<string, function>|nil the action handlers; octo's own when omitted
---@return { action: string, lhs: string, label: string }[]
function M.entries(kind, handlers)
  handlers = handlers or require "octo.mappings"
  return keymap_help.entries_from(config.values.mappings[kind] or {}, M.ORDER[kind] or {}, handlers)
end
```

The `utils` require at the top of `help-bar.lua` is now unused — delete that line.

- [ ] **Step 5: Run both specs to verify they pass**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/keymap_help_spec.lua"
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/review_help_bar_spec.lua"
```

Expected: both PASS. `review_help_bar_spec.lua` is not edited — its 36 assertions passing unchanged is the proof.

- [ ] **Step 6: Commit**

```bash
git add lua/octo/ui/keymap-help.lua lua/octo/reviews/help-bar.lua lua/tests/plenary/keymap_help_spec.lua
git commit --message "refactor(help): the key formatters move where popups, buffers and pickers share them"
```

---

### Task 6: The keymap float, and the symbol on octo buffers

**Files:**
- Modify: `lua/octo/ui/keymap-help.lua` (append the float and the buffer winbar)
- Modify: `lua/octo/model/octo-buffer.lua` (`apply_mappings`, `configure`)
- Test: `lua/tests/plenary/keymap_help_spec.lua` (append)

**Interfaces:**
- Consumes: `keymap_help.entries_from`, `keymap_help.truncate`, `keymap_help.section`, `keymap_help.SYMBOL`, `keymap_help.HELP_KEY` from Task 5.
- Produces: `keymap_help.float_lines(kind: string, handlers: table?): string[]`, `keymap_help.float(kind: string): integer, integer` returning winid and bufnr, `keymap_help.bar_line(kind: string, width: integer, handlers: table?): string`, `keymap_help.winbar(): string`, `keymap_help.attach(win: integer, bufnr: integer, kind: string): nil`, `keymap_help.VARIABLE: string`, `keymap_help.GROUP: string`, `keymap_help.ORDER: table<string, string[]>`.

- [ ] **Step 1: Write the failing test**

Append to `lua/tests/plenary/keymap_help_spec.lua`:

```lua
describe("octo.ui.keymap-help float:", function()
  it("lists every key an issue buffer has, one to a line", function()
    local lines = keymap_help.float_lines "issue"

    local joined = table.concat(lines, "\n")
    eq(true, joined:find("add comment", 1, true) ~= nil)
    eq(true, joined:find("reload", 1, true) ~= nil)
  end)

  it("resolves the leader in the float, not just on the bar", function()
    local original = vim.g.maplocalleader
    vim.g.maplocalleader = ","

    local joined = table.concat(keymap_help.float_lines "issue", "\n")

    vim.g.maplocalleader = original
    eq(true, joined:find(",ca", 1, true) ~= nil)
    eq(false, joined:find("<localleader>", 1, true) ~= nil)
  end)

  it("says so rather than opening an empty float for a kind with no keys", function()
    local lines = keymap_help.float_lines "not_a_real_kind"

    eq(1, #lines)
    eq(true, lines[1]:find("no keys", 1, true) ~= nil)
  end)

  it("opens a float that takes the cursor, so it can be scrolled and closed", function()
    local win, buf = keymap_help.float "issue"

    local focusable = vim.api.nvim_win_get_config(win).focusable
    local closed_by = vim.fn.maparg("q", "n", false, true)
    pcall(vim.api.nvim_win_close, win, true)

    eq(true, focusable)
    eq(true, vim.api.nvim_buf_is_valid(buf) == false or true)
    eq(true, closed_by ~= nil)
  end)

  it("puts the help section on the bar for a buffer kind", function()
    local line = keymap_help.bar_line("issue", 200)

    eq(true, line:find(keymap_help.SYMBOL, 1, true) ~= nil)
  end)

  it("keeps the help section even when the bar is too narrow for the keys", function()
    local line = keymap_help.bar_line("issue", 24)

    eq(true, vim.fn.strdisplaywidth((line:gsub("%%%%", "%%"))) <= 24)
    eq(true, line:find(keymap_help.SYMBOL, 1, true) ~= nil)
  end)

  it("escapes every percent, which a statusline expression would otherwise read", function()
    local line = keymap_help.bar_line("issue", 200)

    for percent in line:gmatch "%%+" do
      eq(0, #percent % 2)
    end
  end)

  it("returns an empty bar for a buffer that has no recorded kind", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)

    local bar = keymap_help.winbar()

    vim.api.nvim_buf_delete(bufnr, { force = true })
    eq("", bar)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/keymap_help_spec.lua"
```

Expected: FAIL — `attempt to call field 'float_lines' (a nil value)`.

- [ ] **Step 3: Append the float and the bar**

Append to `lua/octo/ui/keymap-help.lua`, before `return M`:

```lua
local config = require "octo.config"

---The buffer variable a buffer's mapping kind is recorded under.
M.VARIABLE = "octo_keymap_help_kind"

---The highlight group the bar is drawn in.
M.GROUP = "OctoKeymapHelpBar"

---What a window's `winbar` is set to, so the bar is rebuilt on every redraw and
---follows the window's current width.
M.EXPRESSION = "%!v:lua.require'octo.ui.keymap-help'.winbar()"

---The order each buffer kind's keys are drawn in, most useful first.
---
---The bar is truncated to the window, so what comes first is what survives a narrow
---one. Actions the config has that are not named here are drawn after these, sorted,
---so a mapping added upstream still shows.
M.ORDER = {
  issue = { "add_comment", "add_reply", "react_thumbs_up", "close_issue", "reload", "open_in_browser" },
  pull = { "add_comment", "add_reply", "checkout_pr", "list_changed_files", "merge_pr", "reload", "open_in_browser" },
  discussion = { "add_comment", "add_reply", "react_thumbs_up", "reload", "open_in_browser" },
  repo = { "reload", "open_in_browser", "copy_url" },
  release = { "reload", "open_in_browser", "copy_url" },
}

---How a buffer kind is named on the bar.
M.LABELS = {
  issue = "issue",
  pull = "pull",
  discussion = "discussion",
  repo = "repo",
  release = "release",
}

---The keys one kind has, in the order they are drawn.
---@param kind string a key of `M.ORDER`, or any mappings table name
---@param handlers table<string, function>|nil the action handlers; octo's own when omitted
---@return { action: string, lhs: string, label: string }[]
function M.entries(kind, handlers)
  handlers = handlers or require "octo.mappings"
  return M.entries_from(config.values.mappings[kind] or {}, M.ORDER[kind] or {}, handlers)
end

---The float's content: every key a kind has, one to a line.
---@param kind string the mapping kind to describe
---@param handlers table<string, function>|nil the action handlers; octo's own when omitted
---@return string[] lines at least one, never empty
function M.float_lines(kind, handlers)
  local entries = M.entries(kind, handlers)
  if #entries == 0 then
    return { (" no keys mapped for %s"):format(kind) }
  end

  local widest = 0
  for _, entry in ipairs(entries) do
    widest = math.max(widest, vim.fn.strdisplaywidth(entry.lhs))
  end

  local lines = {}
  for _, entry in ipairs(entries) do
    local pad = string.rep(" ", widest - vim.fn.strdisplaywidth(entry.lhs))
    lines[#lines + 1] = (" %s%s   %s"):format(entry.lhs, pad, entry.label)
  end
  return lines
end

---Open a float listing every key a kind has.
---
---Takes the cursor, unlike everything else octo floats: it is read, scrolled and
---dismissed, so it is the one surface where the keys should go to the float itself.
---@param kind string the mapping kind to describe
---@return integer winid
---@return integer bufnr
function M.float(kind)
  local lines = M.float_lines(kind)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = "octo-keymap-help"
  vim.bo[bufnr].bufhidden = "wipe"

  local widest = 0
  for _, line in ipairs(lines) do
    widest = math.max(widest, vim.fn.strdisplaywidth(line))
  end

  local vim_height = vim.o.lines - vim.o.cmdheight
  local width = math.min(widest + 2, math.max(vim.o.columns - 8, 20))
  local height = math.min(#lines, math.max(vim_height - 6, 3))

  local winid = vim.api.nvim_open_win(bufnr, true, {
    relative = "editor",
    row = math.max(math.floor((vim_height - height) / 2), 0),
    col = math.max(math.floor((vim.o.columns - width) / 2), 0),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = (" %s  %s keys "):format(M.SYMBOL, M.LABELS[kind] or kind),
    title_pos = "center",
    zindex = 70,
  })

  for _, lhs in ipairs { "q", "<Esc>", M.HELP_KEY } do
    vim.keymap.set("n", lhs, function()
      pcall(vim.api.nvim_win_close, winid, true)
    end, { buffer = bufnr, silent = true, noremap = true, desc = "Octo: close the keymap help" })
  end

  return winid, bufnr
end

---The keys that fit, joined, each one drawn whole.
---
---Stops at the first key too wide to finish rather than cutting through one, because
---half a label reads as a different action.
---@param parts string[] each key with its label, in the order they are drawn
---@param width integer columns available for the keys
---@return string
local function keys_that_fit(parts, width)
  local separator = "  "
  local tail = #separator + vim.fn.strdisplaywidth(M.CUT)
  local kept, used = {}, 0

  for _, part in ipairs(parts) do
    local cost = vim.fn.strdisplaywidth(part) + (#kept > 0 and #separator or 0)
    if used + cost > width then
      while #kept > 0 and used + tail > width do
        local dropped = table.remove(kept)
        used = used - vim.fn.strdisplaywidth(dropped) - (#kept > 0 and #separator or 0)
      end
      if #kept == 0 then
        return M.truncate(parts[1], width)
      end
      return table.concat(kept, separator) .. separator .. M.CUT
    end
    kept[#kept + 1] = part
    used = used + cost
  end

  return table.concat(kept, separator)
end

---The bar's single line for one buffer kind.
---
---The help section is reserved out of the width before the keys are laid out, so it
---is the one thing that cannot be truncated away: it is what tells the reader where
---the rest went.
---@param kind string the mapping kind to describe
---@param width integer columns available
---@param handlers table<string, function>|nil the action handlers; octo's own when omitted
---@return string a statusline expression with every percent escaped
function M.bar_line(kind, width, handlers)
  local section = ("  %s %s"):format(vim.fn.nr2char(0x2502), M.section())
  local opening = (" %s   "):format(M.LABELS[kind] or kind)
  local reserved = vim.fn.strdisplaywidth(opening) + vim.fn.strdisplaywidth(section)

  if width <= reserved then
    return ((M.truncate(opening .. section, width):gsub("%%", "%%%%")))
  end

  local parts = {}
  for _, entry in ipairs(M.entries(kind, handlers)) do
    parts[#parts + 1] = ("%s %s"):format(entry.lhs, entry.label)
  end
  if #parts == 0 then
    parts[1] = "no keys mapped"
  end

  return ((opening .. keys_that_fit(parts, width - reserved) .. section):gsub("%%", "%%%%"))
end

---Records which mapping kind a buffer's keys were bound from.
---@param bufnr integer the buffer the mappings were applied to
---@param kind string the mapping kind they came from
function M.remember(bufnr, kind)
  if M.LABELS[kind] and vim.api.nvim_buf_is_valid(bufnr) then
    vim.b[bufnr][M.VARIABLE] = kind
  end
end

---The mapping kind a buffer's keys came from, if it has one.
---@param bufnr integer the buffer to ask about
---@return string|nil kind a key of `M.LABELS`
function M.kind(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  local kind = vim.b[bufnr][M.VARIABLE]
  return M.LABELS[kind] and kind or nil
end

---The bar as the window it hangs on redraws it.
---@return string a winbar expression, empty when there is no kind to describe
function M.winbar()
  local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(win) then
    return ""
  end

  local kind = M.kind(vim.api.nvim_win_get_buf(win))
  if not kind then
    return ""
  end

  return ("%%#%s#%s"):format(M.GROUP, M.bar_line(kind, vim.api.nvim_win_get_width(win)))
end

---Dims the bar, unless something has already said how it should look.
---
---Emptiness is the test rather than existence, because naming a group in a statusline
---expression brings it into existence with nothing in it.
function M.highlight()
  if vim.tbl_isempty(vim.api.nvim_get_hl(0, { name = M.GROUP })) then
    vim.api.nvim_set_hl(0, M.GROUP, { link = "Comment" })
  end
end

---Hangs the bar on a window and binds the key that opens the float.
---@param win integer the window to draw the bar on
---@param bufnr integer the buffer whose kind the bar describes
---@param kind string the mapping kind
function M.attach(win, bufnr, kind)
  M.remember(bufnr, kind)
  if not M.LABELS[kind] then
    return
  end
  vim.keymap.set("n", M.HELP_KEY, function()
    M.float(kind)
  end, { buffer = bufnr, silent = true, noremap = true, desc = "Octo: show the keys this buffer has" })
  if vim.api.nvim_win_is_valid(win) then
    M.highlight()
    vim.api.nvim_set_option_value("winbar", M.EXPRESSION, { win = win, scope = "local" })
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/keymap_help_spec.lua"
```

Expected: PASS.

- [ ] **Step 5: Wire it into OctoBuffer**

In `lua/octo/model/octo-buffer.lua`, add the require:

```lua
local keymap_help = require "octo.ui.keymap-help"
```

In `OctoBuffer:configure()`, after the `vim.api.nvim_buf_call` block and after `self:apply_mappings()`, add:

```lua
  keymap_help.attach(vim.api.nvim_get_current_win(), self.bufnr, self.kind)
```

- [ ] **Step 6: Run the whole suite and typecheck**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedDirectory lua/tests/plenary/ {minimal_init = 'lua/tests/minimal_init.vim'}"
make check
```

Expected: every spec passes.

- [ ] **Step 7: Commit**

```bash
git add lua/octo/ui/keymap-help.lua lua/octo/model/octo-buffer.lua lua/tests/plenary/keymap_help_spec.lua
git commit --message "feat(help): every octo buffer carries a key bar and g? opens the full list"
```

---

### Task 7: The keymap helper on comment popups

**Files:**
- Modify: `lua/octo/ui/window.lua:17-42` (`create_floating_window`) and `:44-53` (`octo.CenteredFloatOpts`)
- Modify: `lua/octo/ui/comment-popup.lua:234-292`
- Test: `lua/tests/plenary/comment_popup_help_spec.lua`

**Interfaces:**
- Consumes: `keymap_help.section`, `keymap_help.float`, `keymap_help.SYMBOL`, `keymap_help.HELP_KEY` from Tasks 5 and 6.
- Produces: `octo.ui.window.create_floating_window` and `create_centered_float` accept `footer: string?`. `comment-popup.FOOTER: string` — the exact footer text the popup hangs.

- [ ] **Step 1: Write the failing test**

Create `lua/tests/plenary/comment_popup_help_spec.lua`:

```lua
---@diagnostic disable
local eq = assert.are.same

local popup = require "octo.ui.comment-popup"
local window = require "octo.ui.window"
local keymap_help = require "octo.ui.keymap-help"

describe("octo comment popup help:", function()
  it("names the three keys that matter, and the symbol", function()
    eq(true, popup.FOOTER:find("<C-s>", 1, true) ~= nil)
    eq(true, popup.FOOTER:find("q", 1, true) ~= nil)
    eq(true, popup.FOOTER:find(keymap_help.SYMBOL, 1, true) ~= nil)
    eq(true, popup.FOOTER:find(keymap_help.HELP_KEY, 1, true) ~= nil)
  end)

  it("hangs the footer on the popup's own window", function()
    local winid, bufnr = popup.open {
      target = {},
      on_submit = function(_, _, done)
        done(true)
      end,
    }

    local footer = vim.api.nvim_win_get_config(winid).footer
    popup.cancel(bufnr)

    eq(true, footer ~= nil)
  end)

  it("binds the help key inside the popup", function()
    local winid, bufnr = popup.open {
      target = {},
      on_submit = function(_, _, done)
        done(true)
      end,
    }

    local mapping = vim.fn.maparg(keymap_help.HELP_KEY, "n", false, true)
    local bound = mapping and mapping.buffer == 1
    popup.cancel(bufnr)

    eq(true, bound)
  end)

  it("passes a footer straight through to the float it opens", function()
    local winid, bufnr = window.create_centered_float {
      header = "Test",
      content = { "one", "two" },
      footer = "a footer",
      enter = false,
    }

    local footer = vim.api.nvim_win_get_config(winid).footer
    pcall(vim.api.nvim_win_close, winid, true)

    eq(true, footer ~= nil)
  end)

  it("opens a float with no footer when none was asked for", function()
    local winid = window.create_centered_float {
      header = "Test",
      content = { "one" },
      enter = false,
    }

    local config_footer = vim.api.nvim_win_get_config(winid).footer
    pcall(vim.api.nvim_win_close, winid, true)

    eq(true, config_footer == nil or config_footer == "")
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/comment_popup_help_spec.lua"
```

Expected: FAIL — `attempt to index field 'FOOTER' (a nil value)`.

- [ ] **Step 3: Pass a footer through the window helpers**

In `lua/octo/ui/window.lua`, in `create_floating_window`, add the two keys to the `nvim_open_win` config table, after `title = opts.header,`:

```lua
    footer = opts.footer,
    footer_pos = opts.footer and "left" or nil,
```

In the `octo.CenteredFloatOpts` class annotation, add:

```lua
---@field footer? string
```

In `create_centered_float`, add `footer = opts.footer,` to the table passed to `create_floating_window`, after `header = opts.header,`.

- [ ] **Step 4: Hang the footer and bind the key on the popup**

In `lua/octo/ui/comment-popup.lua`, add the require:

```lua
local keymap_help = require "octo.ui.keymap-help"
```

Add beside `M.COMPOSE_MARK`:

```lua
---What the popup's bottom border says.
---
---The three keys a compose window actually needs, then the help section. It is a
---constant rather than built per popup because every popup has exactly these keys:
---they are bound here, not read from the mapping config.
M.FOOTER = (" <C-s> send  q close  %s "):format(keymap_help.section())
```

In `M.open`, add `footer = M.FOOTER,` to the `window.create_centered_float` call:

```lua
  local winid, bufnr = window.create_centered_float {
    header = opts.title or "Comment",
    content = content,
    footer = M.FOOTER,
    enter = true,
  }
```

Add the help mapping alongside the existing `q` and `<C-c>` mappings:

```lua
  vim.keymap.set("n", keymap_help.HELP_KEY, function()
    keymap_help.float "comment_popup"
  end, vim.tbl_extend("force", map_opts, { desc = "Octo: show the keys this popup has" }))
```

- [ ] **Step 5: Teach the float about the popup's keys**

The popup's keys are bound in code rather than read from the mapping config, so
`config.values.mappings.comment_popup` does not exist. In `lua/octo/ui/keymap-help.lua`,
add the kind to `M.LABELS`:

```lua
  comment_popup = "comment",
```

and add a literal entry table, since there is no config table to read. Insert immediately
before `M.entries`:

```lua
---The keys a surface binds in code rather than reading from the mapping config.
---
---A comment popup binds its own keys in `octo.ui.comment-popup`, so there is no
---`config.values.mappings` table to build entries from and the float would otherwise
---have nothing to show.
M.LITERAL = {
  comment_popup = {
    { action = "submit", lhs = "<C-s>", label = "send this comment" },
    { action = "submit_leader", lhs = "<leader>op", label = "send this comment" },
    { action = "cancel", lhs = "q", label = "close, keeping a draft" },
    { action = "cancel_ctrl", lhs = "<C-c>", label = "close, keeping a draft" },
  },
}
```

and make `M.entries` consult it first:

```lua
function M.entries(kind, handlers)
  if M.LITERAL[kind] then
    local entries = {}
    for _, entry in ipairs(M.LITERAL[kind]) do
      entries[#entries + 1] = {
        action = entry.action,
        lhs = M.pretty_lhs(entry.lhs),
        label = entry.label,
      }
    end
    return entries
  end
  handlers = handlers or require "octo.mappings"
  return M.entries_from(config.values.mappings[kind] or {}, M.ORDER[kind] or {}, handlers)
end
```

- [ ] **Step 6: Run test to verify it passes**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/comment_popup_help_spec.lua"
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/keymap_help_spec.lua"
```

Expected: both PASS.

- [ ] **Step 7: Commit**

```bash
git add lua/octo/ui/window.lua lua/octo/ui/comment-popup.lua lua/octo/ui/keymap-help.lua lua/tests/plenary/comment_popup_help_spec.lua
git commit --message "feat(popup): a comment popup says which keys send it, close it and list the rest"
```

---

### Task 8: The keymap section in fzf

**Files:**
- Modify: `lua/octo/pickers/fzf-lua/pickers/fzf_actions.lua` (add the help action)
- Modify: `lua/octo/pickers/fzf-lua/pickers/utils.lua` (add the shared header builder)
- Modify: `lua/octo/pickers/fzf-lua/pickers/prs.lua:145-155` and `issues.lua` (use them)
- Test: `lua/tests/plenary/picker_help_spec.lua`

**Interfaces:**
- Consumes: `keymap_help.section`, `keymap_help.float`, `keymap_help.PICKER_HELP_KEY`, `keymap_help.SYMBOL` from Tasks 5-7.
- Produces: `picker_utils.help_header(): string` — the `--header` value, and `fzf_actions.help_action(): table` — the single-entry action table keyed by the fzf form of `PICKER_HELP_KEY`.

- [ ] **Step 1: Write the failing test**

Create `lua/tests/plenary/picker_help_spec.lua`:

```lua
---@diagnostic disable
local eq = assert.are.same

local picker_utils = require "octo.pickers.fzf-lua.pickers.utils"
local fzf_actions = require "octo.pickers.fzf-lua.pickers.fzf_actions"
local keymap_help = require "octo.ui.keymap-help"
local utils = require "octo.utils"

describe("octo picker help:", function()
  it("puts the symbol and its key in the header", function()
    local header = picker_utils.help_header()

    eq(true, header:find(keymap_help.SYMBOL, 1, true) ~= nil)
    eq(true, header:find("ctrl-g", 1, true) ~= nil or header:find("<C-g>", 1, true) ~= nil)
  end)

  it("sets the header off in a section of its own", function()
    eq(true, picker_utils.help_header():find(vim.fn.nr2char(0x2502), 1, true) ~= nil)
  end)

  it("binds the help key in the fzf form fzf-lua expects", function()
    local action = fzf_actions.help_action()
    local key = utils.convert_vim_mapping_to_fzf(keymap_help.PICKER_HELP_KEY)

    eq(true, action[key] ~= nil)
    eq("function", type(action[key]))
  end)

  it("lists the picker's own keys, not a buffer's", function()
    local joined = table.concat(keymap_help.float_lines "picker", "\n")

    eq(true, joined:find("open in browser", 1, true) ~= nil or joined:find("browser", 1, true) ~= nil)
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/picker_help_spec.lua"
```

Expected: FAIL — `attempt to call field 'help_header' (a nil value)`.

- [ ] **Step 3: Teach the float about the picker's keys**

In `lua/octo/ui/keymap-help.lua`, add to `M.LABELS`:

```lua
  picker = "picker",
```

The picker's mappings live under `config.values.picker_config.mappings`, not
`config.values.mappings`, and each entry carries its own `desc`. Add a branch to
`M.entries`, immediately after the `M.LITERAL` branch:

```lua
  if kind == "picker" then
    local entries = {}
    for action, mapping in pairs(config.values.picker_config.mappings or {}) do
      if not utils.is_blank(mapping) and not utils.is_blank(mapping.lhs) then
        entries[#entries + 1] = {
          action = action,
          lhs = M.pretty_lhs(mapping.lhs),
          label = mapping.desc or M.terse(action),
        }
      end
    end
    table.sort(entries, function(a, b)
      return a.action < b.action
    end)
    return entries
  end
```

- [ ] **Step 4: Add the header and the action**

In `lua/octo/pickers/fzf-lua/pickers/utils.lua`, add the require and the builder:

```lua
local keymap_help = require "octo.ui.keymap-help"
```

```lua
---The `--header` line every octo picker carries.
---
---The keymap section sits in a section of its own, set off by a bar, so it reads as
---being about the list rather than as one more key in it.
---@return string
function M.help_header()
  return ("%s %s %s keys"):format(
    vim.fn.nr2char(0x2502),
    keymap_help.SYMBOL,
    require("octo.utils").convert_vim_mapping_to_fzf(keymap_help.PICKER_HELP_KEY)
  )
end
```

In `lua/octo/pickers/fzf-lua/pickers/fzf_actions.lua`, add the require and the action:

```lua
local keymap_help = require "octo.ui.keymap-help"
```

```lua
---The one action every octo picker adds: open the list of keys it has.
---
---Scheduled, because fzf-lua is still tearing its own window down when the action
---runs and a float opened inside that teardown is closed with it.
---@return table<string, function>
function M.help_action()
  return {
    [utils.convert_vim_mapping_to_fzf(keymap_help.PICKER_HELP_KEY)] = function()
      vim.schedule(function()
        keymap_help.float "picker"
      end)
    end,
  }
end
```

- [ ] **Step 5: Use them in the pull request and issue pickers**

In `lua/octo/pickers/fzf-lua/pickers/prs.lua`, in the `fzf.fzf_exec` call, add the header to `fzf_opts` and the action to `actions`:

```lua
    fzf_opts = {
      ["--no-multi"] = "", -- TODO this can support multi, maybe.
      ["--info"] = "default",
      ["--header"] = picker_utils.help_header(),
    },
```

and extend the actions table with one more `vim.tbl_extend` argument:

```lua
    actions = vim.tbl_extend("force", fzf_actions.common_open_actions(formatted_pulls), fzf_actions.help_action(), {
```

Make the same two edits in `lua/octo/pickers/fzf-lua/pickers/issues.lua`.

- [ ] **Step 6: Run test to verify it passes**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/picker_help_spec.lua"
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lua/octo/ui/keymap-help.lua lua/octo/pickers/fzf-lua/pickers/utils.lua lua/octo/pickers/fzf-lua/pickers/fzf_actions.lua lua/octo/pickers/fzf-lua/pickers/prs.lua lua/octo/pickers/fzf-lua/pickers/issues.lua lua/tests/plenary/picker_help_spec.lua
git commit --message "feat(pickers): the keymap section sits in its own part of the fzf header"
```

---

### Task 9: What buttons each section has

Pure module first, with no drawing at all, so the vocabulary is settled and asserted before anything touches a buffer.

**Files:**
- Create: `lua/octo/ui/buttons.lua`
- Test: `lua/tests/plenary/buttons_spec.lua`

**Interfaces:**
- Consumes: `keymap_help.pretty_lhs` from Task 5.
- Produces: `octo.ui.buttons` exposing `KINDS: table<string, true>`, `rows(kind: string, caps: octo.ButtonCaps): octo.Button[]` where `octo.Button` is `{ label: string, action: string, lhs: string, hl: string }`, `line(buttons: octo.Button[]): { [1]: string, [2]: string }[]` returning a `virt_lines` chunk list, and `octo.ButtonCaps` is `{ viewer_can_update: boolean?, is_resolved: boolean? }`.

- [ ] **Step 1: Write the failing test**

Create `lua/tests/plenary/buttons_spec.lua`:

```lua
---@diagnostic disable
local eq = assert.are.same

local buttons = require "octo.ui.buttons"
local config = require "octo.config"

---The action names a section's buttons carry.
---@param kind string
---@param caps table
---@return string[]
local function actions(kind, caps)
  return vim.tbl_map(function(button)
    return button.action
  end, buttons.rows(kind, caps))
end

describe("octo.ui.buttons rows:", function()
  it("defaults ui.section_buttons to on", function()
    eq(true, config.values.ui.section_buttons)
  end)

  it("offers a comment and a reaction on a body nobody may edit", function()
    eq({ "add_comment", "react_thumbs_up" }, actions("body", { viewer_can_update = false }))
  end)

  it("offers an edit on a body the viewer may update", function()
    eq(true, vim.tbl_contains(actions("body", { viewer_can_update = true }), "edit"))
  end)

  it("offers a reply on a comment", function()
    eq(true, vim.tbl_contains(actions("comment", {}), "add_reply"))
  end)

  it("offers delete only on a comment the viewer may update", function()
    eq(false, vim.tbl_contains(actions("comment", { viewer_can_update = false }), "delete_comment"))
    eq(true, vim.tbl_contains(actions("comment", { viewer_can_update = true }), "delete_comment"))
  end)

  it("offers resolve on an open thread and unresolve on a resolved one", function()
    eq(true, vim.tbl_contains(actions("thread", { is_resolved = false }), "resolve_thread"))
    eq(false, vim.tbl_contains(actions("thread", { is_resolved = false }), "unresolve_thread"))
    eq(true, vim.tbl_contains(actions("thread", { is_resolved = true }), "unresolve_thread"))
  end)

  it("offers the footer the entry point for a new comment", function()
    eq(true, vim.tbl_contains(actions("footer", {}), "add_comment"))
  end)

  it("returns nothing at all for a section kind it does not know", function()
    eq({}, buttons.rows("not_a_section", {}))
  end)

  it("prints the key on the button, because a virtual line cannot hold the cursor", function()
    local original = vim.g.maplocalleader
    vim.g.maplocalleader = ","

    local row = buttons.rows("comment", {})

    vim.g.maplocalleader = original
    for _, button in ipairs(row) do
      eq(true, button.lhs ~= "" and button.lhs ~= nil)
      eq(false, button.lhs:find("<localleader>", 1, true) ~= nil)
    end
  end)

  it("builds a virt_lines chunk list, each chunk a text and a highlight", function()
    local chunks = buttons.line(buttons.rows("comment", {}))

    eq(true, #chunks > 0)
    for _, chunk in ipairs(chunks) do
      eq("string", type(chunk[1]))
      eq("string", type(chunk[2]))
    end
  end)

  it("draws nothing for a section with no buttons", function()
    eq({}, buttons.line {})
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/buttons_spec.lua"
```

Expected: FAIL — `module 'octo.ui.buttons' not found`.

- [ ] **Step 3: Add the config value**

In `lua/octo/config.lua`, add to the `ui` defaults after `pr_loading`:

```lua
      section_buttons = true, -- draw a row of actions under each body, comment and thread
```

Add to the `OctoConfigUi` class annotation:

```lua
---@field section_buttons boolean
```

Add to the `ui` validation block:

```lua
      validate_type(config.ui.section_buttons, "ui.section_buttons", "boolean")
```

- [ ] **Step 4: Create the buttons module**

Create `lua/octo/ui/buttons.lua`:

```lua
---The actions each section of an octo buffer offers, and how they are drawn.
---
---Drawn as `virt_lines`, which is why every button carries the key that fires it: a
---virtual line is not buffer content, so the cursor can never be placed on one and no
---mapping can act on "the button under the cursor". The mouse can reach them, and a
---reader who is not using one reads the key off the button and presses it. `<CR>` is
---in any case already `pr_options` and `issue_options`.
---
---`rows` and `line` are pure and are where the whole vocabulary lives, so the button
---set for every capability combination is asserted without a buffer.
local config = require "octo.config"
local keymap_help = require "octo.ui.keymap-help"

local M = {}

---@class octo.Button
---@field label string what the button says
---@field action string the mapping action it fires
---@field lhs string the key, with any leader placeholder already resolved
---@field hl string the highlight group the button is drawn in

---@class octo.ButtonCaps
---@field viewer_can_update boolean? whether the viewer may edit or delete this section
---@field is_resolved boolean? whether a review thread is resolved

---The section kinds that have buttons.
M.KINDS = {
  body = true,
  comment = true,
  thread = true,
  footer = true,
}

---The highlight group a button is drawn in.
M.GROUP = "OctoButton"

---Which mapping table each section kind reads its keys from.
---
---A thread's keys are the review thread ones; everything else in a conversation
---buffer takes the issue table, which pull requests and discussions share.
local TABLES = {
  body = "issue",
  comment = "issue",
  thread = "review_thread",
  footer = "issue",
}

---The buttons each section kind offers, before capabilities are applied.
---
---`when` is the capability test; a button with no `when` is always offered.
local VOCABULARY = {
  body = {
    { label = "+ Comment", action = "add_comment" },
    { label = "React", action = "react_thumbs_up" },
    {
      label = "Edit",
      action = "edit",
      when = function(caps)
        return caps.viewer_can_update == true
      end,
    },
  },
  comment = {
    { label = "Reply", action = "add_reply" },
    { label = "React", action = "react_thumbs_up" },
    {
      label = "Delete",
      action = "delete_comment",
      when = function(caps)
        return caps.viewer_can_update == true
      end,
    },
  },
  thread = {
    { label = "Reply", action = "add_reply" },
    {
      label = "Resolve",
      action = "resolve_thread",
      when = function(caps)
        return caps.is_resolved ~= true
      end,
    },
    {
      label = "Unresolve",
      action = "unresolve_thread",
      when = function(caps)
        return caps.is_resolved == true
      end,
    },
    { label = "React", action = "react_thumbs_up" },
  },
  footer = {
    { label = "+ New Comment", action = "add_comment" },
    { label = "Reload", action = "reload" },
  },
}

---The key an action is bound to in a section kind's mapping table.
---
---`edit` has no mapping of its own -- editing a body in octo is done by typing in the
---buffer and saving it -- so it is labelled with the write command instead.
---@param kind string the section kind
---@param action string the action's name
---@return string? lhs nil when nothing is bound
local function key_for(kind, action)
  if action == "edit" then
    return ":w"
  end
  local mappings = config.values.mappings[TABLES[kind]] or {}
  local mapping = mappings[action]
  if not mapping or not mapping.lhs or mapping.lhs == "" then
    return nil
  end
  return keymap_help.pretty_lhs(mapping.lhs)
end

---Whether buttons are wanted, per `ui.section_buttons`.
---@return boolean true unless the option is explicitly false
function M.enabled()
  return config.values.ui.section_buttons ~= false
end

---The buttons one section offers.
---
---A button whose action has no key bound is dropped rather than drawn keyless: the
---key is the whole of how a reader without a mouse fires it.
---@param kind string one of `M.KINDS`' keys
---@param caps octo.ButtonCaps what the viewer may do to this section
---@return octo.Button[]
function M.rows(kind, caps)
  caps = caps or {}
  if not M.KINDS[kind] then
    return {}
  end

  local row = {}
  for _, entry in ipairs(VOCABULARY[kind] or {}) do
    if not entry.when or entry.when(caps) then
      local lhs = key_for(kind, entry.action)
      if lhs then
        row[#row + 1] = { label = entry.label, action = entry.action, lhs = lhs, hl = M.GROUP }
      end
    end
  end
  return row
end

---A button row as a `virt_lines` chunk list.
---
---Each button is one chunk so a click can be resolved to a button by counting display
---columns across the chunks, and the separators are chunks of their own so they are
---never mistaken for part of a label.
---@param row octo.Button[] the buttons, in the order they are drawn
---@return { [1]: string, [2]: string }[] chunks empty when there are no buttons
function M.line(row)
  local chunks = {}
  for index, button in ipairs(row or {}) do
    chunks[#chunks + 1] = { index == 1 and "  " or "  ", "Normal" }
    chunks[#chunks + 1] = { ("[ %s %s ]"):format(button.label, button.lhs), button.hl }
  end
  return chunks
end

return M
```

- [ ] **Step 5: Run test to verify it passes**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/buttons_spec.lua"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lua/octo/ui/buttons.lua lua/octo/config.lua lua/tests/plenary/buttons_spec.lua
git commit --message "feat(buttons): the actions each section of a buffer offers"
```

---

### Task 10: Draw the buttons and make them clickable

**Files:**
- Modify: `lua/octo/ui/buttons.lua` (append drawing and hit-testing)
- Modify: `lua/octo/model/octo-buffer.lua` (`render_markdown` becomes `render_decorations`, plus the mouse mapping)
- Modify: `lua/octo/ui/colors.lua` (the button highlight)
- Modify: `doc/octo.txt`
- Test: `lua/tests/plenary/buttons_spec.lua` (append)

**Interfaces:**
- Consumes: `buttons.rows`, `buttons.line`, `buttons.enabled`, `buttons.GROUP` from Task 9; `OctoBuffer:markdown_regions` from Task 2.
- Produces: `buttons.namespace(): integer`, `buttons.render(bufnr: integer, sections: octo.ButtonSection[]): boolean` where `octo.ButtonSection` is `{ kind: string, last_line: integer, caps: octo.ButtonCaps }`, `buttons.hit(chunks, column: integer): octo.Button?`, `buttons.click(): nil`. `OctoBuffer:button_sections(): octo.ButtonSection[]` and `OctoBuffer:render_decorations(): nil`.

- [ ] **Step 1: Write the failing test**

Append to `lua/tests/plenary/buttons_spec.lua`:

```lua
describe("octo.ui.buttons drawing:", function()
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

  it("draws a button row as virtual lines below the section", function()
    local bufnr, wipe = scratch { "a comment", "", "another" }

    buttons.render(bufnr, { { kind = "comment", last_line = 1, caps = {} } })
    local marks = vim.api.nvim_buf_get_extmarks(bufnr, buttons.namespace(), 0, -1, { details = true })

    wipe()
    eq(1, #marks)
    eq(0, marks[1][2])
    eq(true, marks[1][4].virt_lines ~= nil)
  end)

  it("clears its previous rows so a repainted buffer does not accumulate them", function()
    local bufnr, wipe = scratch { "a comment" }

    buttons.render(bufnr, { { kind = "comment", last_line = 1, caps = {} } })
    buttons.render(bufnr, { { kind = "comment", last_line = 1, caps = {} } })
    local count = #vim.api.nvim_buf_get_extmarks(bufnr, buttons.namespace(), 0, -1, {})

    wipe()
    eq(1, count)
  end)

  it("uses a namespace of its own, never the markdown one", function()
    eq(false, buttons.namespace() == require("octo.ui.markdown").buffer_namespace())
  end)

  it("draws nothing at all when the option is off", function()
    local original = config.values.ui.section_buttons
    config.values.ui.section_buttons = false
    local bufnr, wipe = scratch { "a comment" }

    buttons.render(bufnr, { { kind = "comment", last_line = 1, caps = {} } })
    local count = #vim.api.nvim_buf_get_extmarks(bufnr, buttons.namespace(), 0, -1, {})

    config.values.ui.section_buttons = original
    wipe()
    eq(0, count)
  end)

  it("skips a section whose line is past the end of the buffer", function()
    local bufnr, wipe = scratch { "a comment" }

    local ok = pcall(buttons.render, bufnr, { { kind = "comment", last_line = 999, caps = {} } })
    local count = #vim.api.nvim_buf_get_extmarks(bufnr, buttons.namespace(), 0, -1, {})

    wipe()
    eq(true, ok)
    eq(0, count)
  end)

  it("refuses to touch a buffer that is no longer valid", function()
    local bufnr, wipe = scratch { "a comment" }
    wipe()

    eq(false, buttons.render(bufnr, { { kind = "comment", last_line = 1, caps = {} } }))
  end)
end)

describe("octo.ui.buttons hit testing:", function()
  it("finds the button a column falls inside", function()
    local row = buttons.rows("comment", {})
    local chunks = buttons.line(row)

    -- Column 0 and 1 are the leading separator; the first label starts at 2.
    eq(row[1].action, buttons.hit(chunks, 3, row).action)
  end)

  it("finds a later button past the first", function()
    local row = buttons.rows("comment", {})
    local chunks = buttons.line(row)
    local first_width = vim.fn.strdisplaywidth(chunks[1][1]) + vim.fn.strdisplaywidth(chunks[2][1])

    eq(row[2].action, buttons.hit(chunks, first_width + 3, row).action)
  end)

  it("finds nothing in the gap between two buttons", function()
    local row = buttons.rows("comment", {})

    eq(nil, buttons.hit(buttons.line(row), 0, row))
  end)

  it("finds nothing past the end of the row", function()
    local row = buttons.rows("comment", {})

    eq(nil, buttons.hit(buttons.line(row), 9999, row))
  end)

  it("finds nothing in an empty row", function()
    eq(nil, buttons.hit({}, 3, {}))
  end)
end)
```

- [ ] **Step 2: Run test to verify it fails**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedFile lua/tests/plenary/buttons_spec.lua"
```

Expected: FAIL — `attempt to call field 'namespace' (a nil value)`.

- [ ] **Step 3: Append drawing and hit-testing**

Append to `lua/octo/ui/buttons.lua`, before `return M`:

```lua
---@class octo.ButtonSection
---@field kind string one of `M.KINDS`' keys
---@field last_line integer 1-based buffer line the row is drawn below
---@field caps octo.ButtonCaps what the viewer may do to this section

local namespace = vim.api.nvim_create_namespace "octo_buttons"

---The extmark namespace the button rows are drawn in.
---@return integer
function M.namespace()
  return namespace
end

---What each drawn row holds, keyed by buffer then by the row's zero-based anchor.
---
---Kept so a click can be resolved without rebuilding the vocabulary: the chunks are
---what was actually drawn, and the columns must be measured against those rather than
---against what `rows` would return now.
---@type table<integer, table<integer, { chunks: table, row: octo.Button[] }>>
local drawn = {}

---Draw a button row under each section.
---@param bufnr integer the octo buffer
---@param sections octo.ButtonSection[] the sections to draw under
---@return boolean drawn false when buttons are off or the buffer is gone
function M.render(bufnr, sections)
  if not M.enabled() or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  drawn[bufnr] = {}

  local total = vim.api.nvim_buf_line_count(bufnr)
  for _, section in ipairs(sections or {}) do
    local anchor = (section.last_line or 0) - 1
    if anchor >= 0 and anchor < total then
      local row = M.rows(section.kind, section.caps)
      local chunks = M.line(row)
      if #chunks > 0 then
        local ok = pcall(vim.api.nvim_buf_set_extmark, bufnr, namespace, anchor, 0, {
          virt_lines = { chunks },
          virt_lines_above = false,
        })
        if ok then
          drawn[bufnr][anchor] = { chunks = chunks, row = row }
        end
      end
    end
  end

  return true
end

---The button a display column falls inside.
---
---Measured in display columns across the chunks in order, because a label can hold a
---glyph wider than one cell and a byte count would find the wrong button. The row the
---chunks were drawn from is passed in rather than rebuilt, because `rows` reads the
---live config and a mapping changed since the draw would return a different set.
---@param chunks { [1]: string, [2]: string }[] the chunks as drawn
---@param column integer zero-based display column within the virtual line
---@param row octo.Button[]|nil the buttons those chunks were drawn from
---@return octo.Button? button nil when the column is in a gap or past the end
function M.hit(chunks, column, row)
  local at = 0
  local index = 0
  for _, chunk in ipairs(chunks or {}) do
    local width = vim.fn.strdisplaywidth(chunk[1])
    if chunk[2] ~= "Normal" then
      index = index + 1
      if column >= at and column < at + width then
        return row and row[index] or { index = index }
      end
    end
    at = at + width
  end
  return nil
end

---Fire the button under the mouse.
---
---A `virt_lines` row has no buffer position of its own, so the row is found by
---subtracting the anchor line's screen row from the click's: `getmousepos` reports the
---nearest real line, which for a click on a virtual line is the line it hangs from.
function M.click()
  local pos = vim.fn.getmousepos()
  local win, bufnr = pos.winid, vim.api.nvim_win_get_buf(pos.winid)
  local rows = drawn[bufnr]
  if not rows or pos.line < 1 then
    return
  end

  local anchor = pos.line - 1
  local entry = rows[anchor]
  if not entry then
    return
  end

  local anchor_screen = vim.fn.screenpos(win, pos.line, 1)
  if anchor_screen.row == 0 or pos.screenrow <= anchor_screen.row then
    return
  end

  local target = M.hit(entry.chunks, pos.wincol - 1, entry.row)
  if not target then
    return
  end

  local handlers = require "octo.mappings"
  local handler = handlers[target.action]
  if type(handler) == "function" then
    vim.api.nvim_win_set_cursor(win, { pos.line, 0 })
    handler()
  end
end
```

- [ ] **Step 4: Define the highlight**

In `lua/octo/ui/colors.lua`, find the block where octo defines its highlight groups and
add:

```lua
  vim.api.nvim_set_hl(0, "OctoButton", { link = "DiffAdd", default = true })
```

- [ ] **Step 5: Wire it into OctoBuffer**

In `lua/octo/model/octo-buffer.lua`, add the require:

```lua
local buttons = require "octo.ui.buttons"
```

Add this method beside `markdown_regions`:

```lua
---The sections a button row is drawn under.
---
---A body's row hangs under the body; each comment's under that comment. The footer's
---hangs under the last line in the buffer, which is where a reader who has read to the
---end is looking.
---@return octo.ButtonSection[]
function OctoBuffer:button_sections()
  local sections = {}

  ---@param metadata BodyMetadata|CommentMetadata|nil
  ---@param kind string
  local function add(metadata, kind)
    if not metadata or not metadata.extmark then
      return
    end
    local mark =
      vim.api.nvim_buf_get_extmark_by_id(self.bufnr, constants.OCTO_COMMENT_NS, metadata.extmark, { details = true })
    if vim.tbl_isempty(mark) then
      return
    end
    local _, last = utils.get_extmark_region(self.bufnr, mark)
    if last then
      sections[#sections + 1] = {
        kind = kind,
        last_line = last,
        caps = { viewer_can_update = metadata.viewerCanUpdate == true },
      }
    end
  end

  add(self.bodyMetadata, "body")
  for _, metadata in ipairs(self.commentsMetadata or {}) do
    add(metadata, self:isReviewThread() and "thread" or "comment")
  end

  sections[#sections + 1] = {
    kind = "footer",
    last_line = vim.api.nvim_buf_line_count(self.bufnr),
    caps = {},
  }

  return sections
end
```

Rename `OctoBuffer:render_markdown` to `OctoBuffer:render_decorations` and have it do both:

```lua
---Renders the markdown and the button rows in this buffer.
---
---Safe to call on a buffer that is not ready: there is nothing to decorate yet, so it
---does nothing rather than half-drawing a buffer mid-paint.
function OctoBuffer:render_decorations()
  if not self.ready then
    return
  end
  markdown.render_regions(self.bufnr, self:markdown_regions())
  buttons.render(self.bufnr, self:button_sections())
end
```

Update the four render methods and the `TextChanged` autocommand from Task 2 to call
`self:render_decorations()` instead of `self:render_markdown()`.

In `OctoBuffer:configure()`, bind the mouse:

```lua
  vim.keymap.set("n", "<LeftRelease>", function()
    require("octo.ui.buttons").click()
  end, { buffer = self.bufnr, silent = true, desc = "Octo: press the button under the mouse" })
```

- [ ] **Step 6: Document the option**

In `doc/octo.txt`, in the `ui` block, add:

```
        section_buttons                 boolean (default: true)
            Draw a row of actions under each body, comment and thread.
            The rows are virtual text, not buffer content, so they cannot
            be edited or submitted. Each button carries the key that
            fires it; the mouse works too.
```

- [ ] **Step 7: Run the whole suite and typecheck**

```bash
nvim --headless --noplugin -u lua/tests/minimal_init.vim \
  -c "PlenaryBustedDirectory lua/tests/plenary/ {minimal_init = 'lua/tests/minimal_init.vim'}"
make check
make format
```

Expected: every spec passes; `make format` leaves a clean tree or reformats only what this task touched.

- [ ] **Step 8: Commit**

```bash
git add lua/octo/ui/buttons.lua lua/octo/model/octo-buffer.lua lua/octo/ui/colors.lua doc/octo.txt lua/tests/plenary/buttons_spec.lua
git commit --message "feat(buttons): each section draws what can be done to it, by key or by mouse"
```

---

### Task 11: Verify it in a real editor

Nothing here is asserted by a headless spec: this is the step that catches a bar that
renders as bold `WinBar` text, a conceal that eats a character it should not, or a float
that opens behind the picker.

**Files:**
- Modify: whatever the run turns up.
- Test: manual, in nvim, against a real repository.

**Interfaces:**
- Consumes: every task above.
- Produces: nothing new.

- [ ] **Step 1: Point the editor at the worktree**

The user's nvim loads octo from `~/.local/share/nvim/lazy/octo.nvim`. Add a `dev` path
override, or start nvim with the worktree prepended:

```bash
nvim --cmd "set runtimepath^=/home/brianthemessiah/src/octo.nvim-prui"
```

- [ ] **Step 2: Walk the list-to-buffer transition**

Run `:Octo pr list`. Confirm:
- the fzf header carries `│ ⌨ ctrl-g keys` set off from the other keys
- `<C-g>` opens a float listing the picker's keys, and `q` closes it
- picking a pull request shows a centered float naming it, which comes down as the
  buffer paints

- [ ] **Step 3: Read the buffer**

In the pull request buffer, confirm:
- headings show no `#`, bullets show `•`, `**bold**` shows as bold with no delimiters
- octo's own colours are intact: label bubbles, detail labels, usernames, state
- moving the cursor onto a rendered line reveals its raw source, and moving off re-renders
- timeline event lines are untouched — no event line has been given a bullet
- the winbar shows the buffer's keys, ending in `│ ⌨ g? keys`
- `g?` opens the full float

- [ ] **Step 4: Use the buttons**

Confirm:
- a row of buttons sits under the body, under each comment, and at the foot of the buffer
- each button prints its key
- clicking a button fires its action
- the buttons cannot be selected, deleted or submitted as buffer text — `yy` on the line
  above copies only the real line

- [ ] **Step 5: Use a popup**

Press the reply key on a comment. Confirm the popup's bottom border reads
`<C-s> send  q close  ⌨ g? keys`, that `g?` opens the popup's own key list, and that
`<C-s>` still sends.

- [ ] **Step 6: Turn each option off**

```vim
:lua require("octo.config").values.ui.render_markdown = false
:lua require("octo.config").values.ui.pr_loading = false
:lua require("octo.config").values.ui.section_buttons = false
```

Reload a buffer after each and confirm the corresponding surface is gone and nothing else
changed.

- [ ] **Step 7: Commit any fixes and record what was seen**

```bash
git add --all
git commit --message "fix(pr-ui): what the live run turned up"
```

If the run turned up nothing, make no commit and say so.

---

## Self-Review

**Spec coverage.** Every section of the design maps to a task: markdown core and buffer
rendering to Tasks 1-2; spinner and loading float to Tasks 3-4; keymap help core, float,
buffer bar, popup footer and fzf header to Tasks 5-8; buttons to Tasks 9-10; the live run
to Task 11. The three config values, their `validate_type` lines and their `doc/octo.txt`
rows are in Tasks 2, 4 and 9-10.

**Known deviation from the spec.** The spec's architecture sketch named
`OctoBuffer:render_markdown`; Task 10 renames it to `render_decorations` once buttons
share the same call site. Tasks 2 and 10 are consistent with each other, and Task 10
states the rename explicitly.

**Type consistency.** `M.hit(chunks, column, row)` takes three arguments everywhere it
appears — in its definition, in `M.click`, and in all five spec assertions.
`octo.MarkdownRegion` is `{ first_line, last_line }`, 1-based inclusive, in both Task 2's
producer (`OctoBuffer:markdown_regions`) and its consumer (`markdown.render_regions`).
`octo.ButtonSection` is `{ kind, last_line, caps }` in both Task 9's `rows` signature and
Task 10's `render`. `OctoBuffer:render_markdown` exists only between Tasks 2 and 10, where
it becomes `render_decorations`; no task references the old name after that point.

**Residual risk carried from the spec.** Treesitter's inline conceal is buffer-wide, so a
stray `*` in octo chrome may render as emphasis. Task 11, Step 3 is where that gets
looked at against a real pull request.
