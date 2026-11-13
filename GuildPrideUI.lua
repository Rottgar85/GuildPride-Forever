-- GuildPride: eigenes Gildenfenster im "Schmiede"-Stil
-- Seitenleiste mit Logo + Navigation links, Glut-Banner oben, Inhalt rechts
local ADDON, ns = ...
local L = ns.L

local MEDIA = "Interface\\AddOns\\GuildPrideForever\\Media\\"
local CLASS_COLORS = RAID_CLASS_COLORS
local GOLD_TEXT = "|cfff0c88c"
local Paint = ns.Paint

local W, H, SIDEBAR, HEADER = 860, 580, 180, 96

---------------------------------------------------------------------
-- Hauptfenster
---------------------------------------------------------------------
local frame = CreateFrame("Frame", "GuildPrideFrame", UIParent)
frame:SetSize(W, H)
frame:SetPoint("CENTER")
frame:SetFrameStrata("HIGH")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:SetClampedToScreen(true)
frame:Hide()
tinsert(UISpecialFrames, "GuildPrideFrame") -- ESC schließt

-- Hintergrund
local bg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
bg:SetAllPoints()
bg:SetTexture(MEDIA .. "bg")
Paint(bg, "tex")

-- Rahmen (2 px, Farbe je nach Style) und Ecken-Ornamente
local function Line(p1, p2, size)
    local t = frame:CreateTexture(nil, "BORDER")
    Paint(t, "accent")
    t:SetPoint(p1); t:SetPoint(p2)
    if p1:find("LEFT") and p2:find("LEFT") or p1:find("RIGHT") and p2:find("RIGHT") then t:SetWidth(size) else t:SetHeight(size) end
end
Line("TOPLEFT", "TOPRIGHT", 2)
Line("BOTTOMLEFT", "BOTTOMRIGHT", 2)
Line("TOPLEFT", "BOTTOMLEFT", 2)
Line("TOPRIGHT", "BOTTOMRIGHT", 2)

local corners = {
    { "TOPLEFT",     0, 1, 0, 1 },
    { "TOPRIGHT",    1, 0, 0, 1 },
    { "BOTTOMLEFT",  0, 1, 1, 0 },
    { "BOTTOMRIGHT", 1, 0, 1, 0 },
}
for _, c in ipairs(corners) do
    local t = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    t:SetSize(40, 40)
    t:SetPoint(c[1], c[1]:find("LEFT") and -6 or 6, c[1]:find("TOP") and 6 or -6)
    t:SetTexture(MEDIA .. "corner")
    t:SetTexCoord(c[2], c[3], c[4], c[5])
    Paint(t, "tex")
end

-- Seitenleiste
local side = frame:CreateTexture(nil, "BACKGROUND", nil, -6)
side:SetPoint("TOPLEFT", 2, -2)
side:SetPoint("BOTTOMLEFT", 2, 2)
side:SetWidth(SIDEBAR)
side:SetTexture(MEDIA .. "sidebar")
Paint(side, "tex")

-- Fraktionslogo (Horde/Allianz) oben in der Seitenleiste
local crestGlow = frame:CreateTexture(nil, "ARTWORK", nil, 0)
crestGlow:SetSize(140, 140)
crestGlow:SetPoint("TOP", frame, "TOPLEFT", SIDEBAR / 2 + 2, -10)
crestGlow:SetTexture(MEDIA .. "crest_glow")
Paint(crestGlow, "tex")

local factionLogo = frame:CreateTexture(nil, "ARTWORK", nil, 1)
factionLogo:SetSize(104, 104)
factionLogo:SetPoint("CENTER", crestGlow, "CENTER", 0, 0)

local FACTION_LOGO = {
    Horde = "Interface\\Timer\\Horde-Logo",
    Alliance = "Interface\\Timer\\Alliance-Logo",
}

-- Neutral (z. B. Pandaren vor der Fraktionswahl): eigenes GuildPride-Wappen
local function UpdateCrest()
    local logo = FACTION_LOGO[UnitFactionGroup("player") or ""]
    factionLogo:SetTexture(logo or (MEDIA .. "logo"))
    factionLogo:SetSize(logo and 104 or 84, logo and 104 or 84)
end

local versionText = frame:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
versionText:SetPoint("BOTTOM", frame, "BOTTOMLEFT", SIDEBAR / 2 + 2, 14)

-- Banner oben
local header = frame:CreateTexture(nil, "BACKGROUND", nil, -5)
header:SetPoint("TOPLEFT", SIDEBAR + 2, -2)
header:SetPoint("TOPRIGHT", -2, -2)
header:SetHeight(HEADER)
header:SetTexture(MEDIA .. "header")
Paint(header, "tex")

local title = frame:CreateFontString(nil, "OVERLAY", "GPFont_Huge")
title:SetPoint("TOPLEFT", header, "TOPLEFT", 24, -20)
title:SetShadowOffset(2, -2)

local subtitle = frame:CreateFontString(nil, "OVERLAY", "GPFont_Text")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 2, -6)

local pageTitle = frame:CreateFontString(nil, "OVERLAY", "GPFont_Large")
pageTitle:SetPoint("TOPRIGHT", header, "TOPRIGHT", -46, -24)
Paint(pageTitle, "title")

local close = CreateFrame("Button", nil, frame)
close:SetSize(26, 26)
close:SetPoint("TOPRIGHT", -12, -12)
close:SetNormalTexture(MEDIA .. "close")
close:SetHighlightTexture(MEDIA .. "close_hover")
close:SetPushedTexture(MEDIA .. "close_hover")
close:SetScript("OnClick", function() ns.ToggleUI() end)

local function UpdateHeader()
    local guildName = GetGuildInfo("player")
    title:SetText(guildName or L["Keine Gilde"])
    UpdateCrest()
    local total, online = GetNumGuildMembers()
    subtitle:SetText((L["%s%d|r Mitglieder  ·  |cff40ff40%d|r online"]):format(GOLD_TEXT, total or 0, online or 0))
    versionText:SetText("GuildPride " .. (ns.VERSION or ""))
end

---------------------------------------------------------------------
-- Navigation (Seitenleiste)
---------------------------------------------------------------------
local pages, tabs = {}, {}
local content = CreateFrame("Frame", nil, frame)
content:SetPoint("TOPLEFT", SIDEBAR + 14, -HEADER - 12)
content:SetPoint("BOTTOMRIGHT", -14, 14)

-- Kompaktes Menü: mehrere Reiter teilen sich einen Platz in der Seitenleiste,
-- oben auf der Seite schaltet eine Leiste zwischen ihnen um. Schlüssel = feste
-- Standard-Ordnung der Reiter (10 Übersicht, 30 Events, 40 Gruppensuche,
-- 50 Umfragen, 60 Meilensteine, 65 Ziele, 70 Gildeninfo, 75 Berufe).
-- Der erste Schlüssel ist der Gastgeber.
local GROUPS = {
    { host = "10", label = L["Übersicht"], keys = { "10", "60", "65" } },
    { host = "30", label = L["Planen"],    keys = { "30", "40", "50" } },
    { host = "70", label = L["Gildeninfo"], keys = { "70", "75" } },
}
local groupOf = {}
for _, g in ipairs(GROUPS) do for _, k in ipairs(g.keys) do groupOf[k] = g end end
local function Compact() return not GuildPrideDB or GuildPrideDB.compactMenu ~= false end
local function GroupOf(tab) return tab and Compact() and groupOf[tab.key] or nil end
-- Reiter, der im kompakten Menü keinen eigenen Platz in der Seitenleiste hat
local function IsGuest(tab) local g = GroupOf(tab); return g ~= nil and g.host ~= tab.key end
local function TabByKey(key) for _, t in ipairs(tabs) do if t.key == key then return t end end end

-- Umschaltleiste oben auf gruppierten Seiten
local switchBar = CreateFrame("Frame", nil, content)
switchBar:SetPoint("TOPLEFT"); switchBar:SetPoint("TOPRIGHT")
switchBar:SetHeight(26)
switchBar:Hide()
switchBar.buttons = {}
local TabHiddenFwd, SelectTabFwd
local function ShowSwitchBar(g, selectedTab)
    if not g then switchBar:Hide() return end
    local n = 0
    for _, key in ipairs(g.keys) do
        local t = TabByKey(key)
        if t and not TabHiddenFwd(t) then
            n = n + 1
            local b = switchBar.buttons[n]
            if not b then
                b = CreateFrame("Button", nil, switchBar, "UIPanelButtonTemplate")
                b:SetSize(130, 24)
                b:SetPoint("LEFT", (n - 1) * 136, 0)
                if ns.SkinButton then ns.SkinButton(b) end   -- GuildPride-Design statt Blizzard-Rot
                switchBar.buttons[n] = b
            end
            local e = GuildPrideDB and GuildPrideDB.menu and GuildPrideDB.menu[t.key]
            -- Gastgeber: dessen eigener Name (der umbenannte gilt für die ganze Gruppe)
            local name = t.key ~= g.host and e and type(e.name) == "string" and e.name ~= "" and e.name or t.defaultLabel
            b:SetText(name .. (t.badge and (" |cffff8c40" .. t.badge .. "|r") or ""))
            b:SetScript("OnClick", function() PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB); SelectTabFwd(t.id) end)
            -- aktive Unterseite wie im Chat/Liste-Umschalter hervorheben
            if b.gpBg then b.gpBg:SetTexture(MEDIA .. (t == selectedTab and "nav_active" or "nav")) end
            b:SetNormalFontObject(t == selectedTab and GPFont_Normal or GPFont_Button)
            b:Show()
        end
    end
    for i = n + 1, #switchBar.buttons do switchBar.buttons[i]:Hide() end
    switchBar:SetShown(n > 1)
    return n > 1
end

local function MarkTabs()
    local t = ns.Theme()
    local sel = tabs[frame.selected or 0]
    local selGroup = GroupOf(sel)
    for i, tab in ipairs(tabs) do
        local on = i == frame.selected or (selGroup ~= nil and selGroup.host == tab.key)
        tab.bgTex:SetTexture(MEDIA .. (on and "nav_active" or "nav"))
        if on then tab.text:SetTextColor(t.button[1], t.button[2], t.button[3])
        else tab.text:SetTextColor(0.82, 0.79, 0.76) end
    end
end
ns.OnThemeChanged(MarkTabs)

local function SelectTab(id)
    local tab = tabs[id]
    local g = GroupOf(tab)
    local bar = ShowSwitchBar(g, tab)
    for i, page in ipairs(pages) do
        if i == id then
            page:ClearAllPoints()
            if bar then
                page:SetPoint("TOPLEFT", 0, -32); page:SetPoint("BOTTOMRIGHT")
            else
                page:SetAllPoints()
            end
        end
        page:SetShown(i == id)
    end
    frame.selected = id
    if g then g.last = tab.key end
    MarkTabs()
    local host = g and TabByKey(g.host)
    pageTitle:SetText(host and host.label or (tab and tab.label) or "")
    if pages[id] and pages[id].Refresh then pages[id]:Refresh() end
end
SelectTabFwd = SelectTab

-- Eigene Menü-Einstellungen: GuildPrideDB.menu[Schlüssel] = { hide, name, order }
-- Schlüssel ist die feste Standard-Ordnung des Reiters (z. B. "30" = Events)
local function MenuEntry(tab, create)
    local db = GuildPrideDB
    if not db then return nil end
    if create then db.menu = db.menu or {} end
    local menu = db.menu
    if not menu then return nil end
    if create and not menu[tab.key] then menu[tab.key] = {} end
    return menu[tab.key]
end

-- Einstellungen (ab Ordnung 90) bleiben immer sichtbar und unten
local function IsFixed(tab) return tab.defaultOrder >= 90 end

-- Reiter nur für Offiziere (wer die Gildennachricht ändern darf), z. B. Verwaltung
local function OfficerOK(tab) return not tab.officerOnly or (CanEditMOTD and CanEditMOTD()) and true or false end
local function TabHidden(tab)
    if not OfficerOK(tab) then return true end
    if IsFixed(tab) then return false end
    local e = MenuEntry(tab)
    return e and e.hide and true or false
end
TabHiddenFwd = TabHidden

local function ApplyTabText(tab)
    local e = MenuEntry(tab)
    local name = e and type(e.name) == "string" and e.name ~= "" and e.name or nil
    local g = GroupOf(tab)
    local badge = tab.badge
    if g and g.host == tab.key then
        -- Gastgeber: Gruppenname, Hinweis eines beliebigen Mitglieds
        for _, key in ipairs(g.keys) do
            local t = TabByKey(key)
            if not badge and t and t.badge and not TabHidden(t) then badge = t.badge end
        end
    end
    -- Standardname, wie er gerade gilt (Gastgeber im kompakten Menü: Gruppenname)
    tab.shownDefault = (g and g.host == tab.key) and g.label or tab.defaultLabel
    tab.label = name or tab.shownDefault
    tab.text:SetText(tab.label .. (badge and ("  |cffff8c40" .. badge .. "|r") or ""))
end

-- Reiter in Anzeige-Reihenfolge (ohne Einstellungen)
local function MenuTabs()
    local list = {}
    for _, tab in ipairs(tabs) do
        if not IsFixed(tab) and not IsGuest(tab) and OfficerOK(tab) then
            local e = MenuEntry(tab)
            tab.order = e and tonumber(e.order) or tab.defaultOrder
            list[#list + 1] = tab
        end
    end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.defaultOrder < b.defaultOrder
    end)
    return list
end
ns.MenuTabs = MenuTabs

-- Reiter nach "order" sortiert untereinander; ab Ordnung 90 (Einstellungen)
-- unten in der Seitenleiste
local function LayoutTabs()
    local top, bottom = 0, 0
    for _, tab in ipairs(tabs) do if IsGuest(tab) then tab:Hide() end end
    for _, tab in ipairs(MenuTabs()) do
        tab:ClearAllPoints()
        ApplyTabText(tab)
        if TabHidden(tab) then
            tab:Hide()
        else
            tab:Show()
            tab:SetPoint("TOPLEFT", 10, -168 - top * 40)
            top = top + 1
        end
    end
    for _, tab in ipairs(tabs) do
        if IsFixed(tab) then
            tab:ClearAllPoints()
            ApplyTabText(tab)
            tab:Show()
            tab:SetPoint("BOTTOMLEFT", 10, 34 + bottom * 40)
            bottom = bottom + 1
        end
    end
end

-- Startreiter: gespeicherter Schlüssel, falls sichtbar, sonst der erste sichtbare
local function StartTabId()
    local key = GuildPrideDB and GuildPrideDB.startTab
    for i, tab in ipairs(tabs) do
        if key and tab.key == key and not TabHidden(tab) then return i end
    end
    for _, tab in ipairs(MenuTabs()) do
        if not TabHidden(tab) then return tab.id end
    end
    for i, tab in ipairs(tabs) do
        if IsFixed(tab) then return i end
    end
    return 1
end
ns.StartTabId = StartTabId
ns.TabHidden = TabHidden

-- Nach Änderungen im Menü neu anordnen; ausgeblendete Seite verlassen
function ns.MenuChanged()
    LayoutTabs()
    local cur = tabs[frame.selected or 0]
    if cur and TabHidden(cur) then SelectTab(StartTabId()) end
    if cur and not TabHidden(cur) then SelectTab(cur.id) end
end

-- order: Platz in der Seitenleiste (kleiner = weiter oben)
local function AddTab(label, order)
    local id = #pages + 1
    local page = CreateFrame("Frame", nil, content)
    page:SetAllPoints()
    page:Hide()
    pages[id] = page

    local tab = CreateFrame("Button", nil, frame)
    tab:SetSize(SIDEBAR - 16, 36)
    tab.bgTex = tab:CreateTexture(nil, "BACKGROUND")
    tab.bgTex:SetAllPoints()
    tab.bgTex:SetTexture(MEDIA .. "nav")
    Paint(tab.bgTex, "tex")
    local hl = tab:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 3, -3); hl:SetPoint("BOTTOMRIGHT", -3, 3)
    Paint(hl, "glow", 0.12)
    tab.text = tab:CreateFontString(nil, "OVERLAY", "GPFont_Normal")
    tab.text:SetPoint("LEFT", 18, 0)
    tab.text:SetText(label)
    tab.label = label
    tab.defaultLabel = label
    tab.order = order or id * 10
    tab.defaultOrder = tab.order
    tab.key = tostring(tab.defaultOrder)
    tab.id = id
    tab:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
        -- Gruppe: zuletzt benutzte Unterseite (falls noch sichtbar)
        local g = GroupOf(tab)
        local last = g and g.last and TabByKey(g.last)
        if last and not TabHidden(last) then SelectTab(last.id) return end
        if g and TabHidden(tab) then
            for _, key in ipairs(g.keys) do
                local t = TabByKey(key)
                if t and not TabHidden(t) then SelectTab(t.id) return end
            end
        end
        SelectTab(id)
    end)
    tabs[id] = tab
    page.tabId = id
    LayoutTabs()
    return page
end

-- Reiter nur für Offiziere zeigen
function ns.SetTabOfficerOnly(page)
    local tab = tabs[page.tabId]
    if tab then tab.officerOnly = true; LayoutTabs() end
end

-- Zusatz hinter dem Reiternamen, z. B. ungelesene Nachrichten "(3)"
function ns.SetTabBadge(page, text)
    local tab = tabs[page.tabId]
    if not tab then return end
    tab.badge = text
    ApplyTabText(tab)
    local g = GroupOf(tab)
    local host = g and TabByKey(g.host)
    if host and host ~= tab then ApplyTabText(host) end
    if g and switchBar:IsShown() and GroupOf(tabs[frame.selected or 0]) == g then ShowSwitchBar(g, tabs[frame.selected]) end
end

-- Abschnitts-Überschrift mit Kupferlinie
local function Section(parent, text, anchor, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GPFont_Large")
    if anchor then fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y or -20) else fs:SetPoint("TOPLEFT", 4, y or -4) end
    fs:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 10, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
    Paint(line, "accent", 0.5)
    return fs
end
ns.Section = Section

-- Scrollbereich mit schmalem Blizzard-Scrollbalken wie im Chat
-- (ältere Clients ohne die Vorlage: klassischer Balken)
function ns.NewScroll(parent)
    local ok, scroll = pcall(CreateFrame, "ScrollFrame", nil, parent, "ScrollFrameTemplate")
    if not ok or not scroll then scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate") end
    return scroll
end

-- Scrollbare Liste (width: Zeilenbreite, Standard 620)
local function CreateList(parent, rowHeight, width)
    width = width or 620
    local scroll = ns.NewScroll(parent)
    scroll:SetPoint("TOPLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 0)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(width, 1)
    scroll:SetScrollChild(child)
    child.rows = {}
    function child:GetRow(i)
        local row = self.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, self)
            row:SetSize(width, rowHeight)
            row:SetPoint("TOPLEFT", 0, -(i - 1) * rowHeight)
            row.bg = row:CreateTexture(nil, "BACKGROUND")
            row.bg:SetAllPoints()
            Paint(row.bg, "glow", i % 2 == 0 and 0.05 or 0)
            row.left = row:CreateFontString(nil, "OVERLAY", "GPFont_Text")
            row.left:SetPoint("LEFT", 8, 0)
            row.mid = row:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
            row.mid:SetPoint("LEFT", 200, 0)
            row.right = row:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
            row.right:SetPoint("RIGHT", -8, 0)
            self.rows[i] = row
        end
        row:Show()
        return row
    end
    function child:Finish(count)
        for i = count + 1, #self.rows do self.rows[i]:Hide() end
        self:SetHeight(math.max(1, count * rowHeight))
    end
    return child
end

---------------------------------------------------------------------
-- 1) Übersicht
---------------------------------------------------------------------
local overview = AddTab(L["Übersicht"], 10)
-- Der Gildenknopf in der Mikroleiste ruft ToggleGuildFrame auf und
-- öffnet damit automatisch dieses Fenster (siehe Hook unten).

-- Statistik-Kacheln
local tiles = {}
local function Tile(i, label)
    local f = CreateFrame("Frame", nil, overview)
    f:SetSize(196, 64)
    f:SetPoint("TOPLEFT", (i - 1) * 210, -4)
    local b = f:CreateTexture(nil, "BACKGROUND"); b:SetAllPoints(); b:SetColorTexture(0, 0, 0, 0.45)
    local edge = f:CreateTexture(nil, "BORDER"); edge:SetPoint("TOPLEFT"); edge:SetPoint("BOTTOMLEFT"); edge:SetWidth(3)
    Paint(edge, "ember")
    f.value = f:CreateFontString(nil, "OVERLAY", "GPFont_Huge")
    f.value:SetPoint("TOPLEFT", 14, -10)
    Paint(f.value, "button")
    f.label = f:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    f.label:SetPoint("BOTTOMLEFT", 14, 10)
    f.label:SetText(label)
    tiles[i] = f
end
Tile(1, L["MITGLIEDER ONLINE"])
Tile(2, L["NÄCHSTES EVENT"])
Tile(3, L["MEILENSTEINE DIESE WOCHE"])

local motdLabel = Section(overview, L["Nachricht des Tages"], nil, -92)
local motd = overview:CreateFontString(nil, "OVERLAY", "GPFont_Text")
motd:SetPoint("TOPLEFT", motdLabel, "BOTTOMLEFT", 0, -10)
motd:SetWidth(620); motd:SetJustifyH("LEFT")

local weekLabel = Section(overview, L["Diese Woche"], motd, -26)
local weekText = overview:CreateFontString(nil, "OVERLAY", "GPFont_Text")
weekText:SetPoint("TOPLEFT", weekLabel, "BOTTOMLEFT", 0, -10)
weekText:SetWidth(620); weekText:SetJustifyH("LEFT"); weekText:SetSpacing(4)

-- Wochenrückblick aus dem Verlauf (seit dem letzten Wochenreset)
local WEEK_KINDS = {
    { kinds = { LEVEL = true }, label = L["Level-Aufstiege"] },
    { kinds = { BOSS = true },  label = L["Raid-Siege"] },
    { kinds = { MPLUS = true }, label = L["M+-Bestwerte"], retail = true },
    { kinds = { ACH = true },   label = L["Erfolge"] },
    { kinds = { MOUNT = true }, label = L["Reittiere"] },
    { kinds = { JOIN = true },  label = L["Neue Mitglieder"] },
    { kinds = { LEAVE = true, KICK = true }, label = L["Abgänge"] },
}
local function WeekSummary()
    local since, counts, byWho = ns.WeekStart(), {}, {}
    for _, e in ipairs(ns.GuildLog()) do
        if (e.t or 0) >= since then
            for i, w in ipairs(WEEK_KINDS) do
                if w.kinds[e.kind] then counts[i] = (counts[i] or 0) + 1 end
            end
            if e.kind ~= "JOIN" and e.kind ~= "LEAVE" and e.kind ~= "KICK" and e.who then
                byWho[e.who] = (byWho[e.who] or 0) + 1
            end
        end
    end
    local parts = {}
    for i, w in ipairs(WEEK_KINDS) do
        if not w.retail or ns.IS_RETAIL then
            parts[#parts + 1] = ("%s |cffffd18c%d|r"):format(w.label, counts[i] or 0)
        end
    end
    local text = table.concat(parts, "  ·  ")
    local best, n = nil, 0
    for who, c in pairs(byWho) do if c > n then best, n = who, c end end
    if best then text = text .. "\n" .. (L["Fleißigstes Mitglied: |cfff0c88c%s|r (%d Meilensteine)"]):format(best, n) end
    return text
end

local recentLabel = Section(overview, L["Letzte Meilensteine"], weekText, -26)
local recent = overview:CreateFontString(nil, "OVERLAY", "GPFont_Text")
recent:SetPoint("TOPLEFT", recentLabel, "BOTTOMLEFT", 0, -10)
recent:SetWidth(620); recent:SetJustifyH("LEFT"); recent:SetSpacing(6)

function overview:Refresh()
    local total, online = GetNumGuildMembers()
    tiles[1].value:SetText(("%d / %d"):format(online or 0, total or 0))

    local nextEvent
    if ns.RollEvents then ns.RollEvents() end   -- wöchentliche Events auf den nächsten Termin
    for _, e in pairs(ns.GuildTable("events")) do
        if e.title and not e.deleted and e.t and e.t > GetServerTime() and (not nextEvent or e.t < nextEvent.t) then
            nextEvent = e
        end
    end
    tiles[2].value:SetText(nextEvent and ns.FormatDate(nextEvent.t, "short") or "–")
    tiles[2].label:SetText(nextEvent and (L["NÄCHSTES EVENT: "] .. nextEvent.title:upper()) or L["NÄCHSTES EVENT"])

    local week, cutoff = 0, ns.WeekStart()
    for _, e in ipairs(ns.GuildLog()) do if e.t >= cutoff then week = week + 1 end end
    tiles[3].value:SetText(week)

    local text = ns.GuildMOTD()
    text = text ~= "" and text or L["|cff888888Keine Nachricht gesetzt.|r"]
    local board = ns.BoardText and ns.BoardText()
    motd:SetText(board and (text .. "\n\n" .. board) or text)
    weekText:SetText(WeekSummary())
    local lines = {}
    local log = ns.GuildLog()
    for i = 1, math.min(5, #log) do
        local e = log[i]
        local icon = (e.kind == "LEVEL" and ns.BadgeFor) and ("|T%s:18|t"):format(ns.BadgeFor(e.kind, e.value)) or "|cffff8c40•|r"
        lines[#lines + 1] = ("%s |cfff0c88c%s|r %s  |cff777777%s|r"):format(icon, e.who, ns.LogText(e), ns.FormatDay(e.t))
    end
    recent:SetText(#lines > 0 and table.concat(lines, "\n") or L["|cff888888Noch keine Meilensteine.|r"])
end

---------------------------------------------------------------------
-- 2) Gilde & Chat – wie Blizzards Community-Fenster: Chat links, Mitglieder
--    rechts. "Mitgliederliste" schaltet auf die große Liste mit Details um.
--    Die Kanal-Leiste oben links (GuildPrideChat.lua) bestimmt auch, wessen
--    Mitglieder angezeigt werden (Gilde oder eine Community).
---------------------------------------------------------------------
local community = AddTab(L["Gilde & Chat"], 20)
local ROSTER_W = 210

local bViewList = CreateFrame("Button", nil, community, "UIPanelButtonTemplate")
bViewList:SetSize(130, 24); bViewList:SetPoint("TOPRIGHT", 0, 0); bViewList:SetText(L["Mitgliederliste"])
local bViewChat = CreateFrame("Button", nil, community, "UIPanelButtonTemplate")
bViewChat:SetSize(70, 24); bViewChat:SetPoint("RIGHT", bViewList, "LEFT", -6, 0); bViewChat:SetText(L["Chat"])

-- Chat-Bereich (wird von GuildPrideChat.lua gefüllt)
local chatPane = CreateFrame("Frame", nil, community)
chatPane:SetPoint("TOPLEFT", 0, -32)
chatPane:SetPoint("BOTTOMRIGHT", -(ROSTER_W + 10), 0)

-- Kompakte Mitgliederliste neben dem Chat
local roster = CreateFrame("Frame", nil, community)
roster:SetPoint("TOPRIGHT", 0, -32)
roster:SetPoint("BOTTOMRIGHT", 0, 0)
roster:SetWidth(ROSTER_W)

-- Sicherer Knopf, der beim Klick einen Makrotext ausführt (/gremove, /gpromote …):
-- Befördern, Degradieren und Entfernen sind für Addons gesperrt, ein Makro nicht.
-- Nur die sichere Vorlage: eine zweite Vorlage (z. B. UIPanelButtonTemplate)
-- kann den sicheren Klick-Handler ersetzen – dann passiert beim Klick nichts.
-- Aussehen deshalb selbst gebaut, im Stil der übrigen Knöpfe.
local secureButtons = {}
local function SecureButton(parent, w, label)
    local b = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    b:SetSize(w, 24)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetTexture(MEDIA .. "nav")
    ns.Paint(bg, "tex")
    b.gpBg = bg
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 3, -3); hl:SetPoint("BOTTOMRIGHT", -3, 3)
    ns.Paint(hl, "glow", 0.15)
    b:SetNormalFontObject(GPFont_Button)
    b:SetHighlightFontObject(GPFont_Button)
    b:SetDisabledFontObject(GPFont_ButtonOff)
    b:SetText(label)
    hooksecurefunc(b, "SetEnabled", function(_, on) ns.PaintEnabled(bg, on) end)

    -- Genau eine Klick-Phase: ohne festes useOnKeyDown hängt es an der
    -- Einstellung ActionButtonUseKeyDown und der Knopf kann "tot" sein.
    b:RegisterForClicks("AnyDown")
    b:SetAttribute("useOnKeyDown", true)
    secureButtons[#secureButtons + 1] = b
    return b
end

-- Klickt sicher einen Blizzard-Knopf: So öffnet Blizzard sein Fenster selbst,
-- und unser Addon-Code läuft nicht mit (keine Sperren in dem Fenster).
function ns.SecureClickButton(parent, w, label, target)
    local b = SecureButton(parent, w, label)
    b:SetAttribute("type", "click")
    b:SetAttribute("clickbutton", target)
    return b
end

function ns.SecureMacroButton(parent, w, label)
    local b = SecureButton(parent, w, label)
    b:SetAttribute("type", "macro")

    b:HookScript("OnClick", function(self)
        local text = self:GetAttribute("macrotext")
        if text and text ~= "" then
            ns.Print((L["Befehl gesendet: |cffffd100%s|r"]):format((text:gsub("\n", " · "))))
        end
        -- Nach der Aktion die Gildenliste neu laden
        C_Timer.After(1, function() if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end end)
    end)
    return b
end

-- Sichere Knöpfe machen ihre Elternfenster im Kampf mitgeschützt: dann ließe sich das
-- Gildenfenster nicht öffnen oder schließen. Deshalb hängen wir sie kurz vor
-- Kampfbeginn (PLAYER_REGEN_DISABLED ist noch erlaubt) ab und danach wieder an.
local parking = CreateFrame("Frame")
parking:Hide()
local secureState = CreateFrame("Frame")
secureState:RegisterEvent("PLAYER_REGEN_DISABLED")
secureState:RegisterEvent("PLAYER_REGEN_ENABLED")
secureState:SetScript("OnEvent", function(_, event)
    for _, b in ipairs(secureButtons) do
        if event == "PLAYER_REGEN_DISABLED" then
            if not b.gpParked then
                local points = {}
                for i = 1, b:GetNumPoints() do points[i] = { b:GetPoint(i) } end
                b.gpParked = { parent = b:GetParent(), points = points, shown = b:IsShown() }
                b:Hide(); b:ClearAllPoints(); b:SetParent(parking)
            end
        elseif b.gpParked then
            local s = b.gpParked
            b.gpParked = nil
            b:SetParent(s.parent)
            for _, p in ipairs(s.points) do b:SetPoint(unpack(p)) end
            -- Bestätigungsknöpfe nicht wieder zeigen: ihr Makro kann im Kampf veraltet sein
            if b.gpAfterCombat then b.gpAfterCombat(b, s.shown) else b:SetShown(s.shown) end
        end
    end
end)

-- Große Mitgliederliste (statt Chat)
local members = CreateFrame("Frame", nil, community)
members:SetPoint("TOPLEFT", 0, -32)
members:SetPoint("BOTTOMRIGHT")
members:Hide()

local showOffline = false
local source   -- nil = Gilde, sonst { id, name, bnet } einer Community
local HAS_CLUB = C_Club and C_Club.GetSubscribedClubs and C_Club.GetClubMembers and C_Club.GetMemberInfo

local function FullName(name)
    return ns.Normalize(name)
end

-- Communities (ohne Gilde), nach Name sortiert
local function Communities()
    local out = {}
    if not (HAS_CLUB and ns.HAS_COMMUNITIES) then return out end
    for _, club in ipairs(C_Club.GetSubscribedClubs() or {}) do
        if club.clubType ~= Enum.ClubType.Guild then
            out[#out + 1] = { id = club.clubId, name = club.name, bnet = club.clubType == Enum.ClubType.BattleNet }
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local function CanInviteToClub(clubId)
    local priv = C_Club.GetClubPrivileges and C_Club.GetClubPrivileges(clubId)
    return priv and priv.canSendInvitation
end

-- Forever sperrt die Gildeneinladung für alles, was ein Addon auslöst: direkter Aufruf,
-- /ginvite aus einem Makroskript, Blizzards Einladefenster per Knopf und vom Addon
-- eingetragener Chat-Text (taint.log: ChatFrame1EditBox:GetText() -> Invite()).
-- Nur selbst getippt geht es, darum zeigt das Addon hier nur den Befehl an.
local ShowInviteHint
if ns.IS_FOREVER then
    ShowInviteHint = function(rawName)
        -- Keine Zeilenumbrüche, Farb- oder Linkcodes aus dem Namen in die Ausgabe
        local name = rawName:gsub("[%c|]", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then return end
        ns.Print((L["Zum Einladen bitte im Chat eingeben: |cffffd100/ginvite %s|r"]):format(name))
    end
end

-- Einladen: in die Gilde bzw. in eine Charakter-Community
function ns.InviteToGuild(name)
    if not IsInGuild() then ns.Print(L["Du bist in keiner Gilde."]); return end
    if CanGuildInvite and not CanGuildInvite() then
        ns.Print(L["|cffff4040Du darfst keine Spieler in die Gilde einladen.|r"]); return
    end
    if ShowInviteHint then ShowInviteHint(name); return end
    if C_GuildInfo and C_GuildInfo.Invite then C_GuildInfo.Invite(name) else GuildInvite(name) end
    ns.Print((L["Gildeneinladung an |cffffd100%s|r gesendet."]):format(name))
end

function ns.InviteToClub(club, name)
    if club.bnet then
        ns.Print(L["Battle.net-Communities: Einladungen bitte über das Blizzard-Community-Fenster verschicken."]); return
    end
    if not (C_Club and C_Club.SendCharacterInvitation) then return end
    if not CanInviteToClub(club.id) then
        ns.Print((L["|cffff4040Du darfst in „%s“ niemanden einladen.|r"]):format(club.name)); return
    end
    local ok = pcall(C_Club.SendCharacterInvitation, club.id, name)
    if ok then
        ns.Print((L["Einladung in „%s“ an |cffffd100%s|r gesendet."]):format(club.name, name))
    else
        ns.Print(L["|cffff4040Einladung konnte nicht gesendet werden.|r"])
    end
end

-- Große Liste, Kopfzeile: Nur online | Alle
local bOnline = CreateFrame("Button", nil, members, "UIPanelButtonTemplate")
bOnline:SetSize(110, 24); bOnline:SetPoint("TOPLEFT", 0, 0); bOnline:SetText(L["Nur online"])
local bAll = CreateFrame("Button", nil, members, "UIPanelButtonTemplate")
bAll:SetSize(150, 24); bAll:SetPoint("LEFT", bOnline, "RIGHT", 6, 0); bAll:SetText(L["Alle (inkl. offline)"])

-- Suche (Name, Rang, Notiz, Zone)
local searchBox = CreateFrame("EditBox", nil, members, "InputBoxTemplate")
searchBox:SetSize(150, 22); searchBox:SetPoint("LEFT", bAll, "RIGHT", 14, 0)
searchBox:SetAutoFocus(false); searchBox:SetMaxLetters(30)
local searchHint = searchBox:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
searchHint:SetPoint("LEFT", 2, 0); searchHint:SetText(L["Suchen …"])
searchBox:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
searchBox:SetScript("OnEnterPressed", searchBox.ClearFocus)

-- Inaktive Mitglieder (nur Gilde, nur wer entfernen darf): Tage im Menü wählbar,
-- Ränge ausnehmbar – die Liste zeigt dann genau die, die entfernt würden
local INACTIVE_STEPS = { 0, 14, 30, 60, 90, 180 }
local inactiveDays = 0
local promoteMode = false   -- Liste zeigt fällige Beförderungen
local bInactive = CreateFrame("Button", nil, members, "UIPanelButtonTemplate")
bInactive:SetSize(150, 24); bInactive:SetPoint("TOPRIGHT", 0, 0)

-- Spaltenköpfe: Klick sortiert, erneuter Klick dreht die Richtung
local SORT_COLS = {
    { key = "name",  label = L["Name"],             x = 8 },
    { key = "level", label = L["Level"],            x = 200 },
    { key = "rank",  label = L["Rang"],             x = 260 },
    { key = "last",  label = L["Online / zuletzt"], right = true },
}
local sortHeads = {}
local function MarkSort()
    local s = GuildPrideDB.memberSort or {}
    for _, h in ipairs(sortHeads) do
        local on = (s.key or "last") == h.key
        local arrow = s.desc and "Interface\\Buttons\\Arrow-Up-Up" or "Interface\\Buttons\\Arrow-Down-Up"
        h.text:SetText(h.label .. (on and (" |T" .. arrow .. ":10|t") or ""))
        if on then h.text:SetTextColor(1, 0.82, 0.55) else h.text:SetTextColor(0.6, 0.56, 0.52) end
    end
end
for _, c in ipairs(SORT_COLS) do
    local h = CreateFrame("Button", nil, members)
    h:SetSize(110, 16)
    if c.right then h:SetPoint("TOPRIGHT", -34, -30) else h:SetPoint("TOPLEFT", c.x, -30) end
    h.text = h:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    h.text:SetPoint(c.right and "RIGHT" or "LEFT")
    h.key, h.label = c.key, c.label
    h:SetScript("OnClick", function(self)
        local s = GuildPrideDB.memberSort or {}
        if (s.key or "last") == self.key then s.desc = not s.desc else s.key, s.desc = self.key, false end
        GuildPrideDB.memberSort = s
        members:Refresh()
    end)
    sortHeads[#sortHeads + 1] = h
end

local listHolder = CreateFrame("Frame", nil, members)
listHolder:SetPoint("TOPLEFT", 0, -46)
listHolder:SetPoint("BOTTOMRIGHT", 0, 36)
local memberList = CreateList(listHolder, 24)

-- Kompakte Liste: Kopf mit Anzahl und "Offline zeigen", darunter die Namen
local rosterBg = roster:CreateTexture(nil, "BACKGROUND")
rosterBg:SetAllPoints(); rosterBg:SetColorTexture(0, 0, 0, 0.45)
local rosterCount = roster:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
rosterCount:SetPoint("TOPLEFT", 10, -10)
local rosterOffline = CreateFrame("CheckButton", nil, roster, "UICheckButtonTemplate")
rosterOffline:SetSize(20, 20); rosterOffline:SetPoint("TOPRIGHT", -4, -3)
local rosterOfflineText = roster:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
rosterOfflineText:SetPoint("RIGHT", rosterOffline, "LEFT", -2, 0); rosterOfflineText:SetText(L["Offline zeigen"])
local rosterHolder = CreateFrame("Frame", nil, roster)
rosterHolder:SetPoint("TOPLEFT", 6, -24)
rosterHolder:SetPoint("BOTTOMRIGHT", -2, 4)
local rosterList = CreateList(rosterHolder, 20, ROSTER_W - 34)

-- Fußzeile: Name eingeben + Einladen, rechts die Anzahl
local inviteBox = CreateFrame("EditBox", nil, members, "InputBoxTemplate")
inviteBox:SetSize(170, 22); inviteBox:SetPoint("BOTTOMLEFT", 8, 6)
inviteBox:SetAutoFocus(false); inviteBox:SetMaxLetters(60)
local inviteHint = inviteBox:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
local INVITE_HINT = ns.IS_FOREVER and L["Vor- und Nachname"] or L["Name-Realm"]
inviteHint:SetPoint("LEFT", 2, 0); inviteHint:SetText(INVITE_HINT)
inviteBox:SetScript("OnTextChanged", function(self) inviteHint:SetShown(self:GetText() == "") end)
local inviteBtn = CreateFrame("Button", nil, members, "UIPanelButtonTemplate")
inviteBtn:SetSize(210, 24); inviteBtn:SetPoint("LEFT", inviteBox, "RIGHT", 8, 0)
local countText = members:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
countText:SetPoint("BOTTOMRIGHT", -4, 12)

-- Inaktive entfernen / fällige Beförderungen (statt Einladen, solange der Filter
-- an ist): erst fragen, dann sicherer Knopf mit /gremove bzw. /gpromote. Ein
-- Makro fasst nur 255 Zeichen, daher je Klick ein Paket; danach zeigt der Knopf den Rest.
local REMOVE_CMD, PROMOTE_CMD = ns.SlashCmd("GUILD_UNINVITE", "/gremove"), ns.SlashCmd("GUILD_PROMOTE", "/gpromote")
local MACRO_MAX = 255
local bActAsk = CreateFrame("Button", nil, members, "UIPanelButtonTemplate")
bActAsk:SetSize(260, 24); bActAsk:SetPoint("BOTTOMLEFT", 8, 6); bActAsk:Hide()
local bActYes = ns.SecureMacroButton(members, 260, "")
bActYes:SetPoint("BOTTOMLEFT", 8, 6); bActYes:Hide()
-- nach dem Kampf neu aufbauen, damit Makro und Namen zur aktuellen Liste passen
bActYes.gpAfterCombat = function(self)
    self:Hide()
    if members:IsShown() then members:Refresh() end
end
local actNames, actKind = {}, "kick"

bActAsk:SetScript("OnClick", function() if not InCombatLockdown() then bActAsk:Hide(); bActYes:Show() end end)
bActYes:HookScript("OnClick", function()
    -- verzögert, damit der Befehl beim Klick noch läuft
    C_Timer.After(0.3, function() if not InCombatLockdown() then bActYes:Hide(); members:Refresh() end end)
end)
bActYes:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(actKind == "kick" and L["Wird jetzt entfernt:"] or L["Wird jetzt befördert:"])
    for _, n in ipairs(actNames) do GameTooltip:AddLine(n, 1, 1, 1) end
    GameTooltip:Show()
end)
bActYes:HookScript("OnLeave", function() GameTooltip:Hide() end)

-- kind: "kick" oder "promote"; list: die gerade gezeigten Mitglieder,
-- nil = Filter aus (dann Einladen zeigen)
local function UpdateAction(kind, list)
    if InCombatLockdown() then return end
    inviteBox:SetShown(not list); inviteBtn:SetShown(not list)
    if not list then bActAsk:Hide(); bActYes:Hide(); return end
    if kind ~= actKind then bActYes:Hide(); actKind = kind end
    local _, _, my = GetGuildInfo("player")
    local lines, len, total = {}, 0, 0
    wipe(actNames)
    for _, m in ipairs(list) do
        -- nur Ränge unter mir, nie ich selbst
        local target = kind == "promote" and ns.PromoteTarget and ns.PromoteTarget(m)
        if not m.isSelf and (m.rankIndex or -1) > (my or 99) and (kind == "kick" and not m.online or target) then
            total = total + 1
            local part = {}
            if kind == "kick" then part[1] = REMOVE_CMD .. " " .. Ambiguate(m.full, "none")
            -- /gpromote braucht in Retail den vollen Namen mit Server (wie Guild Roster Manager)
            else for _ = 1, m.rankIndex - target do part[#part + 1] = PROMOTE_CMD .. " " .. m.full end end
            local text = table.concat(part, "\n")
            if len + #text + 1 <= MACRO_MAX then
                lines[#lines + 1] = text; len = len + #text + 1
                actNames[#actNames + 1] = kind == "kick" and m.name
                    or (m.name .. "  »  " .. (GuildControlGetRankName(target + 1) or ""))
            end
        end
    end
    local allowed = kind == "kick" and CanGuildRemove and CanGuildRemove() or kind == "promote" and CanGuildPromote and CanGuildPromote()
    local can = total > 0 and allowed
    if kind == "kick" then
        bActAsk:SetText(total > 0 and (L["Inaktive entfernen (%d) …"]):format(total) or L["Niemand zum Entfernen"])
        bActYes:SetText((L["|cffff4040Wirklich %d entfernen|r"]):format(#actNames))
    else
        bActAsk:SetText(total > 0 and (L["Fällige befördern (%d) …"]):format(total) or L["Keine Beförderung fällig"])
        bActYes:SetText((L["|cff40ff40Jetzt %d befördern|r"]):format(#actNames))
    end
    bActAsk:SetEnabled(can and true or false)
    bActYes:SetAttribute("macrotext", table.concat(lines, "\n"))
    if not can then bActYes:Hide() end
    bActAsk:SetShown(not bActYes:IsShown())
end

-- Ausgenommene Ränge (Rangname -> true), je Gilde gespeichert
local function SkippedRanks()
    local guild = GetGuildInfo("player") or ""
    GuildPrideDB.kickSkip = GuildPrideDB.kickSkip or {}
    GuildPrideDB.kickSkip[guild] = GuildPrideDB.kickSkip[guild] or {}
    return GuildPrideDB.kickSkip[guild]
end

local function DoInvite(box)
    local name = strtrim(box:GetText() or "")
    if name == "" then ns.Print(L["Bitte einen Charakternamen eingeben."]); return end
    if source then ns.InviteToClub(source, name) else ns.InviteToGuild(name) end
    box:SetText(""); box:ClearFocus()
end
inviteBtn:SetScript("OnClick", function() DoInvite(inviteBox) end)
inviteBox:SetScript("OnEnterPressed", DoInvite)
inviteBox:SetScript("OnEscapePressed", inviteBox.ClearFocus)

-- Dasselbe unter der kompakten Mitgliederliste neben dem Chat, nur mit Einladerecht
local rosterInviteBox = CreateFrame("EditBox", nil, roster, "InputBoxTemplate")
rosterInviteBox:SetSize(118, 22); rosterInviteBox:SetPoint("BOTTOMLEFT", 10, 5)
rosterInviteBox:SetAutoFocus(false); rosterInviteBox:SetMaxLetters(60)
local rosterInviteHint = rosterInviteBox:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
rosterInviteHint:SetPoint("LEFT", 2, 0); rosterInviteHint:SetText(INVITE_HINT)
rosterInviteBox:SetScript("OnTextChanged", function(self) rosterInviteHint:SetShown(self:GetText() == "") end)
rosterInviteBox:SetScript("OnEnterPressed", DoInvite)
rosterInviteBox:SetScript("OnEscapePressed", rosterInviteBox.ClearFocus)
local rosterInviteBtn = CreateFrame("Button", nil, roster, "UIPanelButtonTemplate")
rosterInviteBtn:SetSize(72, 24); rosterInviteBtn:SetPoint("LEFT", rosterInviteBox, "RIGHT", 4, 0)
rosterInviteBtn:SetText(L["Einladen"])
rosterInviteBtn:SetScript("OnClick", function() DoInvite(rosterInviteBox) end)

local function UpdateRosterInvite()
    local can
    if source then can = not source.bnet and CanInviteToClub(source.id)
    else can = IsInGuild() and (not CanGuildInvite or CanGuildInvite()) end
    rosterInviteBox:SetShown(can and true or false)
    rosterInviteBtn:SetShown(can and true or false)
    rosterHolder:SetPoint("BOTTOMRIGHT", -2, can and 32 or 4)
end

-- Beide Listen neu zeichnen (nur die sichtbare)
local function RefreshMembers()
    if members:IsShown() then members:Refresh() end
    if roster:IsShown() then roster:Refresh() end
end

local function SetOffline(on)
    showOffline = on
    -- Manche Clients liefern Offline-Mitglieder nur, wenn das eingeschaltet ist
    if not source then
        if SetGuildRosterShowOffline then SetGuildRosterShowOffline(on) end
        if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    end
    RefreshMembers()
end
bOnline:SetScript("OnClick", function() SetOffline(false) end)
bAll:SetScript("OnClick", function() SetOffline(true) end)
searchBox:SetScript("OnTextChanged", function(self)
    searchHint:SetShown(self:GetText() == "")
    if members:IsShown() then members:Refresh() end
end)
local function SetInactive(days, promote)
    inactiveDays, promoteMode = days, promote and true or false
    -- Offline-Mitglieder vom Server holen
    if (days > 0 or promote) and SetGuildRosterShowOffline then SetGuildRosterShowOffline(true) end
    if promote and ns.QueryRankLog then ns.QueryRankLog() end   -- Ereignisprotokoll für die Zeit im Rang
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    members:Refresh()
end
-- Beförderungsregel anlegen: je Ausgangsrang höchstens eine Regel
local function AddPromoteRule(from, to, days)
    local rules = ns.PromoteRules()
    for i = #rules, 1, -1 do if rules[i].from == from then table.remove(rules, i) end end
    rules[#rules + 1] = { from = from, to = to, days = days }
    ns.Print((L["Regel: %s » %s nach %d Tagen im Rang."]):format(from, to, days))
    members:Refresh()
end
StaticPopupDialogs["GUILDPRIDE_PROMOTE_DAYS"] = {
    text = L["Befördern nach wie vielen Tagen im Rang? (1–3650)"],
    button1 = OKAY, button2 = CANCEL,
    hasEditBox = true,
    OnShow = function(self)
        local eb = self.editBox or self.EditBox
        eb:SetText("30"); eb:SetFocus(); eb:HighlightText()
    end,
    OnAccept = function(self, data)
        local n = tonumber((self.editBox or self.EditBox):GetText())
        if n and n >= 1 and n <= 3650 and data then
            AddPromoteRule(data.from, data.to, math.floor(n))
        else
            ns.Print(L["Bitte eine Zahl von 1 bis 3650 eingeben."])
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        StaticPopupDialogs["GUILDPRIDE_PROMOTE_DAYS"].OnAccept(p, p.data); p:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
local PROMOTE_DAYS = { 7, 14, 30, 60, 90 }
StaticPopupDialogs["GUILDPRIDE_INACTIVE_DAYS"] = {
    text = L["Inaktiv seit wie vielen Tagen? (1–3650)"],
    button1 = OKAY, button2 = CANCEL,
    hasEditBox = true,
    OnShow = function(self)
        local eb = self.editBox or self.EditBox
        eb:SetText(tostring(GuildPrideDB.inactiveCustom or 45)); eb:SetFocus(); eb:HighlightText()
    end,
    OnAccept = function(self)
        local n = tonumber((self.editBox or self.EditBox):GetText())
        if n and n >= 1 and n <= 3650 then
            GuildPrideDB.inactiveCustom = math.floor(n)
            SetInactive(GuildPrideDB.inactiveCustom)
        else
            ns.Print(L["Bitte eine Zahl von 1 bis 3650 eingeben."])
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        StaticPopupDialogs["GUILDPRIDE_INACTIVE_DAYS"].OnAccept(p); p:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
local function DaysLabel(d) return d == 0 and L["Aus"] or (L["%d Tage"]):format(d) end
bInactive:SetScript("OnClick", function(self)
    -- ohne Blizzards Menüsystem: Klick schaltet weiter (aus -> 14 -> … -> 180)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        local nextDays = 0
        for i, d in ipairs(INACTIVE_STEPS) do
            if d == inactiveDays then nextDays = INACTIVE_STEPS[i % #INACTIVE_STEPS + 1]; break end
        end
        SetInactive(nextDays)
        return
    end
    MenuUtil.CreateContextMenu(self, function(_, root)
        root:CreateTitle(L["Inaktiv seit"])
        local steps = { unpack(INACTIVE_STEPS) }
        local custom = GuildPrideDB.inactiveCustom
        if custom and not tContains(steps, custom) then steps[#steps + 1] = custom end
        for _, d in ipairs(steps) do
            root:CreateRadio(DaysLabel(d), function() return not promoteMode and inactiveDays == d end, function() SetInactive(d) end)
        end
        root:CreateButton(L["Eigene Tage …"], function() StaticPopup_Show("GUILDPRIDE_INACTIVE_DAYS") end)
        -- Ränge unter mir, die nie angezeigt und entfernt werden (z. B. Twinks)
        local _, _, my = GetGuildInfo("player")
        local num = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
        if my and num > my + 1 then
            root:CreateDivider()
            local sub = root:CreateButton(L["Ränge ausnehmen"])
            local skip = SkippedRanks()
            for r = my + 1, num - 1 do
                local name = GuildControlGetRankName(r + 1)
                if name and name ~= "" then
                    sub:CreateCheckbox(name, function() return skip[name] and true or false end, function()
                        skip[name] = not skip[name] or nil
                        members:Refresh()
                    end)
                end
            end
        end
        -- Beförderung nach Zeit im Rang: Regeln und fällige Mitglieder
        if my and num > my + 2 and CanGuildPromote and CanGuildPromote() then
            root:CreateDivider()
            root:CreateRadio(L["Beförderung fällig"], function() return promoteMode end, function() SetInactive(0, true) end)
            local rules = root:CreateButton(L["Beförderungsregeln"])
            for i, rule in ipairs(ns.PromoteRules()) do
                local entry = rules:CreateButton((L["%s » %s nach %d Tagen"]):format(rule.from, rule.to, rule.days))
                entry:CreateButton(L["|cffff4040Regel löschen|r"], function()
                    table.remove(ns.PromoteRules(), i)
                    members:Refresh()
                end)
            end
            -- Neue Regel: Ausgangsrang -> Zielrang (über ihm, unter mir) -> Tage
            local add = rules:CreateButton(L["Neue Regel …"])
            for a = num - 1, my + 2, -1 do
                local from = GuildControlGetRankName(a + 1)
                local fromSub = add:CreateButton((L["Von %s"]):format(from))
                for b = a - 1, my + 1, -1 do
                    local to = GuildControlGetRankName(b + 1)
                    local toSub = fromSub:CreateButton((L["nach %s"]):format(to))
                    for _, d in ipairs(PROMOTE_DAYS) do
                        toSub:CreateButton((L["%d Tage"]):format(d), function() AddPromoteRule(from, to, d) end)
                    end
                    toSub:CreateButton(L["Eigene Tage …"], function()
                        StaticPopup_Show("GUILDPRIDE_PROMOTE_DAYS", nil, nil, { from = from, to = to })
                    end)
                end
            end
        end
    end)
end)
rosterOffline:SetScript("OnClick", function(self) SetOffline(self:GetChecked() and true or false) end)

-- Wessen Mitglieder? nil = Gilde, sonst { id, name, bnet } einer Community.
-- Wird beim Kanalwechsel im Chat aufgerufen.
function ns.SetMemberSource(club)
    if (club and club.id) == (source and source.id) then return end
    source = club
    if ns.HideMemberPanel then ns.HideMemberPanel() end
    -- Online-Status der Community-Mitglieder vom Server holen
    if C_Club and C_Club.ClearClubPresenceSubscription then pcall(C_Club.ClearClubPresenceSubscription) end
    if club and C_Club.SetClubPresenceSubscription then pcall(C_Club.SetClubPresenceSubscription, club.id) end
    if not club and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    RefreshMembers()
end

-- Chat oder große Liste
local function SetView(list)
    GuildPrideDB.listView = list
    chatPane:SetShown(not list); roster:SetShown(not list); members:SetShown(list)
    if bViewChat.gpBg then bViewChat.gpBg:SetTexture(MEDIA .. (list and "nav" or "nav_active")) end
    if bViewList.gpBg then bViewList.gpBg:SetTexture(MEDIA .. (list and "nav_active" or "nav")) end
    RefreshMembers()
end
bViewChat:SetScript("OnClick", function() SetView(false) end)
bViewList:SetScript("OnClick", function() SetView(true) end)

function community:Refresh()
    SetView(GuildPrideDB.listView and true or false)
    if ns.ChatRefresh then ns.ChatRefresh() end
end

-- Für Chat und Mitgliederverwaltung (GuildPrideChat.lua, GuildPrideManage.lua)
ns.Communities = Communities
ns.CanInviteToClub = CanInviteToClub
ns.FullName = FullName
ns.CommunityPage = community
ns.ChatPane = chatPane
ns.MembersPage = community

-- "zuletzt online vor …"
local function LastOnline(i)
    if not GetGuildRosterLastOnline then return L["offline"] end
    local y, m, d, h = GetGuildRosterLastOnline(i)
    if not y then return L["offline"] end
    if y > 0 then return (L["vor %d Jahr(en)"]):format(y) end
    if m > 0 then return (L["vor %d Monat(en)"]):format(m) end
    if d > 0 then return (L["vor %d Tag(en)"]):format(d) end
    if h > 0 then return (L["vor %d Std."]):format(h) end
    return L["vor < 1 Std."]
end

local function LastOnlineHours(i)
    if not GetGuildRosterLastOnline then return 0 end
    local y, m, d, h = GetGuildRosterLastOnline(i)
    return ((y or 0) * 365 + (m or 0) * 30 + (d or 0)) * 24 + (h or 0)
end

local function AgoText(y, m, d, h)
    if not y then return L["offline"] end
    if y > 0 then return (L["vor %d Jahr(en)"]):format(y) end
    if m > 0 then return (L["vor %d Monat(en)"]):format(m) end
    if d > 0 then return (L["vor %d Tag(en)"]):format(d) end
    if h > 0 then return (L["vor %d Std."]):format(h) end
    return L["vor < 1 Std."]
end

local CLUB_ROLES = { [1] = L["Besitzer"], [2] = L["Leiter"], [3] = L["Moderator"], [4] = L["Mitglied"] }
ns.CLUB_ROLES = CLUB_ROLES

local function ClassFile(classID)
    local info = classID and C_CreatureInfo and C_CreatureInfo.GetClassInfo and C_CreatureInfo.GetClassInfo(classID)
    return info and info.classFile
end

-- Gildenmitglieder (Name-Realm -> true), um "In Gilde einladen" nur Nicht-Mitgliedern anzubieten
local function GuildNames()
    local set = {}
    for i = 1, GetNumGuildMembers() do
        local name = GetGuildRosterInfo(i)
        if name then set[FullName(name)] = true end
    end
    return set
end

local function GuildData(withOffline)
    local data, total, online = {}, 0, 0
    for i = 1, GetNumGuildMembers() do
        local name, rank, rankIndex, level, _, zone, note, officerNote, isOnline, _, classFile = GetGuildRosterInfo(i)
        if name then
            total = total + 1
            if isOnline then online = online + 1 end
            if isOnline or withOffline then
                local full = FullName(name)
                data[#data + 1] = { name = Ambiguate(name, "guild"), full = full, rank = rank, rankIndex = rankIndex,
                                    level = level, zone = zone, note = note, officerNote = officerNote,
                                    online = isOnline, class = classFile, inGuild = true, guild = true,
                                    isSelf = full == ns.Me(), guid = select(17, GetGuildRosterInfo(i)),
                                    last = not isOnline and LastOnline(i) or nil,
                                    hours = not isOnline and LastOnlineHours(i) or 0 }
            end
        end
    end
    return data, total, online
end

local function ClubData(club, inGuild, withOffline)
    local data, total, online = {}, 0, 0
    local P = Enum.ClubMemberPresence or {}
    for _, id in ipairs(C_Club.GetClubMembers(club.id) or {}) do
        local info = C_Club.GetMemberInfo(club.id, id)
        if info and info.name and not (issecretvalue and issecretvalue(info.name)) then
            total = total + 1
            local p = info.presence
            local isOnline = p ~= nil and p ~= P.Offline and p ~= P.Unknown
            local mobile = p ~= nil and p == P.OnlineMobile
            if isOnline then online = online + 1 end
            if isOnline or withOffline then
                local full = not club.bnet and FullName(info.name) or nil
                local y, mo, d, h = info.lastOnlineYear, info.lastOnlineMonth, info.lastOnlineDay, info.lastOnlineHour
                data[#data + 1] = { name = club.bnet and info.name or Ambiguate(info.name, "guild"), full = full,
                                    rank = CLUB_ROLES[info.role] or "", level = info.level, online = isOnline,
                                    zone = mobile and L["Battle.net-App"] or info.zone,
                                    class = ClassFile(info.classID), isSelf = info.isSelf, club = club, clubId = club.id,
                                    memberId = info.memberId, role = info.role, note = info.memberNote,
                                    inGuild = full and inGuild[full] or false,
                                    last = not isOnline and AgoText(y, mo, d, h) or nil,
                                    hours = not isOnline and (((y or 0) * 365 + (mo or 0) * 30 + (d or 0)) * 24 + (h or 0)) or 0 }
            end
        end
    end
    return data, total, online
end

local function Plain(v)
    return type(v) == "string" and not (issecretvalue and issecretvalue(v)) and v or ""
end

-- Passt das Mitglied zur Suche? (Name, Rang, Notiz, Zone)
local function Matches(m, q)
    if q == "" then return true end
    for _, v in ipairs({ m.name, m.rank, m.note, m.zone }) do
        if Plain(v):lower():find(q, 1, true) then return true end
    end
    return false
end

-- Sortierwert je Spalte; "last": online zuerst, dann zuletzt online
local function SortValue(m, key)
    if key == "name" then return Plain(m.name):lower() end
    if key == "level" then return -(m.level or 0) end
    if key == "rank" then return m.rankIndex or m.role or 99 end
    if m.alts then return m.groupOnline and -1 or (m.groupHours or 0) end
    return m.online and -1 or (m.hours or 0)
end

---------------------------------------------------------------------
-- Twinks: Charaktere eines Spielers (GuildPrideAusweis.lua) zu einer Zeile
-- zusammenfassen. m.alts = Twinks, m.groupOnline = irgendein Charakter online,
-- m.groupHours = kürzeste Abwesenheit, m.playing = online gespielter Twink.
---------------------------------------------------------------------
local expanded = {}   -- [Main] = true: Twinks aufgeklappt
ns.ExpandedAlts = expanded

local GroupedMemberData
local function GroupingOn() return ns.AltGroups and GuildPrideDB.groupAlts ~= false end

local function GroupAlts(data)
    local groups, byFull, mains = ns.AltGroups(), {}, {}
    for _, m in ipairs(data) do byFull[m.full] = m end
    for _, m in ipairs(data) do
        local alts = groups[m.full]
        if alts then
            m.alts, m.playing = {}, nil
            m.groupOnline, m.groupHours = m.online, m.online and 0 or (m.hours or 0)
            for _, name in ipairs(alts) do
                local a = byFull[name]
                if a then
                    a.isAlt, a.mainName = true, m.name
                    m.alts[#m.alts + 1] = a
                    if a.online then
                        m.groupOnline, m.groupHours = true, 0
                        if not m.online and not m.playing then m.playing = a end
                    else
                        m.groupHours = math.min(m.groupHours, a.hours or 0)
                    end
                end
            end
            mains[#mains + 1] = m
        end
    end
    return mains
end

-- Tooltip: alle Twinks mit Level und Status
function ns.AddAltLines(tt, m)
    if not (m and m.alts and #m.alts > 0) then return end
    tt:AddLine(" ")
    tt:AddLine(L["Twinks:"], 0.94, 0.78, 0.55)
    for _, a in ipairs(m.alts) do
        local c = CLASS_COLORS[a.class] or NORMAL_FONT_COLOR
        tt:AddDoubleLine(("%s (%d)"):format(a.name, a.level or 0),
            a.online and L["online"] or (a.last or L["offline"]),
            c.r, c.g, c.b, a.online and 0.25 or 0.5, a.online and 1 or 0.5, a.online and 0.25 or 0.5)
    end
end

local function GroupMatches(m, q)
    if Matches(m, q) then return true end
    for _, a in ipairs(m.alts or {}) do if Matches(a, q) then return true end end
    return false
end

-- Wie MemberData, aber eine Zeile je Spieler. Inaktiv zählt je Spieler: Wer mit
-- irgendeinem Charakter da war, ist nicht inaktiv. Im Inaktiv-Filter stehen
-- alle Charaktere inaktiver Spieler einzeln in der Liste (für das Entfernen).
-- Rückgabe: Liste, Spieler gesamt, Spieler online, Charaktere gesamt
GroupedMemberData = function(opts, inactive, withOffline)
    local all = GuildData(true)
    local mains = GroupAlts(all)
    local total, online = #mains, 0
    for _, m in ipairs(mains) do if m.groupOnline then online = online + 1 end end
    local q, keep = strtrim(opts.query or ""):lower(), {}
    for _, m in ipairs(mains) do
        if GroupMatches(m, q) and (withOffline or m.groupOnline)
                and (inactive == 0 or (not m.groupOnline and m.groupHours >= inactive * 24
                     and not (opts.skip and opts.skip[m.rank or ""]))) then
            keep[#keep + 1] = m
        end
    end
    local key = opts.sort or "last"
    table.sort(keep, function(a, b)
        local va, vb = SortValue(a, key), SortValue(b, key)
        if va ~= vb then if opts.desc then return va > vb end return va < vb end
        if a.groupOnline ~= b.groupOnline then return a.groupOnline end
        return Plain(a.name):lower() < Plain(b.name):lower()
    end)
    local out = {}
    for _, m in ipairs(keep) do
        out[#out + 1] = m
        if inactive > 0 then
            for _, a in ipairs(m.alts) do
                if not (opts.skip and opts.skip[a.rank or ""]) then out[#out + 1] = a end
            end
        elseif expanded[m.full] and not opts.noExpand then
            for _, a in ipairs(m.alts) do out[#out + 1] = a end
        end
    end
    return out, total, online, #all
end

-- Mitglieder der aktuellen Quelle
-- opts: offline (auch Offline), query (Suche), inactive (Tage, nur Offline ab da),
--       sort/desc (Spalte und Richtung, Standard "last"), noExpand (Twinks nie aufklappen)
local function MemberData(opts)
    opts = opts or {}
    -- Community nicht mehr vorhanden (verlassen) -> zurück zur Gilde
    if source and not (C_Club.GetClubInfo and C_Club.GetClubInfo(source.id)) then source = nil end
    local inactive = opts.inactive or 0
    local withOffline = opts.offline or inactive > 0 or opts.filter
    local data, total, online
    -- Gilde mit Twink-Gruppen (nicht bei fälligen Beförderungen: die gelten je Charakter)
    if not source and not opts.filter and GroupingOn() then
        return GroupedMemberData(opts, inactive, withOffline)
    end
    if source then data, total, online = ClubData(source, GuildNames(), withOffline) else data, total, online = GuildData(withOffline) end
    local q, keep = strtrim(opts.query or ""):lower(), {}
    for _, m in ipairs(data) do
        if Matches(m, q) and (inactive == 0 or (not m.online and (m.hours or 0) >= inactive * 24
                and not (opts.skip and opts.skip[m.rank or ""])))
                and (not opts.filter or opts.filter(m)) then keep[#keep + 1] = m end
    end
    local key = opts.sort or "last"
    table.sort(keep, function(a, b)
        local va, vb = SortValue(a, key), SortValue(b, key)
        if va ~= vb then if opts.desc then return va > vb end return va < vb end
        if a.online ~= b.online then return a.online end
        return Plain(a.name):lower() < Plain(b.name):lower()
    end)
    return keep, total, online
end

local function ClassName(m)
    local c = CLASS_COLORS[m.class] or NORMAL_FONT_COLOR
    return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, m.name)
end

-- Name mit Rang-Krone; nur Gildenmitglieder, in Communities sagt der Gildenrang nichts aus
local function CrownedName(m)
    local crown = m.guild and ns.RankCrown and ns.RankCrown(m.rankIndex) or ""
    return crown .. ClassName(m)
end

-- Linksklick: Details/Verwaltung · Rechtsklick: Menü (GuildPrideManage.lua)
local function RowClicks(row)
    row:EnableMouse(true)
    row:SetScript("OnMouseUp", function(self, button)
        if not self.data then return end
        if button == "RightButton" then
            if ns.MemberMenu then ns.MemberMenu(self, self.data) end
        elseif ns.ShowMemberPanel then
            ns.ShowMemberPanel(self.data, self)
        end
    end)
end

function members:Refresh()
    local function mark(btn, on)
        if btn.gpBg then btn.gpBg:SetTexture(MEDIA .. (on and "nav_active" or "nav")) end
    end
    mark(bOnline, not showOffline); mark(bAll, showOffline)
    inviteBtn:SetText(source and L["In Community einladen"] or L["In Gilde einladen"])
    -- Inaktive / Beförderungen: nur Gilde, nur wer entfernen oder befördern darf
    local canInactive = not source and ((CanGuildRemove and CanGuildRemove())
        or (CanGuildPromote and CanGuildPromote()) or ns.IsOfficer())
    if not canInactive then inactiveDays, promoteMode = 0, false end
    bInactive:SetShown(canInactive and true or false)
    bInactive:SetText(promoteMode and L["Beförderung fällig"]
        or inactiveDays > 0 and (L["Inaktiv %d+ Tage"]):format(inactiveDays) or L["Inaktive: aus"])
    MarkSort()

    local s = GuildPrideDB.memberSort or {}
    local data, total, online, chars = MemberData({ offline = showOffline, sort = s.key, desc = s.desc,
                                             query = searchBox:GetText(), inactive = inactiveDays,
                                             skip = inactiveDays > 0 and SkippedRanks() or nil,
                                             filter = promoteMode and ns.PromoteTarget or nil })
    if chars then
        countText:SetText((L["%d Spieler online · %d offline (%d Charaktere)"]):format(online, total - online, chars))
    else
        countText:SetText((L["%d online · %d offline"]):format(online, total - online))
    end
    if promoteMode then UpdateAction("promote", data)
    else UpdateAction("kick", canInactive and inactiveDays > 0 and data or nil) end
    for i, m in ipairs(data) do
        local row = memberList:GetRow(i)
        if not row.gpMenu then
            row.gpMenu = true
            row.mid:SetWidth(260); row.mid:SetJustifyH("LEFT"); row.mid:SetWordWrap(false)
            RowClicks(row)
        end
        row.data = m
        local active = m.online or (m.alts and m.groupOnline)
        local alpha = active and 1 or 0.55   -- Offline-Mitglieder gedimmt
        if m.isAlt then
            row.left:SetText("    |cff777777└|r " .. CrownedName(m))
        else
            row.left:SetText(CrownedName(m))
        end
        row.left:SetAlpha(alpha); row.mid:SetAlpha(alpha)
        -- Knopf "+3" hinter dem Namen: Twinks auf- und zuklappen
        if not row.gpToggle then
            local t = CreateFrame("Button", nil, row)
            t:SetSize(28, 16)
            t:SetPoint("LEFT", row.left, "RIGHT", 6, 0)
            t.text = t:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
            t.text:SetAllPoints()
            t:SetScript("OnClick", function(self)
                local d = self:GetParent().data
                if not d then return end
                ns.ExpandedAlts[d.full] = not ns.ExpandedAlts[d.full] or nil
                RefreshMembers()
            end)
            t:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(ns.ExpandedAlts[self:GetParent().data.full] and L["Twinks zuklappen"] or L["Twinks zeigen"])
                GameTooltip:Show()
            end)
            t:SetScript("OnLeave", GameTooltip_Hide)
            row.gpToggle = t
        end
        local nAlts = m.alts and #m.alts or 0
        row.gpToggle:SetShown(nAlts > 0 and inactiveDays == 0)
        if nAlts > 0 then
            row.gpToggle.text:SetText((expanded[m.full] and "−" or "+") .. nAlts)
        end
        local mid = (m.level and m.level > 0) and ("Lvl %d · %s"):format(m.level, m.rank or "") or (m.rank or "")
        if source and m.inGuild then mid = mid .. "  |cff999999(" .. L["Gilde"] .. ")|r" end
        local key = ns.KeyText and m.full and ns.KeyText(m.full)
        if key then mid = mid .. "  " .. key end
        if m.note and m.note ~= "" then mid = mid .. "  |cff888888" .. m.note .. "|r" end
        if m.isAlt and ns.IsNewLink and ns.CanSetAlts and ns.CanSetAlts() and ns.IsNewLink(m.full) then
            mid = mid .. "  |cffffd100" .. L["neu verknüpft"] .. "|r"
        end
        row.mid:SetText(mid)
        if m.playing then
            row.right:SetText(("|cff40ff40●|r " .. L["spielt %s (%d)"]):format(m.playing.name, m.playing.level or 0))
        else
            row.right:SetText(m.online and ("|cff40ff40●|r " .. (m.zone or "")) or ("|cff777777" .. (m.last or "") .. "|r"))
        end
    end
    memberList:Finish(#data)
end

-- Kompakte Liste: Name und Level, Rest im Tooltip
local function RosterTooltip(row)
    local m = row.data
    if not m then return end
    GameTooltip:SetOwner(row, "ANCHOR_LEFT")
    GameTooltip:AddLine(ClassName(m))
    if m.level and m.level > 0 then GameTooltip:AddLine(("Lvl %d"):format(m.level), 1, 1, 1) end
    if m.rank and m.rank ~= "" then GameTooltip:AddLine((L["Rang: %s"]):format(m.rank), 0.8, 0.8, 0.8) end
    -- Blizzards Tooltip-Schrift kennt "●" nicht (Kästchen) -> Online-Symbol als Grafik
    if m.online then GameTooltip:AddLine("|TInterface\\FriendsFrame\\StatusIcon-Online:12:12|t " .. (m.zone or ""), 1, 1, 1)
    else GameTooltip:AddLine(m.last or L["offline"], 0.5, 0.5, 0.5) end
    if m.note and m.note ~= "" then GameTooltip:AddLine(m.note, 0.6, 0.6, 0.6, true) end
    if ns.KeyTooltip and m.full then ns.KeyTooltip(GameTooltip, m.full) end
    local since = m.guild and ns.HistoryLine and ns.HistoryLine(m.full)
    if since then GameTooltip:AddLine(since, 0.6, 0.6, 0.6) end
    ns.AddAltLines(GameTooltip, m)
    GameTooltip:Show()
end

function roster:Refresh()
    rosterOffline:SetChecked(showOffline)
    UpdateRosterInvite()
    local data, total, online = MemberData({ offline = showOffline, noExpand = true })
    rosterCount:SetText((L["%d online · %d offline"]):format(online, total - online))
    for i, m in ipairs(data) do
        local row = rosterList:GetRow(i)
        if not row.gpMenu then
            row.gpMenu = true
            row.mid:Hide()
            row.left:SetPoint("RIGHT", row.right, "LEFT", -4, 0)
            row.left:SetWordWrap(false)
            RowClicks(row)
            row:SetScript("OnEnter", RosterTooltip)
            row:SetScript("OnLeave", GameTooltip_Hide)
        end
        row.data = m
        local active = m.online or (m.alts and m.groupOnline)
        local alpha = active and 1 or 0.55
        row.left:SetText((active and "|cff40ff40●|r " or "|cff555555●|r ") .. CrownedName(m)
            .. ((m.alts and #m.alts > 0) and (" |cff999999+" .. #m.alts .. "|r") or ""))
        row.left:SetAlpha(alpha)
        row.right:SetText((m.level and m.level > 0) and m.level or "")
    end
    rosterList:Finish(#data)
end

-- Style gewechselt: Kronen in der neuen Farbe zeigen
ns.OnThemeChanged(RefreshMembers)

-- Community-Mitglieder ändern sich -> Liste neu zeichnen (gebündelt)
if HAS_CLUB then
    local pending
    local cf = CreateFrame("Frame")
    for _, e in ipairs({ "CLUB_MEMBER_ADDED", "CLUB_MEMBER_REMOVED", "CLUB_MEMBER_UPDATED",
                         "CLUB_MEMBER_PRESENCE_UPDATED", "CLUB_REMOVED" }) do
        pcall(cf.RegisterEvent, cf, e)
    end
    cf:SetScript("OnEvent", function(_, _, clubId)
        if not (source and community:IsVisible()) or pending then return end
        if clubId and clubId ~= source.id then return end
        pending = C_Timer.NewTimer(0.5, function() pending = nil; RefreshMembers() end)
    end)
    community:HookScript("OnHide", function()
        if C_Club.ClearClubPresenceSubscription then pcall(C_Club.ClearClubPresenceSubscription) end
    end)
    community:HookScript("OnShow", function()
        if source and C_Club.SetClubPresenceSubscription then pcall(C_Club.SetClubPresenceSubscription, source.id) end
    end)
end

---------------------------------------------------------------------
-- 3) Meilensteine (Verlauf)
---------------------------------------------------------------------
local milestones = AddTab(L["Meilensteine"], 60)
local msList = CreateList(milestones, 24)

function milestones:Refresh()
    local log = ns.GuildLog()
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

---------------------------------------------------------------------
-- 4) Einstellungen
---------------------------------------------------------------------
local settingsPage = AddTab(L["Einstellungen"], 90)
-- Die Seite ist länger als das Fenster: Inhalt in einem Scrollbereich
local settingsScroll = ns.NewScroll(settingsPage)
settingsScroll:SetPoint("TOPLEFT", 0, -30)
settingsScroll:SetPoint("BOTTOMRIGHT", -26, 0)
local settings = CreateFrame("Frame", nil, settingsScroll)
settings:SetSize(640, 1)
settingsScroll:SetScrollChild(settings)

-- Style-Auswahl ganz oben: ein Knopf je Style, der aktive ist hervorgehoben
local styleLabel = settings:CreateFontString(nil, "OVERLAY", "GPFont_TextBold")
styleLabel:SetPoint("TOPLEFT", 4, -4)
styleLabel:SetText(L["Style"])
local styleButtons = {}
for i, t in ipairs(ns.THEMES) do
    local b = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
    b:SetSize(98, 24)
    b:SetPoint("TOPLEFT", 4 + (i - 1) * 104, -22)
    b:SetText(t.name)
    b:SetScript("OnClick", function() ns.ApplyTheme(t.key) end)
    -- Farbtupfer des Styles
    local dot = b:CreateTexture(nil, "OVERLAY")
    dot:SetSize(8, 8); dot:SetPoint("LEFT", 8, 0)
    b.dot, b.theme = dot, t
    b.key = t.key
    styleButtons[i] = b
end
local function MarkStyle()
    local current = ns.Theme().key
    for _, b in ipairs(styleButtons) do
        if b.gpBg then b.gpBg:SetTexture(MEDIA .. (b.key == current and "nav_active" or "nav")) end
        local c = b.theme.ember   -- "Eigene" ändert die Farbe
        b.dot:SetColorTexture(c[1], c[2], c[3], 1)
    end
end
ns.OnThemeChanged(MarkStyle)

-- Eigener Style: Farbe über Blizzards Farbwähler
local colorBtn = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
colorBtn:SetSize(170, 22); colorBtn:SetPoint("TOPLEFT", 4, -50)
colorBtn:SetText(L["Eigene Farbe wählen …"])
colorBtn:SetScript("OnClick", function() ns.PickCustomColor() end)

local OPT_Y = -80
local options = {
    { header = L["Allgemein"] },
    { key = "replaceGuildFrame", label = L["Dieses Fenster statt Blizzard-Gildenfenster (J)"] },
    { key = "compactMenu",   label = L["Kompaktes Menü (Übersicht + Meilensteine, Events + Gruppensuche + Umfragen zusammen)"],
      changed = function() if ns.MenuChanged then ns.MenuChanged() end end },
    { key = "minimap",       label = L["Minimap-Knopf anzeigen"],
      changed = function() if ns.UpdateMinimap then ns.UpdateMinimap() end end },
    { header = L["Hinweise"] },
    { key = "popup",         label = L["Meilenstein-Popups anzeigen"] },
    { key = "sound",         label = L["Sounds abspielen"] },
    { key = "memberAlerts",  label = L["Warnung bei Beitritt / Austritt"] },
    { key = "helpAlerts",    label = L["Hinweis, wenn jemand Gruppe / Quest-Hilfe sucht"] },
    { header = L["Teilen"] },
    { key = "shareMilestones", label = L["Eigene Erfolge, Bosse, M+ und Reittiere mit der Gilde teilen"] },
    { key = "mapShow",       label = L["Gildenmitglieder mit GuildPride auf der Weltkarte zeigen"],
      changed = function() if ns.MapShowChanged then ns.MapShowChanged() end end },
    { key = "mapShare",      label = L["Eigene Position auf der Weltkarte mit der Gilde teilen"],
      changed = function() if ns.MapShareChanged then ns.MapShareChanged() end end },
    { key = "publicLFG",     label = L["Serverweite Gruppensuche (alle mit GuildPride, gleiche Spielversion)"], public = true,
      changed = function() if ns.PublicLFGChanged then ns.PublicLFGChanged() end end },
    { key = "publicAlerts",  label = L["Hinweis auch bei Einträgen vom Server"], public = true },
    { header = L["Gilde"] },
    { key = "welcome",       label = L["Neue Mitglieder automatisch im Gildenchat begrüßen"] },
    { key = "discordBridge", label = L["Discord-Anbindung nutzen (Events, Anmeldungen, DKP an Discord)"] },
    { key = "discordLinked", label = L["Mein Discord ist mit WoW verknüpft (Optionen > Soziales)"] },
    { header = L["Twinks"] },
    { key = "ausweisAuto",   label = L["Meine Charaktere automatisch verknüpfen (BattleTag bleibt privat)"] },
    { key = "groupAlts",     label = L["Twinks in der Mitgliederliste unter dem Main zusammenfassen"],
      changed = function() if ns.RefreshUI then ns.RefreshUI() end end },
}
-- Serverweite Gruppensuche: in Classic-Clients nicht möglich, Schalter weglassen
for i = #options, 1, -1 do
    if options[i].public and not ns.HAS_PUBLIC_LFG then table.remove(options, i) end
end
local function SetOption(opt, on)
    GuildPrideDB[opt.key] = on and true or false
    if opt.changed then opt.changed() end
end
local checks = {}
for i, opt in ipairs(options) do
  if opt.header then
    -- Abschnitts-Überschrift statt Haken
    local h = settings:CreateFontString(nil, "OVERLAY", "GPFont_TextBold")
    h:SetPoint("TOPLEFT", 4, OPT_Y - (i - 1) * 30 - 8)
    h:SetText(opt.header)
    opt.fs, opt.y = h, OPT_Y - (i - 1) * 30
  else
    local cb = CreateFrame("CheckButton", nil, settings, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 0, OPT_Y - (i - 1) * 30)
    local label = settings:CreateFontString(nil, "OVERLAY", "GPFont_Text")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetText(opt.label)
    cb:SetScript("OnClick", function(self) SetOption(opt, self:GetChecked()) end)
    checks[opt.key] = cb
    opt.fs, opt.cb, opt.y = label, cb, OPT_Y - (i - 1) * 30
  end
end

do
-- Suche oben: passende Einstellungen hervorheben, andere abblenden,
-- zur ersten passenden springen (Inhalt wird unten nach "options" gefüllt)
local settingsSearch = CreateFrame("EditBox", nil, settingsPage, "InputBoxTemplate")
settingsSearch:SetSize(220, 22); settingsSearch:SetPoint("TOPLEFT", 10, -2)
settingsSearch:SetAutoFocus(false)
local settingsSearchHint = settingsSearch:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
settingsSearchHint:SetPoint("LEFT", 4, 0)
settingsSearchHint:SetText(L["Einstellung suchen …"])
settingsSearch:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
settingsSearch:SetScript("OnEnterPressed", settingsSearch.ClearFocus)

settingsSearch:SetScript("OnTextChanged", function(self)
    local q = strtrim(self:GetText() or ""):lower()
    settingsSearchHint:SetShown(q == "")
    local first
    for _, opt in ipairs(options) do
        if opt.fs then
            local text = (opt.label or opt.header or ""):lower()
            local hit = q ~= "" and text:find(q, 1, true) ~= nil
            local a = (q == "" or hit) and 1 or 0.3
            opt.fs:SetAlpha(a)
            if opt.cb then opt.cb:SetAlpha(a) end
            if hit and not opt.header then
                opt.fs:SetTextColor(1, 0.82, 0.2)
                if not first then first = opt end
            elseif not opt.header then
                opt.fs:SetTextColor(0.92, 0.90, 0.88)
            end
        end
    end
    if first then
        local range = settingsScroll:GetVerticalScrollRange() or 0
        settingsScroll:SetVerticalScroll(math.min(range, math.max(0, -first.y - 40)))
    end
end)
end

local blizzBtn = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
blizzBtn:SetSize(220, 26)
blizzBtn:SetPoint("TOPLEFT", 4, OPT_Y - (#options * 30) - 8)
blizzBtn:SetText(L["Blizzard-Gildenfenster öffnen"])
blizzBtn:SetScript("OnClick", function() ns.OpenBlizzardGuild() end)

do
local backupBtn = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
backupBtn:SetSize(180, 26)
backupBtn:SetPoint("LEFT", blizzBtn, "RIGHT", 10, 0)
backupBtn:SetText(L["Datensicherung …"])
backupBtn:SetScript("OnClick", function() if ns.ToggleBackupWindow then ns.ToggleBackupWindow() end end)
end

-- Begrüßungstext (GuildPrideMembers.lua), {name} = neues Mitglied
local welcomeY = OPT_Y - (#options * 30) - 46
local welcomeLabel = settings:CreateFontString(nil, "OVERLAY", "GPFont_TextBold")
welcomeLabel:SetPoint("TOPLEFT", 4, welcomeY)
welcomeLabel:SetText(L["Begrüßungstext ({name} = neues Mitglied)"])
local welcomeBox = CreateFrame("EditBox", nil, settings, "InputBoxTemplate")
welcomeBox:SetSize(470, 22); welcomeBox:SetPoint("TOPLEFT", 10, welcomeY - 18)
welcomeBox:SetAutoFocus(false); welcomeBox:SetMaxLetters(200)
welcomeBox:SetScript("OnTextChanged", function(self, user)
    if user then GuildPrideDB.welcomeText = self:GetText() end
end)
welcomeBox:SetScript("OnEnterPressed", welcomeBox.ClearFocus)
welcomeBox:SetScript("OnEscapePressed", welcomeBox.ClearFocus)

-- Regler mit - / +: Fenstergröße, Deckkraft, Chat-Schrift
local function ApplyLook()
    frame:SetScale(GuildPrideDB.scale or 1)
    frame:SetAlpha(GuildPrideDB.alpha or 1)
end
local steppers = {}
local function Stepper(label, y, key, step, min, max, fmt, apply)
    local l = settings:CreateFontString(nil, "OVERLAY", "GPFont_Text")
    l:SetPoint("TOPLEFT", 8, y); l:SetWidth(170); l:SetText(label)
    local minus = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
    minus:SetSize(26, 22); minus:SetPoint("LEFT", l, "RIGHT", 4, 0); minus:SetText("-")
    local value = settings:CreateFontString(nil, "OVERLAY", "GPFont_TextBold")
    value:SetPoint("LEFT", minus, "RIGHT", 6, 0); value:SetWidth(60)
    local plus = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
    plus:SetSize(26, 22); plus:SetPoint("LEFT", value, "RIGHT", 6, 0); plus:SetText("+")
    local s = { value = value }
    function s.Show() value:SetText(fmt(GuildPrideDB[key])) end
    local function Change(d)
        local v = (GuildPrideDB[key] or min) + d
        v = math.max(min, math.min(max, math.floor(v / step + 0.5) * step))
        GuildPrideDB[key] = v
        apply(v)
        s.Show()
    end
    minus:SetScript("OnClick", function() Change(-step) end)
    plus:SetScript("OnClick", function() Change(step) end)
    steppers[#steppers + 1] = s
end
local lookY = welcomeY - 56
local function Pct(v) return ("%d %%"):format(math.floor((v or 1) * 100 + 0.5)) end
Stepper(L["Fenstergröße"], lookY, "scale", 0.05, 0.6, 2, Pct, ApplyLook)
Stepper(L["Deckkraft"], lookY - 28, "alpha", 0.05, 0.5, 1, Pct, ApplyLook)
Stepper(L["Chat-Schrift"], lookY - 56, "chatFont", 1, 10, 18, function(v) return ("%d pt"):format(v or 12) end,
    function(v) if ns.SetChatFont then ns.SetChatFont(v) end end)

-- Ecke unten rechts: ziehen vergrößert/verkleinert das ganze Fenster
-- (alles wächst mit, auch die Schrift). Die linke obere Ecke bleibt stehen.
do   -- eigener Block (Grenze von 200 lokalen Variablen)
local SCALE_MIN, SCALE_MAX = 0.6, 2
local grip = CreateFrame("Button", nil, frame)
grip:SetSize(18, 18)
grip:SetPoint("BOTTOMRIGHT", -3, 3)
grip:SetFrameLevel(frame:GetFrameLevel() + 50)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["Ziehen: Fenster größer oder kleiner"])
    GameTooltip:AddLine(L["Rechtsklick: zurück auf 100 %"], 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
grip:SetScript("OnLeave", GameTooltip_Hide)
local function KeepTopLeft(left, top, scale)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
end
local function ShowSteppers() for _, st in ipairs(steppers) do st.Show() end end
grip:RegisterForClicks("RightButtonUp")
grip:SetScript("OnClick", function()
    local sc = frame:GetScale()
    local left, top = frame:GetLeft() * sc, frame:GetTop() * sc
    GuildPrideDB.scale = 1
    frame:SetScale(1)
    KeepTopLeft(left, top, 1)
    ShowSteppers()
end)
grip:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    local sc = frame:GetScale()
    -- Lage in UIParent-Einheiten (unabhängig von der eigenen Skalierung)
    local left, top = frame:GetLeft() * sc, frame:GetTop() * sc
    local uiScale = UIParent:GetEffectiveScale()
    self:SetScript("OnUpdate", function()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / uiScale, cy / uiScale
        local new = math.max((cx - left) / W, (top - cy) / H)
        new = math.max(SCALE_MIN, math.min(SCALE_MAX, new))
        if math.abs(new - frame:GetScale()) > 0.005 then
            frame:SetScale(new)
            KeepTopLeft(left, top, new)
        end
    end)
end)
grip:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
    GuildPrideDB.scale = math.floor(frame:GetScale() * 100 + 0.5) / 100
    ShowSteppers()
end)
end

local lookFrame = CreateFrame("Frame")
lookFrame:RegisterEvent("PLAYER_LOGIN")
lookFrame:SetScript("OnEvent", ApplyLook)

-- Werbetext, Bewerbungen und Notiz-Vorlagen: Reiter "Verwaltung" (GuildPrideAdmin.lua)
local baseY = lookY - 96

-- Menü anpassen: Reiter zeigen/ausblenden, umbenennen, verschieben, Startreiter.
-- Die Zeilen entstehen erst beim ersten Öffnen, weil andere Dateien ihre
-- Reiter nach dieser Datei anlegen.
local MENU_ROWS = 10
local menuY = baseY
Section(settings, L["Menü anpassen"], nil, menuY)
local menuHint = settings:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
menuHint:SetPoint("TOPLEFT", 4, menuY - 26)
menuHint:SetWidth(620); menuHint:SetJustifyH("LEFT")
menuHint:SetText(L["Haken = sichtbar, Name ändern, Pfeile = Reihenfolge, Start = beim Öffnen gezeigt. „Einstellungen“ bleibt immer da."])
menuHint:SetTextColor(0.75, 0.72, 0.68)
local menuRows = {}

local function RenumberMenu(list)
    for i, tab in ipairs(list) do MenuEntry(tab, true).order = i * 10 end
end

local RefreshMenuRows
local function MoveTab(index, dir)
    local list = MenuTabs()
    local other = index + dir
    if not list[index] or not list[other] then return end
    list[index], list[other] = list[other], list[index]
    RenumberMenu(list)
    ns.MenuChanged()
    RefreshMenuRows()
end

local function ArrowButton(parent, up)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(24, 24)
    local base = "Interface\\ChatFrame\\UI-ChatIcon-Scroll" .. (up and "Up" or "Down")
    b:SetNormalTexture(base .. "-Up")
    b:SetPushedTexture(base .. "-Down")
    b:SetDisabledTexture(base .. "-Disabled")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    return b
end

local function BuildMenuRow(i)
    local y = menuY - 48 - (i - 1) * 30
    local row = {}
    row.show = CreateFrame("CheckButton", nil, settings, "UICheckButtonTemplate")
    row.show:SetSize(26, 26); row.show:SetPoint("TOPLEFT", 4, y)
    row.show:SetScript("OnClick", function(self)
        local tab = row.tab
        if not tab then return end
        MenuEntry(tab, true).hide = not self:GetChecked() or nil
        ns.MenuChanged()
        RefreshMenuRows()
    end)
    row.name = CreateFrame("EditBox", nil, settings, "InputBoxTemplate")
    row.name:SetSize(200, 22); row.name:SetPoint("TOPLEFT", 42, y - 2)
    row.name:SetAutoFocus(false); row.name:SetMaxLetters(24)
    row.name:SetScript("OnTextChanged", function(self, user)
        local tab = row.tab
        if not user or not tab then return end
        local text = strtrim(((self:GetText() or ""):gsub("|", "")))
        MenuEntry(tab, true).name = (text ~= "" and text ~= (tab.shownDefault or tab.defaultLabel)) and text or nil
        ns.MenuChanged()
    end)
    row.name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    row.name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    row.name:SetScript("OnEditFocusLost", function(self)
        if row.tab then self:SetText(row.tab.label) end
    end)
    row.orig = settings:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    row.orig:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
    row.orig:SetWidth(150); row.orig:SetJustifyH("LEFT")
    row.orig:SetTextColor(0.6, 0.58, 0.55)
    row.up = ArrowButton(settings, true)
    row.up:SetPoint("LEFT", row.name, "RIGHT", 168, 0)
    row.up:SetScript("OnClick", function() MoveTab(row.index, -1) end)
    row.down = ArrowButton(settings, false)
    row.down:SetPoint("LEFT", row.up, "RIGHT", 2, 0)
    row.down:SetScript("OnClick", function() MoveTab(row.index, 1) end)
    row.start = CreateFrame("CheckButton", nil, settings, "UIRadioButtonTemplate")
    row.start:SetPoint("LEFT", row.down, "RIGHT", 16, 0)
    row.start:SetScript("OnClick", function()
        -- Nochmal klicken: kein fester Start mehr (zuletzt offener Reiter)
        if row.tab then
            GuildPrideDB.startTab = GuildPrideDB.startTab ~= row.tab.key and row.tab.key or nil
        end
        RefreshMenuRows()
    end)
    row.startText = settings:CreateFontString(nil, "OVERLAY", "GPFont_Text")
    row.startText:SetPoint("LEFT", row.start, "RIGHT", 4, 0)
    row.startText:SetText(L["Start"])
    row.widgets = { row.show, row.name, row.orig, row.up, row.down, row.start, row.startText }
    menuRows[i] = row
    return row
end

local menuReset = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
menuReset:SetSize(200, 24)
menuReset:SetText(L["Menü zurücksetzen"])
menuReset:SetScript("OnClick", function()
    GuildPrideDB.menu = nil
    GuildPrideDB.startTab = nil
    ns.MenuChanged()
    RefreshMenuRows()
end)

function RefreshMenuRows()
    local list = MenuTabs()
    local startKey = GuildPrideDB.startTab
    for i = 1, math.min(#list, MENU_ROWS) do
        local row = menuRows[i] or BuildMenuRow(i)
        local tab = list[i]
        row.tab, row.index = tab, i
        for _, w in ipairs(row.widgets) do w:Show() end
        row.show:SetChecked(not TabHidden(tab))
        if not row.name:HasFocus() then row.name:SetText(tab.label) end
        local def = tab.shownDefault or tab.defaultLabel
        row.orig:SetText(tab.label ~= def and ("(" .. def .. ")") or "")
        row.up:SetEnabled(i > 1)
        row.down:SetEnabled(i < #list)
        row.start:SetChecked(startKey == tab.key)
    end
    for i = #list + 1, #menuRows do
        menuRows[i].tab = nil
        for _, w in ipairs(menuRows[i].widgets) do w:Hide() end
    end
    menuReset:ClearAllPoints()
    menuReset:SetPoint("TOPLEFT", 10, menuY - 56 - math.min(#list, MENU_ROWS) * 30)
end

settings:SetHeight(-(menuY - 56 - MENU_ROWS * 30 - 60))

function settingsPage:Refresh()
    RefreshMenuRows()
    MarkStyle()
    for key, cb in pairs(checks) do cb:SetChecked(GuildPrideDB[key]) end
    for _, s in ipairs(steppers) do s.Show() end
    if not welcomeBox:HasFocus() then
        local w = GuildPrideDB.welcomeText
        welcomeBox:SetText((w and w ~= "") and w or (ns.WELCOME_DEFAULT or ""))
    end
end
ns.SettingsPage = settingsPage

-- Dieselben Schalter im WoW-Menü (Optionen -> AddOns -> GuildPride)
-- Ältere Classic-Clients ohne neues Settings-Menü: alte Interface-Optionen
if (Settings and Settings.RegisterCanvasLayoutCategory) or InterfaceOptions_AddCategory then
    local panel = CreateFrame("Frame")
    panel.name = "GuildPride"
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("GuildPride")
    local panelChecks = {}
    for i, opt in ipairs(options) do
      if opt.header then
        local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h:SetPoint("TOPLEFT", 20, -44 - (i - 1) * 32 - 8)
        h:SetText(opt.header)
      else
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 16, -44 - (i - 1) * 32)
        local label = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        label:SetText(opt.label)
        cb:SetScript("OnClick", function(self) SetOption(opt, self:GetChecked()) end)
        panelChecks[opt.key] = cb
      end
    end
    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(220, 26)
    open:SetPoint("TOPLEFT", 20, -44 - #options * 32 - 12)
    open:SetText(L["Gildenfenster öffnen"])
    open:SetScript("OnClick", function()
        if SettingsPanel then HideUIPanel(SettingsPanel) end
        if InterfaceOptionsFrame then HideUIPanel(InterfaceOptionsFrame) end
        if not frame:IsShown() then ns.ToggleUI() end
    end)
    panel:SetScript("OnShow", function()
        if not GuildPrideDB then return end
        for key, cb in pairs(panelChecks) do cb:SetChecked(GuildPrideDB[key]) end
    end)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "GuildPride")
        Settings.RegisterAddOnCategory(category)
        ns.SettingsCategory = category
    else
        InterfaceOptions_AddCategory(panel)
        ns.SettingsPanel = panel
    end
end

---------------------------------------------------------------------
-- Öffnen / Aktualisieren
---------------------------------------------------------------------
function ns.RefreshUI()
    if not frame:IsShown() then return end
    UpdateHeader()
    local page = pages[frame.selected or 1]
    if page and page.Refresh then page:Refresh() end
end

function ns.ToggleUI()
    if frame:IsShown() then
        frame:Hide()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
    else
        if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        LayoutTabs()
        -- Gewählter Startreiter bei jedem Öffnen, sonst der zuletzt offene
        local cur = tabs[frame.selected or 0]
        if (GuildPrideDB and GuildPrideDB.startTab) or not cur or TabHidden(cur) then
            frame.selected = StartTabId()
        end
        frame:Show()   -- OnShow-Haken (z. B. geänderte Gildeninfo) darf das noch ändern
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
        UpdateHeader()
        SelectTab(frame.selected or 1)
    end
end

---------------------------------------------------------------------
-- Blizzard-Gildenfenster ersetzen
---------------------------------------------------------------------
do   -- eigener Block: Lua erlaubt nur 200 lokale Variablen je Datei-Ebene
local bypass = false
local blockUntil = 0   -- Blizzard-Fenster bis zu diesem Zeitpunkt sofort wieder schließen

-- Blizzard-Gildenfenster je nach Client: Communities (Retail, MoP),
-- GuildFrame (Cata/Wrath) oder der Gilden-Reiter im Freundesfenster (Era, Anniversary)
local function HideBlizzardGuild()
    -- Im Kampf kein HideUIPanel: das läuft über den geschützten Fenster-Manager
    local hide = InCombatLockdown() and function(f) f:Hide() end or HideUIPanel
    local hidden = false
    for _, f in ipairs({ CommunitiesFrame, GuildFrame }) do
        if f and f:IsShown() then hide(f); hidden = true end
    end
    -- Freundesfenster nur, wenn ToggleGuildFrame kein eigenes Gildenfenster geöffnet hat
    if not hidden and FriendsFrame and FriendsFrame:IsShown() then hide(FriendsFrame) end
end

function ns.OpenBlizzardGuild()
    frame:Hide()
    blockUntil = 0
    bypass = true
    if ToggleGuildFrame then ToggleGuildFrame() end
    bypass = false
end

-- Öffnet sich das Blizzard-Fenster verzögert oder ein zweites Mal (Laden bei Bedarf,
-- Fenster-Manager), schließen wir es beim Anzeigen gleich wieder.
local hookedShow = {}
local function HookBlizzardShow()
    for _, f in ipairs({ CommunitiesFrame, GuildFrame }) do
        if f and not hookedShow[f] then
            hookedShow[f] = true
            f:HookScript("OnShow", function(self)
                if GetTime() < blockUntil then C_Timer.After(0, HideBlizzardGuild) end
            end)
        end
    end
end
HookBlizzardShow()
local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", HookBlizzardShow)

-- Wir überschreiben ToggleGuildFrame NICHT (würde Taint verursachen),
-- sondern schließen das Blizzard-Fenster direkt nach dem Öffnen wieder.
-- Gilt auch im Kampf: unser Fenster ist dann weiter bedienbar (Chat lesen und schreiben).
if ToggleGuildFrame then
    hooksecurefunc("ToggleGuildFrame", function()
        if bypass or not GuildPrideDB or not GuildPrideDB.replaceGuildFrame then return end
        if not IsInGuild() then return end
        blockUntil = GetTime() + 0.5
        HookBlizzardShow()
        HideBlizzardGuild()
        C_Timer.After(0, HideBlizzardGuild)
        ns.ToggleUI()
    end)
end
end

-- Für andere Module freigeben
ns.AddTab = AddTab
ns.SelectTab = SelectTab
ns.CreateList = CreateList
ns.GuildFrame = frame
ns.MEDIA = MEDIA
