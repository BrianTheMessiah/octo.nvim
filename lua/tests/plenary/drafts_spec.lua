---@diagnostic disable
local drafts = require "octo.drafts"
local eq = assert.are.same

describe("octo.drafts:", function()
  local original_stdpath
  local tmp

  before_each(function()
    tmp = vim.fn.tempname()
    original_stdpath = vim.fn.stdpath
    vim.fn.stdpath = function(what)
      if what == "state" then
        return tmp
      end
      return original_stdpath(what)
    end
  end)

  after_each(function()
    vim.fn.stdpath = original_stdpath
    vim.fn.delete(tmp, "rf")
  end)

  it("round-trips text through a key", function()
    local key = drafts.key("owner/repo", "IssueComment", nil)

    drafts.save(key, "hello\nworld")

    eq("hello\nworld", drafts.load(key))
  end)

  it("returns nil for a key never saved", function()
    eq(nil, drafts.load(drafts.key("owner/repo", "IssueComment", "nope")))
  end)

  it("gives different threads different keys", function()
    local a = drafts.key("owner/repo", "PullRequestReviewComment", "thread-1")
    local b = drafts.key("owner/repo", "PullRequestReviewComment", "thread-2")

    assert.is_not.equal(a, b)
  end)

  it("builds keys containing no path separators", function()
    local key = drafts.key("owner/repo", "IssueComment", "a/b:c")

    eq(nil, key:find("/", 1, true))
  end)

  it("discards a draft", function()
    local key = drafts.key("owner/repo", "IssueComment", nil)
    drafts.save(key, "text")

    drafts.discard(key)

    eq(nil, drafts.load(key))
  end)

  it("treats discarding an absent draft as a no-op", function()
    assert.has_no.errors(function()
      drafts.discard(drafts.key("owner/repo", "IssueComment", "absent"))
    end)
  end)

  it("overwrites rather than appending on repeated saves", function()
    local key = drafts.key("owner/repo", "IssueComment", nil)

    drafts.save(key, "first")
    drafts.save(key, "second")

    eq("second", drafts.load(key))
  end)

  it("preserves a trailing newline in the body", function()
    local key = drafts.key("owner/repo", "IssueComment", nil)

    drafts.save(key, "line\n")

    eq("line\n", drafts.load(key))
  end)

  it("sweeps drafts older than the cutoff and reports the count", function()
    local key = drafts.key("owner/repo", "IssueComment", "old")
    drafts.save(key, "stale")
    -- backdate the file 40 days
    local path = drafts.root() .. "/" .. key
    local forty_days_ago = os.time() - (40 * 24 * 60 * 60)
    vim.uv.fs_utime(path, forty_days_ago, forty_days_ago)

    local removed = drafts.sweep(30)

    eq(1, removed)
    eq(nil, drafts.load(key))
  end)

  it("keeps drafts newer than the cutoff", function()
    local key = drafts.key("owner/repo", "IssueComment", "fresh")
    drafts.save(key, "keep me")

    local removed = drafts.sweep(30)

    eq(0, removed)
    eq("keep me", drafts.load(key))
  end)

  it("sweeps nothing when the directory does not exist yet", function()
    eq(0, drafts.sweep(30))
  end)
end)
