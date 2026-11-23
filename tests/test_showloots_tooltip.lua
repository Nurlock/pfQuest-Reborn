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

-- Hook: AppendTooltipLines writes loot lines onto a tooltip frame.
local added = {}
local fakeTip = { AddLine = function(self, t) table.insert(added, t) end }
env.pfQuest_config["showloots"] = "1"
env.pfQuest_config["showlootsMaxLines"] = "5"
assert(env.pfQuestLoot.AppendTooltipLines(fakeTip, 7001) == true, "must append lines")
assert(#added >= 1, "tooltip must gain loot lines")
env.pfQuest_config["showloots"] = "0"
assert(env.pfQuestLoot.AppendTooltipLines(fakeTip, 7001) == false, "disabled toggle must skip")
print("  PASS: hook appends lines")

-- One-slot memo: repeated hovers on the same unit name must not rescan
-- the unit DB via GetIDByName; a different name triggers one fresh call.
env.UnitIsPlayer = function() return false end
env.pfQuest = env.pfQuest or {}
env.pfQuest.partyapi = env.pfQuest.partyapi or {
  IsInGroup = function() return false end,
  IsTooltipEnabled = function() return false end,
}
local lookups = 0
local hoverName = "Defias Thug"
env.pfDatabase = { GetIDByName = function(self, name, db)
  lookups = lookups + 1
  assert(name == hoverName, "lookup must use the hovered name")
  return { [7001] = true }
end }
load_file("partytooltip.lua")
env.pfQuest.partyapi.HookGameTooltip()

env.pfQuest_config["showloots"] = "1"
local tip = env.GameTooltip
tip.AddLine = function() end
tip.Show = function() end
tip.GetUnit = function() return hoverName, "target" end

tip:FireScript("OnTooltipSetUnit")
assert(lookups == 1, "first hover must call GetIDByName once, got " .. lookups)
tip:FireScript("OnTooltipSetUnit")
assert(lookups == 1, "same-name hover must hit the memo, got " .. lookups .. " calls")
hoverName = "Bandit Bruiser"
tip:FireScript("OnTooltipSetUnit")
assert(lookups == 2, "new name must refresh the memo, got " .. lookups .. " calls")
print("  PASS: one-slot loot memo")
