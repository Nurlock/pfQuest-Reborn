-- pfQuest Reborn: third-party addon compatibility.
-- DragonUI and the Nameplates addon draw their own quest objective nameplate
-- icons. The setup wizard calls compatibilityCheck() every time it is shown
-- (first run and manual re-runs); each helper below switches the conflicting
-- pfQuest setting off so features never double up. That is all they do:
-- afterwards the settings behave normally and the user's choice sticks for
-- the session. Add future per-addon helpers below and call them from
-- compatibilityCheck. IsAddOnLoaded is only reliable in-game (once every
-- addon has loaded), so this must run at event time, never at file top.

local function ExternalNameplatesActive()
  return IsAddOnLoaded and (IsAddOnLoaded("DragonUI") or IsAddOnLoaded("Nameplates")) and true or false
end

local function ApplyExternalNameplateCompat()
  if ExternalNameplatesActive()
    and pfQuest_config and pfQuest_config["epochnameplatesEnabled"] ~= "0" then
    pfQuest_config["epochnameplatesEnabled"] = "0"
    if DEFAULT_CHAT_FRAME then
      DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpf|cffffffffQuest:|r Nameplate icons switched off (external nameplate addon detected).")
    end
  end
end

-- Runs every compatibility helper. Called by the setup wizard (config.lua);
-- exposed for the regression suite.
pfQuestCompat.compatibilityCheck = function()
  ApplyExternalNameplateCompat()
end
