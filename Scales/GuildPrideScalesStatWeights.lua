-- Default stat weights per archetype. Values are "points per 1 stat", primary stat = 1.0.
-- They are starting points; users can override them in ScalesDB.customWeights.
local ADDON, GP = ...
-- Scales läuft in GuildPride in einem eigenen Unter-Namensraum (GP.Scales)
GP.Scales = GP.Scales or {}
local ns = GP.Scales
local C = ns.C

local W = {}
ns.Weights = W

W.archetypes = {
  STR_DPS  = { role = "DAMAGER", primary = "STR", STR = 1.00, CRIT = .42, HASTE = .45, MASTERY = .40, VERS = .38, HIT = .60, EXP = .50, AP = .45, WDPS = 3.0, STA = .02, ARMOR = 0 },
  AGI_DPS  = { role = "DAMAGER", primary = "AGI", AGI = 1.00, CRIT = .44, HASTE = .42, MASTERY = .40, VERS = .38, HIT = .60, EXP = .45, AP = .45, WDPS = 2.0, STA = .02, ARMOR = 0 },
  INT_DPS  = { role = "DAMAGER", primary = "INT", INT = 1.00, CRIT = .43, HASTE = .46, MASTERY = .40, VERS = .38, HIT = .70, SP = .85, SPI = .05, STA = .02, ARMOR = 0 },
  INT_HEAL = { role = "HEALER",  primary = "INT", INT = 1.00, CRIT = .38, HASTE = .44, MASTERY = .40, VERS = .36, SP = .90, SPI = .45, MP5 = .80, STA = .03, ARMOR = 0 },
  STR_TANK = { role = "TANK",    primary = "STR", STR = .80, STA = 1.00, ARMOR = .10, DODGE = .55, PARRY = .55, BLOCK = .40, DEF = .70, HASTE = .45, MASTERY = .50, VERS = .55, CRIT = .25, HIT = .35, EXP = .45, WDPS = 1.0 },
  AGI_TANK = { role = "TANK",    primary = "AGI", AGI = .90, STA = 1.00, ARMOR = .12, DODGE = .60, DEF = .70, HASTE = .40, MASTERY = .45, VERS = .55, CRIT = .25, HIT = .35, EXP = .45, AP = .20 },
}

-- Retail spec order.
local retail = {
  WARRIOR = { "STR_DPS", "STR_DPS", "STR_TANK" },
  PALADIN = { "INT_HEAL", "STR_TANK", "STR_DPS" },
  HUNTER  = { "AGI_DPS", "AGI_DPS", "AGI_DPS" },
  ROGUE   = { "AGI_DPS", "AGI_DPS", "AGI_DPS" },
  PRIEST  = { "INT_HEAL", "INT_HEAL", "INT_DPS" },
  DEATHKNIGHT = { "STR_TANK", "STR_DPS", "STR_DPS" },
  SHAMAN  = { "INT_DPS", "AGI_DPS", "INT_HEAL" },
  MAGE    = { "INT_DPS", "INT_DPS", "INT_DPS" },
  WARLOCK = { "INT_DPS", "INT_DPS", "INT_DPS" },
  MONK    = { "AGI_TANK", "INT_HEAL", "AGI_DPS" },
  DRUID   = { "INT_DPS", "AGI_DPS", "AGI_TANK", "INT_HEAL" },
  DEMONHUNTER = { "AGI_DPS", "AGI_TANK", "INT_DPS" },
  EVOKER  = { "INT_DPS", "INT_HEAL", "INT_DPS" },
}
-- Classic talent tree order (Era / Cata / Mists differ only where noted).
local classic = {
  WARRIOR = { "STR_DPS", "STR_DPS", "STR_TANK" },
  PALADIN = { "INT_HEAL", "STR_TANK", "STR_DPS" },
  HUNTER  = { "AGI_DPS", "AGI_DPS", "AGI_DPS" },
  ROGUE   = { "AGI_DPS", "AGI_DPS", "AGI_DPS" },
  PRIEST  = { "INT_HEAL", "INT_HEAL", "INT_DPS" },
  DEATHKNIGHT = { "STR_TANK", "STR_DPS", "STR_DPS" },
  SHAMAN  = { "INT_DPS", "AGI_DPS", "INT_HEAL" },
  MAGE    = { "INT_DPS", "INT_DPS", "INT_DPS" },
  WARLOCK = { "INT_DPS", "INT_DPS", "INT_DPS" },
  MONK    = { "AGI_TANK", "INT_HEAL", "AGI_DPS" },
  -- Mists has 4 druid specs; Forever has GetSpecialization (Midnight client) but only 3 classic trees.
  DRUID   = (GetSpecialization and not C.isForever and { "INT_DPS", "AGI_DPS", "AGI_TANK", "INT_HEAL" }) or { "INT_DPS", "AGI_DPS", "INT_HEAL" },
}
W.specMap = C.isRetail and retail or classic

function W.GetArchetypeKey(class, specIndex)
  local list = W.specMap[class] or {}
  return list[specIndex] or list[1] or "STR_DPS"
end

function W.Get(class, specIndex)
  local key = W.GetArchetypeKey(class, specIndex)
  local custom = ScalesDB and ScalesDB.customWeights and ScalesDB.customWeights[class .. specIndex]
  return custom or W.archetypes[key], key
end
