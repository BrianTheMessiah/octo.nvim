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

  it("keeps the body correct after deleting a quoted context line above the separator", function()
    local _, bufnr = open {
      target = { kind = "PullRequestComment" },
      context = { "quote line one", "quote line two" },
      draft_key = "k15",
      on_submit = function() end,
    }
    vim.api.nvim_buf_set_lines(bufnr, 3, -1, false, { "my first line", "my second line" })
    eq("my first line\nmy second line", comment_popup.body(bufnr))

    -- Delete the first quoted context line the way a user editing in the
    -- window would: it sits above the separator, and nothing marks it
    -- read-only.
    vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, {})

    eq("my first line\nmy second line", comment_popup.body(bufnr))
  end)

  it("keeps the body correct after adding a line above the separator", function()
    local _, bufnr = open {
      target = { kind = "PullRequestComment" },
      context = { "quote line one" },
      draft_key = "k16",
      on_submit = function() end,
    }
    vim.api.nvim_buf_set_lines(bufnr, 2, -1, false, { "my first line", "my second line" })
    eq("my first line\nmy second line", comment_popup.body(bufnr))

    -- Insert a new line above the separator, the way a user extending their
    -- quote in the window would.
    vim.api.nvim_buf_set_lines(bufnr, 1, 1, false, { "quote line two" })

    eq("my first line\nmy second line", comment_popup.body(bufnr))
  end)

  it("refuses to submit when the separator itself is deleted", function()
    local called = false
    local _, bufnr = open {
      target = { kind = "PullRequestComment" },
      context = { "quote line one" },
      draft_key = "k17",
      on_submit = function()
        called = true
      end,
    }
    vim.api.nvim_buf_set_lines(bufnr, 2, -1, false, { "my first line", "my second line" })

    -- Delete the separator line itself (line 2: "quote line one" is line 1).
    vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, {})

    eq(nil, comment_popup.body(bufnr))

    comment_popup.submit(bufnr)

    eq(false, called)
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

  it("binds both submit keys buffer-locally in both normal and insert mode", function()
    local _, bufnr = open {
      target = { kind = "IssueComment" },
      draft_key = "k11",
      on_submit = function() end,
    }

    ---@param mode string
    ---@return table<string, boolean>
    local function lhs_set(mode)
      local lhs = {}
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, mode)) do
        lhs[m.lhs] = true
      end
      return lhs
    end

    local normal = lhs_set "n"
    local insert = lhs_set "i"

    -- nvim reports <leader> resolved to its current value
    eq(true, normal["\\op"] ~= nil or normal["<Leader>op"] ~= nil)
    eq(true, normal["<C-S>"] ~= nil or normal["<C-s>"] ~= nil)

    -- Insert mode is the half that matters most: <C-s> is globally
    -- vim.lsp.buf.signature_help() in insert mode, so losing this binding
    -- means pressing it mid-compose pops LSP help instead of submitting.
    eq(true, insert["\\op"] ~= nil or insert["<Leader>op"] ~= nil)
    eq(true, insert["<C-S>"] ~= nil or insert["<C-s>"] ~= nil)
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

  it("persists the draft and forgets its state when the buffer is wiped out directly", function()
    local winid, bufnr = open {
      target = { kind = "IssueComment" },
      draft_key = "k12",
      on_submit = function() end,
    }
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "abandoned via :bdelete" })

    -- Neither submit nor cancel: the popup's buffer is torn down directly, the
    -- way :bd!, :bwipeout!, or external code would, bypassing both.
    vim.api.nvim_buf_delete(bufnr, { force = true })

    eq("abandoned via :bdelete", drafts.load "k12")
    eq(false, vim.api.nvim_win_is_valid(winid))
  end)

  it("persists the draft and forgets its state when only the window is closed", function()
    local winid, bufnr = open {
      target = { kind = "IssueComment" },
      draft_key = "k13",
      on_submit = function() end,
    }
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "abandoned via :q!" })

    -- Neither submit nor cancel, and no :bd/:bwipeout: only the window closes,
    -- the way :q! or an external nvim_win_close would.
    vim.api.nvim_win_close(winid, true)

    eq("abandoned via :q!", drafts.load "k13")
    -- The buffer is bufhidden=wipe, so the window close wipes it out too; a
    -- read against it now errors rather than returning stale content.
    eq(false, vim.api.nvim_buf_is_valid(bufnr))
  end)

  it("calls on_submit exactly once when submit is invoked twice before it resolves", function()
    local call_count = 0
    local _, bufnr = open {
      target = { kind = "IssueComment" },
      draft_key = "k14",
      on_submit = function(_, _)
        call_count = call_count + 1
        -- deliberately never calls done(): on_submit is still in flight
      end,
    }
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "submit me once" })

    comment_popup.submit(bufnr)
    comment_popup.submit(bufnr)

    eq(1, call_count)
  end)

  it("persists nothing when draft_key is nil, even with text present", function()
    local _, bufnr = open {
      target = { kind = "IssueComment" },
      draft_key = nil,
      on_submit = function() end,
    }
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "never written to disk" })

    comment_popup.cancel(bufnr)

    local before = {}
    for name in vim.fs.dir(drafts.root()) do
      table.insert(before, name)
    end
    eq({}, before)
  end)
end)
