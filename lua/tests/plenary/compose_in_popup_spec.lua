---@diagnostic disable
local commands = require "octo.commands"
local config = require "octo.config"
local eq = assert.are.same

---Builds a stub OctoBuffer whose do_add_* methods are spies recording the
---comment_metadata they were called with, and optionally invoking the
---completion callback they were given the way a resolved `gh` call would.
---@param opts? { number: integer?, resolve: table<string, { ok: boolean, err: string? }>? }
---@return table buffer
---@return table<string, table> calls kind -> the comment_metadata it received
local function fake_buffer(opts)
  opts = opts or {}
  local calls = {}
  local buffer = {
    commentsMetadata = {},
    repo = "owner/name",
    number = opts.number,
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
  local original_open
  local original_reload
  local original_comments
  local recorded_opts
  local submit_result
  local reload_calls

  before_each(function()
    original_open = comment_popup.open
    original_reload = commands.reload
    original_comments = config.values.comments
    recorded_opts = nil
    submit_result = nil
    reload_calls = 0

    comment_popup.open = function(opts)
      recorded_opts = opts
      opts.on_submit("a composed body", function(ok, err)
        submit_result = { ok = ok, err = err }
      end)
    end
    commands.reload = function()
      reload_calls = reload_calls + 1
    end
  end)

  after_each(function()
    comment_popup.open = original_open
    commands.reload = original_reload
    config.values.comments = original_comments
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

  it("dispatches a new review thread (blank replyTo) to do_add_new_thread, not do_add_thread_comment", function()
    local buffer, calls = fake_buffer()
    commands.compose_in_popup(buffer, {
      kind = "PullRequestReviewComment",
      replyTo = nil,
      reviewId = "review-9",
    }, nil)

    eq("a composed body", calls.do_add_new_thread.body)
    eq(nil, calls.do_add_thread_comment)
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

  it("calls done(true) once GitHub confirms the reply, on the popup path (C1)", function()
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
