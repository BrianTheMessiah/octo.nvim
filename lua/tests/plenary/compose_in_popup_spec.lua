---@diagnostic disable
local commands = require "octo.commands"
local config = require "octo.config"
local utils = require "octo.utils"
local eq = assert.are.same

---Builds a stub OctoBuffer whose do_add_* methods are spies recording the
---comment_metadata they were called with, and optionally invoking the
---completion callback they were given the way a resolved `gh` call would.
---@param opts? {
---  repo: string?,
---  number: integer?,
---  is_review_thread: boolean?,
---  resolve: table<string, { ok: boolean, err: string? }>?,
---}
---@return table buffer
---@return table<string, table> calls kind -> the comment_metadata it received
local function fake_buffer(opts)
  opts = opts or {}
  local calls = {}
  local buffer = {
    commentsMetadata = {},
    repo = opts.repo or "owner/name",
    number = opts.number,
    isReviewThread = function()
      return opts.is_review_thread == true
    end,
  }
  for _, name in ipairs {
    "do_add_issue_comment",
    "do_add_discussion_comment",
    "do_add_pull_request_comment",
    "do_add_thread_comment",
    "do_add_new_thread",
  } do
    buffer[name] = function(_, comment_metadata, done)
      calls[name] = comment_metadata
      local resolution = opts.resolve and opts.resolve[name]
      if resolution and done then
        done(resolution.ok, resolution.err)
      end
    end
  end
  return buffer, calls
end

describe("commands.compose_in_popup:", function()
  local comment_popup = require "octo.ui.comment-popup"

  ---The text the stubbed popup leaves in its compose region, below the separator.
  local COMPOSED_BODY = "a composed body"

  local original_open
  local original_reload
  local original_comments
  local original_error
  local recorded_opts
  local popup_bufnrs
  local edit_popup
  local submit_result
  local reload_calls
  local error_messages

  ---Builds the buffer a real comment_popup.open would have left behind.
  ---
  ---Laid out exactly as M.open lays it out: the context lines, then the
  ---COMPOSE_MARK separator when there is any context at all, then the composed
  ---body. compose_in_popup re-reads the region above that separator at submit
  ---time via comment_popup.context_body, so a stub that handed on_submit
  ---anything but a genuine buffer containing a genuine separator would exercise
  ---none of that -- and a stub that handed it a placeholder would only prove
  ---context_body tolerates junk.
  ---@param context string[]|nil the lines comment_popup.open was asked to show as context
  ---@return integer bufnr a scratch buffer laid out like a freshly opened popup
  local function popup_buffer(context)
    local content = {}
    for _, line in ipairs(context or {}) do
      table.insert(content, line)
    end
    if #content > 0 then
      table.insert(content, comment_popup.COMPOSE_MARK)
    end
    table.insert(content, COMPOSED_BODY)

    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
    table.insert(popup_bufnrs, bufnr)
    return bufnr
  end

  before_each(function()
    original_open = comment_popup.open
    original_reload = commands.reload
    original_comments = config.values.comments
    original_error = utils.error
    recorded_opts = nil
    popup_bufnrs = {}
    edit_popup = nil
    submit_result = nil
    reload_calls = 0
    error_messages = {}

    -- Stands in for the real popup without opening a floating window: builds
    -- the same buffer, lets the test edit it the way a user would, then submits
    -- the body read back out of it. The body is read through the real
    -- comment_popup.body so that an edit above the separator cannot silently
    -- leak into what is submitted as the comment.
    comment_popup.open = function(opts)
      recorded_opts = opts
      local bufnr = popup_buffer(opts.context)
      if edit_popup then
        edit_popup(bufnr)
      end
      opts.on_submit(comment_popup.body(bufnr), bufnr, function(ok, err)
        submit_result = { ok = ok, err = err }
      end)
      return nil, bufnr
    end
    commands.reload = function()
      reload_calls = reload_calls + 1
    end
    utils.error = function(msg)
      table.insert(error_messages, msg)
    end
  end)

  after_each(function()
    comment_popup.open = original_open
    commands.reload = original_reload
    config.values.comments = original_comments
    utils.error = original_error
    for _, bufnr in ipairs(popup_bufnrs or {}) do
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end)

  it("dispatches an issue comment to do_add_issue_comment only", function()
    local buffer, calls = fake_buffer()
    commands.compose_in_popup(buffer, { kind = "IssueComment" }, nil)

    eq("a composed body", calls.do_add_issue_comment.body)
    eq(nil, calls.do_add_discussion_comment)
    eq(nil, calls.do_add_pull_request_comment)
    eq(nil, calls.do_add_thread_comment)
    eq(nil, calls.do_add_new_thread)
  end)

  it("dispatches a discussion comment to do_add_discussion_comment only", function()
    local buffer, calls = fake_buffer()
    commands.compose_in_popup(buffer, { kind = "DiscussionComment" }, nil)

    eq("a composed body", calls.do_add_discussion_comment.body)
    eq(nil, calls.do_add_issue_comment)
  end)

  it("dispatches a PR comment to do_add_pull_request_comment only", function()
    local buffer, calls = fake_buffer()
    commands.compose_in_popup(buffer, { kind = "PullRequestComment", replyTo = "node-1", replyToRest = 42 }, nil)

    eq("a composed body", calls.do_add_pull_request_comment.body)
    eq("node-1", calls.do_add_pull_request_comment.replyTo)
    eq(42, calls.do_add_pull_request_comment.replyToRest)
    eq(nil, calls.do_add_thread_comment)
  end)

  it("dispatches a review-thread reply (non-blank replyTo) to do_add_thread_comment, not do_add_new_thread", function()
    local buffer, calls = fake_buffer()
    commands.compose_in_popup(buffer, {
      kind = "PullRequestReviewComment",
      replyTo = "node-1",
      replyToRest = 42,
      reviewId = "review-9",
    }, nil)

    eq("a composed body", calls.do_add_thread_comment.body)
    eq(nil, calls.do_add_new_thread)
  end)

  it("refuses a new review thread (blank replyTo) instead of dispatching an input GitHub would reject", function()
    local buffer, calls = fake_buffer()
    commands.compose_in_popup(buffer, {
      kind = "PullRequestReviewComment",
      replyTo = nil,
      reviewId = "review-9",
    }, nil)

    -- do_add_new_thread needs .path/.diffSide/.snippetStartLine/.snippetEndLine,
    -- none of which the popup builds (I4): refusing means never opening the
    -- popup for this branch at all, not opening it and rejecting on submit.
    eq(nil, recorded_opts)
    eq(nil, calls.do_add_new_thread)
    eq(nil, calls.do_add_thread_comment)
    eq(1, #error_messages)
  end)

  it("refuses a new review thread carrying the numeric -1 stub sentinel the same as a blank replyTo", function()
    local buffer, calls = fake_buffer()
    commands.compose_in_popup(buffer, {
      kind = "PullRequestReviewComment",
      replyTo = -1,
      reviewId = "review-9",
    }, nil)

    eq(nil, recorded_opts)
    eq(nil, calls.do_add_new_thread)
  end)

  it("passes the full comment_metadata shape to the do_add_* spy", function()
    local buffer, calls = fake_buffer()
    commands.compose_in_popup(buffer, {
      kind = "PullRequestReviewComment",
      replyTo = "node-1",
      replyToRest = 42,
      reviewId = "review-9",
    }, nil)

    local metadata = calls.do_add_thread_comment
    eq("a composed body", metadata.body)
    eq("PullRequestReviewComment", metadata.kind)
    eq("node-1", metadata.replyTo)
    eq(42, metadata.replyToRest)
    eq("review-9", metadata.reviewId)
    eq("", metadata.savedBody)
    eq(true, metadata.dirty)
  end)

  it("builds a string draft_key when comments.drafts.enabled is true", function()
    config.values.comments = {
      style = "popup",
      style_overrides = {},
      drafts = { enabled = true, sweep_after_days = 30 },
    }
    local buffer, _ = fake_buffer()
    commands.compose_in_popup(buffer, { kind = "IssueComment" }, nil)

    eq("string", type(recorded_opts.draft_key))
  end)

  it("passes a nil draft_key when comments.drafts.enabled is false", function()
    config.values.comments = {
      style = "popup",
      style_overrides = {},
      drafts = { enabled = false, sweep_after_days = 30 },
    }
    local buffer, _ = fake_buffer()
    commands.compose_in_popup(buffer, { kind = "IssueComment" }, nil)

    eq(nil, recorded_opts.draft_key)
  end)

  it("gives two different issue/PR numbers in the same repo different draft keys (C2)", function()
    config.values.comments = {
      style = "popup",
      style_overrides = {},
      drafts = { enabled = true, sweep_after_days = 30 },
    }

    local buffer_a = fake_buffer { number = 100 }
    commands.compose_in_popup(buffer_a, { kind = "IssueComment" }, nil)
    local key_a = recorded_opts.draft_key

    local buffer_b = fake_buffer { number = 42 }
    commands.compose_in_popup(buffer_b, { kind = "IssueComment" }, nil)
    local key_b = recorded_opts.draft_key

    assert.is_not.equal(key_a, key_b)
  end)

  it("titles a fresh comment 'New comment' and a reply 'Reply'", function()
    local buffer, _ = fake_buffer()

    commands.compose_in_popup(buffer, { kind = "IssueComment" }, nil)
    eq("New comment", recorded_opts.title)

    commands.compose_in_popup(buffer, { kind = "PullRequestComment", replyTo = "node-1" }, nil)
    eq("Reply", recorded_opts.title)
  end)

  it("treats a -1 replyTo as 'New comment' rather than 'Reply' wherever it appears", function()
    local buffer, _ = fake_buffer()

    -- -1 (ReviewThread.default_id) only actually reaches a real target as
    -- PullRequestReviewComment.replyTo, and that combination is refused before
    -- the title is even set (see the refusal test above). Exercising the
    -- title logic itself on another kind proves has_real_reply_to, not just
    -- the refusal, treats the sentinel as blank.
    commands.compose_in_popup(buffer, { kind = "PullRequestComment", replyTo = -1 }, nil)

    eq("New comment", recorded_opts.title)
  end)

  it("reattaches the quote to the body for an IssueComment reply, so it publishes (I3)", function()
    local buffer, calls = fake_buffer()
    commands.compose_in_popup(buffer, { kind = "IssueComment" }, { "> quoted line 1", "> quoted line 2" })

    eq("> quoted line 1\n> quoted line 2\n\na composed body", calls.do_add_issue_comment.body)
  end)

  -- The three tests below are the ones the quote-at-open-time implementation
  -- could not pass. It captured `context` when the popup opened and glued that
  -- capture onto the body at submit, so whatever the user did to the quote in
  -- between was discarded: trimming published the untrimmed original, and
  -- deleting published the quote anyway. Each edits the context region of the
  -- popup's real buffer before submit and asserts on the body that reaches the
  -- do_add_* spy -- i.e. on what would actually be published.

  it("publishes the trimmed quote, not the longer quote the popup opened with", function()
    local buffer, calls = fake_buffer()
    -- The user cuts a three-line quote down to the one line they are answering.
    edit_popup = function(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, 3, false, { "> the line actually being answered" })
    end
    commands.compose_in_popup(buffer, { kind = "IssueComment" }, {
      "> quoted line 1",
      "> quoted line 2",
      "> quoted line 3",
    })

    eq("> the line actually being answered\n\na composed body", calls.do_add_issue_comment.body)
  end)

  it("publishes no quote at all when the user deletes the quote from the popup", function()
    local buffer, calls = fake_buffer()
    -- Deletes the quote lines and leaves the separator: deleting the separator
    -- too is the case comment_popup.submit refuses outright, so it never gets
    -- as far as a published body.
    edit_popup = function(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 0, 2, false, {})
    end
    commands.compose_in_popup(buffer, { kind = "IssueComment" }, { "> quoted line 1", "> quoted line 2" })

    eq("a composed body", calls.do_add_issue_comment.body)
  end)

  it("publishes an untouched quote intact, byte for byte", function()
    local buffer, calls = fake_buffer()
    -- Re-reading the region rather than using the captured array must not
    -- rewrite a quote nobody edited: blank lines inside it and trailing
    -- punctuation both survive.
    edit_popup = nil
    commands.compose_in_popup(
      buffer,
      { kind = "IssueComment" },
      { "> first paragraph of the quote", ">", "> second paragraph, with trailing space and a colon:" }
    )

    eq(
      "> first paragraph of the quote\n>\n> second paragraph, with trailing space and a colon:\n\na composed body",
      calls.do_add_issue_comment.body
    )
  end)

  it("does not reattach the quote for kinds that already thread structurally", function()
    local buffer, calls = fake_buffer()
    commands.compose_in_popup(
      buffer,
      { kind = "PullRequestComment", replyTo = "node-1", replyToRest = 42 },
      { "> quoted line" }
    )

    eq("a composed body", calls.do_add_pull_request_comment.body)
  end)

  it("does not publish a quote when composing a fresh IssueComment with no context", function()
    local buffer, calls = fake_buffer()
    commands.compose_in_popup(buffer, { kind = "IssueComment" }, nil)

    eq("a composed body", calls.do_add_issue_comment.body)
  end)

  it("tells the popup the comment posted only once do_add_* calls back with success (C1)", function()
    local buffer = fake_buffer { resolve = { do_add_issue_comment = { ok = true } } }
    commands.compose_in_popup(buffer, { kind = "IssueComment" }, nil)

    eq({ ok = true, err = nil }, submit_result)
  end)

  it("reloads only after the mutation succeeds, not merely after it is dispatched (C1)", function()
    local buffer = fake_buffer { resolve = { do_add_issue_comment = { ok = true } } }
    commands.compose_in_popup(buffer, { kind = "IssueComment" }, nil)

    eq(1, reload_calls)
  end)

  it("tells the popup the comment failed, keeping its draft, when do_add_* calls back with failure (C1)", function()
    local buffer = fake_buffer { resolve = { do_add_issue_comment = { ok = false, err = "network error" } } }
    commands.compose_in_popup(buffer, { kind = "IssueComment" }, nil)

    eq({ ok = false, err = "network error" }, submit_result)
    eq(0, reload_calls)
  end)

  it("does not reload after a review-thread reply: the review layer already refreshed it (I2)", function()
    local buffer = fake_buffer {
      is_review_thread = true,
      resolve = { do_add_thread_comment = { ok = true } },
    }
    commands.compose_in_popup(buffer, {
      kind = "PullRequestReviewComment",
      replyTo = "node-1",
      reviewId = "review-9",
    }, nil)

    eq({ ok = true, err = nil }, submit_result)
    eq(0, reload_calls)
  end)

  it("still reports success on a review-thread reply even though it skips the reload (I2)", function()
    local buffer = fake_buffer {
      is_review_thread = true,
      resolve = { do_add_thread_comment = { ok = true } },
    }
    commands.compose_in_popup(buffer, {
      kind = "PullRequestReviewComment",
      replyTo = "node-1",
      reviewId = "review-9",
    }, nil)

    eq(true, submit_result.ok)
  end)
end)

describe("OctoBuffer:do_add_thread_comment on the popup path:", function()
  local OctoBuffer = require("octo.model.octo-buffer").OctoBuffer
  local gh = require "octo.gh"
  local original_graphql

  -- The query-building helper looks up its template in octo.gh.mutations,
  -- but that module (and the fragments it interpolates) only fill in their
  -- templates when .setup() runs -- normally from octo.gh's own .setup(),
  -- called once from octo.setup(). Calling the whole gh.setup() here would
  -- shell out to `gh auth status`, so populate just what this test needs.
  require("octo.gh.fragments").setup()
  require("octo.gh.mutations").setup()

  before_each(function()
    original_graphql = gh.api.graphql
  end)

  after_each(function()
    gh.api.graphql = original_graphql
  end)

  ---Stubs gh.api.graphql to synchronously invoke the success callback with a
  ---GitHub response carrying no matching placeholder comment.
  local function stub_graphql_success()
    gh.api.graphql = function(opts)
      local output = vim.json.encode {
        data = {
          addPullRequestReviewComment = {
            comment = {
              id = "comment-1",
              body = "hello",
              pullRequest = {
                reviewThreads = { nodes = {} },
              },
            },
          },
        },
      }
      opts.opts.cb(output, nil)
    end
  end

  it("does not error when commentsMetadata holds no inline placeholder", function()
    stub_graphql_success()

    -- The popup path never writes an id == -1 placeholder into commentsMetadata,
    -- so the search below finds nothing and comment_end stays nil. Before the
    -- fix, the code past this point used comment_end unconditionally and threw.
    local buffer = {
      bufnr = 1,
      commentsMetadata = {},
      threadsMetadata = {},
      render_signs = function() end,
    }

    local ok, err = xpcall(function()
      OctoBuffer.do_add_thread_comment(buffer, {
        replyTo = "node-1",
        body = "hello",
        reviewId = "review-1",
      })
    end, debug.traceback)

    eq(true, ok, err)
  end)

  it("calls done(true) once GitHub confirms the reply, on the popup path", function()
    stub_graphql_success()

    local buffer = {
      bufnr = 1,
      commentsMetadata = {},
      threadsMetadata = {},
      render_signs = function() end,
    }

    local done_result
    OctoBuffer.do_add_thread_comment(buffer, {
      replyTo = "node-1",
      body = "hello",
      reviewId = "review-1",
    }, function(ok, err)
      done_result = { ok = ok, err = err }
    end)

    eq({ ok = true, err = nil }, done_result)
  end)
end)
