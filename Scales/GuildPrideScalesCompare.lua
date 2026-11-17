local ADDON, GP = ...
-- Scales läuft in GuildPride in einem eigenen Unter-Namensraum (GP.Scales)
GP.Scales = GP.Scales or {}
local ns = GP.Scales
local C, S = ns.C, ns.Stats
local Cmp = {}
ns.Compare = Cmp

local TRIGGERS = { ITEM_SPELL_TRIGGER_ONUSE, ITEM_SPELL_TRIGGER_ONEQUIP, ITEM_SPELL_TRIGGER_ONPROC }
local ROLE_HINTS = {
  HEALER = { "heal", "heil" },
  TANK = { "absorb", "armor", "rüstung", "dodge", "ausweich", "parry", "parier", "block" },
}

-- Score budget per item level, derived from the currently equipped non-trinket gear,
-- so trinket effects are valued on the same scale as normal stats on every client.
-- Cached per weights table, because every spec has its own scale.
local budgetCache = {}
function Cmp.BudgetPerIlvl(weights)
  if budgetCache[weights] then return budgetCache[weights] end
  local score, ilvl = 0, 0
  for slot = 1, 17 do
    local link = slot ~= 13 and slot ~= 14 and slot ~= 4 and GetInventoryItemLink("player", slot)
    if link then
      score = score + S.Score(S.GetItemStats(link), weights)
      ilvl = ilvl + C.GetItemLevel(link)
    end
  end
  budgetCache[weights] = ilvl > 0 and score / ilvl or 0.5
  return budgetCache[weights]
end
-- Trinket effect values depend on the budget, so both are cleared together.
local effectCache = {}
function Cmp.InvalidateBudget() wipe(budgetCache); wipe(effectCache) end

-- Estimates the value of Use:/Equip:/Chance on hit: effects on trinkets.
function Cmp.TrinketEffectScore(link, weights)
  effectCache[weights] = effectCache[weights] or {}
  local cache = effectCache[weights]
  if cache[link] then return cache[link] end
  local value = 0
  for _, line in ipairs(C.GetTooltipLines(link)) do
    for i, trig in ipairs(TRIGGERS) do
      if trig and line:find(trig, 1, true) == 1 then
        local factor = i == 1 and 0.7 or 0.9 -- on-use effects have downtime
        local text = line:lower()
        for role, hints in pairs(ROLE_HINTS) do
          for _, h in ipairs(hints) do
            if text:find(h, 1, true) then
              factor = factor * (role == weights.role and 1.3 or 0.35)
              break
            end
          end
        end
        value = value + factor
      end
    end
  end
  if value > 0 then
    value = math.min(value, 1.5) * C.GetItemLevel(link) * Cmp.BudgetPerIlvl(weights)
  end
  cache[link] = value
  return value
end

local RANGED = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true }
local OFFHAND_DPS = 0.5 -- Nebenhand-Waffen treffen nur mit halbem Schaden
local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- Gewicht der Waffen-DPS: Nahkampf und Fernkampf getrennt (ein Jäger kämpft mit dem Bogen,
-- ein Krieger mit der Nahkampfwaffe, Zauberer höchstens mit dem Zauberstab).
local function DpsWeight(weights, equipLoc, subID)
  local _, class = UnitClass("player")
  if RANGED[equipLoc] then
    if weights.RDPS then return weights.RDPS end
    if class == "HUNTER" then return 6.5 end
    if subID == 19 then return weights.primary == "INT" and 2 or 0 end
    return 0.4
  end
  local w = weights.WDPS or 0
  if class == "HUNTER" and not weights.RDPS then w = w * 0.25 end
  return w
end

-- asOffhand: das Teil steckt (oder käme) in die Nebenhand.
function Cmp.ItemScore(link, weights, asOffhand)
  local stats = S.GetItemStats(link)
  if not stats then return 0 end
  local _, _, _, equipLoc, _, _, subID = C.GetItemInfoInstant(link)
  local score = 0
  for k, v in pairs(stats) do
    if k == "WDPS" then
      score = score + v * DpsWeight(weights, equipLoc, subID) * (asOffhand and OFFHAND_DPS or 1)
    else
      local w = weights[k]
      if type(w) == "number" then score = score + v * w end
    end
  end
  if equipLoc == "INVTYPE_TRINKET" then score = score + Cmp.TrinketEffectScore(link, weights) end
  return score
end

function Cmp.EquippedScore(weights)
  local total = 0
  for slot = 1, 19 do
    local link = GetInventoryItemLink("player", slot)
    if link then total = total + Cmp.ItemScore(link, weights, slot == 17) end
  end
  return total
end

local function equippedInfo(slot, weights)
  local link = GetInventoryItemLink("player", slot)
  return link, link and Cmp.ItemScore(link, weights, slot == 17) or 0
end

local function itemID(link) return link and tonumber(link:match("item:(%d+)")) end

-- Bestes tragbares Haupthand- bzw. Nebenhand-Teil in den Taschen (nicht das Kandidaten-Teil),
-- um es mit einer Einhandwaffe zu kombinieren, wenn gerade eine Zweihandwaffe getragen wird.
local function BagBest(weights, wantOff, except)
  local num = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
  local get = C_Container and C_Container.GetContainerItemLink or GetContainerItemLink
  if not (num and get) then return 0 end
  local dw, lvl, best = ns.Armor.CanDualWield(), UnitLevel("player"), 0
  for bag = 0, 4 do
    for slot = 1, (num(bag) or 0) do
      local link = get(bag, slot)
      if link and link ~= except then
        local _, _, _, loc = C.GetItemInfoInstant(link)
        local ok
        if wantOff then
          ok = loc == "INVTYPE_SHIELD" or loc == "INVTYPE_HOLDABLE"
            or (dw and (loc == "INVTYPE_WEAPONOFFHAND" or loc == "INVTYPE_WEAPON"))
        else
          ok = loc == "INVTYPE_WEAPON" or loc == "INVTYPE_WEAPONMAINHAND"
        end
        local minLevel = ok and GetInfo and select(5, GetInfo(link)) or 0
        if ok and (minLevel or 0) <= lvl and ns.Armor.Check(link) ~= "unusable" then
          local sc = Cmp.ItemScore(link, weights, wantOff)
          if sc > best then best = sc end
        end
      end
    end
  end
  return best
end

-- Merkt sich die Variante mit dem größten Gewinn.
local function Option(best, slot, eqLink, old, new)
  if not best.delta or new - old > best.delta then
    best.slot, best.equippedLink, best.old, best.new, best.delta = slot, eqLink, old, new, new - old
  end
end

-- Returns { score, delta, pct, slot, equippedLink, armor, newValue } or nil if not comparable.
-- weights defaults to the active spec; only the active spec gets a DPS/HPS/EHP projection.
function Cmp.Evaluate(link, weights)
  local w = weights or ns.weights
  if not link or not w then return nil end
  local _, _, _, equipLoc = C.GetItemInfoInstant(link)
  local slots = equipLoc and C.SlotsForEquipLoc[equipLoc]
  if not slots then return nil end
  if IsEquippableItem and not IsEquippableItem(link) then return nil end

  local armor = ns.Armor.Check(link)
  if armor == "unusable" then return { unusable = true } end
  if not ns.Sim.last and ns.weights then ns.Sim.Run(ns.weights) end

  for _, slot in ipairs(slots) do
    if GetInventoryItemLink("player", slot) == link then
      return { same = true, score = Cmp.ItemScore(link, w, slot == 17) }
    end
  end

  local asOff = equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" or equipLoc == "INVTYPE_WEAPONOFFHAND"
  local score = Cmp.ItemScore(link, w, asOff)
  local best = {}
  local mhLink, mh = equippedInfo(16, w)
  local ohLink, oh = equippedInfo(17, w)
  local twoHander = mhLink and select(4, C.GetItemInfoInstant(mhLink)) == "INVTYPE_2HWEAPON"

  if equipLoc == "INVTYPE_2HWEAPON" then
    -- Zweihänder ersetzt Haupt- und Nebenhand zusammen
    Option(best, 16, mhLink, mh + oh, score)
  elseif equipLoc == "INVTYPE_FINGER" or equipLoc == "INVTYPE_TRINKET" then
    local id = itemID(link)
    local a, b = slots[1], slots[2]
    local la, sa = equippedInfo(a, w)
    local lb, sb = equippedInfo(b, w)
    local slot
    if id and itemID(la) == id then slot = a          -- gleiches (oft einzigartiges) Teil ersetzen
    elseif id and itemID(lb) == id then slot = b
    elseif not la then slot = a                       -- freier Platz zuerst
    elseif not lb then slot = b
    else slot = sb < sa and b or a end                -- sonst das schwächere Teil
    Option(best, slot, slot == a and la or lb, slot == a and sa or sb, score)
  elseif equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND" or asOff then
    if not asOff then
      -- Einhänder statt Zweihänder: mit dem besten Nebenhand-Teil aus den Taschen kombinieren
      Option(best, 16, mhLink, mh, score + (twoHander and BagBest(w, true, link) or 0))
    end
    if asOff or (equipLoc == "INVTYPE_WEAPON" and ns.Armor.CanDualWield()) then
      local offScore = asOff and score or Cmp.ItemScore(link, w, true)
      if twoHander then
        Option(best, 17, mhLink, mh, offScore + BagBest(w, false, link))
      else
        Option(best, 17, ohLink, oh, offScore)
      end
    end
  else
    local eqLink, eqScore = equippedInfo(slots[1], w)
    Option(best, slots[1], eqLink, eqScore, score)
  end

  best.armor = armor
  best.score = score
  best.pct = best.old > 0 and (best.delta / best.old * 100) or (best.new > 0 and 100 or 0)
  best.empty = best.equippedLink == nil
  if w == ns.weights then
    best.simDelta, best.simLabel = ns.Sim.ProjectDelta(best.delta)
    if best.simDelta then best.newValue = ns.Sim.last.value + best.simDelta end
  end
  return best
end

function Cmp.IsUpgrade(link, weights)
  local r = Cmp.Evaluate(link, weights)
  if not r or r.unusable or r.same then return false, r end
  -- In Retail, off-type armor is never an upgrade.
  if r.armor == "wrong" and ns.C.isRetail then return false, r end
  return r.delta > 0.5 and r.pct >= (ScalesDB.minUpgradePct or 0.5), r
end

-- "up", "down" or nil (not equipment, already equipped, not wearable, or within the tolerance).
function Cmp.Verdict(link, weights)
  local up, r = Cmp.IsUpgrade(link, weights)
  if up then return "up", r end
  if not r or r.unusable or r.same or r.empty then return nil, r end
  if r.armor == "wrong" and ns.C.isRetail then return nil, r end
  if r.delta < -0.5 and r.pct <= -(ScalesDB.minUpgradePct or 0.5) then return "down", r end
  return nil, r
end

-- Pawn-style comparison for the other specs ticked in the window: one entry per distinct scale,
-- specs sharing a scale with each other are merged; specs sharing the active scale are left out.
-- Returns { { names = "Arms / Fury", icon, verdict, r }, ... }
function Cmp.OtherSpecs(link)
  local out, byWeights = {}, {}
  for _, s in ipairs(ns.Specs.List()) do
    if not s.active and s.weights ~= ns.weights and ns.Specs.InTooltip(s.index) then
      local e = byWeights[s.weights]
      if e then
        e.names = e.names .. " / " .. s.name
      elseif e == nil then
        local verdict, r = Cmp.Verdict(link, s.weights)
        if r and not r.unusable and not r.same then
          e = { names = s.name, icon = s.icon, verdict = verdict, r = r }
          out[#out + 1] = e
        end
        byWeights[s.weights] = e or false -- false: already evaluated, nothing to show
      end
    end
  end
  return out
end

-- True if the item is an upgrade for any other spec ticked for the tooltip.
function Cmp.UpgradeForOtherSpec(link)
  for _, e in ipairs(Cmp.OtherSpecs(link)) do
    if e.verdict == "up" then return true end
  end
  return false
end
