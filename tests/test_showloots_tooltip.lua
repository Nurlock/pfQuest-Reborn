-- ShowLoots hover lines: top-N drops for a unit, sorted by chance desc.
local mock = require("tests.mock_wow_api")
local env = mock.create_env()

local function load_file(path)
  local f = io.open(path, "r")
  assert(f, "Could not open " .. path)
  local content = f:read("*a")
  f:close()
  local fn, err = loadstring(content, path)
  assert(fn, err)
  setfenv(fn, env)
  return fn()
end

env.pfQuest_config = { mindropchance = 0, epochLootPanelShowReference = "1",
  epochLootPanelShowUnknownChance = "1" }
env.pfDB = { items = { data = {
  [101] = { U = { [7001] = 80 } },
  [102] = { U = { [7001] = 13.23 } },
  [103] = { U = { [7001] = 0.02 } },
}, loc = { [101] = "Bandana", [102] = "Bleu", [103] = "Bread" } },
  refloot = { data = {} }, units = { data = {}, loc = {} } }
env.pfDB.units.data[7001] = { lvl = 10 }
env.pfDB.units.loc[7001] = "Defias Thug"
env.GetItemInfo = function(id) return "n", "l", 1, 1, 1, "Misc" end
load_file("lootpanel.lua")
local lines = env.pfQuestLoot.GetTooltipLines(7001, 2)
assert(#lines == 2, "must return top 2 lines, got " .. #lines)
assert(lines[1].item == 101 and lines[1].chance == 80, "first line must be highest chance")
print("  PASS: tooltip lines")
