---@diagnostic disable
local eq = assert.are.same

-- Deliberately independent of any picker provider module (fzf-lua, telescope,
-- snacks, ...): it only touches octo.config and octo.utils, so it always runs
-- under the standard test harness even when a picker's own dependencies
-- (e.g. fzf-lua) are unavailable to the test process.
---The fzf key each picker mapping converts to, keyed by the mapping's name.
---@return table<string, string> keys mapping name -> fzf key
local function mapping_keys()
  local mappings = require("octo.config").get_default_values().picker_config.mappings
  local keys = {}
  for name, m in pairs(mappings) do
    keys[name] = require("octo.utils").convert_vim_mapping_to_fzf(m.lhs)
  end
  return keys
end

describe("picker mappings:", function()
  it("gives every picker mapping a distinct fzf key", function()
    local mappings = require("octo.config").get_default_values().picker_config.mappings
    local seen, count = {}, 0
    for name, m in pairs(mappings) do
      count = count + 1
      local fzf = require("octo.utils").convert_vim_mapping_to_fzf(m.lhs)
      assert.is_nil(seen[fzf], ("%s collides with %s on %q"):format(name, tostring(seen[fzf]), fzf))
      seen[fzf] = name
    end
    eq(count, vim.tbl_count(seen))
  end)
end)

-- These two do need fzf-lua, because what a mapping might silently overwrite
-- lives half in octo's own action tables and half in fzf-lua's defaults.
describe("picker mappings against the keys already taken:", function()
  local ok, fzf_actions = pcall(require, "octo.pickers.fzf-lua.pickers.fzf_actions")
  local defaults_ok, fzf_defaults = pcall(require, "fzf-lua.defaults")

  if not ok or not defaults_ok then
    it("requires fzf-lua and octo's fzf-lua actions", function()
      assert(
        false,
        "could not load the fzf-lua action tables (is fzf-lua on the runtimepath?): "
          .. tostring(fzf_actions)
          .. " / "
          .. tostring(fzf_defaults)
      )
    end)
    return
  end

  it("never rebinds one of octo's own hardcoded picker keys", function()
    local hardcoded = fzf_actions.common_buffer_actions {}

    for name, key in pairs(mapping_keys()) do
      assert.is_nil(
        hardcoded[key],
        (
          "picker_config.mappings.%s takes %q, which octo already hardcodes; the mapping would win and the "
          .. "hardcoded action would vanish"
        ):format(name, key)
      )
    end
  end)

  it("shadows exactly the three fzf-lua default binds it has always shadowed", function()
    local reserved = {}
    for key in pairs(fzf_defaults.defaults.keymap.fzf) do
      reserved[key] = true
    end
    for key in pairs(fzf_defaults.defaults.keymap.builtin) do
      reserved[string.lower(key)] = true
    end

    local shadowed = {}
    for _, key in pairs(mapping_keys()) do
      if reserved[key] then
        shadowed[#shadowed + 1] = key
      end
    end
    table.sort(shadowed)

    eq({ "alt-a", "ctrl-b", "ctrl-e" }, shadowed)
  end)
end)
