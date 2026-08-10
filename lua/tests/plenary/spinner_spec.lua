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
