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

function Cmp.ItemScore(link, weights)
  local score = S.Score(S.GetItemStats(link), weights)
  local _, _, _, equipLoc = C.GetItemInfoInstant(link)
  if equipLoc == "INVTYPE_TRINKET" then score = score + Cmp.TrinketEffectScore(link, weights) end
  return score
end

function Cmp.EquippedScore(weights)
  local total = 0
  for slot = 1, 19 do
    local link = GetInventoryItemLink("player", slot)
    if link then total = total + Cmp.ItemScore(link, weights) end
  end
  return total
end

local function equippedInfo(slot, weights)
  local link = GetInventoryItemLink("player", slot)
  return link, link and Cmp.ItemScore(link, weights) or 0
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

  local score = Cmp.ItemScore(link, w)
  local best

  if equipLoc == "INVTYPE_2HWEAPON" then
    local mhLink, mh = equippedInfo(16, w)
    local _, oh = equippedInfo(17, w)
    best = { slot = 16, equippedLink = mhLink, old = mh + oh }
  else
    -- Rings/trinkets/dual wield: compare against the weaker equipped item.
    -- An empty off hand does not count for one-handers: most classes cannot dual wield,
    -- and a two-hander in the main hand leaves it empty too.
    local mainOnly = equipLoc == "INVTYPE_WEAPON" and GetInventoryItemLink("player", 16)
      and not GetInventoryItemLink("player", 17)
    for _, slot in ipairs(slots) do
      if not (mainOnly and slot == 17) then
        local eqLink, eqScore = equippedInfo(slot, w)
        if eqLink == link then return { same = true, score = score } end
        if not best or eqScore < best.old then best = { slot = slot, equippedLink = eqLink, old = eqScore } end
      end
    end
  end

  best.armor = armor
  best.score = score
  best.delta = score - best.old
  best.pct = best.old > 0 and (best.delta / best.old * 100) or (score > 0 and 100 or 0)
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
