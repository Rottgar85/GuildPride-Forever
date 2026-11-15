local ADDON, GP = ...
-- Scales läuft in GuildPride in einem eigenen Unter-Namensraum (GP.Scales)
GP.Scales = GP.Scales or {}
local ns = GP.Scales
local L = ns.L
local St = ns.Style
local UI = {}
ns.UI = UI

local W, H = 380, 540
local RH, TOP = 18, 196
local SB = 32 -- height of the spec bar below the header
local DT = 12 -- extra room for the two-line stat details
-- Equipment slots shown in the list (no shirt and tabard; the ranged slot only exists outside Retail).
local SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17 }
if not ns.C.isRetail then SLOTS[#SLOTS + 1] = 18 end
local SLOT_NAMES = { "HEAD", "NECK", "SHOULDER", "SHIRT", "CHEST", "WAIST", "LEGS", "FEET", "WRIST", "HANDS",
  "FINGER0", "FINGER1", "TRINKET0", "TRINKET1", "BACK", "MAINHAND", "SECONDARYHAND", "RANGED", "TABARD" }

local function fmt(n) return BreakUpLargeNumbers(math.floor(n + 0.5)) end

local function Row(f, i)
  local r = CreateFrame("Button", nil, f)
  r:SetSize(W - 20, RH)
  r:SetPoint("TOPLEFT", 10, -(TOP + (i - 1) * RH))
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(); if GP.Paint then GP.Paint(hl, "glow", 0.15) else hl:SetColorTexture(St.CYAN[1], St.CYAN[2], St.CYAN[3], 0.12) end
  r.slot = St.Text(r, 11, "GameFontNormalSmall")
  r.slot:SetPoint("LEFT", 2, 0); r.slot:SetWidth(78); r.slot:SetWordWrap(false)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(15, 15); r.icon:SetPoint("LEFT", 82, 0)
  r.name = St.Text(r, 12)
  r.name:SetPoint("LEFT", r.icon, "RIGHT", 4, 0); r.name:SetWidth(200)
  r.name:SetWordWrap(false)
  r.score = St.Text(r, 12)
  r.score:SetPoint("RIGHT", -2, 0); r.score:SetJustifyH("RIGHT")
  r:SetScript("OnEnter", function(self)
    if not self.invSlot then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetInventoryItem("player", self.invSlot)
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", GameTooltip_Hide)
  return r
end

function UI.Create()
  local f = St.Panel("ScalesFrame", UIParent, W, H)
  f:SetPoint("CENTER")
  St.Movable(f)
  St.Header(f)
  f:Hide()

  local ob = St.Button(f, L.OPTIONS, 70)
  ob:SetPoint("TOPRIGHT", -28, -6)
  ob:SetScript("OnClick", function() ns.Options.Toggle() end)

  f.specBtns = {}

  f.header = St.Text(f, 12, "GameFontNormal")
  f.header:SetPoint("TOPLEFT", 12, -38 - SB)

  f.result = St.Text(f, 26)
  f.result:SetPoint("TOPLEFT", 12, -56 - SB)
  f.label = St.Text(f, 13, "GameFontNormal")
  f.label:SetPoint("BOTTOMLEFT", f.result, "BOTTOMRIGHT", 6, 3)

  f.details = St.Text(f, 11, "GameFontHighlightSmall")
  f.details:SetPoint("TOPLEFT", 12, -92 - SB)
  f.details:SetWidth(W - 24)

  local sep = f:CreateTexture(nil, "ARTWORK")
  sep:SetHeight(1); sep:SetPoint("TOPLEFT", 10, -126 - SB - DT); sep:SetPoint("TOPRIGHT", -10, -126 - SB - DT)
  sep:SetColorTexture(St.CYAN[1], St.CYAN[2], St.CYAN[3], 0.4)

  f.gearTitle = St.Text(f, 12, "GameFontNormal")
  f.gearTitle:SetPoint("TOPLEFT", 12, -133 - SB - DT)
  f.gearTitle:SetText(L.GEAR)
  f.score = St.Text(f, 12, "GameFontNormal")
  f.score:SetPoint("TOPRIGHT", -12, -133 - SB - DT); f.score:SetJustifyH("RIGHT")

  f.rows = {}
  for i = 1, #SLOTS do f.rows[i] = Row(f, i) end

  f.preview = St.Text(f, 12)
  f.preview:SetPoint("BOTTOMLEFT", 12, 12)
  f.preview:SetWidth(W - 24)
  f.preview:SetWordWrap(false)

  f:SetScript("OnShow", UI.Refresh)
  UI.frame = f
end

-- Spec bar: one button per spec. Click = show that spec in the window,
-- tick box = compare it in item tooltips too (like Pawn's scales).
local function SpecButton(f)
  local b = CreateFrame("Button", nil, f, BackdropTemplateMixin and "BackdropTemplate" or nil)
  b:SetHeight(26)
  -- Hintergrund wie die GuildPride-Knöpfe, dünner Rahmen in Akzentfarbe
  b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  b.gpBg = b:CreateTexture(nil, "BACKGROUND")
  b.gpBg:SetAllPoints(); b.gpBg:SetTexture("Interface\\AddOns\\GuildPrideForever\\Media\\nav")
  if GP.Paint then GP.Paint(b.gpBg, "tex") end
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetPoint("TOPLEFT", 2, -2); hl:SetPoint("BOTTOMRIGHT", -2, 2)
  if GP.Paint then GP.Paint(hl, "glow", 0.15) end
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(18, 18); b.icon:SetPoint("LEFT", 4, 0)
  b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  b.name = St.Text(b, 11)
  b.name:SetPoint("LEFT", b.icon, "RIGHT", 4, 0); b.name:SetPoint("RIGHT", -20, 0)
  b.name:SetWordWrap(false)
  b.check = CreateFrame("CheckButton", nil, b, "UICheckButtonTemplate")
  b.check:SetSize(18, 18); b.check:SetPoint("RIGHT", 0, 0)
  b.check:HookScript("OnClick", function(self)
    ns.Specs.SetInTooltip(b.specIndex, self:GetChecked())
    ns.Bags.QueueFullRefresh()
  end)
  b.check:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(L.SPEC_TOOLTIP_CHECK, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b.check:SetScript("OnLeave", GameTooltip_Hide)
  b:SetScript("OnClick", function(self)
    UI.viewIndex = self.specIndex
    UI.Refresh()
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(self.specName)
    GameTooltip:AddLine(self.isActive and L.SPEC_ACTIVE or L.SPEC_CLICK, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)
  return b
end

local function UpdateSpecBar(f, specs, view)
  local n = #specs
  local bw = (W - 20 - (n - 1) * 4) / math.max(n, 1)
  for i, s in ipairs(specs) do
    local b = f.specBtns[i] or SpecButton(f)
    f.specBtns[i] = b
    b:SetWidth(bw)
    b:ClearAllPoints(); b:SetPoint("TOPLEFT", 10 + (i - 1) * (bw + 4), -34)
    b.specIndex, b.specName, b.isActive = s.index, s.name, s.active
    b.icon:SetTexture(s.icon)
    b.name:SetText(s.active and ("|cffffd100" .. s.name .. "|r") or s.name)
    -- With four specs the buttons are too narrow for names; hovering still shows them.
    b.name:SetShown(n < 4)
    -- The active spec is always the main tooltip line, and specs sharing its scale would give
    -- the same result, so neither gets a tick box.
    b.check:SetShown(not s.active and s.weights ~= ns.weights)
    b.check:SetChecked(ns.Specs.InTooltip(s.index))
    local sel = s == view
    b.gpBg:SetTexture("Interface\\AddOns\\GuildPrideForever\\Media\\" .. (sel and "nav_active" or "nav"))
    if s.active then b:SetBackdropBorderColor(St.GOLD[1], St.GOLD[2], St.GOLD[3], 1)
    else b:SetBackdropBorderColor(St.CYAN[1], St.CYAN[2], St.CYAN[3], sel and 1 or 0.35) end
    b:Show()
  end
  for i = n + 1, #f.specBtns do f.specBtns[i]:Hide() end
end

local function StatLine(c, role)
  local parts = {}
  local function add(key, v, suffix) parts[#parts + 1] = string.format("%s |cffffffff%s%s|r", L[key], v, suffix or "") end
  if role == "TANK" then
    add("ARMOR", fmt(c.ARMOR)); add("DODGE", string.format("%.1f", c.DODGE), "%")
    add("PARRY", string.format("%.1f", c.PARRY), "%"); add("BLOCK", string.format("%.1f", c.BLOCK), "%")
  else
    add("CRIT", string.format("%.1f", c.CRIT), "%"); add("HASTE", string.format("%.1f", c.HASTE), "%")
    if ns.C.isRetail then
      add("MASTERY", string.format("%.1f", c.MASTERY), "%"); add("VERS", string.format("%.1f", c.VERS), "%")
    else
      add(role == "HEALER" and "HEALPOWER" or (c.SP > c.AP and "SP" or "AP"), fmt(role == "HEALER" and c.HEALPOWER or math.max(c.SP, c.AP)))
    end
  end
  -- Two values per line, so long names (e.g. German "Vielseitigkeit") never split from their number.
  local lines = {}
  for i = 1, #parts, 2 do lines[#lines + 1] = parts[i] .. (parts[i + 1] and ("    " .. parts[i + 1]) or "") end
  return "|cff99ccdd" .. table.concat(lines, "\n") .. "|r"
end

function UI.Refresh()
  local f = UI.frame
  if not f then return end
  -- In combat the active spec stays as it was before the fight, matching Sim.last.
  if not InCombatLockdown() then ns.UpdateWeights() end
  local specs = ns.Specs.List()
  local view = UI.viewIndex and specs[UI.viewIndex]
  if not view or view.active then
    UI.viewIndex = nil
    for _, s in ipairs(specs) do if s.active then view = s end end
  end
  local weights = view and view.weights or ns.weights
  UpdateSpecBar(f, specs, view)

  local r
  if weights == ns.weights then
    -- In combat keep the last result from before the fight (see Core/Init.lua).
    r = (InCombatLockdown() and ns.Sim.last) or ns.Sim.Run(ns.weights)
  else
    r = ns.Sim.Compute(weights)
  end
  local c = r.stats
  local role = r.role or "DAMAGER" -- custom weights may lack a role
  -- Other specs are simulated with the current character sheet, so their values are only an estimate.
  f.header:SetText(string.format("%s%s  |cff999999·|r  %s", view and view.name or "",
    (view and view.active) and (" |cffffd100(" .. L.ACTIVE .. ")|r") or (" |cff999999(" .. L.ESTIMATE .. ")|r"),
    L["ROLE_" .. role]))
  if UI.viewIndex then f.preview:SetText("") end
  if r.role == "TANK" then
    f.result:SetText(string.format("%.1f%%", r.mitigation))
    f.label:SetText(L.MITIGATION)
    f.details:SetText(string.format("%s |cffffffff%s|r\n%s", L.EHP, fmt(r.ehp), StatLine(c, r.role)))
  else
    f.result:SetText(fmt(r.value))
    f.label:SetText(r.role == "HEALER" and L.HPS or L.DPS)
    f.details:SetText(StatLine(c, r.role))
  end
  f.score:SetText(string.format("%s |cffffffff%s|r", L.SCORE, fmt(r.gearScore)))

  for i, slot in ipairs(SLOTS) do
    local row, link = f.rows[i], GetInventoryItemLink("player", slot)
    row.invSlot = link and slot or nil
    row.slot:SetText(_G[SLOT_NAMES[slot] .. "SLOT"] or SLOT_NAMES[slot])
    if link then
      row.icon:SetTexture(GetInventoryItemTexture("player", slot)); row.icon:Show()
      row.name:SetText(link)
      row.score:SetText(string.format("%.0f", ns.Compare.ItemScore(link, weights)))
    else
      row.icon:Hide()
      row.name:SetText(St.GREY .. L.EMPTY .. "|r")
      row.score:SetText("")
    end
  end
end

-- Live "what if" line while hovering an item; no manual simulation needed.
-- verdict comes from Compare.Verdict (via the tooltip), so preview, tooltip and bag arrow agree.
function UI.Preview(link, r, verdict)
  local f = UI.frame
  if not f or not f:IsShown() then return end
  -- The projection belongs to the active spec, so it is hidden while another spec is shown.
  if not link or not r or not r.newValue or UI.viewIndex then f.preview:SetText(""); return end
  local icon = verdict == "up" and St.Icon(St.ARROW_UP, 12) .. " " or verdict == "down" and St.Icon(St.ARROW_DOWN, 12) .. " " or ""
  local color = verdict == "up" and St.GREEN or verdict == "down" and St.RED or St.GREY
  f.preview:SetText(string.format("%s%s %s: %s -> %s%s|r", icon, L.PREVIEW, link,
    fmt(ns.Sim.last.value), color, fmt(r.newValue)))
end

function UI.Toggle()
  if not UI.frame then UI.Create() end
  UI.frame:SetShown(not UI.frame:IsShown())
end
