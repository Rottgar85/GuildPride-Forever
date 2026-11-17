-- GuildPride: "Was ist neu?" – nach einem Update einmal die Änderungen zeigen
-- (Texte in GuildPrideNewsData.lua, erzeugt aus CHANGELOG.md). Wieder öffnen: /gp changelog
local ADDON, ns = ...
local L = ns.L

local W, H = 560, 440
local win

local function Text()
    local de = ns.IS_GERMAN
    local seen = GuildPrideDB and GuildPrideDB.newsSeen
    local parts, new = {}, true
    for i, v in ipairs(ns.NEWS or {}) do
        -- Neue Versionen seit dem letzten Mal hell, ab der zuletzt gesehenen gedämpft
        if seen and v.version == seen then new = false end
        parts[#parts + 1] = (i == 1 and "" or "\n") .. (new and "|cffff7d0a" or "|cff9a7a5a") .. "Version " .. v.version .. "|r"
        for _, line in ipairs((de and v.de) or v.en or {}) do
            parts[#parts + 1] = (new and "|cffe6e0da" or "|cffb0a8a0") .. "•|r " .. line
        end
    end
    return table.concat(parts, "\n")
end

local function Create()
    win = CreateFrame("Frame", "GuildPrideNewsFrame", UIParent, "BackdropTemplate")
    win:SetSize(W, H)
    win:SetPoint("CENTER", 0, 40)
    win:SetFrameStrata("DIALOG")
    win:SetClampedToScreen(true)
    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    tinsert(UISpecialFrames, "GuildPrideNewsFrame")   -- ESC schließt

    local title = win:CreateFontString(nil, "OVERLAY", "GPFont_Large")
    title:SetPoint("TOPLEFT", 18, -16)
    title:SetText(L["Was ist neu in GuildPride?"])
    local sub = win:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    sub:SetText(L["Wieder öffnen mit /gp changelog"])

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local scroll = ns.NewScroll and ns.NewScroll(win) or CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 18, -56)
    scroll:SetPoint("BOTTOMRIGHT", -36, 52)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(W - 60, 1)
    scroll:SetScrollChild(child)
    win.body = child:CreateFontString(nil, "OVERLAY", "GPFont_Text")
    win.body:SetPoint("TOPLEFT")
    win.body:SetWidth(W - 64)
    win.body:SetJustifyH("LEFT")
    win.body:SetSpacing(3)
    win.child = child

    local ok = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    ok:SetSize(120, 24)
    ok:SetPoint("BOTTOMRIGHT", -18, 16)
    ok:SetText(L["Verstanden"])
    ok:SetScript("OnClick", function() win:Hide() end)

    win:SetScript("OnHide", function()
        if GuildPrideDB then GuildPrideDB.newsSeen = ns.VERSION end
    end)
    if ns.SkinWindow then pcall(ns.SkinWindow, win) end
end

function ns.ShowNews()
    if not (ns.NEWS and #ns.NEWS > 0) then return end
    if not win then Create() end
    win.body:SetText(Text())
    win.child:SetHeight(win.body:GetStringHeight() + 10)
    win:Show()
end

-- Beim Einloggen / nach /reload: einmal je neuer Version
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    C_Timer.After(10, function()
        if not GuildPrideDB or not ns.VERSION then return end
        -- Neu installiert: die Einführung zeigt schon alles, Änderungen nicht extra
        if not GuildPrideDB.newsSeen and (GuildPrideDB.introSeen or 0) == 0 then
            GuildPrideDB.newsSeen = ns.VERSION
            return
        end
        if GuildPrideDB.newsSeen == ns.VERSION or InCombatLockdown() then return end
        -- Läuft gerade die Einführung/Neuerungen-Tour? Dann danach
        if GuildPrideIntroFrame and GuildPrideIntroFrame:IsShown() then
            GuildPrideIntroFrame:HookScript("OnHide", function()
                if GuildPrideDB.newsSeen ~= ns.VERSION then ns.ShowNews() end
            end)
            return
        end
        ns.ShowNews()
    end)
end)

local slash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local a = strtrim(arg or ""):lower()
    if a == "changelog" or a == "änderungen" or a == "aenderungen" then return ns.ShowNews() end
    return slash(arg)
end
