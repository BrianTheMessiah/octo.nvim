---Runs preview fetches for a whole list, a bounded number at a time.
---
---Warming every entry rather than a window around the cursor is only affordable
---because the preview query asks for what the preview paints and nothing else: one
---rate-limit point and 170 nodes per entry. What still has to be bounded is how many
---run at once. Each request is a `gh` child process, and the documented secondary
---limits count concurrent requests and points per minute, so a list of fifty
---released all at once is fifty processes and a burst against both.
---
---Nothing here touches a buffer or a window. It owns a queue and a count, and the
---cache it feeds is what a completion writes to, so a prefetch that lands after the
---picker closed remains inert.
local config = require "octo.config"

local M = {}

---@class octo.PreviewThrottle
---@field private limit integer greatest number of jobs to run at once
---@field private reserve integer rate-limit points to leave unspent
---@field private queue fun(done: fun())[] jobs not yet started, oldest first
---@field private inflight integer jobs started and not yet complete
---@field private accepted integer jobs ever accepted
---@field private done integer jobs ever completed
---@field private stopped boolean whether scheduling has been given up
---@field private on_progress? fun(completed: integer, total: integer) called per completion
local Throttle = {}
Throttle.__index = Throttle

---How many preview fetches may run at once, per `picker_config.preview_prefetch_concurrency`.
---
---Measured against a fifty pull request list: a cap of six warmed every preview in
---7.6s and a cap of twelve in 3.8s, both with no rate-limit error. Six is the default
---because the gain past it is small next to holding twelve `gh` processes open.
---@return integer count at least one
function M.concurrency()
  local configured = tonumber(config.values.picker_config.preview_prefetch_concurrency) or 0
  return math.max(1, math.floor(configured))
end

---Whether a whole list should be warmed, per `picker_config.preview_prefetch_all`.
---@return boolean true unless the option is explicitly false
function M.prefetch_all()
  return config.values.picker_config.preview_prefetch_all ~= false
end

---How many rate-limit points to leave unspent, per `picker_config.preview_rate_limit_reserve`.
---@return integer points never negative
function M.reserve()
  local configured = tonumber(config.values.picker_config.preview_rate_limit_reserve) or 0
  return math.max(0, math.floor(configured))
end

---Build an empty throttle.
---@param opts? { limit?: integer, reserve?: integer, on_progress?: fun(completed: integer, total: integer) }
---@return octo.PreviewThrottle
function M.new(opts)
  opts = opts or {}
  return setmetatable({
    limit = math.max(1, math.floor(opts.limit or M.concurrency())),
    reserve = math.max(0, math.floor(opts.reserve or M.reserve())),
    queue = {},
    inflight = 0,
    accepted = 0,
    done = 0,
    stopped = false,
    on_progress = opts.on_progress,
  }, Throttle)
end

---How many jobs have been accepted.
---@return integer
function Throttle:total()
  return self.accepted
end

---How many accepted jobs have completed.
---@return integer
function Throttle:completed()
  return self.done
end

---Whether scheduling has been given up, by `stop` or by the rate-limit reserve.
---@return boolean
function Throttle:is_stopped()
  return self.stopped
end

---Whether every accepted job has completed.
---@return boolean
function Throttle:is_finished()
  return self.done >= self.accepted
end

---Record one completion and report progress.
---
---A stopped throttle counts the completion but reports nothing. Requests cannot be
---cancelled, so several are still in flight when a picker closes; a progress report
---from one of those would drive a display whose picker no longer exists, which is how
---a closed picker left its loading strip on screen.
---@param self octo.PreviewThrottle
local function complete(self)
  self.inflight = self.inflight - 1
  self.done = self.done + 1
  if self.on_progress and not self.stopped then
    self.on_progress(self.done, self.accepted)
  end
end

---Start queued jobs until the cap or the queue is reached.
---
---A job is handed a `done` it may only spend once: `octo.gh` offers no guarantee that
---a callback fires exactly once, and a second call would free a slot that was never
---taken and count a completion that never happened.
---@param self octo.PreviewThrottle
local function pump(self)
  while not self.stopped and self.inflight < self.limit and #self.queue > 0 do
    local job = table.remove(self.queue, 1)
    self.inflight = self.inflight + 1
    local spent = false
    job(function()
      if spent then
        return
      end
      spent = true
      complete(self)
      pump(self)
    end)
  end
end

---Accept one job, starting it if there is room.
---@param job fun(done: fun()) starts the work and calls `done` when it finishes
---@return boolean accepted false once the throttle has stopped
function Throttle:push(job)
  if self.stopped then
    return false
  end
  self.accepted = self.accepted + 1
  table.insert(self.queue, job)
  pump(self)
  return true
end

---Note the rate-limit points left, and give up scheduling if they reach the reserve.
---
---The preview query returns this alongside the payload, so backing off costs no extra
---request. A reading that is not a number is ignored rather than treated as zero: a
---response that failed to carry one must not stop a prefetch that is going fine.
---@param remaining any points left this hour, from the query's `rateLimit`
---@return boolean stopped whether this reading ended scheduling
function Throttle:note_remaining(remaining)
  local points = tonumber(remaining)
  if not points or self.stopped then
    return self.stopped
  end
  if points <= self.reserve then
    self:stop()
  end
  return self.stopped
end

---Give up scheduling and drop everything not yet started.
---
---In-flight requests are not cancelled, because `octo.gh` returns no job handle for an
---async request. They are left to complete into the cache and find nobody waiting.
function Throttle:stop()
  self.stopped = true
  self.queue = {}
end

M.Throttle = Throttle

return M
