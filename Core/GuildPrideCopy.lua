-- GuildPride: einzelne GuildPride-Meldungen aus dem Chat kopieren
-- WoW hat keinen Zugriff auf die Zwischenablage. Darum zeigen wir den Text in
-- einem markierten Eingabefeld, Strg+C kopiert ihn (wie bei der Gildeninfo).
local ADDON, ns = ...
local L = ns.L

local dlg = CreateFrame("Frame", "GuildPrideCopyFrame", UIParent, "BackdropTemplate")
dlg:SetSize(640, 420)
dlg:SetPoint("CENTER")
dlg:SetFrameStrata("DIALOG")
dlg:SetMovable(true); dlg:EnableMouse(true)
dlg:RegisterForDrag("LeftButton")
dlg:SetScript("OnDragStart", dlg.StartMoving)
dlg:SetScript("OnDragStop", dlg.StopMovingOrSizing)
dlg:SetClampedToScreen(true)
dlg:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
dlg:SetBackdropColor(0.15, 0.12, 0.10, 0.95)
dlg:Hide()
tinsert(UISpecialFrames, "GuildPrideCopyFrame")   -- ESC schließt

local title = dlg:CreateFontString(nil, "OVERLAY", "GPFont_TextBold")
title:SetPoint("TOPLEFT", 14, -12)

local close = CreateFrame("Button", nil, dlg, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", -2, -2)

local scroll = ns.NewScroll(dlg)
scroll:SetPoint("TOPLEFT", 12, -34)
scroll:SetPoint("BOTTOMRIGHT", -34, 44)
local box = CreateFrame("EditBox", nil, scroll)
box:SetMultiLine(true)
box:SetAutoFocus(false)
box:SetFontObject(GPFont_Text)
box:SetWidth(580)
scroll:SetScrollChild(box)
local boxBg = scroll:CreateTexture(nil, "BACKGROUND")
boxBg:SetAllPoints(); boxBg:SetColorTexture(0.16, 0.12, 0.09, 0.45)

local hint = dlg:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
hint:SetPoint("BOTTOMLEFT", 14, 18)
hint:SetText(L["Strg+C kopiert den markierten Text. Mit der Maus kannst du auch nur einen Teil markieren."])

local bAll = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
bAll:SetSize(140, 24); bAll:SetPoint("BOTTOMRIGHT", -12, 12)
bAll:SetText(L["Alles markieren"])
bAll:SetScript("OnClick", function() box:SetFocus(); box:HighlightText() end)

-- Nur lesen: Eingaben sofort zurücksetzen, Markieren bleibt möglich
local current = ""
box:SetScript("OnTextChanged", function(self, userInput)
    if userInput then
        local pos = self:GetCursorPosition()
        self:SetText(current)
        self:SetCursorPosition(math.min(pos, #current))
    end
end)
box:SetScript("OnEscapePressed", function() dlg:Hide() end)
scroll:SetScript("OnMouseDown", function() box:SetFocus() end)

-- Text im Kopierfenster zeigen, komplett markiert
function ns.ShowCopy(heading, text)
    current = text or ""
    title:SetText(heading or L["Text kopieren"])
    dlg:Show()
    box:SetText(current)
    box:SetFocus()
    box:HighlightText()
    scroll:SetVerticalScroll(0)
end

-- Farb-, Link- und Bildcodes entfernen: kopiert wird nur der lesbare Text
local function Plain(s)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:|]*:", ""):gsub("|r", "")
    s = s:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    return s
end
ns.PlainText = Plain

-- Klick auf [GuildPride] vor einer Meldung: nur diese eine Zeile kopieren.
-- Blizzard leitet "addon:"-Links als Ereignis "SetItemRef" weiter.
local function OnLink(_, link)
    if type(link) ~= "string" or (issecretvalue and issecretvalue(link)) then return end
    local id = link:match("^addon:GuildPride:copy:(%d+)$")
    if not id then return end
    local msg = ns.printLog and ns.printLog[tonumber(id)]
    if type(msg) ~= "string" or (issecretvalue and issecretvalue(msg)) then
        ns.Print(L["Diese Meldung ist zu alt und lässt sich nicht mehr kopieren."])
        return
    end
    ns.ShowCopy(L["GuildPride-Meldung kopieren"], Plain(msg))
end
if EventRegistry and EventRegistry.RegisterCallback then
    EventRegistry:RegisterCallback("SetItemRef", OnLink, dlg)
end
