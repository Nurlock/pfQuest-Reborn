-- i18n.lua: numeric-array locale runtime. Data tables (pfQuest_I18N_*) are
-- set by the generated i18n_data.lua; this file only does lookups.
local str_format = string.format
local tostring = tostring
local select = select
local base_locale = nil
local active_locale = nil
local id_by_string = nil
pfQuest_i18n = {}
function pfQuest_i18n.init(default_tbl, reverse_map)
  base_locale = default_tbl
  active_locale = default_tbl
  id_by_string = reverse_map
end
function pfQuest_i18n.set_locale(locale_tbl)
  active_locale = locale_tbl or base_locale
end
function pfQuest_i18n.t(id, ...)
  local text = active_locale and active_locale[id]
  if not text then
    text = base_locale and base_locale[id]
  end
  if not text then
    return "[MISSING: " .. tostring(id) .. "]"
  end
  if select("#", ...) == 0 then
    return text
  end
  return str_format(text, ...)
end
function pfQuest_i18n.ApplyLanguage()
  if not base_locale then return end
  local active = base_locale
  if GetLocale then
    local loc = GetLocale()
    if loc == "ptBR" and pfQuest_I18N_ptBR then active = pfQuest_I18N_ptBR
    elseif loc == "frFR" and pfQuest_I18N_frFR then active = pfQuest_I18N_frFR
    elseif loc == "deDE" and pfQuest_I18N_deDE then active = pfQuest_I18N_deDE
    elseif loc == "zhCN" and pfQuest_I18N_zhCN then active = pfQuest_I18N_zhCN
    elseif loc == "zhTW" and pfQuest_I18N_zhTW then active = pfQuest_I18N_zhTW
    elseif loc == "esES" and pfQuest_I18N_esES then active = pfQuest_I18N_esES
    elseif loc == "ruRU" and pfQuest_I18N_ruRU then active = pfQuest_I18N_ruRU
    end
  end
  local override = pfQuest_config and pfQuest_config.language
  if override and override ~= "" and override ~= "auto" then
    local all = { en = pfQuest_I18N_en, ptBR = pfQuest_I18N_ptBR,
      frFR = pfQuest_I18N_frFR, deDE = pfQuest_I18N_deDE, zhCN = pfQuest_I18N_zhCN,
      zhTW = pfQuest_I18N_zhTW, esES = pfQuest_I18N_esES, ruRU = pfQuest_I18N_ruRU }
    if all[override] then active = all[override] end
  end
  pfQuest_i18n.set_locale(active)
  if pfQuest_Loc then
    for k in pairs(pfQuest_Loc) do pfQuest_Loc[k] = nil end
  end
end
if pfQuest_I18N_en and pfQuest_I18N_STR2ID then
  pfQuest_i18n.init(pfQuest_I18N_en, pfQuest_I18N_STR2ID)
  pfQuest_i18n.ApplyLanguage()
end
pfQuest_Loc = setmetatable({}, {
  __index = function(tab, key)
    local id = id_by_string and id_by_string[key]
    local value
    if id then
      value = pfQuest_i18n.t(id)
    else
      value = tostring(key)
    end
    rawset(tab, key, value)
    return value
  end,
})
