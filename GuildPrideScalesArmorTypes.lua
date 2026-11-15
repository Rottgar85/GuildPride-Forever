-- Armor proficiency per class: { best subclass, level at which it is learned (classic) }.
-- Subclass ids: 1 Cloth, 2 Leather, 3 Mail, 4 Plate.
local ADDON, GP = ...
-- Scales läuft in GuildPride in einem eigenen Unter-Namensraum (GP.Scales)
GP.Scales = GP.Scales or {}
local ns = GP.Scales
local A = {}
ns.Armor = A

A.ARMOR_SLOTS = { INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true,
  INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_WRIST = true, INVTYPE_HAND = true }

local classArmor = {
  WARRIOR = { 4, 3 }, PALADIN = { 4, 3 }, DEATHKNIGHT = { 4, 4 },
  HUNTER = { 3, 2 }, SHAMAN = { 3, 2 }, EVOKER = { 3, 3 },
  ROGUE = { 2, 2 }, DRUID = { 2, 2 }, MONK = { 2, 2 }, DEMONHUNTER = { 2, 2 },
  PRIEST = { 1, 1 }, MAGE = { 1, 1 }, WARLOCK = { 1, 1 },
}

-- Highest armor type the player can wear right now.
function A.MaxArmor(class, level)
  local t = classArmor[class] or { 1, 1 }
  if ns.C.isRetail then return t[1] end
  -- Classic: mail/plate are learned at level 40.
  if level < 40 then return t[2] end
  return t[1]
end

-- Returns "ok", "wrong" (wearable but not your armor type) or "unusable".
function A.Check(link)
  local _, _, _, equipLoc, _, classID, subID = ns.C.GetItemInfoInstant(link)
  if classID ~= 4 or not A.ARMOR_SLOTS[equipLoc] or subID == 0 or subID > 4 then return "ok" end
  local _, class = UnitClass("player")
  local max = A.MaxArmor(class, UnitLevel("player"))
  if subID > max then return "unusable" end
  if subID < max then return "wrong" end
  return "ok"
end
