local ADDON, GP = ...
-- Scales läuft in GuildPride in einem eigenen Unter-Namensraum (GP.Scales)
GP.Scales = GP.Scales or {}
local ns = GP.Scales
local C = ns.C
local S = {}
ns.Stats = S

-- Blizzard stat keys -> internal short keys
S.keyMap = {
  ITEM_MOD_STRENGTH_SHORT = "STR", ITEM_MOD_AGILITY_SHORT = "AGI", ITEM_MOD_INTELLECT_SHORT = "INT",
  ITEM_MOD_STAMINA_SHORT = "STA", ITEM_MOD_SPIRIT_SHORT = "SPI",
  ITEM_MOD_CRIT_RATING_SHORT = "CRIT", ITEM_MOD_CRIT_SPELL_RATING_SHORT = "CRIT", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "CRIT",
  ITEM_MOD_HASTE_RATING_SHORT = "HASTE", ITEM_MOD_MASTERY_RATING_SHORT = "MASTERY",
  ITEM_MOD_VERSATILITY = "VERS", ITEM_MOD_CR_VERSATILITY_SHORT = "VERS",
  ITEM_MOD_HIT_RATING_SHORT = "HIT", ITEM_MOD_HIT_SPELL_RATING_SHORT = "HIT", ITEM_MOD_HIT_MELEE_RATING_SHORT = "HIT",
  ITEM_MOD_EXPERTISE_RATING_SHORT = "EXP",
  ITEM_MOD_ATTACK_POWER_SHORT = "AP", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "AP",
  ITEM_MOD_SPELL_POWER_SHORT = "SP", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SP", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "SP",
  ITEM_MOD_POWER_REGEN0_SHORT = "MP5", ITEM_MOD_MANA_REGENERATION_SHORT = "MP5",
  ITEM_MOD_DODGE_RATING_SHORT = "DODGE", ITEM_MOD_PARRY_RATING_SHORT = "PARRY", ITEM_MOD_BLOCK_RATING_SHORT = "BLOCK",
  ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "DEF",
  RESISTANCE0_NAME = "ARMOR", ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "WDPS",
}

local cache = {}
function S.GetItemStats(link)
  if not link then return nil end
  if cache[link] then return cache[link] end
  local raw = C.GetItemStats(link)
  if not raw then return nil end
  local out = {}
  for k, v in pairs(raw) do
    local key = S.keyMap[k]
    if key then out[key] = (out[key] or 0) + v end
  end
  cache[link] = out
  return out
end

function S.Score(stats, weights)
  if not stats then return 0 end
  local sum = 0
  for k, v in pairs(stats) do
    local w = weights[k]
    if type(w) == "number" then sum = sum + v * w end
  end
  return sum
end

-- Snapshot of the live character sheet, used by the simulator.
-- Every value goes through C.Num, so secret values (Midnight/Forever, in combat) become 0 instead of erroring.
function S.GetCharacterStats()
  local N = C.Num
  local c = {}
  -- Extra parentheses keep only the first return value; otherwise the next one would become N's fallback.
  c.STR = N((select(2, UnitStat("player", 1))))
  c.AGI = N((select(2, UnitStat("player", 2))))
  c.STA = N((select(2, UnitStat("player", 3))))
  c.INT = N((select(2, UnitStat("player", 4))))
  local base, pos, neg = UnitAttackPower("player")
  c.AP = N(base) + N(pos) + N(neg)
  c.SP = N(GetSpellBonusDamage and GetSpellBonusDamage(3))
  c.HEALPOWER = N(GetSpellBonusHealing and GetSpellBonusHealing(), c.SP)
  c.CRIT = math.max(N(GetCritChance and GetCritChance()), N(GetSpellCritChance and GetSpellCritChance(3)))
  c.HASTE = N(GetHaste and GetHaste())
  c.MASTERY = N(GetMasteryEffect and GetMasteryEffect())
  c.VERS = N(GetCombatRatingBonus and CR_VERSATILITY_DAMAGE_DONE and GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE))
         + N(GetVersatilityBonus and CR_VERSATILITY_DAMAGE_DONE and GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE))
  c.DODGE = N(GetDodgeChance and GetDodgeChance())
  c.PARRY = N(GetParryChance and GetParryChance())
  c.BLOCK = N(GetBlockChance and GetBlockChance())
  c.ARMOR = N((select(2, UnitArmor("player"))))
  c.HP = N(UnitHealthMax("player"), 1)
  c.LEVEL = N(UnitLevel("player"), 1)
  local mh = N((UnitAttackSpeed("player")))
  local minD, maxD = UnitDamage("player")
  minD, maxD = N(minD), N(maxD)
  c.WDPS = mh > 0 and ((minD + maxD) / 2 / mh) or 0
  return c
end
