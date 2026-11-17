-- All specs of the player's class with name, icon and weights, for the spec bar and the Pawn-style tooltip lines.
local ADDON, GP = ...
-- Scales läuft in GuildPride in einem eigenen Unter-Namensraum (GP.Scales)
GP.Scales = GP.Scales or {}
local ns = GP.Scales
local C, L = ns.C, ns.L
local Sp = {}
ns.Specs = Sp

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
-- Classic talent tree icons in tree order, used when the client gives no tree icon (WoW Forever).
local I = "Interface\\Icons\\"
local TREE_ICONS = {
  WARRIOR = { I .. "Ability_Rogue_Eviscerate", I .. "Ability_Warrior_InnerRage", I .. "INV_Shield_06" },
  PALADIN = { I .. "Spell_Holy_HolyBolt", I .. "Spell_Holy_DevotionAura", I .. "Spell_Holy_AuraOfLight" },
  HUNTER  = { I .. "Ability_Hunter_BeastTaming", I .. "Ability_Marksmanship", I .. "Ability_Hunter_SwiftStrike" },
  ROGUE   = { I .. "Ability_Rogue_Eviscerate", I .. "Ability_BackStab", I .. "Ability_Stealth" },
  PRIEST  = { I .. "Spell_Holy_WordFortitude", I .. "Spell_Holy_HolyBolt", I .. "Spell_Shadow_ShadowWordPain" },
  SHAMAN  = { I .. "Spell_Nature_Lightning", I .. "Spell_Nature_LightningShield", I .. "Spell_Nature_MagicImmunity" },
  MAGE    = { I .. "Spell_Holy_MagicalSentry", I .. "Spell_Fire_FireBolt02", I .. "Spell_Frost_FrostBolt02" },
  WARLOCK = { I .. "Spell_Shadow_DeathCoil", I .. "Spell_Shadow_Metamorphosis", I .. "Spell_Shadow_RainOfFire" },
  DRUID   = { I .. "Spell_Nature_StarFall", I .. "Ability_Racial_BearForm", I .. "Spell_Nature_HealingTouch" },
}
-- Role icons by weight key, last fallback (classes/specs without a tree icon above).
local ROLE_ICONS = {
  INT_HEAL = "Interface\\Icons\\Spell_Holy_FlashHeal",
  STR_TANK = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
  AGI_TANK = "Interface\\Icons\\Ability_Racial_BearForm",
  STR_DPS  = "Interface\\Icons\\Ability_MeleeDamage",
  AGI_DPS  = "Interface\\Icons\\Ability_Rogue_Eviscerate",
  INT_DPS  = "Interface\\Icons\\Spell_Fire_FireBolt02",
}
local cache

-- Name and icon of spec/talent tree i on every client.
local function Info(i)
  if GetSpecializationInfo then
    local _, name, _, icon = GetSpecializationInfo(i)
    if name then return name, icon end
  end
  if GetTalentTabInfo then
    local r = { GetTalentTabInfo(i) }
    -- Era: (name, icon, pointsSpent, ...); newer classics: (id, name, description, icon, pointsSpent, ...)
    if type(r[1]) == "number" then return r[2], r[4] end
    if r[1] then return r[1], r[2] end
  end
end

-- Number of specs the class has in Scales's tables.
function Sp.Count()
  local _, class = UnitClass("player")
  return #(ns.Weights.specMap[class] or {})
end

-- The manual override from /scales spec only counts if that spec exists.
function Sp.ActiveIndex()
  local o = ScalesCharDB and ScalesCharDB.specOverride
  if o and o >= 1 and o <= Sp.Count() then return o end
  return C.GetSpecIndex()
end

-- { { index, key, weights, name, icon, active }, ... }
function Sp.List()
  if cache then return cache end
  local _, class = UnitClass("player")
  local list = ns.Weights.specMap[class] or {}
  local active = Sp.ActiveIndex()
  cache = {}
  for i = 1, #list do
    local weights, key = ns.Weights.Get(class, i)
    local name, icon = Info(i)
    if icon == 0 or icon == "" then icon = nil end
    if name == "" then name = nil end
    cache[i] = { index = i, key = key, weights = weights, name = name or L["ARCH_" .. key],
      icon = icon or (not C.isRetail and #list == 3 and TREE_ICONS[class] and TREE_ICONS[class][i])
        or ROLE_ICONS[key] or FALLBACK_ICON,
      active = i == active }
  end
  return cache
end

function Sp.Invalidate() cache = nil end

-- Specs ticked for the tooltip (per character, default: all).
function Sp.InTooltip(i)
  local t = ScalesCharDB and ScalesCharDB.tooltipSpecs
  return not t or t[i] ~= false
end

function Sp.SetInTooltip(i, on)
  ScalesCharDB.tooltipSpecs = ScalesCharDB.tooltipSpecs or {}
  ScalesCharDB.tooltipSpecs[i] = on and true or false
end
