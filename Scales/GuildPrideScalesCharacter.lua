-- Scales am Charakterfenster: ein Knopf oben am Charakterfenster, und das Scales-Fenster
-- dockt rechts daneben an. Ersetzt den früheren Minimap-Knopf (ns.Minimap bleibt als Name,
-- damit Init und Optionen unverändert weiterlaufen).
local ADDON, GP = ...
GP.Scales = GP.Scales or {}
local ns = GP.Scales
local M = {}
ns.Minimap = M

local button

-- Scales-Fenster rechts ans Charakterfenster hängen (solange es offen ist)
local function Dock()
  local f = ns.UI and ns.UI.frame
  if not f or not CharacterFrame then return end
  f:ClearAllPoints()
  if CharacterFrame:IsShown() then
    f:SetPoint("TOPLEFT", CharacterFrame, "TOPRIGHT", 50, 0)
  else
    f:SetPoint("CENTER")
  end
end
M.Dock = Dock

local function Open()
  if not ns.UI.frame then ns.UI.Create() end
  Dock()
  ns.UI.frame:Show()
end

local function Create()
  if button or not CharacterFrame then return end
  button = CreateFrame("Button", "GuildPrideScalesCharButton", CharacterFrame, "UIPanelButtonTemplate")
  button:SetSize(74, 22)
  button:SetPoint("TOPRIGHT", CharacterFrame, "TOPRIGHT", -26, -28)
  button:SetText("Scales")
  if GP.SkinButton then GP.SkinButton(button) end
  button:SetFrameLevel(CharacterFrame:GetFrameLevel() + 20)
  button:SetScript("OnClick", function()
    if ns.UI.frame and ns.UI.frame:IsShown() then ns.UI.frame:Hide() else Open() end
  end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Scales", 1, 0.82, 0)
    GameTooltip:AddLine(GetLocale() == "deDE" and "Simulation, Upgrades und Spezialisierung"
      or "Simulation, upgrades and specialization", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", GameTooltip_Hide)

  -- Mit dem Charakterfenster öffnen (abschaltbar) und immer mit ihm schließen
  CharacterFrame:HookScript("OnShow", function()
    if ScalesDB.withCharacter ~= false then Open() end
  end)
  CharacterFrame:HookScript("OnHide", function()
    local f = ns.UI and ns.UI.frame
    if f and f:IsShown() then f:Hide() end
  end)
end

function M.Init()
  Create()
  M.Apply()
end

-- Option "Knopf am Charakterfenster zeigen" (ScalesDB.charButtonHide)
function M.Apply()
  if button then button:SetShown(not ScalesDB.charButtonHide) end
end
