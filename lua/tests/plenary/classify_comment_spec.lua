---@diagnostic disable
local commands = require "octo.commands"
local eq = assert.are.same

---Builds a stub OctoBuffer exposing only what classification reads.
---@param opts table
local function fake_buffer(opts)
  opts = opts or {}
  return {
    bufnr = 1,
    get_thread_at_cursor = function()
      return opts.thread
    end,
    isReviewThread = function()
      return opts.is_review_thread == true
    end,
    isDiscussion = function()
      return opts.is_discussion == true
    end,
  }
end

describe("commands.classify_comment_target:", function()
  it("classifies a plain issue buffer as an issue comment", function()
    local result, err = commands.classify_comment_target(fake_buffer {}, nil)

    eq(nil, err)
    eq("IssueComment", result.kind)
  end)

  it("classifies a discussion buffer as a discussion comment", function()
    local result, err = commands.classify_comment_target(fake_buffer { is_discussion = true }, nil)

    eq(nil, err)
    eq("DiscussionComment", result.kind)
  end)

  it("classifies a thread outside review mode as a PR comment", function()
    local buffer = fake_buffer {
      thread = { replyTo = "node-1", replyToRest = 42 },
    }

    local result, err = commands.classify_comment_target(buffer, nil)

    eq(nil, err)
    eq("PullRequestComment", result.kind)
    eq("node-1", result.replyTo)
    eq(42, result.replyToRest)
  end)

  it("classifies a thread in review mode as a review comment carrying the review id", function()
    local buffer = fake_buffer {
      thread = { replyTo = "node-1", replyToRest = 42 },
      is_review_thread = true,
    }

    local result, err = commands.classify_comment_target(buffer, { id = "review-9" })

    eq(nil, err)
    eq("PullRequestReviewComment", result.kind)
    eq("review-9", result.reviewId)
  end)

  it("refuses a review-thread comment when no review is in progress", function()
    local buffer = fake_buffer {
      thread = { replyTo = "node-1" },
      is_review_thread = true,
    }

    local result, err = commands.classify_comment_target(buffer, nil)

    eq(nil, result)
    eq("Please start or resume a review first", err)
  end)

  it("refuses a review-thread comment when the review id is the sentinel -1", function()
    local buffer = fake_buffer {
      thread = { replyTo = "node-1" },
      is_review_thread = true,
    }

    local result, err = commands.classify_comment_target(buffer, { id = -1 })

    eq(nil, result)
    eq("Please start or resume a review first", err)
  end)

  it("refuses a comment on a review thread with no thread under the cursor", function()
    local buffer = fake_buffer { is_review_thread = true }

    local result, err = commands.classify_comment_target(buffer, { id = "review-9" })

    eq(nil, result)
    eq("Error adding a comment to a review thread", err)
  end)

  it("returns the thread it classified so callers need not re-read it", function()
    local thread = { replyTo = "node-1", replyToRest = 42, bufferEndLine = 7 }
    local buffer = fake_buffer { thread = thread }

    local result = commands.classify_comment_target(buffer, nil)

    eq(7, result.thread.bufferEndLine)
  end)
end)
