---@diagnostic disable
local eq = assert.are.same

-- Deliberately independent of any picker provider module (fzf-lua, telescope,
-- snacks, ...): it only touches octo.config and octo.utils, so it always runs
-- under the standard test harness even when a picker's own dependencies
-- (e.g. fzf-lua) are unavailable to the test process.
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
