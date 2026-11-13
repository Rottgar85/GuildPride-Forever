-- GuildPride: wählbare Layouts für das Hauptfenster
--   forge = "Klassisch"   (Standard: breite Seitenleiste, Banner oben)
--   rail  = "Icon-Leiste" (schmale Leiste mit Symbolen, mehr Platz, flach)
--   book  = "Gildenbuch"  (aufgeschlagenes Buch auf hellem Pergament: links eine
--                          feste Seite mit Aushang, Feldzug und Chronik, rechts
--                          die jeweilige Seite, Register-Reiter als Menü rechts)
-- Das Layout ändert Rahmen, Menü und Hintergrund; die Seiten selbst und die
-- Farben (Style) bleiben gleich und lassen sich frei kombinieren. Im Gildenbuch
-- wird die Schrift zu dunkler Tinte (GuildPrideInk.lua). Umschalten ohne /reload.
local ADDON, ns = ...
local L = ns.L
local P = ns.UIParts
if not P then return end

local MEDIA = ns.MEDIA
local WHITE = "Interface\\Buttons\\WHITE8X8"
local frame = P.frame

local LAYOUTS = {
    { key = "forge", name = L["Klassisch"],   w = 860,  h = 580, side = 180, header = 96 },
    { key = "rail",  name = L["Icon-Leiste"], w = 744,  h = 600, side = 64,  header = 70 },
    { key = "book",  name = L["Gildenbuch"],  w = 1052, h = 640, side = 340, header = 76 },
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
-- Lesezeichen im Gildenbuch: Farbe und kurze Aufschrift
local RIBBONS = {
    ["10"] = { 0.61, 0.18, 0.13 }, ["20"] = { 0.36, 0.43, 0.23 }, ["30"] = { 0.18, 0.33, 0.44 },
    ["40"] = { 0.18, 0.33, 0.44 }, ["50"] = { 0.18, 0.33, 0.44 }, ["55"] = { 0.54, 0.35, 0.12 },
    ["60"] = { 0.61, 0.18, 0.13 }, ["65"] = { 0.61, 0.18, 0.13 }, ["70"] = { 0.36, 0.24, 0.37 },
    ["80"] = { 0.29, 0.29, 0.29 }, ["90"] = { 0.30, 0.20, 0.12 },
}
local RIBBON_DEFAULT = { 0.40, 0.27, 0.15 }
local SHORT = {
    ["10"] = L["START"], ["20"] = L["GILDE"], ["30"] = L["PLANEN"], ["40"] = L["SUCHE"], ["50"] = L["UMFRAGE"],
    ["55"] = L["BERUFE"], ["60"] = L["CHRONIK"], ["65"] = L["ZIELE"], ["70"] = L["INFO"], ["80"] = L["RAT"],
    ["90"] = L["OPTION"],
}

-- Farbverlauf (neuere Spielversionen: Farbobjekte), sonst einfarbig
local function Gradient(tex, orient, a, b)
    if CreateColor and tex.SetGradient then
        tex:SetColorTexture(1, 1, 1, 1)
        local ok = pcall(tex.SetGradient, tex, orient, CreateColor(a[1], a[2], a[3], a[4]), CreateColor(b[1], b[2], b[3], b[4]))
        if ok then return end
    end
    tex:SetColorTexture((a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2, (a[4] + b[4]) / 2)
end


---------------------------------------------------------------------
-- Gildenbuch: alle Teile (nur dort sichtbar)
---------------------------------------------------------------------
local COVER, LPAGE, GUTTER = 18, 310, 12
local book = {}
local function BookTex(layer, sub)
    local t = frame:CreateTexture(nil, layer, nil, sub)
    t:SetTexture(WHITE)
    book[#book + 1] = t
    return t
end
local leftPage, rightPage = BookTex("BACKGROUND", -7), BookTex("BACKGROUND", -7)
local crease = BookTex("BACKGROUND", -6)
local shadowL, shadowR = BookTex("BACKGROUND", -5), BookTex("BACKGROUND", -5)
local rims = { BookTex("BORDER"), BookTex("BORDER"), BookTex("BORDER"), BookTex("BORDER") }
local stacks = {}
for i = 1, 9 do stacks[i] = BookTex("BACKGROUND", -6) end
local ribbon, ribbonTip = BookTex("BACKGROUND", -8), BookTex("BACKGROUND", -8)
local orn1, orn2 = BookTex("ARTWORK"), BookTex("ARTWORK")

-- Linke Seite: eigener Rahmen für Texte (bekommt Tinte über GuildPrideInk.lua)
local lp = CreateFrame("Frame", nil, frame)
lp:SetFrameLevel(frame:GetFrameLevel() + 2)
book[#book + 1] = lp
local function LPText(font, justify, width)
    local fs = lp:CreateFontString(nil, "OVERLAY", font)
    fs:SetJustifyH(justify or "LEFT")
    if width then fs:SetWidth(width) end
    return fs
end
local kicker = LPText("GPFont_MutedSmall", "CENTER")
kicker:SetText(L["DAS BUCH DER GILDE"])
local rule1 = lp:CreateTexture(nil, "ARTWORK")
-- Aushang
local noteBox = lp:CreateTexture(nil, "BACKGROUND")
local noteEdge = lp:CreateTexture(nil, "BACKGROUND", nil, -1)
local noteHead = LPText("GPFont_TextBold", "LEFT", LPAGE - 64)
local noteText = LPText("GPFont_Text", "LEFT", LPAGE - 64)
local noteBy = LPText("GPFont_MutedSmall", "RIGHT", LPAGE - 64)
noteText:SetSpacing(2)
-- Nächster Feldzug
local evHead = LPText("GPFont_Large")
local evSealRing = lp:CreateTexture(nil, "ARTWORK", nil, -1)
local evSeal = lp:CreateTexture(nil, "ARTWORK")
local evDay = LPText("GPFont_MutedSmall", "CENTER", 52)
local evTime = LPText("GPFont_TextBold", "CENTER", 52)
local evName = LPText("GPFont_TextBold", "LEFT", LPAGE - 130)
local evInfo = LPText("GPFont_Muted", "LEFT", LPAGE - 130)
evDay.gpNoInk, evTime.gpNoInk = true, true   -- hell auf dem roten Siegel
local evBtn = CreateFrame("Button", nil, lp, "UIPanelButtonTemplate")
evBtn:SetSize(140, 24); evBtn:SetText(L["Zum Event"])
if ns.SkinButton then pcall(ns.SkinButton, evBtn) end
-- Chronik
local chHead = LPText("GPFont_Large")
local chText = LPText("GPFont_TextSmall", "LEFT", LPAGE - 56)
chText:SetSpacing(4)
local pageNo = LPText("GPFont_MutedSmall", "CENTER", 160)

local function BookGeometry(l)
    local lpX, rpX = COVER, COVER + LPAGE + GUTTER
    leftPage:ClearAllPoints()
    leftPage:SetPoint("TOPLEFT", lpX, -COVER); leftPage:SetPoint("BOTTOMLEFT", lpX, COVER); leftPage:SetWidth(LPAGE)
    rightPage:ClearAllPoints()
    rightPage:SetPoint("TOPLEFT", rpX, -COVER); rightPage:SetPoint("BOTTOMRIGHT", -COVER, COVER)
    -- Pergament: oben heller, unten leicht gealtert
    Gradient(leftPage, "VERTICAL", { 0.86, 0.79, 0.65, 1 }, { 0.94, 0.89, 0.78, 1 })
    Gradient(rightPage, "VERTICAL", { 0.86, 0.79, 0.65, 1 }, { 0.94, 0.89, 0.78, 1 })
    -- Falz in der Mitte und Wölbung der Seiten zum Rücken hin
    crease:ClearAllPoints()
    crease:SetPoint("TOPLEFT", lpX + LPAGE, -COVER); crease:SetPoint("BOTTOMLEFT", lpX + LPAGE, COVER)
    crease:SetWidth(GUTTER); Gradient(crease, "HORIZONTAL", { 0.62, 0.52, 0.38, 1 }, { 0.70, 0.60, 0.45, 1 })
    shadowL:ClearAllPoints()
    shadowL:SetPoint("TOPRIGHT", leftPage, "TOPRIGHT"); shadowL:SetPoint("BOTTOMRIGHT", leftPage, "BOTTOMRIGHT"); shadowL:SetWidth(34)
    Gradient(shadowL, "HORIZONTAL", { 0.35, 0.24, 0.12, 0 }, { 0.35, 0.24, 0.12, 0.45 })
    shadowR:ClearAllPoints()
    shadowR:SetPoint("TOPLEFT", rightPage, "TOPLEFT"); shadowR:SetPoint("BOTTOMLEFT", rightPage, "BOTTOMLEFT"); shadowR:SetWidth(38)
    Gradient(shadowR, "HORIZONTAL", { 0.35, 0.24, 0.12, 0.45 }, { 0.35, 0.24, 0.12, 0 })
    -- Goldkante im Einband
    local rp = { { "TOPLEFT", "TOPRIGHT", false }, { "BOTTOMLEFT", "BOTTOMRIGHT", false },
                 { "TOPLEFT", "BOTTOMLEFT", true }, { "TOPRIGHT", "BOTTOMRIGHT", true } }
    for i, r in ipairs(rims) do
        local p1, p2 = rp[i][1], rp[i][2]
        r:ClearAllPoints()
        r:SetPoint(p1, p1:find("RIGHT") and -6 or 6, p1:find("BOTTOM") and 6 or -6)
        r:SetPoint(p2, p2:find("RIGHT") and -6 or 6, p2:find("BOTTOM") and 6 or -6)
        if rp[i][3] then r:SetWidth(1) else r:SetHeight(1) end
        r:SetColorTexture(0.80, 0.62, 0.32, 0.6)
    end
    -- Seitenkanten (Papierstapel) außen links, rechts und unten
    for i = 1, 3 do
        local c = { 0.80, 0.72, 0.57, 1.0 - i * 0.22 }
        local t = stacks[i]
        t:ClearAllPoints()
        t:SetPoint("TOPRIGHT", leftPage, "TOPLEFT", -(i * 3 - 2), -(i * 2)); t:SetPoint("BOTTOMRIGHT", leftPage, "BOTTOMLEFT", -(i * 3 - 2), i * 2)
        t:SetWidth(2); t:SetColorTexture(c[1], c[2], c[3], c[4])
        t = stacks[i + 3]
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", rightPage, "TOPRIGHT", i * 3 - 2, -(i * 2)); t:SetPoint("BOTTOMLEFT", rightPage, "BOTTOMRIGHT", i * 3 - 2, i * 2)
        t:SetWidth(2); t:SetColorTexture(c[1], c[2], c[3], c[4])
        t = stacks[i + 6]
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", leftPage, "BOTTOMLEFT", i * 2, -(i * 3 - 2)); t:SetPoint("TOPRIGHT", rightPage, "BOTTOMRIGHT", -(i * 2), -(i * 3 - 2))
        t:SetHeight(2); t:SetColorTexture(c[1], c[2], c[3], c[4])
    end
    -- Lesebändchen hängt unten aus dem Buch
    ribbon:ClearAllPoints()
    ribbon:SetPoint("TOP", frame, "BOTTOMLEFT", COVER + LPAGE - 40, COVER + 4); ribbon:SetSize(14, 54)
    ribbon:SetColorTexture(0.61, 0.18, 0.13, 1)
    ribbonTip:ClearAllPoints()
    ribbonTip:SetPoint("CENTER", ribbon, "BOTTOM", 0, 0); ribbonTip:SetSize(10, 10)
    ribbonTip:SetColorTexture(0.61, 0.18, 0.13, 1)
    if ribbonTip.SetRotation then ribbonTip:SetRotation(math.pi / 4) end

    -- Linke Seite: Kopf (Titel/Untertitel setzt ApplyLayout)
    lp:ClearAllPoints()
    lp:SetPoint("TOPLEFT", lpX, -COVER); lp:SetPoint("BOTTOMLEFT", lpX, COVER); lp:SetWidth(LPAGE)
    kicker:ClearAllPoints(); kicker:SetPoint("TOP", lp, "TOP", 0, -24)
    rule1:ClearAllPoints(); rule1:SetPoint("TOP", lp, "TOP", 0, -98); rule1:SetSize(LPAGE - 60, 1)
    rule1:SetColorTexture(0.55, 0.42, 0.24, 0.8)
    -- Aushang
    noteBox:ClearAllPoints(); noteBox:SetPoint("TOPLEFT", 22, -112); noteBox:SetPoint("TOPRIGHT", -22, -112); noteBox:SetHeight(138)
    noteBox:SetColorTexture(0.97, 0.94, 0.86, 1)
    noteEdge:ClearAllPoints(); noteEdge:SetPoint("TOPLEFT", noteBox, "TOPLEFT", -1, 1); noteEdge:SetPoint("BOTTOMRIGHT", noteBox, "BOTTOMRIGHT", 1, -1)
    noteEdge:SetColorTexture(0.72, 0.60, 0.39, 1)
    noteHead:ClearAllPoints(); noteHead:SetPoint("TOPLEFT", noteBox, "TOPLEFT", 10, -10)
    noteText:ClearAllPoints(); noteText:SetPoint("TOPLEFT", noteHead, "BOTTOMLEFT", 0, -6)
    noteText:SetHeight(84); noteText:SetJustifyV("TOP")
    noteBy:ClearAllPoints(); noteBy:SetPoint("BOTTOMRIGHT", noteBox, "BOTTOMRIGHT", -10, 8)
    -- Nächster Feldzug
    evHead:ClearAllPoints(); evHead:SetPoint("TOPLEFT", 22, -268)
    evSealRing:ClearAllPoints(); evSealRing:SetPoint("TOPLEFT", 24, -296); evSealRing:SetSize(64, 64)
    evSealRing:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    evSealRing:SetVertexColor(0.45, 0.13, 0.09)
    evSeal:ClearAllPoints(); evSeal:SetPoint("CENTER", evSealRing, "CENTER"); evSeal:SetSize(56, 56)
    evSeal:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    evSeal:SetVertexColor(0.61, 0.18, 0.13)
    evDay:ClearAllPoints(); evDay:SetPoint("BOTTOM", evSeal, "CENTER", 0, 2)
    evTime:ClearAllPoints(); evTime:SetPoint("TOP", evSeal, "CENTER", 0, 0)
    evDay:SetTextColor(0.98, 0.93, 0.85); evTime:SetTextColor(0.98, 0.93, 0.85)
    evName:ClearAllPoints(); evName:SetPoint("TOPLEFT", evSealRing, "TOPRIGHT", 12, -6)
    evInfo:ClearAllPoints(); evInfo:SetPoint("TOPLEFT", evName, "BOTTOMLEFT", 0, -4)
    evBtn:ClearAllPoints(); evBtn:SetPoint("TOPLEFT", evInfo, "BOTTOMLEFT", 0, -8)
    -- Chronik
    chHead:ClearAllPoints(); chHead:SetPoint("TOPLEFT", 22, -392)
    chText:ClearAllPoints(); chText:SetPoint("TOPLEFT", chHead, "BOTTOMLEFT", 2, -8)
    pageNo:ClearAllPoints(); pageNo:SetPoint("BOTTOM", lp, "BOTTOM", 0, 10)
end

-- Inhalt der linken Seite (bei jedem Öffnen und jeder Aktualisierung)
local function RefreshLeftPage()
    if Current().key ~= "book" or not GuildPrideDB then return end
    -- Aushang: Schwarzes Brett, sonst Nachricht des Tages
    local b = ns.Board and ns.Board.Current and ns.Board.Current()
    if b then
        noteHead:SetText(L["Aushang am Schwarzen Brett"])
        noteText:SetText(b.text)
        noteBy:SetText("– " .. Ambiguate(b.author or "?", "guild") .. ", " .. ns.FormatDay(b.t or 0))
    else
        noteHead:SetText(L["Nachricht des Tages"])
        local motd = ns.GuildMOTD and ns.GuildMOTD() or ""
        noteText:SetText(motd ~= "" and motd or L["Am Schwarzen Brett hängt gerade nichts."])
        noteBy:SetText("")
    end
    -- Nächster Feldzug
    evHead:SetText(L["Nächster Feldzug"])
    local nextEvent
    for _, e in pairs(ns.GuildTable("events")) do
        if e.title and not e.deleted and e.t and e.t > GetServerTime() and (not nextEvent or e.t < nextEvent.t) then nextEvent = e end
    end
    if nextEvent then
        local yes = 0
        for _, s in pairs(nextEvent.signups or {}) do if s.s == "yes" then yes = yes + 1 end end
        evDay:SetText(date("%d.%m.", nextEvent.t))
        evTime:SetText(date("%H:%M", nextEvent.t))
        evName:SetText(nextEvent.title)
        evInfo:SetText((L["%s · %d Zusagen"]):format(ns.FormatDate(nextEvent.t, "short"), yes))
    else
        evDay:SetText(""); evTime:SetText("–")
        evName:SetText(L["Kein Event geplant"])
        evInfo:SetText(L["Unter „Planen“ kann jeder eins anlegen."])
    end
    -- Chronik der Woche
    chHead:SetText(L["Chronik dieser Woche"])
    local lines, cutoff = {}, ns.WeekStart and ns.WeekStart() or 0
    for _, e in ipairs(ns.GuildLog and ns.GuildLog() or {}) do
        if #lines >= 6 then break end
        if e.t >= cutoff then lines[#lines + 1] = ("• %s %s"):format(e.who, ns.LogText(e)) end
    end
    chText:SetText(#lines > 0 and table.concat(lines, "\n") or L["Diese Woche ist noch nichts passiert."])
    pageNo:SetText("— GuildPride " .. (ns.VERSION or "") .. " —")
end
ns.RefreshBookPage = RefreshLeftPage

evBtn:SetScript("OnClick", function()
    for _, tab in ipairs(P.tabs) do
        if tab.key == "30" and not (ns.TabHidden and ns.TabHidden(tab)) then ns.SelectTab(tab.id) return end
    end
end)

-- Icon-Leiste: Trennlinien unter der Kopfzeile und neben der Leiste
local headLine = frame:CreateTexture(nil, "BORDER")
local railLine = frame:CreateTexture(nil, "BORDER")
ns.Paint(headLine, "accent", 0.35)
ns.Paint(railLine, "accent", 0.35)

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
    -- Aufschrift der Register-Reiter im Gildenbuch (waagerecht, gut lesbar)
    tab.gpVert = tab:CreateFontString(nil, "OVERLAY", "GPFont_Ribbon")
    tab.gpVert:SetPoint("LEFT", 18, 0)
    tab.gpVert:SetJustifyH("LEFT")
    tab.gpVert:SetShadowOffset(1, -1)
    tab.gpVert.gpNoInk = true   -- helle Schrift auf farbigem Reiter
    tab.gpEdge = tab:CreateTexture(nil, "OVERLAY")
    tab.gpEdge:SetPoint("TOPRIGHT"); tab.gpEdge:SetPoint("BOTTOMRIGHT"); tab.gpEdge:SetWidth(2)
    tab.gpEdge:SetColorTexture(0, 0, 0, 0.35)
    tab.gpEdge:Hide()
    -- Name als Tooltip (Icon-Leiste und Lesezeichen)
    tab:HookScript("OnEnter", function(self)
        if Current().key == "forge" then return end
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

-- Kurze Aufschrift für das Lesezeichen; umbenannte Reiter: erstes Wort
local function ShortLabel(tab)
    if tab.label and tab.shownDefault and tab.label ~= tab.shownDefault then
        local w = tab.label:match("^%s*(%S+)") or tab.label
        return w:upper():sub(1, 7)
    end
    return SHORT[tab.key] or (tab.label or ""):upper():sub(1, 7)
end

local lastTop = 0
-- Größe und Platz eines Reiters; true = selbst gesetzt (sonst Standard)
function ns.LayoutTab(tab, index, bottom)
    TabExtras(tab)
    local l = Current()
    tab.gpIcon:Hide(); tab.gpMark:Hide(); tab.gpDot:Hide(); tab.gpVert:Hide(); tab.gpEdge:Hide()
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
        -- Register-Reiter: ragen rechts aus dem Buch, Aufschrift waagerecht
        tab:SetSize(82, 32)
        tab.text:Hide()
        tab.gpVert:SetText(ShortLabel(tab))
        tab.gpVert:Show()
        tab.gpEdge:Show()
        if not bottom then lastTop = index end
        local slot = bottom and (lastTop + 1 + index) or index
        tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", -14, -54 - slot * 38 - (bottom and 16 or 0))
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
        local f = on and 1 or 0.72
        tab.bgTex:SetColorTexture(c[1] * f, c[2] * f, c[3] * f, 1)
        tab:SetWidth(on and 94 or 82)   -- der aktive Reiter ragt weiter heraus
        tab.gpVert:SetTextColor(0.98, 0.94, 0.86, on and 1 or 0.82)
        if ns.Ink then ns.Ink.Soon() end
    end
end

-- Größe des Wappens oben links
function ns.CrestSize(faction)
    if Current().key == "rail" then return 38 end
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
        P.bg:SetColorTexture(0.30, 0.17, 0.10, 1)   -- Ledereinband
    else
        P.bg:SetTexture(MEDIA .. "bg")
    end
    for _, t in ipairs(book) do t:SetShown(isBook) end
    if isBook then BookGeometry(l) end

    -- Seitenleiste
    P.side:SetShown(not isBook)
    P.side:SetWidth(l.side)
    if rail then
        P.side:SetColorTexture(0.045, 0.04, 0.05, 1)
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
    P.factionLogo:SetShown(not isBook)
    P.factionLogo:ClearAllPoints()
    if rail then
        P.factionLogo:SetPoint("TOP", frame, "TOPLEFT", l.side / 2 + 1, -14)
    else
        P.factionLogo:SetPoint("CENTER", P.crestGlow, "CENTER", 0, 0)
    end
    P.versionText:SetShown(l.key == "forge")

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
    P.title:SetWidth(isBook and (LPAGE - 40) or 0)
    P.title:SetJustifyH(isBook and "CENTER" or "LEFT")
    P.subtitle:ClearAllPoints()
    P.subtitle:SetJustifyH(isBook and "CENTER" or "LEFT")
    if rail then
        P.title:SetPoint("TOPLEFT", frame, "TOPLEFT", l.side + 20, -14)
        P.subtitle:SetPoint("TOPLEFT", P.title, "BOTTOMLEFT", 2, -6)
    elseif isBook then
        P.title:SetPoint("TOP", kicker, "BOTTOM", 0, -6)
        P.subtitle:SetPoint("TOP", P.title, "BOTTOM", 0, -4)
    else
        P.title:SetPoint("TOPLEFT", P.header, "TOPLEFT", 24, -20)
        P.subtitle:SetPoint("TOPLEFT", P.title, "BOTTOMLEFT", 2, -6)
    end
    P.pageTitle:ClearAllPoints()
    if isBook then
        -- Seitentitel mittig über der rechten Seite, mit Zierstrichen
        local rpX = COVER + LPAGE + GUTTER
        P.pageTitle:SetPoint("TOP", frame, "TOPLEFT", rpX + (l.w - COVER - rpX) / 2, -36)
        orn1:ClearAllPoints(); orn1:SetPoint("RIGHT", P.pageTitle, "LEFT", -14, 0); orn1:SetSize(90, 1)
        orn2:ClearAllPoints(); orn2:SetPoint("LEFT", P.pageTitle, "RIGHT", 14, 0); orn2:SetSize(90, 1)
        orn1:SetColorTexture(0.55, 0.42, 0.24, 0.8); orn2:SetColorTexture(0.55, 0.42, 0.24, 0.8)
    else
        P.pageTitle:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -48, rail and -22 or -26)
    end

    -- Rahmen: Ecken nicht in der Icon-Leiste, Kupferlinien nicht im Buch
    for _, t in ipairs(frame.gpCorners or {}) do t:SetShown(not rail) end
    for _, t in ipairs(frame.gpBorder or {}) do t:SetShown(not isBook) end

    -- Inhalt
    P.content:ClearAllPoints()
    if rail then
        P.content:SetPoint("TOPLEFT", l.side + 16, -l.header - 10); P.content:SetPoint("BOTTOMRIGHT", -16, 14)
    elseif isBook then
        P.content:SetPoint("TOPLEFT", COVER + LPAGE + GUTTER + 24, -l.header); P.content:SetPoint("BOTTOMRIGHT", -COVER - 20, COVER + 14)
    else
        P.content:SetPoint("TOPLEFT", l.side + 14, -l.header - 12); P.content:SetPoint("BOTTOMRIGHT", -14, 14)
    end

    -- Reiter neu anordnen, Farben (Style) neu auftragen, Tinte an/aus
    P.LayoutTabs()
    if ns.ApplyTheme then ns.ApplyTheme() end   -- färbt Texturen neu und ruft MarkTabs
    if P.MarkTabs then P.MarkTabs() end
    local size = ns.CrestSize(UnitFactionGroup("player") == "Alliance" or UnitFactionGroup("player") == "Horde")
    P.factionLogo:SetSize(size, size)
    RefreshLeftPage()
    if ns.Ink then ns.Ink.Set(isBook) end
    if ns.MarkLayout then ns.MarkLayout() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() ns.ApplyLayout() end)
frame:HookScript("OnShow", function() RefreshLeftPage() end)

-- Nach jeder Aktualisierung: linke Buchseite und neue Schriften (Tinte)
if ns.RefreshUI then
    local refresh = ns.RefreshUI
    ns.RefreshUI = function(...)
        refresh(...)
        if Current().key == "book" then
            RefreshLeftPage()
            if ns.Ink then ns.Ink.Soon() end
        end
    end
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
        b:SetNormalFontObject(b.key == cur and GPFont_ButtonActive or GPFont_Button)
    end
end
