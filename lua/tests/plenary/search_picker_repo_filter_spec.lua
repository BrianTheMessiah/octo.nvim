---@diagnostic disable
local eq = assert.are.same

-- fzf-lua is a plugin, not part of this repo, so it is only on the runtimepath
-- when the test harness explicitly provides it (see lua/tests/minimal_init.vim).
-- If it is ever missing again, fail loudly here instead of letting the whole
-- file's require blow up silently.
local ok, search = pcall(require, "octo.pickers.fzf-lua.pickers.search")

describe("search picker repository filter:", function()
  if not ok then
    it("requires octo.pickers.fzf-lua.pickers.search", function()
      assert(
        false,
        "octo.pickers.fzf-lua.pickers.search failed to load (is fzf-lua on the runtimepath?): " .. tostring(search)
      )
    end)
    return
  end

  local cfg = require("octo.config").values
  local utils = require "octo.utils"

  ---@return string fzf_key the fzf key the repository filter is bound to
  local function filter_key()
    return utils.convert_vim_mapping_to_fzf(cfg.picker_config.mappings.filter_repo.lhs)
  end

  describe("what the list binds", function()
    it("binds the repository filter", function()
      local actions = search.list_actions({}, {}, function() end)

      eq("function", type(actions[filter_key()]))
    end)

    it("keeps every open/browse/copy key the list already had", function()
      local base = require("octo.pickers.fzf-lua.pickers.fzf_actions").common_open_actions {}
      local actions = search.list_actions({}, {}, function() end)

      for key in pairs(base) do
        assert.is_not_nil(actions[key], ("the list lost its %q action"):format(key))
      end
    end)

    it("adds exactly one key to the list, so nothing was silently overwritten", function()
      local base = require("octo.pickers.fzf-lua.pickers.fzf_actions").common_open_actions {}
      local actions = search.list_actions({}, {}, function() end)

      eq(vim.tbl_count(base) + 1, vim.tbl_count(actions))
    end)

    it("hands the chosen repository straight through to the narrowing callback", function()
      local chosen
      local actions = search.list_actions({}, {}, function(repo)
        chosen = repo
      end)

      assert.is_not_nil(actions[filter_key()])
      eq(nil, chosen)
    end)
  end)

  describe("the lines a narrowed list is built from", function()
    local snapshot = {
      { repo = "o/one", line = "pull_request o one 1 first" },
      { repo = "o/two", line = "pull_request o two 2 second" },
      { repo = "o/one", line = "pull_request o one 3 third" },
    }

    it("come from the snapshot the previous list built, not from GitHub", function()
      eq({ "pull_request o one 1 first", "pull_request o one 3 third" }, search.scoped_lines(snapshot, "o/one"))
    end)

    it("are every loaded line when the list is widened again", function()
      local repo_scope = require "octo.pickers.fzf-lua.pickers.repo_scope"

      eq({
        "pull_request o one 1 first",
        "pull_request o two 2 second",
        "pull_request o one 3 third",
      }, search.scoped_lines(snapshot, repo_scope.ALL))
    end)

    it("keep the field layout the previewer parses, so a narrowed row still previews", function()
      for _, line in ipairs(search.scoped_lines(snapshot, "o/one")) do
        local fields = vim.split(line, " ")

        eq("pull_request", fields[1])
        eq("o", fields[2])
        eq("one", fields[3])
        assert.is_not_nil(tonumber(fields[4]))
      end
    end)
  end)

  describe("the snapshot a new query replaces", function()
    it("is emptied in place, so the key bound at open time sees the results on screen", function()
      local snapshot = { { repo = "o/one", line = "a" }, { repo = "o/two", line = "b" } }
      local held_by_the_action = snapshot

      search.reset(snapshot)

      eq(0, #held_by_the_action)
    end)

    it("is the same table afterwards, not a fresh one", function()
      local snapshot = { { repo = "o/one", line = "a" } }
      local held_by_the_action = snapshot

      search.reset(snapshot)
      snapshot[#snapshot + 1] = { repo = "o/three", line = "c" }

      eq({ { repo = "o/three", line = "c" } }, held_by_the_action)
    end)
  end)

  describe("what the narrowed list searches on", function()
    it("shows and searches the same fields the unfiltered list does", function()
      eq("4..", search.list_fzf_opts()["--with-nth"])
      eq(" ", search.list_fzf_opts()["--delimiter"])
    end)
  end)
end)
