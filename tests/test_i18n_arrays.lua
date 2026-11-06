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
env.GetLocale = function() return "frFR" end
load_file("i18n.lua")
local i18n = env.pfQuest_i18n
assert(i18n, "i18n.lua must set global pfQuest_i18n")
i18n.init({ [1] = "Hello", [2] = "v%s" }, { ["Hello"] = 1, ["v%s"] = 2 })
i18n.set_locale({ [1] = "Bonjour", [2] = false })
print("[TEST] numeric lookup...")
assert(i18n.t(1) == "Bonjour", "active locale hit")
print("  PASS: active hit")
print("[TEST] false-slot fallback to base...")
assert(i18n.t(2, "1.0") == "v1.0", "false must fall back to base and format")
print("  PASS: fallback + format")
print("[TEST] unknown id...")
assert(i18n.t(9999) == "[MISSING: 9999]", "unknown id must return marker")
print("  PASS: missing marker")
print("[TEST] pfQuest_Loc string shim...")
assert(env.pfQuest_Loc ~= nil, "compat global pfQuest_Loc must exist")
assert(env.pfQuest_Loc["Hello"] == "Bonjour", "string key must resolve via id map")
assert(env.pfQuest_Loc["v%s"] == "v1.0" or env.pfQuest_Loc["v%s"] == "v%s", "unmapped key must echo itself")
print("  PASS: shim")
print("[TEST] full generated data loads under 5.1...")
for _, lang in ipairs({ "en", "ptBR", "koKR", "frFR", "deDE", "zhCN", "zhTW", "esES", "ruRU" }) do
  load_file("locales/" .. lang .. ".lua")
end
assert(env.pfQuest_I18N_ENUM ~= nil, "generated enum missing")
local n = 0
for _ in pairs(env.pfQuest_I18N_en) do n = n + 1 end
assert(n == 195, "expected 195 keys, got " .. n)
for id, txt in pairs(env.pfQuest_I18N_en) do
  for _, lang in ipairs({ "ptBR", "koKR", "frFR", "deDE", "zhCN", "zhTW", "esES", "ruRU" }) do
    local t = env["pfQuest_I18N_" .. lang]
    assert(t ~= nil, "locale table missing: " .. lang)
    assert(t[id] ~= nil, lang .. " has nil hole at id " .. id .. " (must be false)")
  end
end
print("  PASS: dense arrays, no holes")
print("[TEST] legacy string keys resolve...")
load_file("i18n.lua")
env.pfQuest_i18n.init(env.pfQuest_I18N_en, env.pfQuest_I18N_STR2ID)
env.pfQuest_i18n.set_locale(env.pfQuest_I18N_frFR)
local close_id = env.pfQuest_I18N_STR2ID["Close"]
assert(close_id ~= nil, "Close must have an id")
local close_expected = env.pfQuest_I18N_frFR[close_id] or env.pfQuest_I18N_en[close_id]
assert(env.pfQuest_Loc["Close"] == close_expected, "fr Close must match (or fall back to en)")
print("  PASS: legacy keys resolve")
print("[TEST] tracker uses numeric ids...")
local src = io.open("tracker.lua", "r"):read("*a")
assert(src:find("pfQuest_i18n.t(pfQuest_I18N_ENUM", 1, true) ~= nil, "tracker must call i18n.t with enum ids")
print("  PASS: numeric call sites present")
print("[TEST] language override...")
env.pfQuest_config = { language = "esES" }
load_file("i18n.lua")
local es_expected = env.pfQuest_I18N_esES[close_id] or env.pfQuest_I18N_en[close_id]
assert(env.pfQuest_Loc["Close"] == es_expected, "es override must apply")
print("  PASS: override applies")
print("[TEST] invalid override falls back...")
env.pfQuest_config = { language = "xx" }
load_file("i18n.lua")
assert(env.pfQuest_Loc["Close"] == close_expected, "invalid override must fall back to client locale")
print("  PASS: invalid falls back")
print("ALL I18N TESTS PASSED")
