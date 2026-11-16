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

-- Waffen, Schilde und Relikte pro Klasse (Classic-Lehrer, gilt auch für Forever).
-- Waffen-Unterklassen: 0/1 Axt 1H/2H, 2 Bogen, 3 Gewehr, 4/5 Streitkolben 1H/2H, 6 Stangenwaffe,
-- 7/8 Schwert 1H/2H, 10 Stab, 13 Faust, 15 Dolch, 16 Wurfwaffe, 18 Armbrust, 19 Zauberstab.
-- Relikte: 7 Buchband, 8 Götze, 9 Totem. dualWield = Stufe, ab der Beidhändigkeit gelernt wird.
local function set(...)
  local t = {}
  for i = 1, select("#", ...) do t[select(i, ...)] = true end
  return t
end
A.PROF = {
  WARRIOR = { shield = true, dualWield = 20, weapons = set(0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 13, 15, 16, 18) },
  PALADIN = { shield = true, relic = 7, weapons = set(0, 1, 4, 5, 6, 7, 8) },
  HUNTER  = { dualWield = 20, weapons = set(0, 1, 2, 3, 6, 7, 8, 10, 13, 15, 16, 18) },
  ROGUE   = { dualWield = 10, weapons = set(2, 3, 4, 7, 13, 15, 16, 18) },
  PRIEST  = { weapons = set(4, 10, 15, 19) },
  SHAMAN  = { shield = true, relic = 9, weapons = set(0, 1, 4, 5, 10, 13, 15) },
  MAGE    = { weapons = set(7, 10, 15, 19) },
  WARLOCK = { weapons = set(7, 10, 15, 19) },
  DRUID   = { relic = 8, weapons = set(4, 5, 10, 13, 15) },
}

-- Kann der Charakter zwei Waffen tragen? (Stufe laut Tabelle oder Zauber 674 bekannt)
function A.CanDualWield()
  local _, class = UnitClass("player")
  local p = A.PROF[class]
  if p and p.dualWield and UnitLevel("player") >= p.dualWield then return true end
  if IsSpellKnown and IsSpellKnown(674) then return true end
  if ns.C.isRetail and not ns.C.isForever then
    return class == "ROGUE" or class == "DEATHKNIGHT" or class == "MONK" or class == "DEMONHUNTER"
      or class == "WARRIOR" or class == "SHAMAN" or class == "HUNTER"
  end
  return false
end

-- Waffen/Schild/Relikt: false, wenn die Klasse es nie benutzen kann.
local function GearUsable(class, equipLoc, classID, subID)
  local p = not (ns.C.isRetail and not ns.C.isForever) and A.PROF[class]
  if classID == 2 then
    if subID == 20 or subID == 14 then return false end -- Angelruten, Berufswerkzeug
    if p and not p.weapons[subID] then return false end
    if equipLoc == "INVTYPE_WEAPONOFFHAND" and not A.CanDualWield() then return false end
  elseif classID == 4 and p then
    if subID == 6 and not p.shield then return false end
    if (subID == 7 or subID == 8 or subID == 9) and p.relic ~= subID then return false end
  end
  return true
end

-- Returns "ok", "wrong" (wearable but not your armor type) or "unusable".
function A.Check(link)
  local _, _, _, equipLoc, _, classID, subID = ns.C.GetItemInfoInstant(link)
  local _, class = UnitClass("player")
  if not GearUsable(class, equipLoc, classID, subID) then return "unusable" end
  if classID ~= 4 or not A.ARMOR_SLOTS[equipLoc] or subID == 0 or subID > 4 then return "ok" end
  local max = A.MaxArmor(class, UnitLevel("player"))
  if subID > max then return "unusable" end
  if subID < max then return "wrong" end
  return "ok"
end
