---@diagnostic disable
local eq = assert.are.same

local config = require "octo.config"
local throttle = require "octo.pickers.fzf-lua.preview_throttle"

---Run a function with a `picker_config` key temporarily set.
---@param key string key under `picker_config`
---@param value any the value to install for the duration of the call
---@param fn fun() body to run under that setting
local function with_config(key, value, fn)
  local previous = config.values.picker_config[key]
  config.values.picker_config[key] = value
  local ok, err = pcall(fn)
  config.values.picker_config[key] = previous
  assert(ok, err)
end

---A queue of jobs that records how many ran at once and finishes them on demand.
---@return table harness with `job`, `finish`, `pending`, `peak` and `started`
local function harness()
  local self = { peak = 0, live = 0, started = 0, finishers = {} }

  ---One job for the throttle: counts itself in and waits to be finished.
  ---@param done fun() called to report the job complete
  function self.job(done)
    self.started = self.started + 1
    self.live = self.live + 1
    self.peak = math.max(self.peak, self.live)
    table.insert(self.finishers, function()
      self.live = self.live - 1
      done()
    end)
  end

  ---Finish the oldest unfinished job.
  ---@return boolean finished false when nothing was outstanding
  function self.finish()
    local next_finisher = table.remove(self.finishers, 1)
    if not next_finisher then
      return false
    end
    next_finisher()
    return true
  end

  ---Finish every outstanding job, including any started as a result.
  function self.drain()
    while self.finish() do
    end
  end

  return self
end

describe("octo preview throttle:", function()
  it("defaults the concurrency cap to a bounded, positive number", function()
    local default = config.get_default_values().picker_config.preview_prefetch_concurrency
    eq("number", type(default))
    assert.is_true(default > 0 and default <= 16, "expected a small cap, got " .. tostring(default))
  end)

  it("defaults full prefetch on and keeps a rate limit reserve", function()
    local defaults = config.get_default_values().picker_config
    eq(true, defaults.preview_prefetch_all)
    assert.is_true(defaults.preview_rate_limit_reserve > 0)
  end)

  it("reads the cap from config and never returns less than one", function()
    with_config("preview_prefetch_concurrency", 3, function()
      eq(3, throttle.concurrency())
    end)
    with_config("preview_prefetch_concurrency", 0, function()
      eq(1, throttle.concurrency())
    end)
    with_config("preview_prefetch_concurrency", -7, function()
      eq(1, throttle.concurrency())
    end)
  end)

  it("runs a single job and reports it complete", function()
    local runner = throttle.new { limit = 2 }
    local h = harness()
    runner:push(h.job)

    eq(1, h.started)
    eq({ 0, 1 }, { runner:completed(), runner:total() })
    h.drain()
    eq({ 1, 1 }, { runner:completed(), runner:total() })
  end)

  it("never lets more than the cap run at once", function()
    local runner = throttle.new { limit = 3 }
    local h = harness()
    for _ = 1, 12 do
      runner:push(h.job)
    end

    eq(3, h.started)
    h.drain()
    eq(12, h.started)
    eq(3, h.peak)
    eq({ 12, 12 }, { runner:completed(), runner:total() })
  end)

  it("starts a queued job as soon as one in flight finishes", function()
    local runner = throttle.new { limit = 2 }
    local h = harness()
    for _ = 1, 5 do
      runner:push(h.job)
    end

    eq(2, h.started)
    h.finish()
    eq(3, h.started)
    h.finish()
    eq(4, h.started)
  end)

  it("counts a job that reports itself complete twice only once", function()
    local runner = throttle.new { limit = 1 }
    local finishers = {}
    for _ = 1, 2 do
      runner:push(function(done)
        table.insert(finishers, done)
      end)
    end

    finishers[1]()
    finishers[1]()
    eq(1, runner:completed())
    eq(2, #finishers)
  end)

  it("reports progress on every completion", function()
    local seen = {}
    local runner = throttle.new {
      limit = 2,
      on_progress = function(completed, total)
        table.insert(seen, { completed, total })
      end,
    }
    local h = harness()
    for _ = 1, 3 do
      runner:push(h.job)
    end
    h.drain()

    eq({ { 1, 3 }, { 2, 3 }, { 3, 3 } }, seen)
  end)

  it("starts nothing new once stopped, and leaves in-flight jobs harmless", function()
    local runner = throttle.new { limit = 2 }
    local h = harness()
    for _ = 1, 8 do
      runner:push(h.job)
    end
    eq(2, h.started)

    runner:stop()
    h.drain()
    eq(2, h.started)
    eq(true, runner:is_stopped())
  end)

  it("refuses to accept work after it has been stopped", function()
    local runner = throttle.new { limit = 4 }
    local h = harness()
    runner:stop()
    runner:push(h.job)

    eq(0, h.started)
    eq(0, runner:total())
  end)

  it("stops scheduling when the rate limit falls to the reserve", function()
    local runner = throttle.new { limit = 1, reserve = 100 }
    local h = harness()
    for _ = 1, 6 do
      runner:push(h.job)
    end
    eq(1, h.started)

    runner:note_remaining(100)
    h.drain()
    eq(1, h.started)
    eq(true, runner:is_stopped())
  end)

  it("keeps going while the rate limit is above the reserve", function()
    local runner = throttle.new { limit = 1, reserve = 100 }
    local h = harness()
    for _ = 1, 4 do
      runner:push(h.job)
    end

    runner:note_remaining(4000)
    h.drain()
    eq(4, h.started)
    eq(false, runner:is_stopped())
  end)

  it("ignores a rate limit reading it cannot make sense of", function()
    local runner = throttle.new { limit = 1, reserve = 100 }
    local h = harness()
    runner:push(h.job)
    runner:push(h.job)

    runner:note_remaining(nil)
    runner:note_remaining "not a number"
    h.drain()
    eq(2, h.started)
    eq(false, runner:is_stopped())
  end)

  it("is finished only once every accepted job has completed", function()
    local runner = throttle.new { limit = 2 }
    local h = harness()
    for _ = 1, 4 do
      runner:push(h.job)
    end

    eq(false, runner:is_finished())
    h.finish()
    eq(false, runner:is_finished())
    h.drain()
    eq(true, runner:is_finished())
  end)

  it("is finished immediately when it was never given any work", function()
    eq(true, throttle.new({ limit = 2 }):is_finished())
    eq(0, throttle.new({ limit = 2 }):total())
  end)
end)
