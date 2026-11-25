-- GuildPride: Reiter „Meilensteine“ (Verlauf mit Filter und Spielersuche)
local ADDON, ns = ...
local L = ns.L
local AddTab, CreateList = ns.AddTab, ns.CreateList
local MEDIA = "Interface\\AddOns\\GuildPrideForever\\Media\\"

local milestones = AddTab(L["Meilensteine"], 60)
-- Filterleiste oben: Art (Alle, Stufe, Erfolge, Bosse, Gilde) und Suche nach Spielernamen
local msCat, msText = "all", ""
local CATS = { { "all", L["Alle"] }, { "level", L["Stufe"] }, { "ach", L["Erfolge"] }, { "boss", L["Bosse"] },
               { "guild", L["Beitritte"] } }
local catBtns = {}
local function MarkCats()
    for key, b in pairs(catBtns) do
        if b.gpBg then b.gpBg:SetTexture(MEDIA .. (key == msCat and "nav_active" or "nav")) end
        if key == msCat then b:LockHighlight() else b:UnlockHighlight() end
    end
end
for i, c in ipairs(CATS) do
    local b = CreateFrame("Button", nil, milestones, "UIPanelButtonTemplate")
    b:SetSize(84, 22)
    b:SetPoint("TOPLEFT", (i - 1) * 88, -2)
    b:SetText(c[2])
    b:SetScript("OnClick", function() msCat = c[1]; MarkCats(); milestones:Refresh() end)
    catBtns[c[1]] = b
end
local msSearch = CreateFrame("EditBox", nil, milestones, "InputBoxTemplate")
msSearch:SetSize(150, 20); msSearch:SetPoint("TOPRIGHT", -30, -3)
msSearch:SetAutoFocus(false)
if ns.SkinEditBox then ns.SkinEditBox(msSearch) end
local msHint = msSearch:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
msHint:SetPoint("LEFT", 2, 0); msHint:SetText(L["Spieler suchen …"])
msSearch:SetScript("OnTextChanged", function(self)
    msText = self:GetText() or ""
    msHint:SetShown(msText == "")
    milestones:Refresh()
end)
msSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
local msCount = milestones:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
msCount:SetPoint("RIGHT", msSearch, "LEFT", -10, 0)
local listHolder = CreateFrame("Frame", nil, milestones)
listHolder:SetPoint("TOPLEFT", 0, -28); listHolder:SetPoint("BOTTOMRIGHT")
local msList = CreateList(listHolder, 24)

function milestones:Refresh()
    MarkCats()
    local log = {}
    for _, e in ipairs(ns.GuildLog()) do
        if not ns.MilestoneMatch or ns.MilestoneMatch(e, msCat, msText) then log[#log + 1] = e end
    end
    msCount:SetText((L["%d Einträge"]):format(#log))
    for i, e in ipairs(log) do
        local row = msList:GetRow(i)
        if not row.badge then
            row.badge = row:CreateTexture(nil, "ARTWORK")
            row.badge:SetSize(22, 22)
            row.badge:SetPoint("LEFT", 4, 0)
            row.left:SetPoint("LEFT", 32, 0)
        end
        local badged = e.kind == "LEVEL" or (ns.EXTRA_KINDS and ns.EXTRA_KINDS[e.kind])
        row.badge:SetShown(badged and true or false)
        if badged and ns.BadgeFor then row.badge:SetTexture(ns.BadgeFor(e.kind, e.value)) end
        row.left:SetText("|cfff0c88c" .. e.who .. "|r")
        row.mid:SetText(ns.LogText(e))
        row.right:SetText(ns.FormatDay(e.t, true))
    end
    msList:Finish(#log)
end

-- Beim Öffnen verpasste Einträge von anderen holen (höchstens alle 2 Minuten)
local lastHistoryAsk = 0
milestones:HookScript("OnShow", function()
    if GetTime() - lastHistoryAsk < 120 or not ns.RequestHistory then return end
    lastHistoryAsk = GetTime()
    ns.RequestHistory()
end)
