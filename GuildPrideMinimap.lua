-- GuildPride: Knopf am Minimap-Rand
-- Linksklick öffnet das Gildenfenster, Rechtsklick die Einstellungen,
-- ziehen verschiebt ihn am Rand. In den Einstellungen abschaltbar.
local ADDON, ns = ...
local L = ns.L

local btn = CreateFrame("Button", "GuildPrideMinimapButton", Minimap)
btn:SetSize(31, 31)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(8)
btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
btn:RegisterForDrag("LeftButton")
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local back = btn:CreateTexture(nil, "BACKGROUND")
back:SetSize(20, 20); back:SetPoint("CENTER")
back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
local icon = btn:CreateTexture(nil, "ARTWORK")
icon:SetSize(20, 20); icon:SetPoint("CENTER")
icon:SetTexture(ns.MEDIA .. "logo")
local border = btn:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53); border:SetPoint("TOPLEFT")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

-- Position als Winkel am Minimap-Rand (GuildPrideDB.minimapAngle, Grad)
local function Place()
    local a = math.rad(GuildPrideDB.minimapAngle or 200)
    local r = Minimap:GetWidth() / 2 + 5
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function Drag()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    GuildPrideDB.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
    Place()
end
btn:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", Drag) end)
btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

local function Click(button)
    if button == "RightButton" then
        if not ns.GuildFrame:IsShown() then ns.ToggleUI() end
        if ns.GuildFrame:IsShown() and ns.SettingsPage then ns.SelectTab(ns.SettingsPage.tabId) end
    else
        ns.ToggleUI()
    end
end
btn:SetScript("OnClick", function(_, button) Click(button) end)

-- Gemeinsamer Tooltip (Minimap-Knopf, Titan Panel & Co.)
local function OnlineCount()
    if not IsInGuild() then return 0, 0 end
    local total, online = GetNumGuildMembers()
    return online or 0, total or 0
end
local function FillTooltip(tip, drag)
    tip:AddLine("GuildPride")
    if IsInGuild() then
        local online, total = OnlineCount()
        tip:AddLine((L["%d von %d Mitgliedern online"]):format(online, total), 0.8, 0.8, 0.8)
    end
    tip:AddLine(L["Linksklick: Gildenfenster"], 1, 1, 1)
    tip:AddLine(L["Rechtsklick: Einstellungen"], 1, 1, 1)
    if drag then tip:AddLine(L["Ziehen: verschieben"], 0.7, 0.7, 0.7) end
end
btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    FillTooltip(GameTooltip, true)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", GameTooltip_Hide)
btn:Hide()

function ns.UpdateMinimap()
    if GuildPrideDB.minimap == false then btn:Hide() else Place(); btn:Show() end
end

---------------------------------------------------------------------
-- Infoleisten (Titan Panel, ChocolateBar, Bazooka …) über LibDataBroker,
-- falls eine davon die Bibliothek mitbringt
---------------------------------------------------------------------
local broker
local function BrokerText()
    if not IsInGuild() then return "GuildPride" end
    local online = OnlineCount()
    return (L["%d online"]):format(online)
end
local function SetupBroker()
    if broker then return end
    local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
    if not LDB then return end
    broker = LDB:NewDataObject("GuildPride", {
        type = "data source", label = "GuildPride", text = BrokerText(), icon = ns.MEDIA .. "logo",
        OnClick = function(_, button) Click(button) end,
        OnTooltipShow = function(tip) FillTooltip(tip, false) end,
    })
end

---------------------------------------------------------------------
-- Knopf am Blizzard-Gildenfenster: ein Seitenreiter unter Blizzards eigenen
-- (Chat, Mitglieder …). Wir fügen nur einen eigenen Rahmen hinzu und ändern
-- nichts an Blizzards Fenster. Umschalt+Ziehen verschiebt ihn senkrecht.
---------------------------------------------------------------------
local gtab, gHost
local function Host() return CommunitiesFrame or GuildFrame end

-- Unterkante der Blizzard-Seitenreiter rechts am Fenster (falls vorhanden)
local function SideTabsBottom(host)
    local right, top = host:GetRight(), host:GetTop()
    if not right or not top then return end
    local bottom
    for _, c in ipairs({ host:GetChildren() }) do
        if c ~= gtab and c:IsShown() and c.GetLeft then
            local l, b, w = c:GetLeft(), c:GetBottom(), c:GetWidth()
            if l and b and w and math.abs(l - right) < 8 and w < 64 and (not bottom or b < bottom) then bottom = b end
        end
    end
    return bottom and (bottom - top) or nil
end

local function PlaceTab()
    if not gtab or not gHost then return end
    local y = GuildPrideDB.guildTabY or SideTabsBottom(gHost)
    y = y and (y - (GuildPrideDB.guildTabY and 0 or 14)) or -230
    gtab:ClearAllPoints()
    gtab:SetPoint("TOPLEFT", gHost, "TOPRIGHT", 0, math.min(-20, math.max(-560, y)))
end

local function TabDrag()
    local _, cy = GetCursorPosition()
    local top = gHost:GetTop()
    if not top then return end
    GuildPrideDB.guildTabY = math.floor(cy / gtab:GetEffectiveScale() - top + 16)
    PlaceTab()
end

local function BuildTab(host)
    gHost = host
    gtab = CreateFrame("Button", "GuildPrideGuildTab", host)
    gtab:SetSize(32, 32)
    gtab:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    gtab:RegisterForDrag("LeftButton")
    local bg = gtab:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(64, 64); bg:SetPoint("TOPLEFT", -3, 11)
    bg:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
    local ic = gtab:CreateTexture(nil, "ARTWORK")
    ic:SetAllPoints(); ic:SetTexture(ns.MEDIA .. "logo")
    gtab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    gtab:SetScript("OnClick", function(_, button)
        if not InCombatLockdown() and host:IsShown() and HideUIPanel then pcall(HideUIPanel, host) end
        if not ns.GuildFrame:IsShown() or button == "RightButton" then Click(button) end
    end)
    gtab:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:SetScript("OnUpdate", TabDrag) end end)
    gtab:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    gtab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        FillTooltip(GameTooltip, false)
        GameTooltip:AddLine(L["Umschalt+Ziehen: verschieben"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    gtab:SetScript("OnLeave", GameTooltip_Hide)
    -- Blizzards Reiter stehen erst nach dem Anzeigen fest
    host:HookScript("OnShow", function() C_Timer.After(0, function() ns.UpdateGuildTab() end) end)
end

function ns.UpdateGuildTab()
    local host = Host()
    if not host or not GuildPrideDB then return end
    if not gtab then
        if GuildPrideDB.guildTab == false then return end
        BuildTab(host)
    end
    gtab:SetShown(GuildPrideDB.guildTab ~= false and IsInGuild())
    PlaceTab()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
local textPending = false
f:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" then
        ns.UpdateMinimap()
        SetupBroker()
        ns.UpdateGuildTab()
    elseif event == "ADDON_LOADED" then
        if name == "Blizzard_Communities" or name == "Blizzard_GuildUI" then ns.UpdateGuildTab() end
    elseif broker and not textPending then
        textPending = true
        C_Timer.After(2, function() textPending = false; broker.text = BrokerText() end)
    end
end)
