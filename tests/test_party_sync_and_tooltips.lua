-- Test Suite: Pure pfQuest-epoch Party Sync & Tooltips
-- Verifies pfqe protocol (V1 batches, REMOVEQ), PARTY-only routing, and tooltips.

local mock = require("tests.mock_wow_api")
local env = mock.create_env()
env.UnitInParty = function(u)
  return u == "PartyFriend" or u == "EpochFriend" or u == "IdFriend"
      or u == "ColonFriend" or u == "BurstFriend" or u == "WireFriend" or u == "BatchFriend" or u == "GoldFriend"
      or nil
end
env.UnitInRaid = function(u) return nil end

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
  ["epochgroupsync"] = "1",
  ["showpartytooltips"] = "1",
  ["epochShowPartyProgress"] = "1",
  ["currentquestgivers"] = "1",
  ["trackingmethod"] = 1,
}
env.pfQuest_history = {}
env.pfQuest_Loc = setmetatable({}, { __index = function(_, k) return k end })
env.pfUI = { api = { SanitizePattern = function(s) return s end, emulated = true } }
env.pfQuest = {
  questlog = {},
  collapsedQuestIDs = {},
  announcedQuests = {},
  queue = {},
  queueHead = 1,
  queueTail = 1,
  queueCount = 0,
}

load_file("compat/client.lua")
load_file("database.lua")
load_file("map.lua")
load_file("quest.lua")
load_file("announce.lua")

-- Setup mock party
env.GetNumPartyMembers = function() return 2 end
env.GetNumRaidMembers = function() return 0 end
env.UnitName = function(u)
  if u == "player" then return "LocalPlayer" end
  if u == "party1" then return "PartyFriend" end
  if u == "party2" then return "EpochFriend" end
  return "PartyFriend"
end
env.UnitClass = function(u)
  return "Warrior", "WARRIOR"
end
env.RAID_CLASS_COLORS = { WARRIOR = { r = 1, g = 0, b = 0 } }

env.GetQuestLogTitle = function(index)
  if index == 1 then return "Defias Hunt", 10, "Elite", false, false, 0 end
  return nil
end
env.pfQuestCompat = env.pfQuestCompat or {}
env.pfQuestCompat.GetQuestLogTitle = env.GetQuestLogTitle
env.GetNumQuestLogEntries = function() return 1 end
env.GetNumQuestLeaderBoards = function(index)
  if index == 1 then return 1 end
  return 0
end
env.GetQuestLogLeaderBoard = function(objIndex, qlogIndex)
  if qlogIndex == 1 and objIndex == 1 then
    return "Defias Bandit: 3/10", "monster", false
  end
  return nil
end

-- Setup dummy quest in DB
env.pfDB = env.pfDB or {}
env.pfDB.quests = env.pfDB.quests or { loc = {}, data = {} }
env.pfDB.quests.loc[100] = { T = "Defias Hunt" }
env.pfDB.quests.data[100] = {
  lvl = 10,
  min = 5,
  ["end"] = { U = { 240 } },
  ["obj"] = { U = { 116 } },
}
env.pfDB.units = env.pfDB.units or { loc = {} }
env.pfDB.units.loc[240] = "Marshal Dughan"
env.pfDB.units.loc[116] = "Defias Bandit"
env.pfDB.units.loc[241] = "Goldshire Guard"
env.pfDatabase = env.pfDatabase or {}
local searchedQuestIds = {}
env.pfDatabase.SearchQuestID = function(self, qid, meta)
  table.insert(searchedQuestIds, { qid = qid, meta = meta })
end
env.pfMap = env.pfMap or {}
env.pfMap.queue_update = nil
env.pfMap.DeleteNode = env.pfMap.DeleteNode or function(self, addon, title) end

local sentAddonMessages = {}
env.SendAddonMessage = function(pfx, text, dist, target)
  table.insert(sentAddonMessages, { prefix = pfx, text = text, dist = dist, target = target })
end

env.UnitIsPlayer = function(u) return false end

-- Load pure pfQuest-epoch tooltip and comms module
load_file("party.lua")
load_file("partytooltip.lua")

local epoch = env.pfQuest.partyapi
assert(epoch, "pfQuest.partyapi must be loaded")
epoch.HookGameTooltip()

print("[TEST] 1. Verifying inbound pfqe V1 batch message...")
epoch.ProcessQuestData("PartyFriend", "V1|U116Q100:4:10;")
local pData = epoch.partyQuestData["PartyFriend"]
assert(pData ~= nil, "PartyFriend data must exist")
assert(pData["Defias Bandit"] ~= nil, "Target 'Defias Bandit' must be mapped")
local obj = pData["Defias Bandit"][1]
assert(obj.quest == "Defias Hunt", "Quest must be 'Defias Hunt'")
assert(obj.current == 4, "Current count must be 4")
assert(obj.total == 10, "Total count must be 10")
print("  ✓ PASS: Inbound pfqe V1 batch parsed into partyQuestData")

print("[TEST] 2. Verifying GameTooltip unit hover shows party progress...")
local testTip = env.GameTooltip
testTip.lines = {}
testTip.AddLine = function(self, text, r, g, b)
  table.insert(self.lines, text)
end
testTip.GetUnit = function(self)
  return "Defias Bandit", "target"
end
testTip.Show = function(self) self.shown = true end

-- Simulate hover
testTip:FireScript("OnTooltipSetUnit")
local foundProgress = false
local cc = env.RAID_CLASS_COLORS.WARRIOR
local classEsc = string.format("|cFF%02x%02x%02x", cc.r * 255, cc.g * 255, cc.b * 255)
for _, line in ipairs(testTip.lines) do
  if string.find(line, "PartyFriend") and string.find(line, "4/10") then
    foundProgress = true
    assert(string.find(line, classEsc .. "PartyFriend", 1, true), "party line must use member class color")
  end
end
assert(foundProgress, "Tooltip must include party member and objective progress 4/10")
print("  ✓ PASS: Unit tooltip displays colored party member progress")

print("[TEST] 2b. Verifying a second hook install does not duplicate lines...")
-- epoch+Reborn migration can install both; HookScript stacks, so without
-- the once-guard every hover would render each line twice.
epoch.HookGameTooltip()
testTip.lines = {}
testTip:FireScript("OnTooltipSetUnit")
local progressLines = 0
for _, line in ipairs(testTip.lines) do
  if string.find(line, "PartyFriend") and string.find(line, "4/10") then
    progressLines = progressLines + 1
  end
end
assert(progressLines == 1, "progress line must render exactly once, got " .. progressLines)
print("  ✓ PASS: repeated hook install renders each line once")

print("[TEST] 1b. Verifying inbound V1 batch draws party map nodes...")
assert(#searchedQuestIds > 0, "Inbound V1 must trigger SearchQuestID for party map nodes")
local foundNode = false
for _, s in ipairs(searchedQuestIds) do
  if s.qid == 100 and s.meta and s.meta.addon == "PARTY" and s.meta.partyMember == "PartyFriend" then
    foundNode = true
  end
end
assert(foundNode, "SearchQuestID must be called for quest 100 with PARTY/PartyFriend meta")
print("  ✓ PASS: Inbound V1 batch wires party map node creation")

print("[TEST] 1c. Verifying pfMap tooltip wrapper does not crash on party data...")
local fakeMeta = { quest = "Defias Hunt", item = {}, partyMember = "PartyFriend" }
env.pfMap.ShowTooltip(nil, fakeMeta, env.GameTooltip)
print("  ✓ PASS: pfMap tooltip wrapper runs with party data present")

print("[TEST] 3. Verifying inbound REMOVEQ message purges quest data...")
epoch.ProcessQuestData("PartyFriend", "REMOVEQ:100:Defias Hunt")
assert(pData["Defias Bandit"] == nil, "Defias Hunt objective should be purged after REMOVEQ")
print("  ✓ PASS: Inbound REMOVEQ cleanly purges party quest data")

print("[TEST] 4. Verifying outbound pfqe V1 broadcast via ShareQuestData...")
sentAddonMessages = {}
epoch.RebuildQuestMappings()
epoch.ShareQuestData(true)

local foundOutboundV1 = false
for _, msg in ipairs(sentAddonMessages) do
  if msg.prefix == "pfqe" and string.find(msg.text, "V1|") and string.find(msg.text, "U116Q100:3:10;") then
    foundOutboundV1 = true
    assert(msg.dist == "PARTY", "Message must be sent to PARTY distribution")
  end
end
assert(foundOutboundV1, "ShareQuestData must broadcast V1 entry for U116Q100:3:10;")
print("  ✓ PASS: Outbound pfqe quest update correctly formatted and transmitted")

print("[TEST] 4b. Verifying abandon prunes our own mirror...")
assert(epoch.partyQuestData["LocalPlayer"] ~= nil, "self-echo must exist after share")
env.GetNumQuestLogEntries = function() return 0 end
epoch.eventFrame:FireScript("OnEvent", "QUEST_LOG_UPDATE")
sentAddonMessages = {}
epoch.ShareQuestData(true)
assert(epoch.partyQuestData["LocalPlayer"] == nil, "abandoned quest must leave our mirror")
local foundRemove = false
for _, msg in ipairs(sentAddonMessages) do
  if msg.prefix == "pfqe" and string.find(msg.text, "^REMOVEQ:100:Defias Hunt") then foundRemove = true end
end
assert(foundRemove, "abandon must broadcast REMOVEQ to peers")
env.GetNumQuestLogEntries = function() return 1 end
epoch.eventFrame:FireScript("OnEvent", "QUEST_LOG_UPDATE")
print("  ✓ PASS: Abandon prunes our mirror and notifies peers")

print("[TEST] 5. Verifying inbound SYNC_REQUEST is answered...")
-- A peer that reloaded mid-party pulls; we answer with a full share.
-- (Invalidate first: the mock log changed without a QUEST_LOG_UPDATE.)
epoch.InvalidateLogCache()
epoch.RebuildQuestMappings()
sentAddonMessages = {}
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "PFQUEST_SYNC_REQUEST", "1", "PARTY", "PartyFriend")
assert(#sentAddonMessages > 0, "trusted SYNC_REQUEST must trigger a full share")
print("  ✓ PASS: SYNC_REQUEST answered")

print("[TEST] 5b. Verifying login sends one pull request...")
env.GetNumRaidMembers = function() return 0 end
sentAddonMessages = {}
epoch.eventFrame:FireScript("OnEvent", "PLAYER_ENTERING_WORLD")
local reqCount, shareCount = 0, 0
for _, msg in ipairs(sentAddonMessages) do
  if msg.prefix == "PFQUEST_SYNC_REQUEST" and msg.dist == "PARTY" then reqCount = reqCount + 1 end
  if msg.prefix == "pfqe" then shareCount = shareCount + 1 end
end
assert(reqCount == 1, "login must send exactly one sync pull request, got " .. reqCount)
assert(shareCount >= 1, "login must also push our full state")
print("  ✓ PASS: Login pulls once and pushes full state")

print("[TEST] 5c. Verifying SYNC_REQUEST answers are cooled down per sender...")
-- Test 5 just answered PartyFriend, so the cooldown is hot: a repeat and
-- a self-request must stay silent, then one share after 11 seconds.
local baseline = #sentAddonMessages
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "PFQUEST_SYNC_REQUEST", "1", "PARTY", "PartyFriend")
assert(#sentAddonMessages == baseline, "repeat SYNC_REQUEST inside cooldown must not re-share")
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "PFQUEST_SYNC_REQUEST", "1", "PARTY", "LocalPlayer")
assert(#sentAddonMessages == baseline, "self SYNC_REQUEST must be ignored")
env.AdvanceTime(11)
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "PFQUEST_SYNC_REQUEST", "1", "PARTY", "PartyFriend")
assert(#sentAddonMessages > baseline, "SYNC_REQUEST after cooldown must share again")
print("  ✓ PASS: SYNC_REQUEST answered once per cooldown")

print("[TEST] 6. Verifying raid traffic stays on PARTY (flood safety)...")
env.GetNumRaidMembers = function() return 10 end
sentAddonMessages = {}
epoch.ShareQuestData(true)
local foundRaidMsg = false
for _, msg in ipairs(sentAddonMessages) do
  if msg.prefix == "pfqe" then
    assert(msg.dist == "PARTY", "no pfqe traffic may use RAID, got " .. tostring(msg.dist))
    foundRaidMsg = true
  end
end
assert(foundRaidMsg, "ShareQuestData must send on PARTY even in a raid")
print("  ✓ PASS: Raid traffic stays on PARTY (subgroup, Epoch parity)")

print("[TEST] 7. Verifying config toggles...")
env.pfQuest_config["epochgroupsync"] = "0"
assert(epoch.IsSyncEnabled() == false, "epochgroupsync=0 must disable sync")
sentAddonMessages = {}
epoch.ShareQuestData(true)
assert(#sentAddonMessages == 0, "No messages should be sent when epochgroupsync=0")

env.pfQuest_config["epochgroupsync"] = "1"
assert(epoch.IsSyncEnabled() == true, "epochgroupsync=1 must enable sync")

print("  ✓ PASS: Protocol enablement correctly governed by epochgroupsync")

print("[TEST] 8. Verifying BroadcastQuestRemove and CleanupPartyData exports...")
assert(epoch.BroadcastQuestRemove ~= nil, "BroadcastQuestRemove must be exported")
env.GetNumRaidMembers = function() return 0 end
env.GetNumPartyMembers = function() return 2 end
sentAddonMessages = {}
epoch.BroadcastQuestRemove(100, "Defias Hunt")
local foundRemove = false
for _, msg in ipairs(sentAddonMessages) do
  if msg.prefix == "pfqe" and msg.text == "REMOVEQ:100:Defias Hunt" and msg.dist == "PARTY" then
    foundRemove = true
  end
end
assert(foundRemove, "BroadcastQuestRemove must send REMOVEQ:100:Defias Hunt to PARTY")
epoch.CleanupPartyData()
print("  ✓ PASS: BroadcastQuestRemove and CleanupPartyData work")

print("[TEST] 9. Verifying colon-tolerant QUEST parsing...")
env.GetNumRaidMembers = function() return 0 end
env.GetNumPartyMembers = function() return 2 end
env.AdvanceTime(30)
epoch.ProcessQuestData("ColonFriend", "QUEST:Darkshore:Escort: The Missing Diplomat:Escort completed:3:10")
local cData = epoch.partyQuestData["ColonFriend"]
assert(cData ~= nil, "ColonFriend data must exist")
local foundColon = false
for targetKey, quests in pairs(cData) do
  for _, q in ipairs(quests) do
    if q.quest == "Escort: The Missing Diplomat" and q.current == 3 and q.total == 10 then
      foundColon = true
    end
  end
end
assert(foundColon, "QUEST with colons in quest name must parse target/quest/objective/counts")
print("  ✓ PASS: Colon-tolerant QUEST parsing works")

print("[TEST] 10. Verifying out-of-range progress is rejected...")
local beforeCount = 0
for _, quests in pairs(epoch.partyQuestData["Troll"] or {}) do
  beforeCount = beforeCount + table.getn(quests)
end
epoch.ProcessQuestData("Troll", "V1|U116Q100:10:0;")
epoch.ProcessQuestData("Troll", "V1|U116Q100:99999:10;")
local afterCount = 0
for _, quests in pairs(epoch.partyQuestData["Troll"] or {}) do
  afterCount = afterCount + table.getn(quests)
end
assert(afterCount == beforeCount, "Out-of-range entries (total=0, current>total) must be dropped")
assert(epoch.IsValidProgress(3, 10) == true, "3/10 must be valid")
assert(epoch.IsValidProgress(10, 0) == false, "total=0 must be invalid")
assert(epoch.IsValidProgress(11, 10) == false, "current>total must be invalid")
print("  ✓ PASS: Out-of-range progress rejected")

print("[TEST] 11. Verifying REMOVEQ matches on quest ID, not just title...")
epoch.ProcessQuestData("IdFriend", "V1|U116Q100:4:10;")
assert(epoch.partyQuestData["IdFriend"] ~= nil, "IdFriend data must exist")
-- inject a same-title entry with a different quest id; REMOVEQ:100 must keep it
table.insert(epoch.partyQuestData["IdFriend"]["Defias Bandit"], {
  quest = "Defias Hunt", questId = 999, objective = "Other", current = 1, total = 5,
})
epoch.ProcessQuestData("IdFriend", "REMOVEQ:100:Defias Hunt")
local remaining = epoch.partyQuestData["IdFriend"]["Defias Bandit"]
assert(remaining ~= nil and table.getn(remaining) == 1 and remaining[1].questId == 999,
  "REMOVEQ must only remove entries matching the quest ID")
print("  ✓ PASS: REMOVEQ ID-scoped removal works")

print("[TEST] 12. Verifying sent-keys-only broadcast state...")
sentAddonMessages = {}
epoch.ShareQuestData(true)
local sentOnce = #sentAddonMessages
epoch.ShareQuestData(false)
assert(#sentAddonMessages == sentOnce, "Second delta broadcast with no changes must send nothing")
print("  ✓ PASS: Broadcast state only tracks sent keys")

print("[TEST] 13. Verifying REMOVEQ arrives through the real CHAT_MSG_ADDON path...")
epoch.ProcessQuestData("WireFriend", "V1|U116Q100:4:10;")
assert(epoch.partyQuestData["WireFriend"] ~= nil, "WireFriend data must exist before removal")
env.AdvanceTime(30)
epoch.PumpSyncTimers()
epoch.HandlePfqeMessage("WireFriend", "REMOVEQ:100:Defias Hunt")
assert(epoch.partyQuestData["WireFriend"] == nil, "direct REMOVEQ must purge")
epoch.ProcessQuestData("WireFriend", "V1|U116Q100:4:10;")
env.AdvanceTime(2)
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "REMOVEQ:100:Defias Hunt", "PARTY", "WireFriend")
epoch.PumpSyncTimers()
assert(epoch.partyQuestData["WireFriend"] == nil, "trusted REMOVEQ through CHAT_MSG_ADDON must purge")
print("  ✓ PASS: REMOVEQ routed through CHAT_MSG_ADDON and purged")

print("[TEST] 13b. Verifying untrusted REMOVEQ is dropped...")
epoch.ProcessQuestData("StrangerData", "V1|U116Q100:4:10;")
assert(epoch.partyQuestData["StrangerData"] ~= nil, "setup: StrangerData must exist")
env.AdvanceTime(30)
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "REMOVEQ:100:Defias Hunt", "PARTY", "Stranger")
local stillThere = epoch.partyQuestData["StrangerData"]
local strangerTouched = epoch.partyQuestData["Stranger"]
assert(stillThere ~= nil, "untrusted REMOVEQ must not purge other senders' data")
assert(strangerTouched == nil, "untrusted sender must not create party data")
print("  ✓ PASS: Untrusted REMOVEQ dropped")

print("[TEST] 14. Verifying nil sender and self-echo are dropped...")
local function countEntries(sender)
  local n = 0
  for _, quests in pairs(epoch.partyQuestData[sender] or {}) do n = n + table.getn(quests) end
  return n
end
local beforeSelf = countEntries("LocalPlayer")
env.AdvanceTime(30)
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "V1|U116Q100:4:10;", "PARTY", nil)
assert(epoch.partyQuestData[nil] == nil, "nil sender must not create party data")
env.AdvanceTime(30)
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "V1|U116Q100:4:10;", "PARTY", "LocalPlayer")
epoch.PumpSyncTimers()
-- ShareQuestData mirrors own progress locally; the wire must add nothing new.
assert(countEntries("LocalPlayer") == beforeSelf, "self-echo must not add party data")
print("  ✓ PASS: Nil sender and self-echo dropped")

print("[TEST] 15. Verifying wrong-channel and GUILD messages are dropped...")
env.AdvanceTime(30)
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "V1|U116Q100:4:10;", "GUILD", "PartyFriend")
epoch.PumpSyncTimers()
local gcount = 0
if epoch.partyQuestData["PartyFriend"] then
  for _, quests in pairs(epoch.partyQuestData["PartyFriend"]) do gcount = gcount + table.getn(quests) end
end
-- PartyFriend already has legit data from test 1; GUILD dup must not add rows
assert(gcount <= 2, "GUILD-channel pfqe must not be ingested")
print("  ✓ PASS: Wrong-channel messages dropped")

print("[TEST] 16. Verifying throttled V1 is queued, not lost...")
-- BurstFriend is fresh: first batch lands inside the trust+throttle window.
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "V1|U116Q100:5:10;", "PARTY", "BurstFriend")
env.AdvanceTime(0.1)
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "V1|U116Q100:7:10;", "PARTY", "BurstFriend")
local function burstCurrent()
  local d = epoch.partyQuestData["BurstFriend"]
  if not d then return nil end
  for _, quests in pairs(d) do
    for _, q in ipairs(quests) do return q.current end
  end
end
assert(burstCurrent() == 5, "first batch applies immediately, second is queued")
env.AdvanceTime(2)
epoch.PumpSyncTimers()
assert(burstCurrent() == 7, "queued newest batch must flush after throttle window")
print("  ✓ PASS: Throttle queues newest batch and flushes it")

print("[TEST] 16b. Verifying multi-batch bursts all arrive in order...")
-- three back-to-back batches (e.g. a split full-sync): first applies,
-- the rest queue as a list, then flush in order via the frame ticker alone
-- (no further events fired).
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "V1|U116Q100:1:10;", "PARTY", "BatchFriend")
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "V1|U240Q100:2:10;", "PARTY", "BatchFriend")
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "V1|U241Q100:3:10;", "PARTY", "BatchFriend")
local function batchCount()
  local n = 0
  local d = epoch.partyQuestData["BatchFriend"]
  if d then for _, quests in pairs(d) do n = n + table.getn(quests) end end
  return n
end
assert(batchCount() >= 1, "first batch of burst must apply immediately")
env.AdvanceTime(2)
-- ticker only: proves the flush does not depend on another event arriving
epoch.eventFrame:FireScript("OnUpdate")
assert(batchCount() == 3, "all three queued batches must flush in order, got " .. batchCount())
print("  ✓ PASS: Multi-batch bursts flush fully via ticker")

print("[TEST] 16c. Verifying shared map carries objectives only...")
local function lastPartyMeta()
  for i = table.getn(searchedQuestIds), 1, -1 do
    if searchedQuestIds[i].meta and searchedQuestIds[i].meta.addon == "PARTY" then
      return searchedQuestIds[i].meta
    end
  end
end
-- 0/10 and 10/10: completion state must never be shared, so no
-- ender/starter logic can key off it; finished targets still blacklist.
epoch.ProcessQuestData("GoldFriend", "V1|U116Q100:0:10;")
local m0 = lastPartyMeta()
assert(m0 and m0.partyComplete == nil, "PARTY meta must not carry completion state")
assert(not m0.partyDone or not m0.partyDone["Defias Bandit"], "0/10 target must not be marked done")
env.AdvanceTime(2)
epoch.PumpSyncTimers()
epoch.ProcessQuestData("GoldFriend", "V1|U116Q100:10:10;")
local m1 = lastPartyMeta()
assert(m1 and m1.partyComplete == nil, "PARTY meta must not carry completion state")
assert(m1.partyDone and m1.partyDone["Defias Bandit"], "10/10 target must be marked done")
print("  ✓ PASS: Shared map is objectives-only")

print("[TEST] 19. Verifying periodic full re-sync while grouped...")
sentAddonMessages = {}
epoch.RebuildQuestMappings()
env.AdvanceTime(400)
epoch.PumpSyncTimers()
assert(#sentAddonMessages > 0, "idle grouped client must full-share every few minutes")
print("  ✓ PASS: Periodic full re-sync fires")

print("[TEST] 17. Verifying QUEST_LOG_UPDATE is debounced...")
sentAddonMessages = {}
env.AdvanceTime(30)
for i = 1, 5 do
  epoch.eventFrame:FireScript("OnEvent", "QUEST_LOG_UPDATE")
end
assert(#sentAddonMessages == 0, "rapid QUEST_LOG_UPDATE ticks must not broadcast synchronously")
epoch.PumpSyncTimers()
local afterDebounce = #sentAddonMessages
assert(afterDebounce >= 0, "debounced flush must run without error")
print("  ✓ PASS: QUEST_LOG_UPDATE debounced")

print("[TEST] 17b. Verifying idle time does not defeat the debounce...")
-- Flush test 17's still-pending burst (in-game the frame ticker does this
-- every frame, so pending never survives idle there).
env.AdvanceTime(2)
epoch.PumpSyncTimers()
sentAddonMessages = {}
-- One more kill moves progress 3/10 -> 4/10, so a sync share would send.
env.GetQuestLogLeaderBoard = function(objIndex, qlogIndex)
  if qlogIndex == 1 and objIndex == 1 then
    return "Defias Bandit: 4/10", "monster", false
  end
  return nil
end
sentAddonMessages = {}
env.AdvanceTime(30) -- idle: nothing pending, accumulators must stay armed
epoch.eventFrame:FireScript("OnEvent", "QUEST_LOG_UPDATE") -- single kill tick
assert(#sentAddonMessages == 0, "QUEST_LOG_UPDATE after idle must not sync-share synchronously")
env.AdvanceTime(2)
epoch.PumpSyncTimers()
assert(#sentAddonMessages > 0, "debounced share must still flush after the interval")
print("  ✓ PASS: idle time does not defeat the debounce")

print("[TEST] 17c. Verifying a failed-load rebuild does not lock out the gate...")
-- Early return while pfDB is nil must clear mappedQuestSet, even when a
-- tooltip hover populated myQuestMappings in the meantime.
local savedDB = env.pfDB
env.pfDB = nil
epoch.RebuildQuestMappings()
-- A tooltip hover populates mappings while pfDB is still missing.
epoch.myQuestMappings["Mankrik"] = { { quest = "Thebarrens", objective = "Mankrik's Wife", current = 0, total = 1 } }
-- Drop the known entry: only a fresh rebuild can bring it back with an ID.
epoch.myQuestMappings["Defias Bandit"] = nil
env.pfDB = savedDB
sentAddonMessages = {}
epoch.eventFrame:FireScript("OnEvent", "QUEST_LOG_UPDATE")
env.AdvanceTime(2.5)
epoch.PumpSyncTimers()
local bandit = epoch.myQuestMappings["Defias Bandit"]
assert(bandit and bandit[1] and bandit[1].questId == 100,
  "gate must rerun the full rebuild after a failed-load early return")
print("  ✓ PASS: failed-load rebuild does not lock out the set-change gate")

print("[TEST] 18. Verifying DeleteNodesWhere cleans every index...")
local pfMap = env.pfMap
assert(pfMap.DeleteNodesWhere ~= nil, "map must expose DeleteNodesWhere")
pfMap:AddNode({ addon = "PARTY", zone = 1, x = 0.5, y = 0.5,
  title = "Defias Hunt (WireFriend)", quest = "Defias Hunt", questid = 100 })
pfMap:AddNode({ addon = "PARTY", zone = 1, x = 0.6, y = 0.6,
  title = "Other Quest (WireFriend)", quest = "Other Quest", questid = 200 })
assert(pfMap.nodes["PARTY"] ~= nil, "setup: PARTY nodes must exist")
local dead = "Defias Hunt (WireFriend)"
local wiped = pfMap:DeleteNodesWhere("PARTY", function(title)
  return title == dead or string.sub(title, 1, string.len(dead) + 1) == dead .. "\1"
end)
assert(wiped == true, "DeleteNodesWhere must report removals")
assert(pfMap.titleIndex["PARTY"] == nil or pfMap.titleIndex["PARTY"]["Defias Hunt"] == nil,
  "title index must not keep the deleted title")
local leftover = false
for _, coords in pairs(pfMap.nodes["PARTY"][1] or {}) do
  for title in pairs(coords) do
    if title == dead or string.sub(title, 1, string.len(dead) + 1) == dead .. "\1" then leftover = true end
  end
end
assert(leftover == false, "nodes store must not keep the deleted title")
assert(pfMap:DeleteNodesWhere("PARTY", function() return false end) == false,
  "DeleteNodesWhere must report no-ops")
print("  ✓ PASS: DeleteNodesWhere removes title + indexes")

print("[TEST] 20. Two objectives on the same quest+target stay separate rows...")
-- V1 carries counts only: two log objectives with distinct totals make the
-- receiver resolve two different objective texts for one quest+target pair.
local savedNumBoards, savedBoard = env.GetNumQuestLeaderBoards, env.GetQuestLogLeaderBoard
env.GetNumQuestLeaderBoards = function(index)
  if index == 1 then return 2 end
  return 0
end
env.GetQuestLogLeaderBoard = function(objIndex, qlogIndex)
  if qlogIndex == 1 and objIndex == 1 then return "Defias Bandit: 4/10", "monster", false end
  if qlogIndex == 1 and objIndex == 2 then return "Collect Defias Silk: 2/5", "item", false end
  return nil
end
epoch.InvalidateLogCache()
epoch.ProcessQuestData("PartyFriend", "V1|U116Q100:4:10;U116Q100:2:5;")
local dualRows = epoch.partyQuestData["PartyFriend"]["Defias Bandit"]
assert(dualRows and table.getn(dualRows) == 2,
  "kill+drop on one NPC must keep two rows, got " .. tostring(dualRows and table.getn(dualRows)))
assert(dualRows[1].objective == "Defias Bandit" and dualRows[1].current == 4 and dualRows[1].total == 10,
  "row 1 must stay the kill objective 4/10")
assert(dualRows[2].objective == "Collect Defias Silk" and dualRows[2].current == 2 and dualRows[2].total == 5,
  "row 2 must be the drop objective 2/5")
-- Restore the shared log mock so later tests see the baseline objective set.
env.GetNumQuestLeaderBoards, env.GetQuestLogLeaderBoard = savedNumBoards, savedBoard
epoch.InvalidateLogCache()
print("  ✓ PASS: kill and drop objectives on one NPC stay two rows")

print("[TEST] 21. REMOVEQ matches by id across locales; title only for legacy rows...")
-- Row title came from the receiver's own DB; the wire title is the sender's locale.
epoch.ProcessQuestData("LocaleFriend", "V1|U116Q100:4:10;")
assert(epoch.partyQuestData["LocaleFriend"] ~= nil, "setup: LocaleFriend data must exist")
epoch.ProcessQuestData("LocaleFriend", "REMOVEQ:100:Chasse aux Défias")
assert(epoch.partyQuestData["LocaleFriend"] == nil,
  "row with questId=100 must be removed even when the wire title differs (mixed locale)")
-- Legacy rows without questId still rely on title matching.
epoch.partyQuestData["LegacyFriend"] = { ["Defias Bandit"] = { {
  quest = "Defias Hunt", objective = "Other", current = 1, total = 5,
} } }
epoch.ProcessQuestData("LegacyFriend", "REMOVEQ:100:Defias Hunt")
assert(epoch.partyQuestData["LegacyFriend"] == nil,
  "legacy id-less row must be removed by title")
print("  ✓ PASS: REMOVEQ cross-locale id match + legacy title match")

print("[TEST] 22. Inbound flush caps total batches per tick...")
-- Drain any leftovers and re-arm the flush accumulator from a known state.
env.AdvanceTime(2)
epoch.eventFrame:FireScript("OnUpdate")

env.pfDB.units.loc[250] = "FlushTarget Alpha"
env.pfDB.units.loc[251] = "FlushTarget Beta"
for i = 101, 108 do env.pfDB.quests.loc[i] = { T = "FlushQuest " .. i } end

-- Head batch per sender applies on arrival (opens its throttle); the rest
-- queue: 3 + 3 = 6 batches > the 4-per-tick flush budget.
local flushBurst = {
  { "BatchFriend", "V1|U250Q101:1:5;" },
  { "GoldFriend",  "V1|U251Q105:1:5;" },
  { "BatchFriend", "V1|U250Q102:1:5;" },
  { "BatchFriend", "V1|U250Q103:1:5;" },
  { "BatchFriend", "V1|U250Q104:1:5;" },
  { "GoldFriend",  "V1|U251Q106:1:5;" },
  { "GoldFriend",  "V1|U251Q107:1:5;" },
  { "GoldFriend",  "V1|U251Q108:1:5;" },
}
for _, m in ipairs(flushBurst) do
  epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", m[2], "PARTY", m[1])
end

-- One row per processed batch (distinct quest per batch, dedup keys on
-- quest+objective, so processed batches are countable).
local function flushRows()
  local n = 0
  for _, sender in ipairs({ "BatchFriend", "GoldFriend" }) do
    for _, list in pairs(epoch.partyQuestData[sender] or {}) do
      for _, row in ipairs(list) do
        if string.find(row.quest or "", "^FlushQuest") then n = n + 1 end
      end
    end
  end
  return n
end

assert(flushRows() == 2, "burst heads must apply immediately, got " .. flushRows())
env.AdvanceTime(2)
epoch.eventFrame:FireScript("OnUpdate")
assert(flushRows() == 6,
  "one flush tick must process exactly the 4-batch budget, got " .. (flushRows() - 2))
env.AdvanceTime(2)
epoch.eventFrame:FireScript("OnUpdate")
assert(flushRows() == 8,
  "queued remainder must flush on the next tick, got " .. (flushRows() - 2))
print("  ✓ PASS: flush processes at most 4 batches/tick, remainder stays queued")

print("[TEST] 23. SYNC_REQUEST answers are globally rate-limited ~1/sec...")
-- Zone-in stampede: every peer asks at once; the first answer shares to
-- the whole party channel, so the rest must be suppressed for ~1s.
env.AdvanceTime(30) -- clear per-sender cooldowns and the global answer window
epoch.RebuildQuestMappings()
sentAddonMessages = {}
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "PFQUEST_SYNC_REQUEST", "1", "PARTY", "PartyFriend")
assert(#sentAddonMessages > 0, "fresh SYNC_REQUEST must be answered")
local afterAnswer = #sentAddonMessages
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "PFQUEST_SYNC_REQUEST", "1", "PARTY", "EpochFriend")
assert(#sentAddonMessages == afterAnswer,
  "second answer inside the 1s window must be suppressed")
env.AdvanceTime(11) -- past both the per-sender cooldown and the global window
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "PFQUEST_SYNC_REQUEST", "1", "PARTY", "PartyFriend")
assert(#sentAddonMessages > afterAnswer, "answer must resume once the window passes")
print("  ✓ PASS: SYNC_REQUEST answers capped globally at ~1/sec")

print("[TEST] 24. Verifying raid-group inbound trust via UnitInRaid (audit finding 19)...")
-- Baseline stubs (UnitInRaid -> nil at line 11, GetNumRaidMembers -> 0 at
-- line 56, reset pattern in test 8 at line 287) never let the raid branch
-- at party.lua:1190-1192 run. Temporarily put the suite in a 10-member raid.
local savedRaidMembers, savedUnitInRaid = env.GetNumRaidMembers, env.UnitInRaid
env.GetNumRaidMembers = function() return 10 end
env.UnitInRaid = function(unit)
  if unit == "RaidFriend" then return 7 end
  return nil -- "Stranger" is not on the roster
end

-- party.lua:1189 gates on channel "PARTY" (the addon always sends PARTY,
-- pinned by test 6), so a literal "RAID" channel is dropped before the raid
-- branch can even run.
env.AdvanceTime(2)
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "V1|U116Q100:4:10;", "RAID", "RaidFriend")
assert(epoch.partyQuestData["RaidFriend"] == nil,
  "literal RAID channel must be dropped at the party.lua:1189 channel gate")

-- In-raid sender present in the roster: raid branch must trust and ingest.
env.AdvanceTime(2)
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "V1|U116Q100:4:10;", "PARTY", "RaidFriend")
local raidData = epoch.partyQuestData["RaidFriend"]
assert(raidData ~= nil and raidData["Defias Bandit"] ~= nil,
  "UnitInRaid(sender) ~= nil in a raid must be trusted and ingested")
assert(raidData["Defias Bandit"][1].current == 4,
  "raid-group row must carry the shared 4/10 progress")

-- Same raid, same channel, but UnitInRaid(sender) == nil: batch must drop.
env.AdvanceTime(2)
epoch.eventFrame:FireScript("OnEvent", "CHAT_MSG_ADDON", "pfqe", "V1|U116Q100:4:10;", "PARTY", "Stranger")
assert(epoch.partyQuestData["Stranger"] == nil,
  "UnitInRaid(sender) == nil must drop the batch (raid branch false)")

-- Restore baseline stubs (same pattern as the test 8 reset).
env.GetNumRaidMembers, env.UnitInRaid = savedRaidMembers, savedUnitInRaid
print("  ✓ PASS: raid-group trust decided by UnitInRaid")

print("[TEST] 25. CleanupPartyData age-prunes per-sender throttle stamps...")
-- Seed stale stamps in both dicts, then age past the 300s prune window.
-- A sender stamped after the jump must survive; stale entries must drop.
epoch.lastInboundBySender["StaleIn"] = env.GetTime()
epoch.lastSyncRequestBySender["StaleSync"] = env.GetTime()
env.AdvanceTime(301)
assert(epoch.InboundAllowed("FreshIn") == true, "fresh sender must pass the inbound throttle")
assert(epoch.lastInboundBySender["FreshIn"] ~= nil, "fresh sender must be stamped")
epoch.CleanupPartyData()
assert(epoch.lastInboundBySender["StaleIn"] == nil, "stale inbound stamp must be pruned")
assert(epoch.lastSyncRequestBySender["StaleSync"] == nil, "stale sync-request stamp must be pruned")
assert(epoch.lastInboundBySender["FreshIn"] ~= nil, "fresh inbound stamp must survive the prune")
print("  ✓ PASS: CleanupPartyData age-prunes stale per-sender throttle stamps")

print("\ntest_party_sync_and_tooltips PASSED successfully!")
