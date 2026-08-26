---@diagnostic disable
local eq = assert.are.same

-- fzf-lua is a plugin, not part of this repo, so it is only on the runtimepath
-- when the test harness explicitly provides it (see lua/tests/minimal_init.vim).
local ok, new_pr = pcall(require, "octo.pickers.fzf-lua.new_pull_request")

describe("the new pull request row:", function()
  if not ok then
    it("requires octo.pickers.fzf-lua.new_pull_request", function()
      assert(false, "the module failed to load: " .. tostring(new_pr))
    end)
    return
  end

  after_each(function()
    new_pr.set_action(nil)
  end)

  describe("the line it puts in the list", function()
    -- Every other line is "<kind> <owner> <name> <number> <title>" and the list runs with
    -- `--delimiter " " --with-nth 4..`, so fzf shows from the fourth field on. A row that
    -- does not have four fields would display as something else entirely, or as nothing.
    it("has as many leading fields as a real entry, so --with-nth shows the label", function()
      local fields = vim.split(new_pr.line(), " ", { plain = true })

      assert.is_true(#fields >= 5, "the row has fewer than the five fields a real entry has")
      eq(new_pr.KIND, fields[1])
    end)

    it("shows its label from the fourth field on, which is what fzf displays", function()
      local fields = vim.split(new_pr.line(), " ", { plain = true })
      local shown = table.concat({ unpack(fields, 4) }, " ")

      assert.is_truthy(shown:find("new pull request", 1, true), "the visible part does not name what it does")
    end)

    it("has no empty field, which the delimiter would turn into a shifted column", function()
      for index, field in ipairs(vim.split(new_pr.line(), " ", { plain = true })) do
        assert.is_true(#field > 0, ("field %d is empty"):format(index))
      end
    end)
  end)

  describe("telling it apart from a real entry", function()
    it("knows its own line", function()
      eq(true, new_pr.is(new_pr.line()))
    end)

    -- The shape a real row arrives in, from `handle_entry`.
    it("does not claim a pull request", function()
      eq(false, new_pr.is("pull_request fii-org service.core 916 ENG-2015 Implements new prechecks"))
    end)

    it("does not claim an issue", function()
      eq(false, new_pr.is("issue fii-org service.core 42 something broke"))
    end)

    -- A title is arbitrary text from GitHub. One that happens to read like the row's own
    -- label must not be mistaken for it, which is why the marker is the *kind* field.
    it("does not claim a pull request whose title reads like the row", function()
      eq(false, new_pr.is("pull_request fii-org service.core 7 open a new pull request"))
    end)

    it("is untroubled by nothing at all", function()
      eq(false, new_pr.is(nil))
      eq(false, new_pr.is(""))
    end)
  end)

  describe("whether the row appears", function()
    -- Off unless something is wired to it. A row that opens nothing is worse than no row.
    it("is absent until an action is set", function()
      eq(false, new_pr.enabled())
      eq({ "a", "b" }, new_pr.prepend { "a", "b" })
    end)

    it("leads the list once an action is set", function()
      new_pr.set_action(function() end)

      eq(true, new_pr.enabled())
      eq({ new_pr.line(), "a", "b" }, new_pr.prepend { "a", "b" })
    end)

    -- The moment it is most wanted: a list that is empty because you have opened nothing
    -- is a list you came to in order to open one.
    it("is there even when the list is empty", function()
      new_pr.set_action(function() end)

      eq({ new_pr.line() }, new_pr.prepend {})
    end)
  end)

  describe("running it", function()
    it("calls what was set", function()
      local called = 0
      new_pr.set_action(function() called = called + 1 end)

      new_pr.run()
      vim.wait(200, function() return called > 0 end, 10)

      eq(1, called)
    end)

    it("raises nothing when no action is set", function()
      assert.has_no.errors(function() new_pr.run() end)
    end)
  end)

  describe("the preview pane", function()
    -- `populate_preview_buf` splits an entry into kind/owner/name/number and formats a
    -- cache key from them. The row's fourth field is not a number, and the key format
    -- does not object -- it returns `octo_new_pull_request:./.:nil`. So the failure is
    -- silent rather than loud: a miss on that key, then a GraphQL request for a
    -- repository that does not exist. The previewer has to recognise the row first.
    it("has lines of its own rather than being looked up", function()
      local lines = new_pr.preview_lines()

      assert.is_true(#lines > 0, "the row previews as nothing")
      eq("table", type(lines))
      for _, line in ipairs(lines) do
        eq("string", type(line))
        assert.is_nil(line:find("\n", 1, true), "a preview line contains a newline")
      end
    end)

    it("says what it will do", function()
      local text = table.concat(new_pr.preview_lines(), "\n")

      assert.is_truthy(text:find("pull request", 1, true))
    end)
  end)
end)

describe("the pickers that carry the row:", function()
  if not ok then
    return
  end

  local actions_ok, fzf_actions = pcall(require, "octo.pickers.fzf-lua.pickers.fzf_actions")

  if not actions_ok then
    it("requires octo.pickers.fzf-lua.pickers.fzf_actions", function()
      assert(false, "failed to load: " .. tostring(fzf_actions))
    end)
    return
  end

  after_each(function()
    new_pr.set_action(nil)
  end)

  -- `formatted_items` has no entry for the row, so every action that looks one up would
  -- hand `nil` to whatever opens it. The row must be intercepted before that.
  it("opens the form rather than looking the row up as a pull request", function()
    local made = 0
    new_pr.set_action(function() made = made + 1 end)

    local actions = fzf_actions.common_buffer_actions {}
    actions["default"] { new_pr.line() }
    vim.wait(200, function() return made > 0 end, 10)

    eq(1, made)
  end)

  it("does the same for the split, vsplit and tab keys", function()
    local made = 0
    new_pr.set_action(function() made = made + 1 end)

    local actions = fzf_actions.common_buffer_actions {}
    for _, key in ipairs { "ctrl-v", "ctrl-s", "ctrl-t" } do
      actions[key] { new_pr.line() }
    end
    vim.wait(300, function() return made >= 3 end, 10)

    eq(3, made)
  end)

  -- Browsing to a row that is not a pull request, or copying its URL, has nothing to do.
  -- It must do nothing rather than reach into a nil entry.
  it("raises nothing when the row is browsed or copied", function()
    new_pr.set_action(function() end)
    local actions = fzf_actions.common_open_actions {}
    local cfg = require("octo.config").values
    local utils = require "octo.utils"

    for _, mapping in ipairs { cfg.picker_config.mappings.open_in_browser, cfg.picker_config.mappings.copy_url } do
      local key = utils.convert_vim_mapping_to_fzf(mapping.lhs)
      assert.has_no.errors(function() actions[key] { new_pr.line() } end)
    end
  end)
end)
