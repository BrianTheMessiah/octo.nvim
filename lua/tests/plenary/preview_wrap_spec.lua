---@diagnostic disable
local eq = assert.are.same

local config = require "octo.config"
local previewers = require "octo.pickers.fzf-lua.previewers"

---Build a stand-in previewer instance whose metatable is the given class, so
---`gen_winopts` resolves `octo_wrap` exactly as a live previewer would.
---@param class table previewer class returned by an `octo.previewers.*` factory
---@return table instance carrying an empty `winopts` table
local function instance_of(class)
  return setmetatable({ winopts = {} }, { __index = class })
end

---Run a function with `picker_config.preview_wrap` temporarily set.
---@param value boolean|nil the value to install for the duration of the call
---@param fn fun() body to run under that setting
local function with_preview_wrap(value, fn)
  local previous = config.values.picker_config.preview_wrap
  config.values.picker_config.preview_wrap = value
  local ok, err = pcall(fn)
  config.values.picker_config.preview_wrap = previous
  assert(ok, err)
end

describe("fzf-lua preview wrap:", function()
  it("defaults picker_config.preview_wrap to true", function()
    eq(true, config.get_default_values().picker_config.preview_wrap)
  end)

  it("soft-wraps prose previews so long body lines are not clipped", function()
    with_preview_wrap(true, function()
      for _, factory in ipairs { "issue", "search", "issue_template" } do
        local winopts = instance_of(previewers[factory]({})):gen_winopts()
        eq(true, winopts.wrap, factory .. " should wrap prose")
      end
    end)
  end)

  it("leaves diff, snippet and source previews unwrapped so their columns survive", function()
    with_preview_wrap(true, function()
      for _, factory in ipairs { "commit", "changed_files", "gist", "review_thread", "repo" } do
        local winopts = instance_of(previewers[factory]({})):gen_winopts()
        eq(false, winopts.wrap, factory .. " should not wrap")
      end
    end)
  end)

  it("honours picker_config.preview_wrap = false for prose previews", function()
    with_preview_wrap(false, function()
      eq(false, instance_of(previewers.issue {}):gen_winopts().wrap)
    end)
  end)

  it("never numbers a preview window", function()
    with_preview_wrap(true, function()
      eq(false, instance_of(previewers.issue {}):gen_winopts().number)
    end)
  end)
end)
