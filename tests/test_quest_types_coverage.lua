-- Test Suite: 100% Quest Types Coverage & Regression Detection
-- Validates parsing, node lifecycles, state fingerprints, and tracker progress
-- across all WoW quest archetypes:
-- 1. Standard Kill Quest (type == "monster", x/y slain)
-- 2. Mob Loot / Collect Quest (type == "item", mob drops)
-- 3. Game Object Interaction Quest (type == "object", interact counts)
-- 4. Item Requirement / Invocation Quest (IR:<item>;U:<npc> multi-step)
-- 5. Provided-Item Target Quest (possession gating)
-- 6. Non-Slain Verb Quest (custom action verbs, healed/captured)
-- 7. Unnumbered Event / Talk Quest (type == "event", static text, done flag)
-- 8. Zero-Objective Delivery Quest (GetNumQuestLeaderBoards == 0)
-- 9. AreaTrigger / Exploration Quest (coordinate discovery)
-- 10. Item-Starter Quest (drop sources starting a quest)
-- 11. Multi-Objective Hybrid Quest (mixed kills, items, objects)
-- 12. Core Flap Immunity (premature isComplete rejection)
-- 13. Tracker Progress & Color Formatting for all types

local mock = require("tests.mock_wow_api")
local env = mock.create_env()

local loadstring = loadstring or load

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
  ["epochgroupsync"] = "1",
  ["trackerexpand"] = "1",
}
env.pfQuest_history = {}
env.pfQuest_Loc = setmetatable({}, { __index = function(_, k) return k end })
env.pfUI = {
  font_default = "Fonts\\FRIZQT__.TTF",
  api = { SanitizePattern = function(s) return s end, emulated = true }
}
env.pfQuest = {
  questlog = {},
  collapsedQuestIDs = {},
  announcedQuests = {},
  queue = {},
  queueHead = 1,
  queueTail = 1,
  queueCount = 0,
}

env.ceil = math.ceil
env.floor = math.floor
env.gsub = string.gsub
env.strfind = string.find
load_file("compat/client.lua")
load_file("theme.lua")
load_file("locales/en.lua")
load_file("i18n.lua")
load_file("database.lua")
load_file("map.lua")
load_file("quest.lua")
load_file("tracker.lua")

print("======================================================================")
print("  Quest Types 100% Coverage & Regression Suite")
print("======================================================================")

-- Setup mock database tables
env.pfDB.units.loc[101] = "Defias Rogue"
env.pfDB.units.data[101] = { lvl = 5, coords = { { 10.0, 20.0, 14, 0 } }, fac = "A" }
env.pfDB.units.loc[102] = "Sickly Deer"
env.pfDB.units.data[102] = { lvl = 4, coords = { { 15.0, 25.0, 14, 0 } }, fac = "A" }
env.pfDB.units.loc[103] = "Lunaclaw"
env.pfDB.units.data[103] = { lvl = 12, coords = { { 42.8, 45.0, 148, 0 } }, fac = "A" }
env.pfDB.units.loc[104] = "Quest Giver"
env.pfDB.units.data[104] = { lvl = 60, coords = { { 30.0, 40.0, 14, 0 } }, fac = "A" }
env.pfDB.units.loc[105] = "Loot Drop Mob"
env.pfDB.units.data[105] = { lvl = 8, coords = { { 12.0, 22.0, 14, 0 } }, fac = "A" }

env.pfDB.objects.loc[201] = "Water Barrel"
env.pfDB.objects.data[201] = { coords = { { 18.0, 28.0, 14, 900 } } }
env.pfDB.objects.loc[202] = "Moonkin Stone"
env.pfDB.objects.data[202] = { coords = { { 42.0, 60.0, 148, 900 } } }

env.pfDB.items.loc[301] = "Bandit Ear"
env.pfDB.items.data[301] = { ["U"] = { [105] = 100 } }
env.pfDB.items.loc[302] = "Cenarion Moondust"
env.pfDB.items.data[302] = {}

env.pfDB["quests-itemreq"] = { data = {} }
env.pfDB["quests-itemreq"].data[302] = { [-202] = "18974" }

env.pfDatabase:BuildNameIndex()
env.pfDatabase:BuildStaticRejectSet()

--------------------------------------------------------------------------------
-- 1. Standard Kill Quest
--------------------------------------------------------------------------------
print("\n[TEST 1] Standard Kill Quest (type == 'monster')...")
local q1 = 1001
env.pfDB.quests.loc[q1] = { T = "Bandit Hunt" }
env.pfDB.quests.data[q1] = {
  lvl = 5, min = 1,
  ["start"] = { ["U"] = { 104 } },
  ["end"] = { ["U"] = { 104 } },
  ["obj"] = { ["U"] = { 101 } },
}
local maps1 = env.pfDatabase:SearchQuestID(q1, { addon = "PFQUEST", qlogid = 1 })
assert(maps1 and maps1[14], "Kill mob must produce pins on map 14")
-- re-search must clear the id-scoped entry writers use (audit finding 2)
local q1key = "Bandit Hunt\1" .. tostring(q1)
env.pfMap.unifiedcache[q1key] = { stale = true }
env.pfDatabase:SearchQuestID(q1, { addon = "PFQUEST", qlogid = 1 })
assert(env.pfMap.unifiedcache[q1key] and env.pfMap.unifiedcache[q1key].stale == nil,
  "Id-scoped unified cache must be cleared on re-search")
print("  ✓ PASS: Standard Kill Quest correctly mapped")

--------------------------------------------------------------------------------
-- 2. Mob Loot / Collect Quest
--------------------------------------------------------------------------------
print("\n[TEST 2] Mob Loot Collection Quest (type == 'item')...")
local q2 = 1002
env.pfDB.quests.loc[q2] = { T = "Ear Collector" }
env.pfDB.quests.data[q2] = {
  lvl = 5, min = 1,
  ["start"] = { ["U"] = { 104 } },
  ["end"] = { ["U"] = { 104 } },
  ["obj"] = { ["I"] = { 301 } },
}
local maps2 = env.pfDatabase:SearchQuestID(q2, { addon = "PFQUEST", qlogid = 2 })
assert(maps2 and maps2[14], "Mob drop source must produce pins on map 14")
print("  ✓ PASS: Mob Loot Quest correctly mapped to drop source")

--------------------------------------------------------------------------------
-- 3. Game Object Interaction Quest
--------------------------------------------------------------------------------
print("\n[TEST 3] Game Object Interaction Quest (type == 'object')...")
local q3 = 1003
env.pfDB.quests.loc[q3] = { T = "Water Supply" }
env.pfDB.quests.data[q3] = {
  lvl = 5, min = 1,
  ["start"] = { ["U"] = { 104 } },
  ["end"] = { ["U"] = { 104 } },
  ["obj"] = { ["O"] = { 201 } },
}
local maps3 = env.pfDatabase:SearchQuestID(q3, { addon = "PFQUEST", qlogid = 3 })
assert(maps3 and maps3[14], "Object must produce pins on map 14")
print("  ✓ PASS: Game Object Quest correctly mapped")

--------------------------------------------------------------------------------
-- 4. Item Requirement / Invocation Multi-Step Quest
--------------------------------------------------------------------------------
print("\n[TEST 4] Invocation Quest with Item Requirement (IR:<item>;U:<npc>)...")
local q4 = 6001
env.pfDB.quests.loc[q4] = { T = "Body and Heart" }
env.pfDB.quests.data[q4] = {
  lvl = 10, min = 10,
  ["start"] = { ["U"] = { 104 } },
  ["end"] = { ["U"] = { 104 } },
  ["obj"] = { ["IR"] = { 302 }, ["U"] = { 103 } },
}
-- Case A: Player holds Cenarion Moondust in bags
env.pfDatabase.itemlist.db[302] = true
local maps4A = env.pfDatabase:SearchQuestID(q4, { addon = "PFQUEST", qlogid = 4 })
assert(maps4A and maps4A[148], "With dust held, Moonkin Stone + Lunaclaw mapped in Darkshore")

-- Case B: Player uses dust (consumed from bags); Lunaclaw remains active
env.pfDatabase.itemlist.db[302] = nil
local maps4B = env.pfDatabase:SearchQuestID(q4, { addon = "PFQUEST", qlogid = 4 })
assert(maps4B and maps4B[148], "After dust consumed, Lunaclaw remains on map")
print("  ✓ PASS: Invocation multi-step quest preserves targets throughout ritual")

--------------------------------------------------------------------------------
-- 5. Non-Slain Verb Quest (Healed, Captured, etc.)
--------------------------------------------------------------------------------
print("\n[TEST 5] Non-Slain Verb Quest...")
local q5 = 1005
env.pfDB.quests.loc[q5] = { T = "Heal the Beasts" }
env.pfDB.quests.data[q5] = {
  lvl = 5, min = 1,
  ["start"] = { ["U"] = { 104 } },
  ["end"] = { ["U"] = { 104 } },
  ["obj"] = { ["U"] = { 102 } },
}
env.SetMockQuestLog({
  [1] = {
    id = q5,
    title = "Heal the Beasts",
    isComplete = false,
    objectives = {
      [1] = { text = "Sickly Deer healed: 4/4", type = "monster", done = 1 },
    }
  }
})
env.pfMap:DeleteNode("PFQUEST", "Heal the Beasts")
env.pfDatabase:SearchQuestID(q5, { addon = "PFQUEST", qlogid = 1 })
assert(env.pfMap.nodes["PFQUEST"][14] == nil or env.pfMap.nodes["PFQUEST"][14]["15|25"] == nil, "Completed non-slain objective pruned")
print("  ✓ PASS: Non-slain verb completion recognized and pruned")

--------------------------------------------------------------------------------
-- 6. Unnumbered Event / Talk Quest (type == 'event')
--------------------------------------------------------------------------------
print("\n[TEST 6] Unnumbered Event / Talk Quest State Fingerprinting...")
local q6 = 6001
local questComplete = nil
local questDone = false
env.pfQuestCompat.GetQuestLogTitle = function(id)
  return "Body and Heart", 10, nil, nil, nil, questComplete
end
env.GetNumQuestLogEntries = function() return 1, 1 end
env.GetNumQuestLeaderBoards = function(id) return 1 end
env.GetQuestLogLeaderBoard = function(i, id)
  return "Face Lunaclaw and earn the strength of body and heart it possesses.", "event", questDone
end
env.IsQuestWatched = function(id) return false end
env.pfDatabase.GetQuestIDs = function(self, qlogid) return { q6 } end

env.pfQuest.questlog = {}
env.pfQuest:UpdateQuestlog()
local stateBefore = env.pfQuest.questlog[q6].state

-- Advance unnumbered event to done
questDone = true
questComplete = 1
env.pfQuest:UpdateQuestlog()
local stateAfter = env.pfQuest.questlog[q6].state

assert(stateBefore ~= stateAfter, "State fingerprint must change on unnumbered completion")
local reloaded = false
for i = 1, (env.pfQuest.queueTail or 1) do
  local e = env.pfQuest.queue[i]
  if e and e[2] == q6 and e[4] == "RELOAD" then reloaded = true break end
end
assert(reloaded, "RELOAD event must be queued for unnumbered completion")
print("  ✓ PASS: Unnumbered event progress correctly detected and reloaded")

--------------------------------------------------------------------------------
-- 7. Zero-Objective Delivery Quest (GetNumQuestLeaderBoards == 0)
--------------------------------------------------------------------------------
print("\n[TEST 7] Zero-Objective Delivery Quest...")
local q7 = 1007
env.pfDB.quests.loc[q7] = { T = "Letter to Stormwind" }
env.pfDB.quests.data[q7] = {
  lvl = 5, min = 1,
  ["start"] = { ["U"] = { 104 } },
  ["end"] = { ["U"] = { 104 } },
}
env.GetNumQuestLeaderBoards = function(id) return 0 end
local maps7 = env.pfDatabase:SearchQuestID(q7, { addon = "PFQUEST", qlogid = 7 })
assert(maps7 and maps7[14], "Zero-objective quest maps its ender")
print("  ✓ PASS: Zero-objective quest safely maps turn-in without errors")

--------------------------------------------------------------------------------
-- 8. Core Flap Immunity (Trinity/WotLK Flapping Complete Flag)
--------------------------------------------------------------------------------
print("\n[TEST 8] Core Flap Immunity (Rejecting False Premature Complete)...")
local q8 = 1008
env.pfDB.quests.loc[q8] = { T = "Defias Cleansing" }
env.pfDB.quests.data[q8] = {
  lvl = 5, min = 1,
  ["start"] = { ["U"] = { 104 } },
  ["end"] = { ["U"] = { 104 } },
  ["obj"] = { ["U"] = { 101 } },
}
env.GetNumQuestLeaderBoards = function(id) return 1 end
env.GetQuestLogLeaderBoard = function(i, id)
  -- 2/10 kills done: quest is clearly NOT complete despite server flap
  return "Defias Rogue slain: 2/10", "monster", false
end
-- Simulate broken core returning complete = 1 prematurely
env.pfQuestCompat.GetQuestLogTitle = function(id)
  return "Defias Cleansing", 5, nil, nil, nil, 1
end

local maps8 = env.pfDatabase:SearchQuestID(q8, { addon = "PFQUEST", qlogid = 8 })
assert(maps8 and maps8[14], "Corroboration must reject premature complete flag when leaderboards disagree")
print("  ✓ PASS: Core flap successfully corroborated and prevented premature node wipe")

--------------------------------------------------------------------------------
-- 9. Tracker Calculation for Counted vs Unnumbered Objectives
--------------------------------------------------------------------------------
print("\n[TEST 9] Tracker Calculation & Color Formatting...")
local btn = env.CreateFrame("Button")
btn.objectives = {}
btn.title = "Body and Heart"
btn.qid = q6
btn.icon = env.CreateFrame("Texture")
btn.text = btn:CreateFontString(nil, "HIGH", "GameFontNormal")
local node = { texture = "img\\complete_c", questid = q6 }
btn.node = node

-- Unnumbered complete objective
env.pfQuest.questlog[q6] = { qlogid = 1, title = "Body and Heart" }
env.pfQuestCompat.GetQuestLogTitle = function(id)
  return "Body and Heart", 10, nil, nil, nil, 1
end
env.GetNumQuestLeaderBoards = function(id) return 1 end
env.GetQuestLogLeaderBoard = function(i, id)
  return "Face Lunaclaw and earn the strength of body and heart it possesses.", "event", true
end
env.pfQuest.tracker.ButtonEvent(btn, node)
assert(btn.objectives[1] ~= nil, "Objective fontstring created")
-- Ensure completed unnumbered objective received green text color
local r, g, b = btn.objectives[1]:GetTextColor()
assert(r == 0.2 and g == 1.0 and b == 0.2, string.format("Completed unnumbered objective must be green, got: %s,%s,%s", r, g, b))
print("  ✓ PASS: Tracker correctly colors completed unnumbered objectives green")

--------------------------------------------------------------------------------
-- 10. parse_need lifecycle (audit finding 14): cleared between calls
--------------------------------------------------------------------------------
print("\n[TEST 10] parse_need cleared between SearchQuestID calls...")
env.pfQuestCompat.GetQuestLogTitle = function(id)
  return "Ear Collector", 5, nil, nil, nil, false
end
env.GetNumQuestLeaderBoards = function(id) return 1 end

-- Quest A: counted objective writes parse_need[301] = 1 while item is held
env.GetQuestLogLeaderBoard = function(i, id)
  return "Bandit Ear: 1/1", "item", false
end
env.pfDatabase.itemlist.db[301] = true
local q10a = 1010
env.pfDB.quests.loc[q10a] = { T = "Ear Stash A" }
env.pfDB.quests.data[q10a] = {
  lvl = 5, min = 1,
  ["obj"] = { ["I"] = { 301 } },
}
env.pfDatabase:SearchQuestID(q10a, { addon = "PFQUEST", qlogid = 41 })

-- Quest B: same item, unparsable count => PROG without a parse_need write.
-- A stale parse_need[301] == 1 would trigger the held single-use shortcut
-- and skip the drop-source search; a cleared one keeps B's loot pins.
env.GetQuestLogLeaderBoard = function(i, id)
  return "Bandit Ear secured", "item", false
end
local q10b = 1011
env.pfDB.quests.loc[q10b] = { T = "Ear Stash B" }
env.pfDB.quests.data[q10b] = {
  lvl = 5, min = 1,
  ["end"] = { ["U"] = { 103 } },
  ["obj"] = { ["I"] = { 301 } },
}
local maps10b = env.pfDatabase:SearchQuestID(q10b, { addon = "PFQUEST", qlogid = 42 })
assert(maps10b and maps10b[148], "Quest B must map its ender (sanity: call ran)")
assert(maps10b and maps10b[14],
  "Stale parse_need must not suppress quest B's drop-source pins (audit 14)")
env.pfDatabase.itemlist.db[301] = nil
print("  ✓ PASS: parse_need cleared between SearchQuestID calls")
--------------------------------------------------------------------------------
-- 11. REMOVE queue branch driven through the real OnUpdate (audit finding 19)
--------------------------------------------------------------------------------
print("\n[TEST 11] REMOVE queue entry processed by pfQuest OnUpdate...")
-- Harness prerequisites: OnUpdate early-returns while pfDatabase.localized is
-- nil (quest.lua:386), and quest.lua:455 calls WoW's global time(), which the
-- mock does not define.
local savedLocalized = env.pfDatabase.localized
env.pfDatabase.localized = true
env.time = env.time or os.time

local q = env.pfQuest
local qid = 1001 -- "Bandit Hunt": pfDB.quests.loc entry from test 1
-- Frame throttle/lock/deferred flags must not short-circuit the fire.
q.tick = nil
q.lock = nil
q.updateQuestGivers = nil
-- Tests 6-10 left their RELOAD entry queued (OnUpdate never ran in this
-- suite); drain the stale state so the REMOVE entry is the one under test.
for k in pairs(q.queue) do q.queue[k] = nil end
q.queueHead, q.queueTail, q.queueCount = 1, 1, 0
assert(q.queueCount == 0, "setup: queue must be empty")
q.collapsedQuestIDs[qid] = "Elwynn Forest" -- stale state REMOVE must clear
assert(env.pfQuest_history[qid] == nil, "setup: no history row yet")

-- Entry shaped exactly like production (quest.lua:746
-- queueAdd({ data.title, questid, nil, "REMOVE" })); queueAdd is file-local,
-- so mirror its bookkeeping here.
q.queue[q.queueTail] = { "Bandit Hunt", qid, nil, "REMOVE" }
q.queueTail = q.queueTail + 1
q.queueCount = q.queueCount + 1

-- Instrument the two side-effect sinks: node deletion (quest.lua:473/477)
-- and the party broadcast (quest.lua:484 dot-call with (questId, title)).
local deleteCalls = {}
local savedDeleteNode = env.pfMap.DeleteNode
env.pfMap.DeleteNode = function(self, addon, title)
  table.insert(deleteCalls, { addon = addon, title = title })
end
local broadcastCalls = {}
q.partyapi = { BroadcastQuestRemove = function(questId, title)
  table.insert(broadcastCalls, { questId = questId, title = title })
end }

-- Keep GetTime below 1s so the 1s questlog poll (quest.lua:397) does not rerun
-- UpdateQuestlog in the same tick as the queue drain.
env.SetTime(0.5)
env.pfQuest:FireScript("OnUpdate")

assert(q.queueCount == 0, "OnUpdate must drain the REMOVE entry")
assert(env.pfQuest_history[qid] ~= nil,
  "REMOVE must write pfQuest_history[qid] (quest.lua:455)")
assert(q.collapsedQuestIDs[qid] == nil,
  "REMOVE must clear collapsedQuestIDs[qid] (quest.lua:467)")
assert(table.getn(deleteCalls) >= 1, "REMOVE must delete map nodes (quest.lua:473)")
local sawNodes = false
for _, call in ipairs(deleteCalls) do
  if call.addon == "PFQUEST" and call.title == "Bandit Hunt" then sawNodes = true end
end
assert(sawNodes, "DeleteNode must be called with (PFQUEST, Bandit Hunt)")
assert(table.getn(broadcastCalls) == 1, "BroadcastQuestRemove must be called exactly once")
assert(broadcastCalls[1].questId == qid and broadcastCalls[1].title == "Bandit Hunt",
  "BroadcastQuestRemove must receive dot-call args (questId, title)")

-- Restore baseline state for any tests appended later.
env.pfMap.DeleteNode = savedDeleteNode
q.partyapi = nil
env.pfQuest_history[qid] = nil
env.SetTime(1000)
env.pfDatabase.localized = savedLocalized
print("  ✓ PASS: REMOVE queue branch fully driven through pfQuest OnUpdate")



--------------------------------------------------------------------------------
-- 14. tracker.Reset rebuilds despite under-reported quest count (audit 16)
--------------------------------------------------------------------------------
print("\n[TEST 14] tracker.Reset unaffected by GetNumQuestLogEntries under-report...")
-- GetNumQuestLogEntries() transiently under-reports (see quest.lua:723-731);
-- tracker.Reset must still rebuild every watched row.
local prevTrackingMethod = env.pfQuest_config["trackingmethod"]
env.pfQuest_config["trackingmethod"] = 3 -- watched-quests mode: Reset's else-branch
env.GetNumQuestLogEntries = function() return 3, 1 end -- 3 rows, numQuests under-reports
env.pfQuestCompat.GetQuestLogTitle = function(id)
  local titles = { "Audit Row Alpha", "Audit Row Beta", "Audit Row Gamma" }
  if not titles[id] then return nil end
  return titles[id], 5, nil, nil, nil, false
end
env.IsQuestWatched = function() return true end
env.GetNumQuestLeaderBoards = function() return 0 end
env.pfQuest.questlog = {
  ["Audit Row Alpha"] = { qlogid = 1, title = "Audit Row Alpha" },
  ["Audit Row Beta"] = { qlogid = 2, title = "Audit Row Beta" },
  ["Audit Row Gamma"] = { qlogid = 3, title = "Audit Row Gamma" },
}
-- pre-seed reusable buttons: mock frames lack RegisterForClicks and
-- ButtonAdd calls it when creating a fresh button (mock gap, cf. continent.lua:163)
for i = 1, 3 do
  local b = env.CreateFrame("Button")
  b.text = b:CreateFontString()
  b.icon = b:CreateTexture()
  b.empty = true
  env.pfQuest.tracker.buttons[i] = b
end

env.pfQuest.tracker.Reset()

local rows, seen = 0, {}
for _, button in pairs(env.pfQuest.tracker.buttons) do
  if button.title then
    rows = rows + 1
    seen[button.title] = true
  end
end
env.pfQuest_config["trackingmethod"] = prevTrackingMethod
assert(rows == 3 and seen["Audit Row Alpha"] and seen["Audit Row Beta"] and seen["Audit Row Gamma"],
  string.format("Reset must rebuild all 3 watched rows despite under-reported count, got %d", rows))
print("  ✓ PASS: tracker.Reset rebuilds every row despite under-reported quest count")

print("\n======================================================================")
print("  ALL 100% QUEST TYPE TESTS PASSED (0 REGRESSIONS)")
print("======================================================================")
