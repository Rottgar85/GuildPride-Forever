-- GuildPride: wählbare Layouts für das Hauptfenster
--   forge = "Klassisch"  (Standard: breite Seitenleiste, Banner oben)
--   rail  = "Icon-Leiste" (schmale Leiste mit Symbolen, mehr Platz, flach)
--   book  = "Gildenbuch"  (Ledereinband, Lesezeichen-Bänder, dunkle Seiten)
-- Das Layout ändert nur Rahmen, Menü und Hintergrund; die Seiten selbst und
-- die Farben (Style) bleiben gleich und lassen sich frei kombinieren.
-- Umschalten geht sofort, ohne /reload.
local ADDON, ns = ...
local L = ns.L
local P = ns.UIParts
if not P then return end

local MEDIA = ns.MEDIA
local WHITE = "Interface\\Buttons\\WHITE8X8"
local frame = P.frame

local LAYOUTS = {
    { key = "forge", name = L["Klassisch"],    w = 860, h = 580, side = 180, header = 96 },
    { key = "rail",  name = L["Icon-Leiste"], w = 744, h = 600, side = 64,  header = 70 },
    { key = "book",  name = L["Gildenbuch"],  w = 900, h = 600, side = 196, header = 88 },
}
local byKey = {}
for _, l in ipairs(LAYOUTS) do byKey[l.key] = l end

local function Current()
    local key = GuildPrideDB and GuildPrideDB.layout
    return byKey[key] or LAYOUTS[1]
end
ns.CurrentLayout = function() return Current().key end

-- Symbole für die Icon-Leiste (nach fester Standard-Ordnung der Reiter)
local ICONS = {
    ["10"] = "Interface\\Icons\\INV_Misc_Book_09",
    ["20"] = "Interface\\Icons\\INV_Letter_15",
    ["30"] = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    ["40"] = "Interface\\Icons\\Ability_Warrior_BattleShout",
    ["50"] = "Interface\\Icons\\INV_Misc_Note_01",
    ["55"] = "Interface\\Icons\\Trade_BlackSmithing",
    ["60"] = "Interface\\Icons\\INV_Misc_Coin_02",
    ["65"] = "Interface\\Icons\\INV_Misc_Spyglass_02",
    ["70"] = "Interface\\Icons\\INV_Scroll_03",
    ["80"] = "Interface\\Icons\\INV_Crown_01",
    ["90"] = "Interface\\Icons\\INV_Misc_Gear_01",
}
-- Farben der Lesezeichen-Bänder im Gildenbuch
local RIBBONS = {
    ["10"] = { 0.56, 0.17, 0.12 }, ["20"] = { 0.34, 0.42, 0.21 }, ["30"] = { 0.17, 0.32, 0.45 },
    ["40"] = { 0.17, 0.32, 0.45 }, ["50"] = { 0.17, 0.32, 0.45 }, ["55"] = { 0.55, 0.36, 0.11 },
    ["60"] = { 0.56, 0.17, 0.12 }, ["65"] = { 0.56, 0.17, 0.12 }, ["70"] = { 0.36, 0.23, 0.38 },
    ["80"] = { 0.30, 0.30, 0.30 }, ["90"] = { 0.28, 0.19, 0.11 },
}
local RIBBON_DEFAULT = { 0.40, 0.27, 0.15 }

---------------------------------------------------------------------
-- Zusätzliche Teile (nur in bestimmten Layouts sichtbar)
---------------------------------------------------------------------
-- Gildenbuch: Seite und Schatten am Buchrücken
local page = frame:CreateTexture(nil, "BACKGROUND", nil, -7)
page:SetTexture(WHITE)
local spine = frame:CreateTexture(nil, "BACKGROUND", nil, -4)
spine:SetTexture(WHITE)
spine:SetWidth(26)
local pageEdge = frame:CreateTexture(nil, "BORDER")
pageEdge:SetTexture(WHITE)
local kicker = frame:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
kicker:SetText(L["DAS BUCH DER GILDE"])
-- Icon-Leiste: Trennlinie unter der Kopfzeile und neben der Leiste
local headLine = frame:CreateTexture(nil, "BORDER")
local railLine = frame:CreateTexture(nil, "BORDER")
ns.Paint(headLine, "accent", 0.35)
ns.Paint(railLine, "accent", 0.35)

local function Gradient(tex, orient, a, b)
    -- Farbverlauf (neuere Spielversionen: Farbobjekte), sonst einfarbig
    if CreateColor and tex.SetGradient then
        local ok = pcall(tex.SetGradient, tex, orient, CreateColor(a[1], a[2], a[3], a[4]), CreateColor(b[1], b[2], b[3], b[4]))
        if ok then return end
    end
    tex:SetColorTexture(a[1], a[2], a[3], a[4])
end

---------------------------------------------------------------------
-- Reiter je Layout (wird von LayoutTabs/MarkTabs in GuildPrideUI.lua gerufen)
---------------------------------------------------------------------
local function TabExtras(tab)
    if tab.gpIcon then return end
    tab.gpIcon = tab:CreateTexture(nil, "ARTWORK")
    tab.gpIcon:SetPoint("CENTER")
    tab.gpIcon:SetSize(28, 28)
    tab.gpIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tab.gpMark = tab:CreateTexture(nil, "OVERLAY")
    tab.gpMark:SetPoint("TOPLEFT", 0, -6); tab.gpMark:SetPoint("BOTTOMLEFT", 0, 6)
    tab.gpMark:SetWidth(3)
    ns.Paint(tab.gpMark, "ember")
    tab.gpDot = tab:CreateTexture(nil, "OVERLAY")
    tab.gpDot:SetSize(8, 8); tab.gpDot:SetPoint("TOPRIGHT", -5, -5)
    tab.gpDot:SetColorTexture(1, 0.55, 0.25, 1)
    -- Icon-Leiste: Name als Tooltip
    tab:HookScript("OnEnter", function(self)
        if Current().key ~= "rail" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.label or "")
        GameTooltip:Show()
    end)
    tab:HookScript("OnLeave", function() if GameTooltip:IsOwned(tab) then GameTooltip:Hide() end end)
end

local function HasBadge(tab)
    local t = tab.text and tab.text:GetText()
    return t and t:find("ff8c40", 1, true) and true or false
end

-- Größe und Platz eines Reiters; true = selbst gesetzt (sonst Standard)
function ns.LayoutTab(tab, index, bottom)
    TabExtras(tab)
    local l = Current()
    tab.gpIcon:Hide(); tab.gpMark:Hide(); tab.gpDot:Hide()
    tab.text:Show()
    tab.text:ClearAllPoints()
    if l.key == "rail" then
        tab:SetSize(44, 44)
        tab.text:Hide()
        tab.gpIcon:SetTexture(ICONS[tab.key] or "Interface\\Icons\\INV_Misc_QuestionMark")
        tab.gpIcon:Show()
        tab.gpDot:SetShown(HasBadge(tab))
        if bottom then
            tab:SetPoint("BOTTOM", frame, "BOTTOMLEFT", l.side / 2 + 1, 14 + index * 50)
        else
            tab:SetPoint("TOP", frame, "TOPLEFT", l.side / 2 + 1, -66 - index * 50)
        end
        return true
    elseif l.key == "book" then
        tab:SetSize(l.side - 26, 34)
        tab.text:SetPoint("LEFT", 16, 0)
        if bottom then
            tab:SetPoint("BOTTOMLEFT", 14, 22 + index * 40)
        else
            tab:SetPoint("TOPLEFT", 14, -150 - index * 40)
        end
        return true
    end
    tab:SetSize(l.side - 16, 36)
    tab.text:SetPoint("LEFT", 18, 0)
    return false
end

-- Aussehen aktiv/inaktiv
function ns.LayoutMarkTab(tab, on)
    TabExtras(tab)
    local key = Current().key
    if key == "rail" then
        if on then tab.bgTex:SetColorTexture(1, 0.55, 0.25, 0.14) else tab.bgTex:SetColorTexture(0, 0, 0, 0) end
        tab.gpMark:SetShown(on)
        tab.gpIcon:SetDesaturated(not on)
        tab.gpIcon:SetAlpha(on and 1 or 0.75)
        tab.gpDot:SetShown(HasBadge(tab))
    elseif key == "book" then
        local c = RIBBONS[tab.key] or RIBBON_DEFAULT
        local f = on and 1 or 0.62
        tab.bgTex:SetColorTexture(c[1] * f, c[2] * f, c[3] * f, 1)
        tab.text:SetTextColor(0.97, 0.92, 0.82)
        -- aktives Band ragt ein Stück in die Seite
        local p, rel, rp, x, y = tab:GetPoint(1)
        if p then tab:SetPoint(p, rel, rp, on and 24 or 14, y) end
    end
end

-- Größe des Wappens oben links
function ns.CrestSize(faction)
    local key = Current().key
    if key == "rail" then return 38 end
    if key == "book" then return faction and 92 or 76 end
    return faction and 104 or 84
end

---------------------------------------------------------------------
-- Layout anwenden
---------------------------------------------------------------------
function ns.ApplyLayout(key)
    if key and byKey[key] then GuildPrideDB.layout = key end
    local l = Current()
    local rail, book = l.key == "rail", l.key == "book"
    frame:SetSize(l.w, l.h)

    -- Hintergrund
    if rail then
        P.bg:SetColorTexture(0.075, 0.065, 0.08, 0.97)
    elseif book then
        P.bg:SetColorTexture(0.20, 0.12, 0.07, 1)   -- Ledereinband
    else
        P.bg:SetTexture(MEDIA .. "bg")
    end
    page:SetShown(book); spine:SetShown(book); pageEdge:SetShown(book); kicker:SetShown(book)
    if book then
        page:ClearAllPoints()
        page:SetPoint("TOPLEFT", l.side + 4, -12); page:SetPoint("BOTTOMRIGHT", -12, 12)
        Gradient(page, "VERTICAL", { 0.12, 0.09, 0.06, 1 }, { 0.17, 0.13, 0.09, 1 })
        spine:ClearAllPoints()
        spine:SetPoint("TOPLEFT", page, "TOPLEFT"); spine:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT")
        Gradient(spine, "HORIZONTAL", { 0, 0, 0, 0.55 }, { 0, 0, 0, 0 })
        pageEdge:ClearAllPoints()
        pageEdge:SetPoint("TOPLEFT", page, "TOPLEFT", -1, 1); pageEdge:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", -1, -1)
        pageEdge:SetWidth(2); pageEdge:SetColorTexture(0.45, 0.32, 0.18, 1)
    end

    -- Seitenleiste
    P.side:SetWidth(l.side)
    if rail then
        P.side:SetColorTexture(0.045, 0.04, 0.05, 1)
    elseif book then
        P.side:SetColorTexture(0, 0, 0, 0)   -- Leder des Einbands
    else
        P.side:SetTexture(MEDIA .. "sidebar")
    end
    railLine:SetShown(rail)
    if rail then
        railLine:ClearAllPoints()
        railLine:SetPoint("TOPLEFT", l.side + 2, -2); railLine:SetPoint("BOTTOMLEFT", l.side + 2, 2)
        railLine:SetWidth(1)
    end

    -- Wappen und Version
    P.crestGlow:SetShown(not rail)
    P.crestGlow:ClearAllPoints()
    P.crestGlow:SetPoint("TOP", frame, "TOPLEFT", l.side / 2 + 2, book and -18 or -10)
    P.crestGlow:SetSize(book and 124 or 140, book and 124 or 140)
    P.factionLogo:ClearAllPoints()
    if rail then
        P.factionLogo:SetPoint("TOP", frame, "TOPLEFT", l.side / 2 + 1, -14)
    else
        P.factionLogo:SetPoint("CENTER", P.crestGlow, "CENTER", 0, 0)
    end
    P.versionText:SetShown(not rail)
    P.versionText:ClearAllPoints()
    P.versionText:SetPoint("BOTTOM", frame, "BOTTOMLEFT", l.side / 2 + 2, book and 6 or 14)

    -- Kopfzeile
    P.header:SetShown(l.key == "forge")
    P.header:ClearAllPoints()
    P.header:SetPoint("TOPLEFT", l.side + 2, -2); P.header:SetPoint("TOPRIGHT", -2, -2)
    P.header:SetHeight(l.header)
    headLine:SetShown(rail)
    if rail then
        headLine:ClearAllPoints()
        headLine:SetPoint("TOPLEFT", l.side + 2, -l.header); headLine:SetPoint("TOPRIGHT", -2, -l.header)
        headLine:SetHeight(1)
    end
    P.title:ClearAllPoints()
    P.title:SetFontObject(rail and GPFont_Large or GPFont_Huge)
    if rail then
        P.title:SetPoint("TOPLEFT", frame, "TOPLEFT", l.side + 20, -14)
    elseif book then
        kicker:ClearAllPoints()
        kicker:SetPoint("TOPLEFT", frame, "TOPLEFT", l.side + 30, -22)
        P.title:SetPoint("TOPLEFT", kicker, "BOTTOMLEFT", 0, -4)
    else
        P.title:SetPoint("TOPLEFT", P.header, "TOPLEFT", 24, -20)
    end
    P.pageTitle:ClearAllPoints()
    P.pageTitle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -48, rail and -22 or (book and -30 or -26))

    -- Rahmen
    for _, t in ipairs(frame.gpCorners or {}) do t:SetShown(not rail) end

    -- Inhalt
    P.content:ClearAllPoints()
    if rail then
        P.content:SetPoint("TOPLEFT", l.side + 16, -l.header - 10); P.content:SetPoint("BOTTOMRIGHT", -16, 14)
    elseif book then
        P.content:SetPoint("TOPLEFT", l.side + 30, -l.header - 6); P.content:SetPoint("BOTTOMRIGHT", -24, 22)
    else
        P.content:SetPoint("TOPLEFT", l.side + 14, -l.header - 12); P.content:SetPoint("BOTTOMRIGHT", -14, 14)
    end

    -- Reiter neu anordnen, Wappen, Farben (Style) neu auftragen
    P.LayoutTabs()
    if ns.ApplyTheme then ns.ApplyTheme() end   -- färbt Texturen neu und ruft MarkTabs
    if P.MarkTabs then P.MarkTabs() end
    local size = ns.CrestSize(UnitFactionGroup("player") == "Alliance" or UnitFactionGroup("player") == "Horde")
    P.factionLogo:SetSize(size, size)
    if ns.MarkLayout then ns.MarkLayout() end
end

-- Hinweis-Punkt der Icon-Leiste aktuell halten, wenn ein Reiter einen Zusatz bekommt
local setBadge = ns.SetTabBadge
if setBadge then
    ns.SetTabBadge = function(...)
        setBadge(...)
        if Current().key == "rail" then
            for _, tab in ipairs(P.tabs) do if tab.gpDot then tab.gpDot:SetShown(HasBadge(tab)) end end
        end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() ns.ApplyLayout() end)

---------------------------------------------------------------------
-- Auswahl in den Einstellungen (unter Style und eigener Farbe)
---------------------------------------------------------------------
local settings = P.settings
if not settings then return end
local label = settings:CreateFontString(nil, "OVERLAY", "GPFont_TextBold")
label:SetPoint("TOPLEFT", 4, -82)
label:SetText(L["Layout"])
local hint = settings:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
hint:SetPoint("LEFT", label, "RIGHT", 10, 0)
hint:SetText(L["Aufbau des Fensters – frei kombinierbar mit dem Style"])
local buttons = {}
for i, l in ipairs(LAYOUTS) do
    local b = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
    b:SetSize(130, 24)
    b:SetPoint("TOPLEFT", 4 + (i - 1) * 136, -100)
    b:SetText(l.name)
    b:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        ns.ApplyLayout(l.key)
    end)
    if ns.SkinButton then pcall(ns.SkinButton, b) end
    b.key = l.key
    buttons[i] = b
end
function ns.MarkLayout()
    local cur = Current().key
    for _, b in ipairs(buttons) do
        if b.gpBg then b.gpBg:SetTexture(MEDIA .. (b.key == cur and "nav_active" or "nav")) end
        b:SetNormalFontObject(b.key == cur and GPFont_Normal or GPFont_Button)
    end
end
