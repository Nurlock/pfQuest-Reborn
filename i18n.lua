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
