-- Abstraction over API differences between Retail, Forever, Mists/Cata Classic, TBC/Anniversary and Classic Era.
local ADDON, GP = ...
-- Scales läuft in GuildPride in einem eigenen Unter-Namensraum (GP.Scales)
GP.Scales = GP.Scales or {}
local ns = GP.Scales
local C = {}
ns.C = C

local project = WOW_PROJECT_ID
C.isRetail  = project == WOW_PROJECT_MAINLINE
C.isForever = WOW_PROJECT_CAMELOT ~= nil and project == WOW_PROJECT_CAMELOT
C.isVanilla = project == WOW_PROJECT_CLASSIC
-- Forever has classic content (talent trees, armor at level 40), so it uses the classic rules.
C.isClassic = not C.isRetail

-- Midnight and Forever may return "secret values" in combat; any arithmetic on them errors.
local issecret = issecretvalue or function() return false end
C.IsSecret = issecret
function C.Num(v, fallback)
  if v == nil or issecret(v) then return fallback or 0 end
  return v
end

C.GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
C.GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
C.GetItemStats = (C_Item and C_Item.GetItemStats) or GetItemStats
C.GetContainerNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
C.GetContainerItemLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
C.NUM_BAGS = NUM_BAG_SLOTS or 4

-- Returns specIndex (1-4) of the active spec; classic without specs falls back to talent tree with most points.
function C.GetSpecIndex()
  if GetSpecialization then
    local s = GetSpecialization()
    if s and s > 0 then return s end
  end
  if GetPrimaryTalentTree then
    local s = GetPrimaryTalentTree()
    if s and s > 0 then return s end
  end
  if GetNumTalentTabs and GetTalentTabInfo then
    local best, bestPts = 1, -1
    for i = 1, GetNumTalentTabs() do
      local r = { GetTalentTabInfo(i) }
      -- Era returns (name, icon, pointsSpent, ...); newer classics (id, name, desc, icon, pointsSpent, ...)
      local pts = type(r[1]) == "number" and r[5] or r[3]
      if type(pts) == "number" and pts > bestPts then best, bestPts = i, pts end
    end
    return best
  end
  return 1
end

-- Inventory slot ids an equipLoc may go into.
C.SlotsForEquipLoc = {
  INVTYPE_HEAD = {1}, INVTYPE_NECK = {2}, INVTYPE_SHOULDER = {3}, INVTYPE_BODY = {4},
  INVTYPE_CHEST = {5}, INVTYPE_ROBE = {5}, INVTYPE_WAIST = {6}, INVTYPE_LEGS = {7},
  INVTYPE_FEET = {8}, INVTYPE_WRIST = {9}, INVTYPE_HAND = {10}, INVTYPE_FINGER = {11, 12},
  INVTYPE_TRINKET = {13, 14}, INVTYPE_CLOAK = {15}, INVTYPE_WEAPON = {16, 17},
  INVTYPE_SHIELD = {17}, INVTYPE_2HWEAPON = {16}, INVTYPE_WEAPONMAINHAND = {16},
  INVTYPE_WEAPONOFFHAND = {17}, INVTYPE_HOLDABLE = {17}, INVTYPE_RANGED = C.isRetail and {16} or {18},
  INVTYPE_RANGEDRIGHT = C.isRetail and {16} or {18}, INVTYPE_THROWN = {18}, INVTYPE_RELIC = {18},
}

-- Returns the tooltip text lines of an item link (works with and without C_TooltipInfo).
local scanner
function C.GetTooltipLines(link)
  local out = {}
  if C_TooltipInfo and C_TooltipInfo.GetHyperlink then
    local data = C_TooltipInfo.GetHyperlink(link)
    if data and data.lines then
      -- Skip secret strings (Midnight/Forever in combat); string functions on them error.
      for _, l in ipairs(data.lines) do
        if l.leftText and not (issecretvalue and issecretvalue(l.leftText)) then out[#out + 1] = l.leftText end
      end
    end
    return out
  end
  if not scanner then
    scanner = CreateFrame("GameTooltip", "ScalesScanTooltip", nil, "GameTooltipTemplate")
    scanner:SetOwner(WorldFrame, "ANCHOR_NONE")
  end
  scanner:ClearLines()
  scanner:SetHyperlink(link)
  for i = 1, scanner:NumLines() do
    local fs = _G["ScalesScanTooltipTextLeft" .. i]
    local t = fs and fs:GetText()
    if t then out[#out + 1] = t end
  end
  return out
end

function C.GetItemLevel(link)
  local f = (C_Item and C_Item.GetDetailedItemLevelInfo) or GetDetailedItemLevelInfo
  local ilvl = f and f(link)
  if not ilvl then ilvl = select(4, C.GetItemInfo(link)) end
  return ilvl or 0
end
