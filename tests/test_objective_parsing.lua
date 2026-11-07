-- Test Suite: Objective Completion Parsing & Node Filtering
-- Tests parsing of monsters, objects, items, non-"slain" verbs, and leaderboards without numbers.

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

env.pfQuestConfig = env.CreateFrame("Frame", "pfQuestConfig")
env.pfQuestConfig.path = "Interface\\AddOns\\pfQuest"
env.pfQuest_config = {
  ["allquestgivers"] = "1",
  ["currentquestgivers"] = "1",
  ["trackingmethod"] = 1,
  ["showlowlevel"] = "1",
  ["showhighlevel"] = "1",
  ["mindropchance"] = 0,
}
env.pfQuest_history = {}
env.pfQuest_Loc = setmetatable({}, { __index = function(_, k) return k end })
env.pfUI = { api = { SanitizePattern = function(s) return s end, emulated = true } }
env.pfQuest = { questlog = {}, collapsedQuestIDs = {}, announcedQuests = {} }

load_file("compat/client.lua")
load_file("database.lua")
load_file("map.lua")

-- Setup a test quest with:
-- 1. A standard kill mob (Unit 1001, "Defias Thug")
-- 2. A non-"slain" verb mob (Unit 1002, "Sickly Gazelle")
-- 3. An interactive game object (Object 2001, "Northshire Water Valve")
-- 4. An item objective (Item 3001, "Garrick's Head", dropped by Unit 1003)
local questId = 500
env.pfDB.quests.data[questId] = {
  lvl = 3,
  min = 1,
  ["start"] = { ["U"] = { 823 } },
  ["end"] = { ["U"] = { 823 } },
  ["obj"] = {
    ["U"] = { 1001, 1002 },
    ["O"] = { 2001 },
    ["I"] = { 3001 },
  }
}
env.pfDB.quests.loc[questId] = { T = "Multi-Objective Test Quest" }

env.pfDB.units.data[1001] = { coords = { { 30.0, 30.0, 1, 0 } }, fac = "A" }
env.pfDB.units.loc[1001] = "Defias Thug"

env.pfDB.units.data[1002] = { coords = { { 32.0, 32.0, 1, 0 } }, fac = "A" }
env.pfDB.units.loc[1002] = "Sickly Gazelle"

env.pfDB.objects.data[2001] = { coords = { { 34.0, 34.0, 1, 0 } }, fac = "A" }
env.pfDB.objects.loc[2001] = "Northshire Water Valve"

env.pfDB.items.data[3001] = { ["U"] = { [1003] = 100 } }
env.pfDB.items.loc[3001] = "Garrick's Head"

env.pfDB.units.data[1003] = { coords = { { 36.0, 36.0, 1, 0 } }, fac = "A" }
env.pfDB.units.loc[1003] = "Garrick Padfoot"

env.pfDatabase:BuildNameIndex()
env.pfDatabase:BuildStaticRejectSet()

print("[TEST] Objective parsing scenario: In-progress quest (0/10 Thugs, 0/4 Gazelles, 0/1 Valve, 0/1 Head)...")
env.SetMockQuestLog({
  [1] = {
    id = questId,
    title = "Multi-Objective Test Quest",
    isComplete = false,
    objectives = {
      [1] = { text = "Defias Thug slain: 0/10", type = "monster", done = nil },
      [2] = { text = "Sickly Gazelle healed: 0/4", type = "monster", done = nil },
      [3] = { text = "Northshire Water Valve turned: 0/1", type = "object", done = nil },
      [4] = { text = "Garrick's Head: 0/1", type = "item", done = nil },
    }
  }
})

local meta = { ["addon"] = "PFQUEST", ["qlogid"] = 1 }
env.pfDatabase:SearchQuestID(questId, meta)

-- Verify all 4 objectives placed nodes
assert(env.pfMap.nodes["PFQUEST"][1]["30|30"], "Defias Thug node should be present")
assert(env.pfMap.nodes["PFQUEST"][1]["32|32"], "Sickly Gazelle node should be present")
assert(env.pfMap.nodes["PFQUEST"][1]["34|34"], "Water Valve node should be present")
assert(env.pfMap.nodes["PFQUEST"][1]["36|36"], "Garrick Padfoot drop node should be present")
print("  ✓ PASS: In-progress objectives successfully placed on map")

print("[TEST] Objective parsing scenario: Partial completion (Defias Thugs 10/10 DONE, Water Valve 1/1 DONE)...")
env.pfMap:DeleteNode("PFQUEST", "Multi-Objective Test Quest")

env.SetMockQuestLog({
  [1] = {
    id = questId,
    title = "Multi-Objective Test Quest",
    isComplete = false,
    objectives = {
      [1] = { text = "Defias Thug slain: 10/10", type = "monster", done = 1 },
      [2] = { text = "Sickly Gazelle healed: 2/4", type = "monster", done = nil },
      [3] = { text = "Northshire Water Valve turned: 1/1", type = "object", done = 1 },
      [4] = { text = "Garrick's Head: 0/1", type = "item", done = nil },
    }
  }
})

local meta2 = { ["addon"] = "PFQUEST", ["qlogid"] = 1 }
env.pfDatabase:SearchQuestID(questId, meta2)

-- Assert finished objectives (Defias Thug & Water Valve) are NOT added
assert(not env.pfMap.nodes["PFQUEST"] or not env.pfMap.nodes["PFQUEST"][1] or not env.pfMap.nodes["PFQUEST"][1]["30|30"],
  "Completed Defias Thug (10/10 slain) node MUST be hidden!")
assert(not env.pfMap.nodes["PFQUEST"] or not env.pfMap.nodes["PFQUEST"][1] or not env.pfMap.nodes["PFQUEST"][1]["34|34"],
  "Completed Water Valve (1/1 object) node MUST be hidden!")

-- Assert remaining incomplete objectives (Gazelle & Garrick's Head) ARE still present
assert(env.pfMap.nodes["PFQUEST"][1]["32|32"], "Incomplete Sickly Gazelle (2/4 healed) node MUST be shown!")
assert(env.pfMap.nodes["PFQUEST"][1]["36|36"], "Incomplete Garrick Padfoot drop node MUST be shown!")
print("  ✓ PASS: Completed kill mob and completed game object correctly filtered out")

print("[TEST] Objective parsing scenario: Non-slain verb completion (Sickly Gazelle 4/4 healed DONE)...")
env.pfMap:DeleteNode("PFQUEST", "Multi-Objective Test Quest")

env.SetMockQuestLog({
  [1] = {
    id = questId,
    title = "Multi-Objective Test Quest",
    isComplete = false,
    objectives = {
      [1] = { text = "Defias Thug slain: 10/10", type = "monster", done = 1 },
      [2] = { text = "Sickly Gazelle healed: 4/4", type = "monster", done = 1 },
      [3] = { text = "Northshire Water Valve turned: 1/1", type = "object", done = 1 },
      [4] = { text = "Garrick's Head: 0/1", type = "item", done = nil },
    }
  }
})

local meta3 = { ["addon"] = "PFQUEST", ["qlogid"] = 1 }
env.pfDatabase:SearchQuestID(questId, meta3)

assert(not env.pfMap.nodes["PFQUEST"] or not env.pfMap.nodes["PFQUEST"][1] or not env.pfMap.nodes["PFQUEST"][1]["32|32"],
  "Completed Sickly Gazelle (4/4 healed, non-slain verb) node MUST be hidden!")
assert(env.pfMap.nodes["PFQUEST"][1]["36|36"], "Only Garrick Padfoot drop node should remain")
print("  ✓ PASS: Non-slain verb ('healed') properly parsed as DONE and node removed")

print("[TEST] Objective parsing scenario: use-counted objective (6395's Buried: 0/1)...")
env.pfMap:DeleteNode("PFQUEST", "Multi-Objective Test Quest")

-- 6395 shape, from the live client: the line counts burials, not possession,
-- is tagged "object", and names the item ("Samuel's Remains Buried: 0/1").
local graveId = 600
env.pfDB.quests.data[graveId] = {
  lvl = 5, min = 3,
  ["start"] = { ["U"] = { 823 } },
  ["end"] = { ["U"] = { 823 } },
  ["obj"] = { ["O"] = { 2002 }, ["I"] = { 3002 }, ["IR"] = { 3002 } },
}
env.pfDB.quests.loc[graveId] = { T = "Remains to the Grave" }
env.pfDB.items.data[3002] = { ["U"] = { [3003] = 100 } }
env.pfDB.items.loc[3002] = "Samuel's Remains"
env.pfDB.units.data[3003] = { coords = { { 36.0, 36.0, 1, 0 } }, fac = "A" }
env.pfDB.units.loc[3003] = "Samuel Fipps"
env.pfDB.objects.data[2002] = { coords = { { 31.0, 31.0, 1, 0 } }, fac = "A" }
env.pfDB.objects.loc[2002] = "Marla's Grave"
env.pfDB["quests-itemreq"].data = { [3002] = { [-2002] = 0 } }
env.pfDatabase:Reload()
env.pfDatabase:BuildNameIndex()
env.pfDatabase:BuildStaticRejectSet()

-- remains in bags, nothing buried yet: ghoul hides, gated grave shows
env.pfDatabase.itemlist.db = { [3002] = true, ["Samuel's Remains"] = true }
env.SetMockQuestLog({
  [1] = {
    id = graveId,
    title = "Remains to the Grave",
    isComplete = false,
    objectives = {
      [1] = { text = "Samuel's Remains Buried: 0/1", type = "object", done = nil },
    }
  }
})
env.pfDatabase:SearchQuestID(graveId, { ["addon"] = "PFQUEST", ["qlogid"] = 1 })
assert(not env.pfMap.nodes["PFQUEST"][1]["36|36"],
  "Held single-use item MUST hide its loot source!")
assert(env.pfMap.nodes["PFQUEST"][1]["31|31"],
  "Gated use-target MUST show while the remains are held!")
local gated = false
for _, m in pairs(env.pfMap.nodes["PFQUEST"][1]["31|31"]) do
  if m.itemreq then gated = true end
end
assert(gated, "Grave pin MUST carry the itemreq flag!")
print("  ✓ PASS: Held item hides the source, gated grave takes over")

print("[TEST] Objective parsing scenario: same quest, remains still missing...")
env.pfMap:DeleteNode("PFQUEST", "Remains to the Grave")
env.pfDatabase.itemlist.db = {}
env.SetMockQuestLog({
  [1] = {
    id = graveId,
    title = "Remains to the Grave",
    isComplete = false,
    objectives = {
      [1] = { text = "Samuel's Remains Buried: 0/1", type = "object", done = nil },
    }
  }
})
env.pfDatabase:SearchQuestID(graveId, { ["addon"] = "PFQUEST", ["qlogid"] = 1 })
assert(env.pfMap.nodes["PFQUEST"][1]["36|36"],
  "Incomplete item line MUST still show its loot source!")
assert(not env.pfMap.nodes["PFQUEST"][1]["31|31"],
  "Ungated use-target MUST stay hidden while the remains are missing!")
print("  ✓ PASS: Incomplete line keeps the source, grave stays hidden")

print("[TEST] Objective parsing scenario: type-tagged lines for kills and objects...")
local typeId = 601
env.pfDB.quests.data[typeId] = {
  lvl = 5, min = 3,
  ["obj"] = { ["U"] = { 1004 }, ["O"] = { 2003 } },
}
env.pfDB.quests.loc[typeId] = { T = "Short-Named Objectives" }
env.pfDB.units.data[1004] = { coords = { { 37.0, 37.0, 1, 0 } }, fac = "A" }
env.pfDB.units.loc[1004] = "Tarren Mill Peasant"
env.pfDB.objects.data[2003] = { coords = { { 38.0, 38.0, 1, 0 } }, fac = "A" }
env.pfDB.objects.loc[2003] = "Northshire Water Valve"
env.pfDatabase:BuildNameIndex()
env.pfDatabase:BuildStaticRejectSet()
env.SetMockQuestLog({
  [1] = {
    id = typeId,
    title = "Short-Named Objectives",
    isComplete = false,
    objectives = {
      [1] = { text = "Peasant slain: 1/1", type = "monster", done = 1 },
      [2] = { text = "Valve turned: 1/1", type = "object", done = 1 },
    }
  }
})
env.pfDatabase:SearchQuestID(typeId, { ["addon"] = "PFQUEST", ["qlogid"] = 1 })
assert(not env.pfMap.nodes["PFQUEST"][1]["37|37"],
  "Completed monster line (type-tagged) MUST hide its mob!")
assert(not env.pfMap.nodes["PFQUEST"][1]["38|38"],
  "Completed object line (type-tagged) MUST hide its object!")
print("  ✓ PASS: Type-tagged kill and object lines hide their sources")

print("[TEST] Objective parsing scenario: several candidates, no guessing...")
env.pfMap:DeleteNode("PFQUEST", "Short-Named Objectives")
local multiId = 602
env.pfDB.quests.data[multiId] = {
  lvl = 5, min = 3,
  ["obj"] = { ["U"] = { 1004, 1005 } },
}
env.pfDB.quests.loc[multiId] = { T = "Ambiguous Objectives" }
env.pfDB.units.data[1005] = { coords = { { 39.0, 39.0, 1, 0 } }, fac = "A" }
env.pfDB.units.loc[1005] = "Other Mob"
env.pfDatabase:BuildNameIndex()
env.pfDatabase:BuildStaticRejectSet()
env.SetMockQuestLog({
  [1] = {
    id = multiId,
    title = "Ambiguous Objectives",
    isComplete = false,
    objectives = {
      [1] = { text = "Something slain: 1/1", type = "monster", done = 1 },
    }
  }
})
env.pfDatabase:SearchQuestID(multiId, { ["addon"] = "PFQUEST", ["qlogid"] = 1 })
assert(env.pfMap.nodes["PFQUEST"][1]["37|37"],
  "Ambiguous line MUST NOT hide the first candidate!")
assert(env.pfMap.nodes["PFQUEST"][1]["39|39"],
  "Ambiguous line MUST NOT hide the second candidate!")
print("  ✓ PASS: Multi-candidate lines stay unattributed")

print("[TEST] Objective parsing scenario: partial multi-count stack keeps its source...")
local partialId = 603
env.pfDB.quests.data[partialId] = {
  lvl = 5, min = 3,
  ["obj"] = { ["I"] = { 3004 } },
}
env.pfDB.quests.loc[partialId] = { T = "Partial Stack Quest" }
env.pfDB.items.data[3004] = { ["U"] = { [3005] = 100 } }
env.pfDB.items.loc[3004] = "Wolf Meat"
env.pfDB.units.data[3005] = { coords = { { 40.0, 40.0, 1, 0 } }, fac = "A" }
env.pfDB.units.loc[3005] = "Starving Wolf"
env.pfDatabase:BuildNameIndex()
env.pfDatabase:BuildStaticRejectSet()
-- holding 1 of 3: the single-use hide MUST NOT fire
env.pfDatabase.itemlist.db = { [3004] = true, ["Wolf Meat"] = true }
env.SetMockQuestLog({
  [1] = {
    id = partialId,
    title = "Partial Stack Quest",
    isComplete = false,
    objectives = {
      [1] = { text = "Wolf Meat: 1/3", type = "item", done = nil },
    }
  }
})
env.pfDatabase:SearchQuestID(partialId, { ["addon"] = "PFQUEST", ["qlogid"] = 1 })
assert(env.pfMap.nodes["PFQUEST"][1]["40|40"],
  "Partial stack (1/3 held) MUST keep its loot source!")
print("  ✓ PASS: Partial multi-count stack keeps farming")

print("[TEST] test_objective_parsing PASSED successfully!")
