---@diagnostic disable
local comment_popup = require "octo.ui.comment-popup"
local drafts = require "octo.drafts"
local eq = assert.are.same

describe("octo.ui.comment-popup:", function()
  local original_stdpath
  local tmp
  local opened

  before_each(function()
    tmp = vim.fn.tempname()
    original_stdpath = vim.fn.stdpath
    vim.fn.stdpath = function(what)
      if what == "state" then
        return tmp
      end
      return original_stdpath(what)
    end
    opened = {}
  end)

  after_each(function()
    for _, winid in ipairs(opened) do
      pcall(vim.api.nvim_win_close, winid, true)
    end
    vim.fn.stdpath = original_stdpath
    vim.fn.delete(tmp, "rf")
  end)

  ---@return integer winid
  ---@return integer bufnr
  local function open(opts)
    local winid, bufnr = comment_popup.open(opts)
    table.insert(opened, winid)
    return winid, bufnr
  end

  it("opens a window whose buffer is an unnamed scratch buffer", function()
    local _, bufnr = open {
      target = { kind = "IssueComment" },
      draft_key = "k1",
      on_submit = function() end,
    }

    eq("nofile", vim.bo[bufnr].buftype)
    eq("", vim.api.nvim_buf_get_name(bufnr))
  end)

  it("shows context lines above the separator", function()
    local _, bufnr = open {
      target = { kind = "PullRequestComment" },
      context = { "> quoted line" },
      draft_key = "k2",
      on_submit = function() end,
    }

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    eq("> quoted line", lines[1])
    eq(comment_popup.COMPOSE_MARK, lines[2])
  end)

  it("reads back only the compose region as the body", function()
    local _, bufnr = open {
      target = { kind = "PullRequestComment" },
      context = { "> quoted" },
      draft_key = "k3",
      on_submit = function() end,
    }

    vim.api.nvim_buf_set_lines(bufnr, 2, -1, false, { "my reply", "second line" })

    eq("my reply\nsecond line", comment_popup.body(bufnr))
  end)

  it("restores a saved draft into the compose region", function()
    drafts.save("k4", "unfinished thought")

    local _, bufnr = open {
      target = { kind = "IssueComment" },
      draft_key = "k4",
      on_submit = function() end,
    }

    eq("unfinished thought", comment_popup.body(bufnr))
  end)

  it("passes the composed body to on_submit", function()
    local submitted
    local _, bufnr = open {
      target = { kind = "IssueComment" },
      draft_key = "k5",
      on_submit = function(body, done)
        submitted = body
        done(true)
      end,
    }
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "shipped" })

    comment_popup.submit(bufnr)

    eq("shipped", submitted)
  end)

  it("discards the draft and closes the window when submit succeeds", function()
    local winid, bufnr = open {
      target = { kind = "IssueComment" },
      draft_key = "k6",
      on_submit = function(_, done)
        done(true)
      end,
    }
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "done" })

    comment_popup.submit(bufnr)

    eq(nil, drafts.load "k6")
    eq(false, vim.api.nvim_win_is_valid(winid))
  end)

  it("keeps the window open and the draft on disk when submit fails", function()
    local winid, bufnr = open {
      target = { kind = "IssueComment" },
      draft_key = "k7",
      on_submit = function(_, done)
        done(false, "network is down")
      end,
    }
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "keep me" })

    comment_popup.submit(bufnr)

    eq(true, vim.api.nvim_win_is_valid(winid))
    eq("keep me", drafts.load "k7")
  end)

  it("binds both submit keys buffer-locally so switchboard's global \\op cannot win", function()
    local _, bufnr = open {
      target = { kind = "IssueComment" },
      draft_key = "k11",
      on_submit = function() end,
    }

    local lhs = {}
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
      lhs[m.lhs] = true
    end

    -- nvim reports <leader> resolved to its current value
    eq(true, lhs["\\op"] ~= nil or lhs["<Leader>op"] ~= nil)
    eq(true, lhs["<C-S>"] ~= nil or lhs["<C-s>"] ~= nil)
  end)

  it("refuses to submit an empty body", function()
    local called = false
    local _, bufnr = open {
      target = { kind = "IssueComment" },
      draft_key = "k8",
      on_submit = function()
        called = true
      end,
    }
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "", "   " })

    comment_popup.submit(bufnr)

    eq(false, called)
  end)

  it("saves a draft when cancelled with text present", function()
    local _, bufnr = open {
      target = { kind = "IssueComment" },
      draft_key = "k9",
      on_submit = function() end,
    }
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "half written" })

    comment_popup.cancel(bufnr)

    eq("half written", drafts.load "k9")
  end)

  it("stores no draft when cancelled with an empty body", function()
    local _, bufnr = open {
      target = { kind = "IssueComment" },
      draft_key = "k10",
      on_submit = function() end,
    }

    comment_popup.cancel(bufnr)

    eq(nil, drafts.load "k10")
  end)
end)
