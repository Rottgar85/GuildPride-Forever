-- GuildPride: wählbare Layouts für das Hauptfenster
--   forge = "Klassisch"  (Standard: breite Seitenleiste, Banner oben)
--   rail  = "Icon-Leiste" (schmale Leiste mit Symbolen, mehr Platz, flach)
--   book  = "Gildenbuch"  (aufgeschlagenes Buch: links Inhaltsverzeichnis = Menü,
--                          rechts die Seite, Buchrücken, Seitenkanten, Lesebändchen)
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
    { key = "book",  name = L["Gildenbuch"],  w = 980, h = 620, side = 260, header = 74 },
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
-- Gildenbuch: alle Teile in einer Tabelle (nur dort sichtbar)
local COVER, LPAGE, GUTTER = 16, 244, 14
local book = {}
local function BookTex(layer, sub)
    local t = frame:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(WHITE)
    book[#book + 1] = t
    return t
end
local leftPage, rightPage = BookTex("BACKGROUND", -7), BookTex("BACKGROUND", -7)
local gutter = BookTex("BACKGROUND", -6)
local shadowL, shadowR = BookTex("BACKGROUND", -5), BookTex("BACKGROUND", -5)
local rims = { BookTex("BORDER"), BookTex("BORDER"), BookTex("BORDER"), BookTex("BORDER") }
local stacks = {}
for i = 1, 9 do stacks[i] = BookTex("BACKGROUND", -6) end
local ribbon, ribbonTip = BookTex("BACKGROUND", -8), BookTex("BACKGROUND", -8)
local divider = BookTex("ARTWORK")
local orn1, orn2 = BookTex("ARTWORK"), BookTex("ARTWORK")
local kicker = frame:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
kicker:SetText(L["DAS BUCH DER GILDE"])
book[#book + 1] = kicker
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII" }

local function BookGeometry(l)
    local lpX, rpX = COVER, COVER + LPAGE + GUTTER
    leftPage:ClearAllPoints()
    leftPage:SetPoint("TOPLEFT", lpX, -COVER); leftPage:SetPoint("BOTTOMLEFT", lpX, COVER); leftPage:SetWidth(LPAGE)
    rightPage:ClearAllPoints()
    rightPage:SetPoint("TOPLEFT", rpX, -COVER); rightPage:SetPoint("BOTTOMRIGHT", -COVER, COVER)
    -- Papier: oben etwas heller, zur Kante hin dunkler
    Gradient(leftPage, "VERTICAL", { 0.17, 0.13, 0.09, 1 }, { 0.24, 0.19, 0.13, 1 })
    Gradient(rightPage, "VERTICAL", { 0.17, 0.13, 0.09, 1 }, { 0.24, 0.19, 0.13, 1 })
    gutter:ClearAllPoints()
    gutter:SetPoint("TOPLEFT", lpX + LPAGE, -COVER + 4); gutter:SetPoint("BOTTOMLEFT", lpX + LPAGE, COVER - 4)
    gutter:SetWidth(GUTTER); gutter:SetColorTexture(0.07, 0.05, 0.03, 1)
    -- Wölbung zum Buchrücken hin
    shadowL:ClearAllPoints()
    shadowL:SetPoint("TOPRIGHT", leftPage, "TOPRIGHT"); shadowL:SetPoint("BOTTOMRIGHT", leftPage, "BOTTOMRIGHT"); shadowL:SetWidth(30)
    Gradient(shadowL, "HORIZONTAL", { 0, 0, 0, 0 }, { 0, 0, 0, 0.6 })
    shadowR:ClearAllPoints()
    shadowR:SetPoint("TOPLEFT", rightPage, "TOPLEFT"); shadowR:SetPoint("BOTTOMLEFT", rightPage, "BOTTOMLEFT"); shadowR:SetWidth(34)
    Gradient(shadowR, "HORIZONTAL", { 0, 0, 0, 0.6 }, { 0, 0, 0, 0 })
    -- Goldkante im Einband
    local rp = { { "TOPLEFT", "TOPRIGHT", 0, 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 1 },
                 { "TOPLEFT", "BOTTOMLEFT", 1, 0 }, { "TOPRIGHT", "BOTTOMRIGHT", 1, 0 } }
    for i, r in ipairs(rims) do
        local p1, p2, vertical = rp[i][1], rp[i][2], rp[i][3] == 1
        r:ClearAllPoints()
        r:SetPoint(p1, p1:find("RIGHT") and -5 or 5, p1:find("BOTTOM") and 5 or -5)
        r:SetPoint(p2, p2:find("RIGHT") and -5 or 5, p2:find("BOTTOM") and 5 or -5)
        if vertical then r:SetWidth(1) else r:SetHeight(1) end
        r:SetColorTexture(0.78, 0.60, 0.32, 0.55)
    end
    -- Seitenkanten (Papierstapel) außen links, rechts und unten
    for i = 1, 3 do
        local t = stacks[i]
        t:ClearAllPoints()
        t:SetPoint("TOPRIGHT", leftPage, "TOPLEFT", -(i * 3 - 2), -(i * 2)); t:SetPoint("BOTTOMRIGHT", leftPage, "BOTTOMLEFT", -(i * 3 - 2), i * 2)
        t:SetWidth(1); t:SetColorTexture(0.62, 0.53, 0.40, 0.9 - i * 0.2)
        t = stacks[i + 3]
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", rightPage, "TOPRIGHT", i * 3 - 2, -(i * 2)); t:SetPoint("BOTTOMLEFT", rightPage, "BOTTOMRIGHT", i * 3 - 2, i * 2)
        t:SetWidth(1); t:SetColorTexture(0.62, 0.53, 0.40, 0.9 - i * 0.2)
        t = stacks[i + 6]
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", leftPage, "BOTTOMLEFT", i * 2, -(i * 3 - 2)); t:SetPoint("TOPRIGHT", rightPage, "BOTTOMRIGHT", -(i * 2), -(i * 3 - 2))
        t:SetHeight(1); t:SetColorTexture(0.62, 0.53, 0.40, 0.9 - i * 0.2)
    end
    -- Lesebändchen hängt unten aus dem Buch
    ribbon:ClearAllPoints()
    ribbon:SetPoint("TOP", frame, "BOTTOMRIGHT", -110, COVER + 6); ribbon:SetSize(14, 52)
    ribbon:SetColorTexture(0.58, 0.12, 0.10, 1)
    ribbonTip:ClearAllPoints()
    ribbonTip:SetPoint("TOP", ribbon, "BOTTOM", 0, 2); ribbonTip:SetSize(10, 10)
    ribbonTip:SetColorTexture(0.58, 0.12, 0.10, 1)
    if ribbonTip.SetRotation then ribbonTip:SetRotation(math.pi / 4) end
    -- Kopf der linken Seite: Wappen, "Das Buch der Gilde", Name, Mitglieder, Zierlinie
    kicker:ClearAllPoints()
    kicker:SetPoint("TOP", frame, "TOPLEFT", lpX + LPAGE / 2, -104)
    divider:ClearAllPoints()
    divider:SetPoint("TOP", frame, "TOPLEFT", lpX + LPAGE / 2, -176); divider:SetSize(150, 1)
    divider:SetColorTexture(0.78, 0.60, 0.32, 0.6)
end
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
    tab.gpNum = tab:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    tab.gpNum:SetPoint("RIGHT", -6, 0)
    tab.gpLine = tab:CreateTexture(nil, "ARTWORK")
    tab.gpLine:SetPoint("BOTTOMLEFT", 10, 0); tab.gpLine:SetPoint("BOTTOMRIGHT", -4, 0); tab.gpLine:SetHeight(1)
    tab.gpLine:SetColorTexture(0.78, 0.60, 0.32, 0.22)
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
    tab.gpIcon:Hide(); tab.gpMark:Hide(); tab.gpDot:Hide(); tab.gpNum:Hide(); tab.gpLine:Hide()
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
        -- Inhaltsverzeichnis: Eintrag, Zierlinie, römische Kapitelzahl
        tab:SetSize(LPAGE - 40, 30)
        tab.text:SetPoint("LEFT", 14, 0)
        tab.gpNum:SetShown(not bottom)
        tab.gpNum:SetText(ROMAN[index + 1] or "")
        tab.gpLine:Show()
        if bottom then
            tab:SetPoint("BOTTOMLEFT", COVER + 20, COVER + 26 + index * 34)
        else
            tab:SetPoint("TOPLEFT", COVER + 20, -190 - index * 34)
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
        -- aktiver Eintrag: Lesezeichen-Band links, Schrift in Stilfarbe
        local t = ns.Theme()
        tab.bgTex:SetColorTexture(1, 0.8, 0.5, on and 0.07 or 0)
        tab.gpMark:SetShown(on)
        local c = RIBBONS[tab.key] or RIBBON_DEFAULT
        tab.gpMark:SetColorTexture(c[1] * 1.4, c[2] * 1.4, c[3] * 1.4, 1)
        tab.gpMark:SetWidth(on and 5 or 3)
        if on then tab.text:SetTextColor(t.title[1], t.title[2], t.title[3])
        else tab.text:SetTextColor(0.90, 0.84, 0.74) end
    end
end

-- Größe des Wappens oben links
function ns.CrestSize(faction)
    local key = Current().key
    if key == "rail" then return 38 end
    if key == "book" then return faction and 70 or 60 end
    return faction and 104 or 84
end

---------------------------------------------------------------------
-- Layout anwenden
---------------------------------------------------------------------
function ns.ApplyLayout(key)
    if key and byKey[key] then GuildPrideDB.layout = key end
    local l = Current()
    local rail, isBook = l.key == "rail", l.key == "book"
    frame:SetSize(l.w, l.h)

    -- Hintergrund
    if rail then
        P.bg:SetColorTexture(0.075, 0.065, 0.08, 0.97)
    elseif isBook then
        P.bg:SetColorTexture(0.26, 0.14, 0.08, 1)   -- Ledereinband
    else
        P.bg:SetTexture(MEDIA .. "bg")
    end
    for _, t in ipairs(book) do t:SetShown(isBook) end
    if isBook then BookGeometry(l) end

    -- Seitenleiste
    P.side:SetWidth(l.side)
    if rail then
        P.side:SetColorTexture(0.045, 0.04, 0.05, 1)
    elseif isBook then
        P.side:SetColorTexture(0, 0, 0, 0)   -- linke Buchseite liegt darunter
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
    P.crestGlow:SetShown(l.key == "forge")
    P.crestGlow:ClearAllPoints()
    P.crestGlow:SetPoint("TOP", frame, "TOPLEFT", l.side / 2 + 2, -10)
    P.crestGlow:SetSize(140, 140)
    P.factionLogo:ClearAllPoints()
    if rail then
        P.factionLogo:SetPoint("TOP", frame, "TOPLEFT", l.side / 2 + 1, -14)
    elseif isBook then
        P.factionLogo:SetPoint("TOP", frame, "TOPLEFT", COVER + LPAGE / 2, -28)
    else
        P.factionLogo:SetPoint("CENTER", P.crestGlow, "CENTER", 0, 0)
    end
    P.versionText:SetShown(not rail)
    P.versionText:ClearAllPoints()
    if isBook then
        P.versionText:SetPoint("BOTTOM", frame, "BOTTOMLEFT", COVER + LPAGE / 2, COVER + 8)
    else
        P.versionText:SetPoint("BOTTOM", frame, "BOTTOMLEFT", l.side / 2 + 2, 14)
    end

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
    P.title:SetFontObject((rail or isBook) and GPFont_Large or GPFont_Huge)
    P.title:SetWidth(isBook and (LPAGE - 24) or 0)
    P.title:SetJustifyH(isBook and "CENTER" or "LEFT")
    P.subtitle:ClearAllPoints()
    P.subtitle:SetJustifyH(isBook and "CENTER" or "LEFT")
    if rail then
        P.title:SetPoint("TOPLEFT", frame, "TOPLEFT", l.side + 20, -14)
        P.subtitle:SetPoint("TOPLEFT", P.title, "BOTTOMLEFT", 2, -6)
    elseif isBook then
        P.title:SetPoint("TOP", kicker, "BOTTOM", 0, -8)
        P.subtitle:SetPoint("TOP", P.title, "BOTTOM", 0, -6)
    else
        P.title:SetPoint("TOPLEFT", P.header, "TOPLEFT", 24, -20)
        P.subtitle:SetPoint("TOPLEFT", P.title, "BOTTOMLEFT", 2, -6)
    end
    P.pageTitle:ClearAllPoints()
    if isBook then
        -- Seitentitel mittig über der rechten Seite, mit Zierstrichen
        local rpX = COVER + LPAGE + GUTTER
        P.pageTitle:SetPoint("TOP", frame, "TOPLEFT", rpX + (l.w - COVER - rpX) / 2, -32)
        orn1:ClearAllPoints(); orn1:SetPoint("RIGHT", P.pageTitle, "LEFT", -12, 0); orn1:SetSize(70, 1)
        orn2:ClearAllPoints(); orn2:SetPoint("LEFT", P.pageTitle, "RIGHT", 12, 0); orn2:SetSize(70, 1)
        orn1:SetColorTexture(0.78, 0.60, 0.32, 0.6); orn2:SetColorTexture(0.78, 0.60, 0.32, 0.6)
    else
        P.pageTitle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -48, rail and -22 or -26)
    end

    -- Rahmen
    for _, t in ipairs(frame.gpCorners or {}) do t:SetShown(not rail) end
    for _, t in ipairs(frame.gpBorder or {}) do t:SetShown(not isBook) end

    -- Inhalt
    P.content:ClearAllPoints()
    if rail then
        P.content:SetPoint("TOPLEFT", l.side + 16, -l.header - 10); P.content:SetPoint("BOTTOMRIGHT", -16, 14)
    elseif isBook then
        P.content:SetPoint("TOPLEFT", COVER + LPAGE + GUTTER + 22, -l.header); P.content:SetPoint("BOTTOMRIGHT", -COVER - 20, COVER + 14)
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
