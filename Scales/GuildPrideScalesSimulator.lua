-- Analytical character model: estimates sustained DPS, HPS or tank mitigation from the
-- live character sheet. It is a fast approximation (no rotation/APL simulation) intended to
-- compare gear, not to replace SimulationCraft.
local ADDON, GP = ...
-- Scales läuft in GuildPride in einem eigenen Unter-Namensraum (GP.Scales)
GP.Scales = GP.Scales or {}
local ns = GP.Scales
local Sim = {}
ns.Sim = Sim

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

-- Armor constant scales with level; tuned per client so results stay in a sensible range.
local function ArmorReduction(armor, level)
  local K
  if ns.C.isRetail then K = 2500 + level * 60
  elseif level < 60 then K = 400 + 85 * level
  else K = 467.5 * level - 22167.5 end
  return clamp(armor / (armor + K), 0, 0.85)
end

local function Multipliers(c)
  local crit = 1 + clamp(c.CRIT, 0, 100) / 100
  local haste = 1 + clamp(c.HASTE, 0, 200) / 100
  local mastery = 1 + clamp(c.MASTERY, 0, 300) / 100 * 0.5
  local vers = 1 + clamp(c.VERS, 0, 100) / 100
  return crit * haste * mastery * vers
end

-- Simulates the character for any spec's weights without touching Sim.last (used by the spec bar).
function Sim.Compute(weights)
  local c = ns.Stats.GetCharacterStats()
  local role = weights.role
  local r = { role = role, stats = c }
  local mult = Multipliers(c)

  if role == "TANK" then
    local dr = ArmorReduction(c.ARMOR, c.LEVEL)
    local avoid = clamp((c.DODGE + c.PARRY) / 100, 0, 0.75)
    local block = clamp(c.BLOCK / 100, 0, 0.75) * 0.3
    local taken = (1 - dr) * (1 - avoid) * (1 - block) * (1 - clamp(c.VERS / 200, 0, 0.5))
    r.mitigation = (1 - taken) * 100
    r.ehp = c.HP / taken
    r.value, r.label = r.ehp, "EHP"
    r.dps = (c.AP / 3.5 + c.WDPS) * mult * 0.6
  elseif role == "HEALER" then
    local power = c.INT * 1.0 + c.HEALPOWER * 1.2
    r.hps = power * 0.9 * mult
    r.value, r.label = r.hps, "HPS"
  else
    local power
    if weights.primary == "INT" then power = c.INT + c.SP * 1.1
    else power = c.AP / 3.5 * 3 + c.WDPS * 2 end
    r.dps = power * 1.1 * mult
    r.value, r.label = r.dps, "DPS"
  end
  -- Total gear score is used to translate item score deltas into simulated output deltas.
  r.gearScore = ns.Compare.EquippedScore(weights)
  return r
end

-- Simulates the active spec; its result drives the tooltip projections.
function Sim.Run(weights)
  Sim.last = Sim.Compute(weights)
  return Sim.last
end

-- Projected change in the role metric (DPS/HPS/EHP) for a score delta.
function Sim.ProjectDelta(scoreDelta)
  local r = Sim.last
  if not r or not r.gearScore or r.gearScore <= 0 then return nil end
  return r.value * scoreDelta / r.gearScore, r.label
end
