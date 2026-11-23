-- GuildPride: Notizzettel auf der Karte
-- „Zettel schreiben“ (Knopf auf der Weltkarte, Kartenfilter, /gp zettel) hängt einen
-- Zettel genau dort auf, wo du stehst. Wer bis auf ~5 m herankommt, dem geht der
-- Zettel auf: Text und als Unterschrift der Charaktername des Schreibers.
--   Gildenzettel (blau):  über den abgesicherten Gildenkanal  ZTG/ZTX (ns.On)
--   Zettel für alle (weiß): über den offenen Kanal            ZTP/ZTD (GuildPride.lua → ns.OnZettelPublic)
-- Die Schlüssel ergeben sich aus dem Absender, darum kann niemand fremde Zettel
-- überschreiben oder abreißen. Der Schreiber schickt seine Zettel regelmäßig
-- erneut, damit auch später Eingeloggte sie bekommen. Zettel halten 7 Tage.
-- Abschalten: Weltkarten-Knopf (Rechtsklick), Kartenfilter, Einstellungen, /gp zettel aus
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP or "\031"

local Z = {}
ns.Zettel = Z

local MAX_TEXT    = 140            -- Byte (Platz für den offenen Kanal: 255 Byte je Nachricht)
local LIFETIME    = 7 * 86400
local RESEND      = 15 * 60        -- eigene Zettel erneut senden
local SEND_GAP    = 3              -- s zwischen zwei eigenen Zettel-Nachrichten
local TRIGGER     = 5.5            -- Yards (~5 m)
local REARM       = 15             -- erst so weit weg, dann löst der Zettel wieder aus
local MAX_OWN     = 10
local MAX_SENDER  = 5              -- fremde Zettel je Absender (offener Kanal)
local MAX_PUBLIC  = 300
local MEDIA       = "Interface\\AddOns\\GuildPrideForever\\Media\\"
local PAPER       = MEDIA .. "zettel"
local PIN         = MEDIA .. "zettel_pin"
local BLUE, WHITE = { 0.35, 0.65, 1 }, { 1, 1, 1 }
local INK         = { 0.12, 0.16, 0.42 }

---------------------------------------------------------------------
-- Daten
---------------------------------------------------------------------
local function DB()
    if type(GuildPrideDB) ~= "table" then return {} end
    if type(GuildPrideDB.zettel) ~= "table" then GuildPrideDB.zettel = {} end
    return GuildPrideDB.zettel
end

function Z.Enabled()
    return not (type(GuildPrideDB) == "table" and GuildPrideDB.mapNotes == false)
end

local function Me() return ns.Me and ns.Me() or UnitName("player") end
-- Unterschrift: Vor- und Nachname (WoW Forever liefert den Absender schon als
-- "Vorname Nachname", siehe ns.Normalize); sonst nur den Realm abschneiden
local function Short(name)
    if name:find(" ", 1, true) then return name end
    return (Ambiguate and Ambiguate(name, "none")) or (name:gsub("%-.*$", ""))
end

-- Text auf Bytes kürzen, ohne ein UTF-8-Zeichen zu zerschneiden
local function Cut(s, max)
    s = (ns.Clean and ns.Clean(s, 1000) or tostring(s or ""):gsub("[%c|]", "")):gsub(SEP, "")
    s = strtrim(s)
    if #s <= max then return s end
    s = s:sub(1, max)
    local i = #s
    while i > 0 and s:byte(i) >= 128 and s:byte(i) < 192 do i = i - 1 end
    if i > 0 and s:byte(i) >= 192 then
        local need = s:byte(i) >= 240 and 4 or s:byte(i) >= 224 and 3 or 2
        if #s - i + 1 < need then s = s:sub(1, i - 1) end
    end
    return s
end
Z.Cut = Cut

local function Num(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= v or v < lo or v > hi then return nil end
    return math.floor(v)
end

local function ValidMap(map)
    if not map then return false end
    if C_Map and C_Map.GetMapInfo then return C_Map.GetMapInfo(map) ~= nil end
    return true
end

local function Key(guild, sender, num) return (guild and "g:" or "p:") .. sender .. "#" .. num end

-- Abgelaufene wegräumen; bei zu vielen fremden Zetteln die ältesten
local function Prune()
    local db, now = DB(), GetServerTime()
    local public = {}
    for k, n in pairs(db) do
        if type(n) ~= "table" or not n.t or now - n.t > LIFETIME then db[k] = nil
        elseif not n.guild and n.sender ~= Me() then public[#public + 1] = k end
    end
    if #public > MAX_PUBLIC then
        table.sort(public, function(a, b) return db[a].t < db[b].t end)
        for i = 1, #public - MAX_PUBLIC do db[public[i]] = nil end
    end
end

local function Refresh()
    if ns.RefreshMapPins then ns.RefreshMapPins(true) end
end

-- Eingang (aus beiden Kanälen). Rückgabe: true, wenn neu oder geändert
function Z.Apply(guild, sender, num, map, x, y, t, text)
    num, map = Num(num, 1, 999999), Num(map, 1, 99999)
    x, y = Num(x, 0, 10000), Num(y, 0, 10000)
    t = ns.Stamp and ns.Stamp(t) or tonumber(t)
    text = Cut(text, MAX_TEXT)
    if not (num and map and x and y and t and t > 0) or text == "" or not ValidMap(map) then return false end
    if GetServerTime() - t > LIFETIME then return false end
    if ns.Block and ns.Block.IsBlocked and ns.Block.IsBlocked(sender) then return false end
    local db, key = DB(), Key(guild, sender, num)
    local old = db[key]
    if old and old.t >= t then return false end
    if not old and not guild then
        local n = 0
        for _, e in pairs(db) do if not e.guild and e.sender == sender then n = n + 1 end end
        if n >= MAX_SENDER then return false end
    end
    db[key] = { num = num, map = map, x = x / 10000, y = y / 10000, t = t, text = text,
                sender = sender, by = Short(sender), guild = guild and true or nil }
    Prune()
    Refresh()
    return true
end

function Z.Remove(guild, sender, num)
    num = Num(num, 1, 999999)
    if not num then return false end
    local key = Key(guild, sender, num)
    if not DB()[key] then return false end
    DB()[key] = nil
    if Z.shownKey == key and Z.reader then Z.reader:Hide() end
    Refresh()
    return true
end

---------------------------------------------------------------------
-- Senden (eigene Warteschlange: der offene Kanal hält je Art nur die neueste Nachricht)
---------------------------------------------------------------------
local outbox = {}
local function Push(item)
    for i = #outbox, 1, -1 do
        if outbox[i].key == item.key then table.remove(outbox, i) end
    end
    outbox[#outbox + 1] = item
end

local function Fields(n)
    return n.num, n.map, math.floor(n.x * 10000 + 0.5), math.floor(n.y * 10000 + 0.5), n.t, n.text
end

local function SendNote(n)
    Push({ key = (n.guild and "g" or "p") .. n.num, fn = function()
        if n.guild then
            if IsInGuild() then ns.Queue("ZTG", "@CHANNEL", Fields(n)) end
        elseif ns.PublicChannelId and ns.PublicChannelId() then
            ns.Queue("ZTP", "@PUBLIC", ns.CLIENT_TAG, Fields(n))
        end
    end })
end

local function SendRemove(guild, num)
    Push({ key = (guild and "g" or "p") .. num, fn = function()
        if guild then
            if IsInGuild() then ns.Queue("ZTX", "@CHANNEL", num) end
        else
            ns.Queue("ZTD", "@PUBLIC", ns.CLIENT_TAG, num)
        end
    end })
end

local function SendNext()
    local item = table.remove(outbox, 1)
    if item and ns.Queue then item.fn() end
    return item ~= nil
end
Z.SendNext = SendNext
C_Timer.NewTicker(SEND_GAP, SendNext)

local function OwnNotes()
    local list, me = {}, Me()
    for k, n in pairs(DB()) do
        if n.sender == me then list[#list + 1] = k end
    end
    table.sort(list, function(a, b) return DB()[a].t < DB()[b].t end)
    return list
end

-- Neuen Zettel schreiben: map + x, y (0 … 1) auf dieser Karte
function Z.Write(map, x, y, text, guild)
    text = Cut(text, MAX_TEXT)
    if text == "" or not map or not x or not y then return false end
    if guild and not IsInGuild() then return false end
    local db, me = DB(), Me()
    GuildPrideDB.zettelN = (tonumber(GuildPrideDB.zettelN) or 0) % 999999 + 1
    local num = GuildPrideDB.zettelN
    local key = Key(guild, me, num)
    db[key] = { num = num, map = map, x = x, y = y, t = GetServerTime(), text = text,
                sender = me, by = Short(me), guild = guild and true or nil }
    -- Höchstens MAX_OWN eigene: die ältesten abreißen
    local own = OwnNotes()
    for i = 1, #own - MAX_OWN do Z.Tear(own[i]) end
    Z.armed[key] = false     -- steht man gerade drauf, nicht sofort aufgehen
    SendNote(db[key])
    Refresh()
    return key
end

-- Eigenen Zettel abreißen (bei allen)
function Z.Tear(key)
    local n = DB()[key]
    if not n or n.sender ~= Me() then return false end
    DB()[key] = nil
    SendRemove(n.guild, n.num)
    if Z.shownKey == key and Z.reader then Z.reader:Hide() end
    Refresh()
    return true
end

-- Eigene Zettel regelmäßig erneut verschicken (für später Eingeloggte)
local function ResendOwn()
    if not Z.Enabled() then return end
    Prune()
    for _, k in ipairs(OwnNotes()) do SendNote(DB()[k]) end
end
C_Timer.NewTicker(RESEND, ResendOwn)

---------------------------------------------------------------------
-- Empfang
---------------------------------------------------------------------
ns.On("ZTG", function(payload, sender)
    if sender == Me() or not Z.Enabled() then return end
    local a = { strsplit(SEP, payload or "") }
    Z.Apply(true, sender, a[1], a[2], a[3], a[4], a[5], a[6])
end)
ns.On("ZTX", function(payload, sender)
    if sender == Me() then return end
    Z.Remove(true, sender, (strsplit(SEP, payload or "")))
end)

-- Offener Kanal: jeder kann schreiben – gebremst und streng geprüft
local perSender = {}
local function Allowed(sender)
    local now = GetTime()
    local s = perSender[sender]
    if not s then s = { n = 0, since = now }; perSender[sender] = s end
    if s.blockedUntil and now < s.blockedUntil then return false end
    if now - s.since > 60 then s.n, s.since = 0, now end
    s.n = s.n + 1
    if s.n > 12 then s.blockedUntil = now + 600; return false end
    return true
end

function ns.OnZettelPublic(message, sender)
    if type(message) ~= "string" or #message > 255 or sender == Me() or not Z.Enabled() then return end
    local kind, value = message:match("^(%u+):(.*)$")
    if kind ~= "ZTP" and kind ~= "ZTD" then return end
    if not Allowed(sender) then return end
    local a = { strsplit(SEP, value) }
    if a[1] ~= ns.CLIENT_TAG then return end
    if kind == "ZTP" then
        Z.Apply(false, sender, a[2], a[3], a[4], a[5], a[6], a[7])
    else
        Z.Remove(false, sender, a[2])
    end
end

---------------------------------------------------------------------
-- Karte: Punkte (blau = Gilde, weiß = alle)
---------------------------------------------------------------------
local function Translate(map, x, y, shown)
    if map == shown then return x, y end
    if not (C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return end
    local ok, cont, world = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
    if not ok or not cont or not world then return end
    local ok2, _, pos = pcall(C_Map.GetMapPosFromWorldPos, cont, world, shown)
    if not ok2 or not pos then return end
    local px, py = pos:GetXY()
    if not px or px < 0 or px > 1 or py < 0 or py > 1 then return end
    return px, py
end
Z.Translate = Translate

local function Ago(t)
    local d = GetServerTime() - (t or 0)
    if d < 3600 then return ("vor %d Min."):format(math.max(1, math.floor(d / 60))) end
    if d < 86400 then return ("vor %d Std."):format(math.floor(d / 3600)) end
    return ("vor %d Tag(en)"):format(math.floor(d / 86400))
end

local function PinEnter(pin, n)
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    GameTooltip:AddLine(n.guild and L["Notizzettel der Gilde"] or L["Notizzettel"],
        n.guild and BLUE[1] or 1, n.guild and BLUE[2] or 1, n.guild and BLUE[3] or 1)
    GameTooltip:AddLine(L["Geh hin, um ihn zu lesen (~5 m)."], 0.8, 0.8, 0.8)
    GameTooltip:AddLine(("– %s · %s"):format(n.by or "?", Ago(n.t)), 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function Pins(shown)
    local list = {}
    if not Z.Enabled() or not shown then return list end
    for _, n in pairs(DB()) do
        local x, y = Translate(n.map, n.x, n.y, shown)
        if x then
            list[#list + 1] = { x = x, y = y, tex = PIN, size = 13, ring = false,
                color = n.guild and BLUE or WHITE, alpha = 0.95,
                enter = function(pin) PinEnter(pin, n) end }
        end
    end
    return list
end
if ns.AddMapSource then ns.AddMapSource(Pins) end

---------------------------------------------------------------------
-- Zettel-Fenster (Lesen und Schreiben): Papier mit Ringbuch-Abriss oben,
-- zerfranst unten (Media/zettel.tga)
---------------------------------------------------------------------
local function Paper(name)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(320, 320)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("FULLSCREEN_DIALOG")   -- auch über der großen Weltkarte
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(PAPER)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 48, -44)
    f.title:SetPoint("TOPRIGHT", -30, -44)
    f.title:SetJustifyH("LEFT")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -30)
    close:SetScale(0.8)
    tinsert(UISpecialFrames, name)
    return f
end

local function Ink(fs, size)
    local font = (STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF")
    fs:SetFont(font, size or 13, "")
    fs:SetTextColor(INK[1], INK[2], INK[3])
    fs:SetShadowOffset(0, 0)
end

local function Reader()
    if Z.reader then return Z.reader end
    local f = Paper("GuildPrideZettelFrame")
    f.text = f:CreateFontString(nil, "OVERLAY")
    Ink(f.text, 14)
    f.text:SetPoint("TOPLEFT", 48, -70)
    f.text:SetPoint("TOPRIGHT", -26, -70)
    f.text:SetJustifyH("LEFT"); f.text:SetJustifyV("TOP")
    f.text:SetSpacing(4)
    f.sign = f:CreateFontString(nil, "OVERLAY")
    Ink(f.sign, 15)
    f.sign:SetPoint("BOTTOMRIGHT", -30, 52)
    f.sign:SetJustifyH("RIGHT")
    f.when = f:CreateFontString(nil, "OVERLAY")
    Ink(f.when, 10)
    f.when:SetTextColor(0.45, 0.42, 0.35)
    f.when:SetPoint("BOTTOMLEFT", 48, 54)
    f.tear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.tear:SetSize(110, 20)
    f.tear:SetPoint("BOTTOMLEFT", 44, 26)
    f.tear:SetText(L["Abreißen"])
    f.tear:SetScript("OnClick", function()
        if Z.shownKey then Z.Tear(Z.shownKey) end
        f:Hide()
    end)
    f:SetScript("OnHide", function() Z.shownKey = nil end)
    Z.reader = f
    return f
end

function Z.Show(key)
    local n = DB()[key]
    if not n then return end
    local f = Reader()
    Z.shownKey = key
    if n.guild then
        f.title:SetText(("|cff3a78c8%s|r"):format(L["Notizzettel der Gilde"]))
    else
        f.title:SetText(("|cff6b5a3a%s|r"):format(L["Notizzettel"]))
    end
    f.text:SetText(n.text)
    f.sign:SetText("– " .. (n.by or "?"))
    f.when:SetText(Ago(n.t))
    f.tear:SetShown(n.sender == Me())
    f:Show()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LOG_OPEN then PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN) end
end

-- Schreiben
local function Writer()
    if Z.writer then return Z.writer end
    local f = Paper("GuildPrideZettelWriteFrame")
    f.title:SetText(("|cff6b5a3a%s|r"):format(L["Zettel schreiben"]))
    local eb = CreateFrame("EditBox", nil, f)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetMaxBytes(MAX_TEXT + 1)
    eb:SetPoint("TOPLEFT", 48, -70)
    eb:SetPoint("TOPRIGHT", -26, -70)
    eb:SetHeight(170)
    eb:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 14, "")
    eb:SetTextColor(INK[1], INK[2], INK[3])
    eb:SetSpacing(4)
    eb:SetScript("OnEscapePressed", function() f:Hide() end)
    f.count = f:CreateFontString(nil, "OVERLAY")
    Ink(f.count, 10)
    f.count:SetTextColor(0.45, 0.42, 0.35)
    f.count:SetPoint("BOTTOMRIGHT", -30, 56)
    eb:SetScript("OnTextChanged", function(self)
        f.count:SetText(("%d/%d"):format(#(self:GetText() or ""), MAX_TEXT))
    end)
    -- Klick irgendwo aufs Papier setzt den Schreibcursor
    f:SetScript("OnMouseDown", function() eb:SetFocus() end)
    f.edit = eb
    local function Done(guild)
        local text = eb:GetText()
        if strtrim(text or "") == "" then return end
        if Z.Write(f.map, f.x, f.y, text, guild) then
            ns.Print(guild and L["Zettel für die Gilde aufgehängt."] or L["Zettel für alle aufgehängt."])
            f:Hide()
        end
    end
    f.guildBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.guildBtn:SetSize(112, 22)
    f.guildBtn:SetPoint("BOTTOMLEFT", 44, 24)
    f.guildBtn:SetText(L["Für die Gilde"])
    f.guildBtn:SetScript("OnClick", function() Done(true) end)
    f.allBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.allBtn:SetSize(112, 22)
    f.allBtn:SetPoint("LEFT", f.guildBtn, "RIGHT", 8, 0)
    f.allBtn:SetText(L["Für alle"])
    f.allBtn:SetScript("OnClick", function() Done(false) end)
    f:SetScript("OnHide", function() eb:ClearFocus() end)
    Z.writer = f
    return f
end

-- Auf Kontinent- oder Weltkarte geklickt: möglichst auf die Gebietskarte umrechnen
local function ZoneOf(map, x, y)
    local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
    local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    if info and info.mapType and info.mapType >= zoneType then return map, x, y end
    local at = C_Map.GetMapInfoAtPosition and C_Map.GetMapInfoAtPosition(map, x, y)
    if at and at.mapID and at.mapID ~= map then
        local zx, zy = Translate(map, x, y, at.mapID)
        if zx then return at.mapID, zx, zy end
    end
    return map, x, y
end

function Z.OpenWriter(map, x, y)
    if not Z.Enabled() then ns.Print(L["Notizzettel sind ausgeschaltet (/gp zettel an)."]); return end
    map, x, y = ZoneOf(map, x, y)
    local f = Writer()
    f.map, f.x, f.y = map, x, y
    f.edit:SetText("")
    f.guildBtn:SetEnabled(IsInGuild() and true or false)
    f:Show()
    f.edit:SetFocus()
end

---------------------------------------------------------------------
-- Auslösen: auf ~5 m heran → Zettel geht auf
---------------------------------------------------------------------
Z.armed = {}
local sizeCache = {}
local function MapSize(map)
    if sizeCache[map] ~= nil then return sizeCache[map] or nil end
    local w, h
    if C_Map.GetMapWorldSize then w, h = C_Map.GetMapWorldSize(map) end
    if not (w and w > 0) and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local ok1, _, a = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(0, 0))
        local ok2, _, b = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(1, 1))
        if ok1 and ok2 and a and b then
            local ax, ay = a:GetXY(); local bx, by = b:GetXY()
            w, h = math.abs(bx - ax), math.abs(by - ay)
        end
    end
    if w and w > 0 and h and h > 0 then sizeCache[map] = { w, h } else sizeCache[map] = false end
    return sizeCache[map] or nil
end

-- Abstand in Yards zwischen Spieler und Zettel (nil = nicht auf dieser Karte)
function Z.Distance(n)
    if not C_Map.GetPlayerMapPosition then return end
    local pos = C_Map.GetPlayerMapPosition(n.map, "player")
    if not pos then return end
    local px, py = pos:GetXY()
    if not px or (px == 0 and py == 0) then return end
    local s = MapSize(n.map)
    if not s then return end
    local dx, dy = (px - n.x) * s[1], (py - n.y) * s[2]
    return math.sqrt(dx * dx + dy * dy)
end

C_Timer.NewTicker(0.5, function()
    if not Z.Enabled() or UnitIsDeadOrGhost("player") then return end
    local best, bestD
    for key, n in pairs(DB()) do
        local d = Z.Distance(n)
        if d then
            if d <= TRIGGER and Z.armed[key] ~= false then
                if not bestD or d < bestD then best, bestD = key, d end
            elseif d > REARM then
                Z.armed[key] = true
            end
        end
    end
    if best and Z.shownKey ~= best then
        Z.armed[best] = false
        Z.Show(best)
    end
end)

---------------------------------------------------------------------
-- Ein/Aus und Knopf auf der Weltkarte (wie bei den Rares)
---------------------------------------------------------------------
local button

local function UpdateButton()
    if not button then return end
    local on = Z.Enabled()
    button.icon:SetDesaturated(not on)
    button.icon:SetAlpha(on and 1 or 0.4)
end

function Z.SetEnabled(on)
    if type(GuildPrideDB) == "table" then GuildPrideDB.mapNotes = on and true or false end
    if not on then
        if Z.reader then Z.reader:Hide() end
        if Z.writer then Z.writer:Hide() end
    end
    UpdateButton()
    Refresh()
end
function Z.Changed() Z.SetEnabled(Z.Enabled()) end

-- „Zettel schreiben“: der Zettel kommt direkt an die Stelle, an der du stehst
function Z.WriteHere()
    if not Z.Enabled() then Z.SetEnabled(true) end
    local map = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    local x, y
    if pos then x, y = pos:GetXY() end
    if not (x and y) or (x == 0 and y == 0) then
        ns.Print(L["Hier kann kein Zettel hängen (keine Position, z. B. in Instanzen)."])
        return
    end
    Z.OpenWriter(map, x, y)
end

local function MakeButton()
    if button or not WorldMapFrame or not WorldMapFrame.ScrollContainer then return end
    local sc = WorldMapFrame.ScrollContainer
    button = CreateFrame("Button", "GuildPrideZettelMapButton", sc)
    button:SetSize(26, 26)
    button:SetFrameLevel(sc:GetFrameLevel() + 2000)
    local bg = button:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.55)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 2, -2); button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    button.icon:SetTexture(PIN)
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(_, b)
        if b == "RightButton" then
            Z.SetEnabled(not Z.Enabled())
            ns.Print(Z.Enabled() and L["Notizzettel |cff40ff40an|r"] or L["Notizzettel |cffff6060aus|r – auf der Karte ausgeblendet"])
        else
            Z.WriteHere()
        end
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["GuildPride Notizzettel"], 1, 0.82, 0)
        GameTooltip:AddLine(L["Linksklick: Zettel schreiben (hängt da, wo du stehst)"], 1, 1, 1)
        GameTooltip:AddLine(L["Rechtsklick: Zettel an/aus"], 1, 1, 1)
        GameTooltip:AddLine(Z.Enabled() and L["Zurzeit: an"] or L["Zurzeit: aus"], 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    -- unter den Rare-Knopf, wenn der zu sehen ist
    local function Place()
        button:ClearAllPoints()
        local rare = _G.GPRaresMapToggle
        if rare and rare:IsShown() then button:SetPoint("TOP", rare, "BOTTOM", 0, -4)
        else button:SetPoint("TOPLEFT", sc, "TOPLEFT", 8, -8) end
    end
    Place()
    WorldMapFrame:HookScript("OnShow", Place)
    UpdateButton()
end

local menuHooked = false
local function HookFilterMenu()
    if menuHooked or not (Menu and Menu.ModifyMenu) then return end
    menuHooked = true
    Menu.ModifyMenu("MENU_WORLD_MAP_TRACKING", function(_, root)
        root:CreateDivider()
        root:CreateTitle(L["GuildPride Notizzettel"])
        root:CreateCheckbox(L["Notizzettel zeigen"], function() return Z.Enabled() end,
            function() Z.SetEnabled(not Z.Enabled()) end)
        root:CreateButton(L["Zettel schreiben"], function() Z.WriteHere() end)
    end)
end

local function Setup()
    MakeButton()
    HookFilterMenu()
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" then
        Setup()
        Prune()
        -- eigene Zettel nach dem Kanalbeitritt erneut verschicken
        C_Timer.After(45, ResendOwn)
    elseif name == "Blizzard_WorldMap" then
        Setup()
    end
end)

---------------------------------------------------------------------
-- /gp zettel [an|aus|schreiben|weg]
---------------------------------------------------------------------
local origSlash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd, rest = strtrim(arg or ""):match("^(%S*)%s*(.-)$")
    cmd, rest = (cmd or ""):lower(), (rest or ""):lower()
    if cmd ~= "zettel" and cmd ~= "notes" then return origSlash(arg) end
    if rest == "aus" or rest == "off" then
        Z.SetEnabled(false); ns.Print(L["Notizzettel |cffff6060aus|r – auf der Karte ausgeblendet"])
    elseif rest == "an" or rest == "on" then
        Z.SetEnabled(true); ns.Print(L["Notizzettel |cff40ff40an|r"])
    elseif rest == "weg" or rest == "clear" then
        local own = OwnNotes()
        for _, k in ipairs(own) do Z.Tear(k) end
        ns.Print((L["%d eigene Zettel abgerissen."]):format(#own))
    elseif rest == "schreiben" or rest == "write" then
        Z.WriteHere()
    else
        local n, own = 0, #OwnNotes()
        for _ in pairs(DB()) do n = n + 1 end
        ns.Print((L["Notizzettel: %s · %d bekannt, %d eigene. /gp zettel an|aus|schreiben|weg"]):format(
            Z.Enabled() and L["an"] or L["aus"], n, own))
    end
end
