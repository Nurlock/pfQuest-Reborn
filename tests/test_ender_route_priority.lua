-- Test Suite: Premature Turn-In Route Priority (quest 6395 case study)
-- The quest ender is always rendered, so at pickup it sits at distance ~0 and
-- would beat the actionable kill objective on distance alone. Same-quest
-- ender pins must sort after objective pins in the route planner.
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
env.pfUI = { api = { SanitizePattern = function(s) return s end, emulated = true },
  font_default = "Fonts\\FRIZQT__.TTF" }
env.pfUI_config = { global = { font_size = 12 } }
env.pfQuest = { questlog = {}, collapsedQuestIDs = {}, announcedQuests = {} }

load_file("compat/client.lua")
load_file("database.lua")
load_file("map.lua")
load_file("route.lua")

-- use the real generated itemreq mapping (covers 16333 and 26939's 62811)
load_file("db/quests-itemreq.lua")
env.pfDatabase:Reload()

-- 6395 shape: kill source (I), gated use-target (O+IR), unit ender
env.pfDB.quests.data[6395] = {
  lvl = 5, min = 3,
  ["start"] = { ["U"] = { 1661 } },
  ["end"] = { ["U"] = { 1661 } },
  ["obj"] = { ["O"] = { 178090 }, ["I"] = { 16333 }, ["IR"] = { 16333 } },
}
env.pfDB.quests.loc[6395] = { T = "Marla's Last Wish" }
env.pfDB.units.data[1919] = { lvl = "5", coords = { { 36.6, 61.6, 85, 300 } }, fac = "H" }
env.pfDB.units.loc[1919] = "Samuel Fipps"
env.pfDB.units.data[1661] = { coords = { { 32.5, 66.0, 85, 0 } }, fac = "H" }
env.pfDB.units.loc[1661] = "Novice Elreth"
env.pfDB.objects.data[178090] = { coords = { { 31.2, 65.1, 85, 900 } }, fac = "" }
env.pfDB.objects.loc[178090] = "Marla's Grave"
env.pfDB.items.data[16333] = { ["U"] = { [1919] = 100 } }
env.pfDB.items.loc[16333] = "Samuel's Remains"
-- 26939 "Peace in Death": same gated-use-target shape, Epoch data
env.pfDB.quests.data[26939] = {
  lvl = 5, min = 3,
  ["start"] = { ["U"] = { 45898 } },
  ["end"] = { ["U"] = { 45898 } },
  ["obj"] = { ["O"] = { 250365 }, ["I"] = { 62811 }, ["IR"] = { 62811 } },
}
env.pfDB.quests.loc[26939] = { T = "Peace in Death" }
env.pfDB.objects.data[250365] = { coords = { { 30.7, 65.2, 85, 0 } }, fac = "" }
env.pfDB.objects.loc[250365] = "Joseph's Grave Dummy"
env.pfDB.objects.data[250600] = { coords = { { 23.1, 59.8, 85, 0 } }, fac = "" }
env.pfDB.objects.loc[250600] = "Joseph's Watch"
env.pfDB.items.data[62811] = { ["O"] = { [250600] = 100 } }
env.pfDB.items.loc[62811] = "Joseph's Watch"
env.pfDB["quests-itemreq"].data[16333] = { [-178090] = 0 }
-- 640: same shape but with an OBJECT ender (covers the OBJECT_END branch)
env.pfDB.quests.data[640] = {
  lvl = 5, min = 3,
  ["end"] = { ["O"] = { 178090 } },
  ["obj"] = { ["U"] = { 1919 } },
}
env.pfDB.quests.loc[640] = { T = "Object Ender Quest" }
env.pfDatabase:BuildNameIndex()
env.pfDatabase:BuildStaticRejectSet()

local function findMeta(zone, spawnName)
  for _, node in pairs(env.pfMap.nodes["PFQUEST"][zone]) do
    for _, meta in pairs(node) do
      if meta.spawn == spawnName then return meta end
    end
  end
end

print("[TEST] Ender pins are flagged, objective pins are not...")
env.pfQuest.questlog[6395] = { title = "Marla's Last Wish", qlogid = 1 }
env.pfQuest.questlog[640] = { title = "Object Ender Quest", qlogid = 2 }
env.pfQuest.questlog[26939] = { title = "Peace in Death", qlogid = 3 }
env.SetMockQuestLog({
  [1] = { id = 6395, title = "Marla's Last Wish", isComplete = false,
    objectives = { [1] = { text = "Samuel's Remains: 0/1", type = "item", done = nil } } },
  [2] = { id = 640, title = "Object Ender Quest", isComplete = false,
    objectives = { [1] = { text = "Samuel Fipps slain: 0/1", type = "monster", done = nil } } },
  [3] = { id = 26939, title = "Peace in Death", isComplete = false, objectives = {} },
})
env.pfDatabase.itemlist.db = {}
env.pfDatabase:SearchQuestID(6395, { ["addon"] = "PFQUEST", ["qlogid"] = 1 })
env.pfDatabase:SearchQuestID(640, { ["addon"] = "PFQUEST", ["qlogid"] = 2 })
env.pfDatabase:SearchQuestID(26939, { ["addon"] = "PFQUEST", ["qlogid"] = 3 })

local enderMeta = findMeta(85, "Novice Elreth")
assert(enderMeta, "Novice Elreth (NPC_END) node must exist")
assert(enderMeta.ender == true, "NPC_END node MUST carry ender=true")
local ghoulMeta = findMeta(85, "Samuel Fipps")
assert(ghoulMeta, "Samuel Fipps (kill source) node must exist")
assert(ghoulMeta.ender == nil, "Objective node MUST NOT carry the ender flag (no meta leak)")
-- grave stays gated behind the item while bags are empty
assert(not findMeta(85, "Marla's Grave") or not findMeta(85, "Marla's Grave").itemreq,
  "grave without itemreq flag must not appear while the remains are missing")
-- 26939's dummy is gated by the regenerated mapping: no watch, no pin
assert(not findMeta(85, "Joseph's Grave Dummy"),
  "Grave Dummy MUST stay hidden while Joseph's Watch is missing")
print("  ✓ PASS: ender flag plumbing (NPC_END set, objectives clean)")

print("[TEST] OBJECT_END branch flags the gameobject ender...")
local objEnder = nil
for _, node in pairs(env.pfMap.nodes["PFQUEST"][85]) do
  for _, meta in pairs(node) do
    if meta.spawn == "Marla's Grave" and meta.QTYPE == "OBJECT_END" then objEnder = meta end
  end
end
assert(objEnder and objEnder.ender == true, "OBJECT_END node MUST carry ender=true")
print("  ✓ PASS: OBJECT_END flagged")
print("[TEST] With the watch in bags, the dummy appears as the flagged use-target...")
env.pfDatabase.itemlist.db = { [62811] = true, ["Joseph's Watch"] = true }
env.pfMap:DeleteNode("PFQUEST", "Peace in Death")
env.pfDatabase:SearchQuestID(26939, { ["addon"] = "PFQUEST", ["qlogid"] = 3 })
local dummyMeta = findMeta(85, "Joseph's Grave Dummy")
assert(dummyMeta, "Grave Dummy node must appear once the watch is held")
assert(dummyMeta.itemreq == "Joseph's Watch", "Dummy MUST be flagged as the watch's use-target")
assert(dummyMeta.QTYPE == "OBJECT_OBJECTIVE_ITEMREQ", "Dummy MUST use the itemreq QTYPE")
print("  ✓ PASS: use-target gated correctly by possession")


print("[TEST] Route sort: actionable kill beats the nearer premature turn-in...")
local sf = env.pfQuest.route.sortfunc
assert(type(sf) == "function", "pfQuest.route.sortfunc must be exposed")
local function tup(pin, dist, qid, watched)
  return { 0, 0, pin, dist, watched, qid }
end
-- the 6395 pickup shape: ender at ~0, ghoul at ~6.5
local enderPin, mobPin = { ender = true }, {}
assert(sf(tup(mobPin, 6.5, 6395), tup(enderPin, 0, 6395)) == true,
  "Outstanding kill MUST sort before the nearer premature turn-in (same quest)")
assert(sf(tup(enderPin, 0, 6395), tup(mobPin, 6.5, 6395)) == false,
  "Premature turn-in MUST NOT sort before the outstanding kill (same quest)")
print("  ✓ PASS: ender demoted within its quest")
-- the reported case: another quest's nearer premature turn-in loses too
assert(sf(tup(mobPin, 7.5, 6395), tup(enderPin, 0.9, 26939)) == true,
  "Actionable kill MUST beat another quest's nearer premature turn-in")
assert(sf(tup(enderPin, 0.9, 26939), tup(mobPin, 7.5, 6395)) == false,
  "Another quest's premature turn-in MUST NOT steal the arrow")
print("  ✓ PASS: ender demoted across quests")
print("[TEST] Completed quest: turn-in loses the flag and stays routable...")
env.pfMap:DeleteNode("PFQUEST") -- drop all quests' pins; findMeta matches by spawn name
env.SetMockQuestLog({
  [1] = { id = 6395, title = "Marla's Last Wish", isComplete = true,
    objectives = { [1] = { text = "Samuel's Remains: 1/1", type = "item", done = 1 } } },
})
env.pfDatabase.itemlist.db = { [16333] = true, ["Samuel's Remains"] = true }
env.pfDatabase:SearchQuestID(6395, { ["addon"] = "PFQUEST", ["qlogid"] = 1 })
local doneEnder = findMeta(85, "Novice Elreth")
assert(doneEnder, "Completed quest ender must exist")
assert(doneEnder.ender == nil, "Completed turn-in MUST NOT carry the ender flag")
assert(not findMeta(85, "Samuel Fipps"), "Finished kill source must hide on completion")
print("  ✓ PASS: completion clears the flag")


print("[TEST] Route sort: no cross-quest or itemreq regressions...")
-- other quests still sort purely by distance
assert(sf(tup({}, 2, 100), tup({}, 5, 200)) == true, "Cross-quest order must stay distance-based")
assert(sf(tup({}, 5, 200), tup({}, 2, 100)) == false, "Cross-quest order must stay distance-based")
-- the gather-before-use rule still holds (grave after ghoul, same quest)
local gravePin = { itemreq = "Samuel's Remains" }
assert(sf(tup(mobPin, 9, 6395), tup(gravePin, 1, 6395)) == true,
  "Kill source MUST still sort before the gated use-target (itemreq rule intact)")
assert(sf(tup(gravePin, 1, 6395), tup(mobPin, 9, 6395)) == false,
  "Gated use-target MUST still sort after the kill source")
-- ender-vs-ender of one quest falls through to distance
assert(sf(tup({ ender = true }, 1, 6395), tup({ ender = true }, 9, 6395)) == true,
  "Same-kind enders must fall through to distance order")
-- a completed turn-in still competes on distance cross-quest
assert(sf(tup({}, 0.5, 6395), tup({}, 6.5, 640)) == true,
  "Completed turn-in MUST stay routable by distance")
print("  ✓ PASS: no regressions")

print("[TEST] test_ender_route_priority PASSED successfully!")
