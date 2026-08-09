---@diagnostic disable
local eq = assert.are.same

-- fzf-lua is a plugin, not part of this repo, so it is only on the runtimepath
-- when the test harness explicitly provides it (see lua/tests/minimal_init.vim).
-- If it is ever missing again, fail loudly here instead of letting the whole
-- file's require blow up silently.
local ok, repo_scope = pcall(require, "octo.pickers.fzf-lua.pickers.repo_scope")

---@param repos string[] one nameWithOwner per loaded pull request, repeats allowed
---@return table[] items shaped like the snapshot the search picker builds
local function items_for(repos)
  local items = {}
  for i, repo in ipairs(repos) do
    items[#items + 1] = { repo = repo, line = ("line %d of %s"):format(i, repo) }
  end
  return items
end

---@param rows table[] the rows repo_scope.rows produced
---@return string[] repos the nameWithOwner (or sentinel) of each row, in order
local function repos_of(rows)
  local repos = {}
  for _, row in ipairs(rows) do
    repos[#repos + 1] = row.repo
  end
  return repos
end

describe("repository scope:", function()
  if not ok then
    it("requires octo.pickers.fzf-lua.pickers.repo_scope", function()
      assert(
        false,
        "octo.pickers.fzf-lua.pickers.repo_scope failed to load (is fzf-lua on the runtimepath?): "
          .. tostring(repo_scope)
      )
    end)
    return
  end

  local three_repos = items_for {
    "fii-org/service.core",
    "fii-org/service.core",
    "fii-org/service.core",
    "fii-org/web.relief",
    "fii-org/web.relief",
    "fii-org/dags",
  }

  describe("counting the loaded pull requests", function()
    it("tallies one count per repository", function()
      eq({
        ["fii-org/dags"] = 1,
        ["fii-org/service.core"] = 3,
        ["fii-org/web.relief"] = 2,
      }, repo_scope.counts(three_repos))
    end)

    it("counts nothing when nothing is loaded", function()
      eq({}, repo_scope.counts {})
    end)
  end)

  describe("the rows of the repository picker", function()
    it("heads the list with the row that widens back to every repository", function()
      local rows = repo_scope.rows(three_repos)

      eq(repo_scope.ALL, rows[1].repo)
      eq("every repository", vim.trim(rows[1].label))
    end)

    it("gives the widening row the total across every repository", function()
      local rows = repo_scope.rows(three_repos)

      eq("6", vim.trim(rows[1].count))
    end)

    it("orders repositories by how many pull requests they hold, most first", function()
      eq({
        repo_scope.ALL,
        "fii-org/service.core",
        "fii-org/web.relief",
        "fii-org/dags",
      }, repos_of(repo_scope.rows(three_repos)))
    end)

    it("breaks a tie on count by name, so the order never wobbles", function()
      local rows = repo_scope.rows(items_for { "o/zebra", "o/apple", "o/mango" })

      eq({ repo_scope.ALL, "o/apple", "o/mango", "o/zebra" }, repos_of(rows))
    end)

    it("produces no rows at all when nothing is loaded", function()
      eq({}, repo_scope.rows {})
    end)

    it("drops the owner while every pull request shares one", function()
      local rows = repo_scope.rows(items_for { "fii-org/service.core", "fii-org/dags" })

      eq({ "every repository", "dags", "service.core" }, {
        vim.trim(rows[1].label),
        vim.trim(rows[2].label),
        vim.trim(rows[3].label),
      })
    end)

    it("keeps the owner once the pull requests span more than one", function()
      local rows = repo_scope.rows(items_for { "fii-org/dags", "other-org/dags" })

      eq({ "fii-org/dags", "other-org/dags" }, {
        vim.trim(rows[2].label),
        vim.trim(rows[3].label),
      })
    end)

    it("aligns every count in one column, measured as the terminal measures it", function()
      local rows = repo_scope.rows(items_for {
        "fii-org/server.compose.pgbouncer",
        "fii-org/dags",
        "fii-org/dags",
      })
      local widths = {}
      for _, row in ipairs(rows) do
        widths[#widths + 1] = vim.fn.strdisplaywidth(repo_scope.line(row))
      end

      eq({ widths[1], widths[1], widths[1] }, widths)
    end)

    it("right-aligns the counts so their last digits line up", function()
      local rows = repo_scope.rows(items_for { "o/a", "o/a", "o/a", "o/a", "o/a", "o/a", "o/a", "o/a", "o/a", "o/b" })

      eq({ "10", " 9", " 1" }, { rows[1].count, rows[2].count, rows[3].count })
    end)
  end)

  describe("the line a row is chosen by", function()
    it("is what the displayed row leaves behind once fzf strips its colours", function()
      for _, row in ipairs(repo_scope.rows(three_repos)) do
        eq(repo_scope.line(row), require("fzf-lua.utils").strip_ansi_coloring(repo_scope.display(row)))
      end
    end)

    it("tells one repository's row from another's", function()
      local rows = repo_scope.rows(three_repos)

      assert.are_not.equal(repo_scope.line(rows[2]), repo_scope.line(rows[3]))
    end)
  end)

  describe("narrowing the loaded pull requests", function()
    it("keeps only the lines belonging to the chosen repository", function()
      local kept = repo_scope.keep(three_repos, "fii-org/web.relief")

      eq({ "line 4 of fii-org/web.relief", "line 5 of fii-org/web.relief" }, {
        kept[1].line,
        kept[2].line,
      })
      eq(2, #kept)
    end)

    it("keeps the lines in the order the list loaded them", function()
      local kept = repo_scope.keep(three_repos, "fii-org/service.core")

      eq({ "line 1 of fii-org/service.core", "line 2 of fii-org/service.core", "line 3 of fii-org/service.core" }, {
        kept[1].line,
        kept[2].line,
        kept[3].line,
      })
    end)

    it("keeps every line for the widening row", function()
      eq(#three_repos, #repo_scope.keep(three_repos, repo_scope.ALL))
    end)

    it("keeps nothing for a repository that loaded nothing", function()
      eq({}, repo_scope.keep(three_repos, "fii-org/absent"))
    end)

    it("widens on a sentinel no repository name can equal", function()
      assert.is_nil(repo_scope.ALL:match "/")
    end)
  end)

  describe("the prompt of a narrowed list", function()
    it("names the repository the list is narrowed to", function()
      eq("fii-org/dags", repo_scope.prompt("Pull Requests", "fii-org/dags"))
    end)

    it("goes back to the original title when the list is not narrowed", function()
      eq("Pull Requests", repo_scope.prompt("Pull Requests", repo_scope.ALL))
    end)

    it("stays untitled when the list it came from was untitled", function()
      assert.is_nil(repo_scope.prompt(nil, repo_scope.ALL))
    end)
  end)
end)
