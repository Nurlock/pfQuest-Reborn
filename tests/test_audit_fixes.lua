-- Audit fix check: REMOVEQ with markup in the title must still purge.
-- Stored titles are sanitized, so the remove path must sanitize before compare.
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
env.pfQuest_config = { ["epochgroupsync"] = "1" }
env.pfQuest_history = {}
env.pfQuest_Loc = setmetatable({}, { __index = function(_, k) return k end })
env.pfUI = { api = { SanitizePattern = function(s) return s end, emulated = true } }
env.pfQuest = { questlog = {}, collapsedQuestIDs = {}, announcedQuests = {} }

load_file("compat/client.lua")
load_file("party.lua")
load_file("partytooltip.lua")

local epoch = env.pfQuest.partyapi
assert(epoch, "partyapi hooks must be exposed")

print("[TEST] Markup-titled REMOVEQ purges sanitized entries...")
epoch.StorePartyObjective("MarkupFriend", "Defias Bandit", 100, "|cffff0000Defias Hunt|r", "Slain: 3/10", 3, 10)
assert(epoch.partyQuestData["MarkupFriend"] ~= nil, "setup: MarkupFriend data must exist")
epoch.HandlePfqeMessage("MarkupFriend", "REMOVEQ:100:|cffff0000Defias Hunt|r")
assert(epoch.partyQuestData["MarkupFriend"] == nil, "markup REMOVEQ must purge the sanitized entry (no ghost pins)")
print("  PASS: markup REMOVEQ purges")

print("[TEST] Unnumbered/event quest objective state transitions...")
-- Simulate quest 6001 with non-numeric text
local qlog = {}
env.GetNumQuestLogEntries = function() return 1, 1 end
local questDone = false
local questComplete = nil
env.pfQuestCompat.GetQuestLogTitle = function(index)
  return "Body and Heart", 10, nil, nil, nil, questComplete
end
env.GetNumQuestLeaderBoards = function(index) return 1 end
env.GetQuestLogLeaderBoard = function(i, index)
  return "Face Lunaclaw and earn the strength of body and heart it possesses.", "event", questDone
end
env.IsQuestWatched = function(index) return false end
env.pfDatabase = env.pfDatabase or {}
env.pfDatabase.GetQuestIDs = function(self, qlogid) return { 6001 } end

load_file("quest.lua")

-- Initial scan (in-progress, not done)
env.pfQuest:UpdateQuestlog()
assert(env.pfQuest.questlog[6001] ~= nil, "Quest 6001 must be tracked")
local state1 = env.pfQuest.questlog[6001].state

-- Advance objective to done
questDone = true
questComplete = 1
env.pfQuest:UpdateQuestlog()
local state2 = env.pfQuest.questlog[6001].state

assert(state1 ~= state2, "Quest state fingerprint must change when unnumbered objective completes")
-- Check queue had RELOAD
local hasReload = false
for i = 1, (env.pfQuest.queueTail or 1) do
  local entry = env.pfQuest.queue[i]
  if entry and entry[2] == 6001 and entry[4] == "RELOAD" then
    hasReload = true
    break
  end
end
assert(hasReload, "Quest 6001 must be queued for RELOAD when unnumbered objective is finished")
print("  PASS: unnumbered objective state transitions detected")

print("[TEST] Continent view clears province pins and route lines...")
-- Mock WorldMapButton and test pins
env.WorldMapButton = env.CreateFrame("Button", "WorldMapButton")
env.WorldMapButton.GetWidth = function() return 1000 end
env.WorldMapButton.GetHeight = function() return 666 end
env.WorldMapButton.GetFrameLevel = function() return 10 end
env.WorldMapFrame = env.CreateFrame("Frame", "WorldMapFrame")
env.WorldMapFrame.IsShown = function() return true end
env.WorldMapDetailFrame = env.CreateFrame("Frame", "WorldMapDetailFrame")
env.WorldMapDetailFrame.GetScale = function() return 1 end
env.WorldMapButton.GetScale = function() return 1 end

env.pfDB = { minimap = {}, zones = { loc = {} } }
env.GetMapZones = function(c) return "Elwynn Forest", "Westfall" end
env.pfQuest = env.pfQuest or {}
env.pfQuest.tracker = { Reset = function() end }
env.pfQuest.route = { Reset = function() end }
load_file("compat/client.lua")
load_file("map.lua")

local pin1 = env.CreateFrame("Button", "pfMapPin1", env.WorldMapButton)
local pin2 = env.CreateFrame("Button", "pfMapPin2", env.WorldMapButton)
pin1:Show()
pin2:Show()
env.pfMap.pins = { pin1, pin2 }

-- Simulate UpdateNodes on continent view (GetCurrentMapZone returns 0)
env.GetCurrentMapZone = function() return 0 end
env.GetCurrentMapContinent = function() return 2 end
env.pfMap:UpdateNodes()

assert(not pin1:IsShown(), "Pin 1 must be hidden in continent view")
assert(not pin2:IsShown(), "Pin 2 must be hidden in continent view")
print("  PASS: province pins hidden when UpdateNodes runs in continent view")

-- Test zone change immediately clears pins and bypasses debounce
print("[TEST] Zone transition immediately cleans stale pins...")
local pin3 = env.CreateFrame("Button", "pfMapPin3", env.WorldMapButton)
pin1:Show()
pin2:Show()
pin3:Show()
env.pfMap.pins = { pin1, pin2, pin3 }
env.pfMap.pinCount = 3
env.pfMap.lastUpdateZone = 1 -- Elwynn Forest
env.pfMap.lastUpdateMap = "Elwynn"
env.pfMap.mapJustOpened = true -- Even if mapJustOpened was true

-- Switch to Westfall (mid=2, returns Westfall)
env.GetCurrentMapZone = function() return 2 end
env.GetMapInfo = function() return "Westfall" end
env.pfMap:FireScript("OnEvent", "WORLD_MAP_UPDATE")

assert(env.pfMap.mapJustOpened == nil, "mapJustOpened must be cleared on deliberate zone change")
assert(env.pfMap.queue_update == nil, "queue_update must be nil on deliberate zone change")
assert(not pin1:IsShown() and not pin2:IsShown() and not pin3:IsShown(), "Previous pins must be hidden immediately on zone change")
print("  PASS: deliberate zone change immediately clears pins and mapJustOpened flag")


-- Audit finding 1: an unknown class token (custom/patched client) makes
-- GetBitByClass return nil, BuildStaticRejectSet early-return an empty set,
-- and QuestFilter must not bit.band against a nil pclass.
print("[TEST] Unknown class token: GetBitByClass nil, QuestFilter must not error...")
env.UnitClass = function() return "Monk", "MONK" end
load_file("database.lua")

assert(env.pfDatabase:GetBitByClass("MONK") == nil, "unknown class token must map to nil")

env.pfDB.quests.data[70000] = { class = 1, lvl = 5, min = 1 }
env.pfDB.quests.loc[70000] = { T = "Audit Class Guard" }
env.pfDatabase:BuildStaticRejectSet()
assert(next(env.pfDatabase.staticRejectSet) == nil, "reject set stays empty while pclass is nil")

local pclass = env.pfDatabase:GetBitByClass("MONK")
local ok, res = pcall(env.pfDatabase.QuestFilter, env.pfDatabase, 70000, 10, pclass, 1)
assert(ok, "QuestFilter must not error when pclass is nil: " .. tostring(res))
assert(res == true, "class-restricted quest must pass when player class is unknown")
print("  PASS: nil pclass handled without error")

--------------------------------------------------------------------------------
-- Audit finding 22: first real coverage for pfDatabase:GetQuestIDs.
-- database.lua was loaded above, so its real GetQuestIDs replaced the {6001}
-- stub installed for the quest.lua test; this block verifies that and scopes
-- its own quest-log providers (restored at the end).
print("[TEST] GetQuestIDs: scoring loop, string-key ids, unknown-title fallback...")

local savedGetQuestIDs = env.pfDatabase.GetQuestIDs
assert(type(savedGetQuestIDs) == "function", "setup: real GetQuestIDs must exist after database.lua load")

local savedQuestLogTitle = env.pfQuestCompat.GetQuestLogTitle
local savedQuestText = env.GetQuestLogQuestText

-- Deterministic quest text. database.lua:2700 builds the cache identifier as
-- title .. ":" .. level .. ":" .. objective .. ":" .. text, with objective/text
-- coming from GetQuestLogQuestText (text first, objective second).
local qtext, qobjective = "Audit description text", "Audit objective text"
env.GetQuestLogQuestText = function() return qtext, qobjective end

local function identifier_for(title, level)
  return title .. ":" .. level .. ":" .. qobjective .. ":" .. qtext
end

env.pfQuest_questcache = {}

-- (a) Known numeric id: title present in pfDB.quests.loc + data resolves to
--     that id, and the success path caches the id list under the full-text key.
env.pfDB.quests.loc[9001] = { T = "Audit Known Quest" }
env.pfDB.quests.data[9001] = { lvl = 10, min = 1 }
env.pfDatabase:BuildNameIndex()

env.pfQuestCompat.GetQuestLogTitle = function()
  return "Audit Known Quest", 10, nil, nil
end

local res1 = env.pfDatabase:GetQuestIDs(1)
assert(type(res1) == "table" and res1[1] == 9001 and res1[2] == nil,
  "case a: known title must resolve to id 9001, got " .. tostring(res1 and res1[1]))
local cache1 = env.pfQuest_questcache[identifier_for("Audit Known Quest", 10)]
assert(type(cache1) == "table" and cache1[1] == 9001,
  "case a: pfQuest_questcache must hold the id list under the full-text identifier")
print("  PASS: known numeric id resolves and caches its id list")

-- (b) String-key id: BuildNameIndex inserts loc keys raw (database.lua:662),
--     so a string-keyed quest must flow through scoring and the cache as a
--     STRING id (the mixed number/string quest-id key hazard from AGENTS.md).
env.pfDB.quests.loc["9002"] = { T = "Audit Stringkey Quest" }
env.pfDB.quests.data["9002"] = { lvl = 10, min = 1 }
env.pfDatabase:BuildNameIndex()

env.pfQuestCompat.GetQuestLogTitle = function()
  return "Audit Stringkey Quest", 10, nil, nil
end

local res2 = env.pfDatabase:GetQuestIDs(1)
assert(type(res2) == "table" and res2[1] == "9002",
  "case b: string-keyed quest must resolve to '9002', got " .. tostring(res2 and res2[1]))
assert(type(res2[1]) == "string", "case b: id must keep its string key type")
local cache2 = env.pfQuest_questcache[identifier_for("Audit Stringkey Quest", 10)]
assert(type(cache2) == "table" and cache2[1] == "9002",
  "case b: questcache must store the string id unchanged")
print("  PASS: string-key id resolves without number coercion")

-- (c) Unknown title: levenshtein title fallback finds nothing and the function
--     returns { title }. Assert the RETURN only - deliberately no cache/marker
--     assertion, because no-match marker persistence is being changed
--     concurrently (audit finding 22 instruction).
env.pfQuestCompat.GetQuestLogTitle = function()
  return "Audit Unfindable Quest of Null Matching", 60, nil, nil
end

local res3 = env.pfDatabase:GetQuestIDs(1)
assert(type(res3) == "table" and res3[1] == "Audit Unfindable Quest of Null Matching" and res3[2] == nil,
  "case c: unknown title must fall back to { title }, got " .. tostring(res3 and res3[1]))
print("  PASS: unknown title falls back to { title }")

-- restore scoped overrides
env.pfQuestCompat.GetQuestLogTitle = savedQuestLogTitle
env.GetQuestLogQuestText = savedQuestText
assert(env.pfDatabase.GetQuestIDs == savedGetQuestIDs, "GetQuestIDs must be left untouched")
print("  PASS: GetQuestIDs audit coverage complete")
