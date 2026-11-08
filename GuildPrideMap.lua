-- GuildPride: Gildenmitglieder mit GuildPride auf der Weltkarte
-- Blizzard zeigt auf der Karte nur Gruppenmitglieder. Hier schickt jeder mit
-- GuildPride seine Position über die Gilde ("POS"), und
-- auf der Weltkarte erscheinen Punkte für alle anderen Gildenmitglieder.
-- Gesendet wird nur, solange jemand in der Gilde die Karte offen hat: wer sie
-- öffnet, fragt mit "POSQ" nach, die anderen melden sich dann eine Weile.
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP

local STALE     = 45    -- s: ältere Positionen nicht mehr zeigen
local WANT_FOR  = 40    -- s: so lange nach einer Anfrage senden
local ASK_EVERY = 20    -- s: bei offener Karte erneut nachfragen
local STEP      = 3     -- s: frühestens so oft die eigene Position senden
local BEAT      = 15    -- s: unveränderte Position trotzdem so oft senden

local positions = {}    -- [Name] = { map, x, y, t }  (x, y: 0 … 1)
local wantedUntil, lastAsk = 0, -999
local askers = {}       -- [Name] = bis wann er Positionen haben will
local lastMsg, lastSentAt = nil, -999

local function Secret(v) return issecretvalue and issecretvalue(v) end
local function Sharing() return GuildPrideDB and GuildPrideDB.mapShare ~= false end
local function Showing() return GuildPrideDB and GuildPrideDB.mapShow ~= false end

---------------------------------------------------------------------
-- Eigene Position
---------------------------------------------------------------------
-- Zähler für /gp karte
local stats = { sent = 0, sentNone = 0, asked = 0, askIn = 0, posIn = 0, lastIn = nil }

-- Karte und Position (je 0 … 1000); ohne Position nil und der Grund
local function MyPosition()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil, "keine Karten-API" end
    if IsInInstance and IsInInstance() then return nil, "in einer Instanz" end
    local map = C_Map.GetBestMapForUnit("player")
    if not map then return nil, "keine Karte für dich" end
    if Secret(map) then return nil, "Karte gesperrt (geschützter Wert)" end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return nil, "keine Position auf Karte " .. map end
    if Secret(pos) then return nil, "Position gesperrt (geschützter Wert)" end
    local x, y = pos:GetXY()
    if not x then return nil, "Position leer" end
    if Secret(x) or Secret(y) then return nil, "Koordinaten gesperrt (geschützter Wert)" end
    if x == 0 and y == 0 then return nil, "Position 0,0" end
    return map, math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5)
end

local function SendPos(force)
    if not IsInGuild() or not ns.QueueLatest then return end
    local map, x, y = MyPosition()
    if not Sharing() then map = nil end
    -- "0" heißt: keine Position (Instanz, Teilen aus) – der Punkt verschwindet
    local msg = map and (map .. ":" .. x .. ":" .. y) or "0"
    local now = GetTime()
    if now - lastSentAt < STEP then return end
    if not force and msg == lastMsg and now - lastSentAt < BEAT then return end
    -- ohne Position nur einmal Bescheid sagen, nicht ständig
    if not map and lastMsg == "0" and not force then return end
    lastMsg, lastSentAt = msg, now
    if map then stats.sent = stats.sent + 1 else stats.sentNone = stats.sentNone + 1 end
    -- Wie Version und Gruppensuche über die Gilde (plus Kanal): nur über den
    -- Kanal kam in WoW Forever nichts an. Der Zeitstempel macht jede Meldung
    -- einmalig – gleiche Nachrichten verwirft der Empfang sonst 30 s lang.
    local stamp = GetServerTime()
    if not map then map, x, y = 0, 0, 0 end
    ns.QueueLatest("POS", nil, map, x, y, stamp)
    -- Zusätzlich direkt an alle, die gerade fragen und die wir nicht im Kanal
    -- hören: Rundsendungen von Rängen ohne Gildenchat-Recht kommen sonst nie an,
    -- ein Flüstern schon (wie die Antwort auf die Versionsabfrage)
    for who, untilT in pairs(askers) do
        if untilT < now then
            askers[who] = nil
        elseif not (ns.HeardInChannel and ns.HeardInChannel(who)) then
            ns.QueueLatest("POS", who, map, x, y, stamp)
        end
    end
end

ns.On("POSQ", function(_, sender)
    if sender == ns.Me() then return end
    stats.askIn, stats.lastAskFrom = stats.askIn + 1, ns.Clean(sender, 40)
    if not Sharing() then return end
    wantedUntil = GetTime() + WANT_FOR
    askers[sender] = wantedUntil
    -- verteilt antworten, damit nicht alle gleichzeitig senden
    C_Timer.After(0.3 + math.random() * 2, function() SendPos(true) end)
end)

ns.On("POS", function(payload, sender)
    if sender == ns.Me() then return end
    -- für die Anzeige im Chat entschärft (keine Farb-, Link- oder Bildcodes)
    stats.posIn, stats.lastIn = stats.posIn + 1,
        ns.Clean(sender, 40) .. ": " .. ns.Clean((tostring(payload):gsub(SEP, " ")), 60)
    local map, x, y = strsplit(SEP, payload or "")
    map = ns.Num(map, 0, 999999)
    x, y = ns.Num(x, 0, 1000), ns.Num(y, 0, 1000)
    if not map or map == 0 or not x or not y then
        -- gemeldet, aber ohne Position (Instanz, Teilen aus …): kein Punkt
        positions[sender] = { none = true, t = GetTime() }
    else
        positions[sender] = { map = map, x = x / 1000, y = y / 1000, t = GetTime() }
    end
end)

-- Gilde fragen: wer hat GuildPride und ist gerade wo?
local function Ask()
    if not IsInGuild() or not Showing() or not ns.Queue then return end
    if GetTime() - lastAsk < ASK_EVERY then return end
    lastAsk = GetTime()
    stats.asked = stats.asked + 1
    local stamp = GetServerTime()
    ns.QueueLatest("POSQ", nil, stamp)
    -- Auch direkt an GuildPride-Nutzer, die wir nicht im Kanal hören (höchstens 8):
    -- kommt die eigene Rundsendung nicht an, hören sie die Anfrage so trotzdem
    local me, n = ns.Me(), 0
    for i = 1, GetNumGuildMembers() do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        local full = name and ns.Normalize(name)
        if online and full ~= me and ns.AddonUsers[full] and n < 8
           and not (ns.HeardInChannel and ns.HeardInChannel(full)) then
            n = n + 1
            ns.QueueLatest("POSQ", full, stamp)
        end
    end
end

---------------------------------------------------------------------
-- Punkte auf der Weltkarte
---------------------------------------------------------------------
-- Je Karte (Weltkarte, Gebietskarte Umschalt+M) eine eigene Ebene mit Punkten
local maps = {}       -- [Kartenrahmen] = { frame, overlay, pins, size }
local cacheAt, cachedGroup, cachedRoster = -999, nil, nil

-- Wer ist in der eigenen Gruppe? Die zeigt Blizzard schon selbst.
local function GroupNames()
    local set = {}
    local raid = IsInRaid()
    for i = 1, raid and 40 or 4 do
        local unit = (raid and "raid" or "party") .. i
        if UnitExists(unit) then
            local name, extra = UnitFullName(unit)
            if name and not Secret(name) then
                set[name] = true
                if extra and not Secret(extra) and extra ~= "" then set[ns.Normalize(name .. "-" .. extra)] = true end
            end
        end
    end
    return set
end

local function InGroup(set, full)
    return set[full] or set[(full:match("^[^ %-]+")) or full]
end

-- Klasse, Stufe und Gebiet aus der Gildenliste (nur online)
local function RosterInfo()
    local info = {}
    for i = 1, GetNumGuildMembers() do
        local name, _, _, level, _, zone, _, _, online, _, class = GetGuildRosterInfo(i)
        if name and online then info[ns.Normalize(name)] = { level = level, zone = zone, class = class } end
    end
    return info
end

-- Position von einer Karte auf die gerade gezeigte umrechnen (Gebiet → Kontinent …)
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

local function PinEnter(pin)
    if not pin.who then return end
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    local c = pin.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[pin.class]
    GameTooltip:AddLine(pin.who, c and c.r or 1, c and c.g or 0.82, c and c.b or 0)
    if pin.level then GameTooltip:AddLine((L["Stufe %s"]):format(pin.level), 1, 1, 1) end
    if pin.zone and pin.zone ~= "" then GameTooltip:AddLine(pin.zone, 0.8, 0.8, 0.8) end
    GameTooltip:AddLine(L["Gildenmitglied mit GuildPride"], 0.94, 0.78, 0.55)
    GameTooltip:Show()
end

local function NewPin(m)
    local pin = CreateFrame("Frame", nil, m.overlay)
    pin:SetSize(m.size, m.size)
    pin:EnableMouse(true)
    if pin.SetPropagateMouseClicks then pcall(pin.SetPropagateMouseClicks, pin, true) end
    local mask = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
    pin.ring = pin:CreateTexture(nil, "ARTWORK")
    pin.ring:SetAllPoints(); pin.ring:SetTexture(mask); pin.ring:SetVertexColor(0, 0, 0, 0.9)
    pin.dot = pin:CreateTexture(nil, "OVERLAY")
    pin.dot:SetPoint("CENTER"); pin.dot:SetSize(m.size - 4, m.size - 4); pin.dot:SetTexture(mask)
    pin:SetScript("OnEnter", PinEnter)
    pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return pin
end

local function AnyMapShown()
    for frame in pairs(maps) do
        if frame:IsShown() then return true end
    end
    return false
end

local function Refresh(m)
    if not m then
        for _, each in pairs(maps) do Refresh(each) end
        return
    end
    local frame, pins = m.frame, m.pins
    if not frame:IsShown() then return end
    local shown = frame:GetMapID()
    local canvas = frame:GetCanvas()
    local cw, ch = canvas:GetWidth(), canvas:GetHeight()
    local scale = 1 / (frame:GetCanvasScale() or 1)
    -- Blizzard stuft Kartenebenen beim Kartenwechsel neu ein: immer obenauf bleiben
    local want = canvas:GetFrameLevel() + 1500
    if m.overlay:GetFrameLevel() < want then m.overlay:SetFrameLevel(want) end
    local now, n = GetTime(), 0
    if Showing() and shown and cw > 0 then
        -- Gruppe und Gildenliste nur alle 2 s neu lesen (große Gilden)
        if now - cacheAt > 2 then cacheAt, cachedGroup, cachedRoster = now, GroupNames(), RosterInfo() end
        local group, roster = cachedGroup, cachedRoster
        for who, p in pairs(positions) do
            if now - p.t > STALE or not roster[who] or p.none then
                if now - p.t > STALE then positions[who] = nil end
            elseif not InGroup(group, who) then
                local x, y = Translate(p.map, p.x, p.y, shown)
                if x then
                    n = n + 1
                    local pin = pins[n] or NewPin(m)
                    pins[n] = pin
                    local r = roster[who]
                    pin.who, pin.level, pin.zone, pin.class = who, r.level, r.zone, r.class
                    local c = r.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[r.class]
                    pin.dot:SetVertexColor(c and c.r or 0.94, c and c.g or 0.78, c and c.b or 0.55)
                    pin:SetScale(scale)
                    pin:ClearAllPoints()
                    pin:SetPoint("CENTER", canvas, "TOPLEFT", cw * x / scale, -ch * y / scale)
                    pin:Show()
                end
            end
        end
    end
    for i = n + 1, #pins do pins[i]:Hide(); pins[i].who = nil end
end

local function SetupMap(frame, size)
    if not frame or maps[frame] or not (frame.GetCanvas and frame.GetMapID) then return end
    local canvas = frame:GetCanvas()
    if not canvas then return end
    local overlay = CreateFrame("Frame", nil, canvas)
    overlay:SetAllPoints(canvas)
    overlay:SetFrameLevel(canvas:GetFrameLevel() + 1500)
    overlay:EnableMouse(false)
    local m = { frame = frame, overlay = overlay, pins = {}, size = size }
    maps[frame] = m
    local elapsed = 0
    overlay:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed < 0.1 then return end
        elapsed = 0
        Refresh(m)
    end)
    frame:HookScript("OnShow", function() Ask(); Refresh(m) end)
    if frame:IsShown() then Ask() end
end

local function SetupMaps()
    SetupMap(WorldMapFrame, 14)
    SetupMap(BattlefieldMapFrame, 12)   -- Gebietskarte (Umschalt+M), wird erst bei Bedarf geladen
end

---------------------------------------------------------------------
-- Takt und Ereignisse
---------------------------------------------------------------------
C_Timer.NewTicker(STEP, function()
    local now = GetTime()
    if now < wantedUntil then SendPos(false) end
    -- Karte offen: weiter nachfragen, damit die anderen weiter senden
    if AnyMapShown() then Ask() end
end)

-- Teilen ausgeschaltet: den eigenen Punkt bei den anderen entfernen
function ns.MapShareChanged()
    lastSentAt = -999
    if not Sharing() then SendPos(true) elseif GetTime() < wantedUntil then SendPos(true) end
end
function ns.MapShowChanged() Refresh() end

---------------------------------------------------------------------
-- /gp karte: Diagnose, warum jemand (nicht) auf der Karte erscheint
---------------------------------------------------------------------
local function MapName(id)
    local info = id and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    return (info and info.name or "?") .. " (" .. tostring(id) .. ")"
end

local function Diagnose()
    local P = ns.Print
    local map, x, y = MyPosition()
    P(("Karte: Anzeigen %s, Teilen %s, Gildenkanal %s"):format(Showing() and "an" or "aus",
        Sharing() and "an" or "aus", ns.DataChannelId and ns.DataChannelId() and "ja" or "nein (über Gilde)"))
    if map then
        P(("Deine Position: %s  %d / %d"):format(MapName(map), x, y))
    else
        P("Deine Position: keine – " .. tostring(x))   -- x ist hier der Grund
    end
    P(("Gesendet: %d Positionen, %d ohne Position, %d Anfragen. Senden noch %d s"):format(
        stats.sent, stats.sentNone, stats.asked, math.max(0, math.floor(wantedUntil - GetTime()))))
    P(("Empfangen: %d Anfragen (zuletzt %s), %d Positionen (zuletzt %s)"):format(
        stats.askIn, tostring(stats.lastAskFrom), stats.posIn, tostring(stats.lastIn)))
    local shown = WorldMapFrame and WorldMapFrame:GetMapID()
    P("Weltkarte zeigt: " .. (shown and MapName(shown) or "nichts (Karte nie geöffnet)")
        .. ((WorldMapFrame and maps[WorldMapFrame]) and "" or "  |cffff4040Kartenebene fehlt|r"))
    local zoneMap = BattlefieldMapFrame and maps[BattlefieldMapFrame]
    P("Gebietskarte (Umschalt+M): " .. (not zoneMap and "noch nicht geladen"
        or zoneMap.frame:IsShown() and ("offen, zeigt " .. MapName(zoneMap.frame:GetMapID())) or "zu"))
    local zoneShown = zoneMap and zoneMap.frame:IsShown() and zoneMap.frame:GetMapID()
    if zoneShown then
        local canvas = zoneMap.frame:GetCanvas()
        P(("  Ebene: sichtbar %s, Alpha %.2f, Stufe %d (Karte %d), Größe %d x %d, Maßstab %.2f"):format(
            tostring(zoneMap.overlay:IsVisible()), zoneMap.overlay:GetEffectiveAlpha(),
            zoneMap.overlay:GetFrameLevel(), canvas:GetFrameLevel(),
            canvas:GetWidth(), canvas:GetHeight(), zoneMap.frame:GetCanvasScale() or 0))
        for _, pin in ipairs(zoneMap.pins) do
            if pin.who then
                local px, py = pin:GetCenter()
                P(("  Punkt %s: sichtbar %s, Bildschirm %s / %s"):format(pin.who, tostring(pin:IsVisible()),
                    px and math.floor(px) or "?", py and math.floor(py) or "?"))
            end
        end
    end
    local group, roster, now, any = GroupNames(), RosterInfo(), GetTime(), false
    for who, p in pairs(positions) do
        any = true
        local why
        if p.none then
            P(("  %s: meldet keine Position (Instanz, Teilen aus oder kein Standort), vor %d s"):format(who, math.floor(now - p.t)))
        elseif now - p.t > STALE then why = "zu alt"
        elseif not roster[who] then why = "nicht in der Gildenliste online gefunden"
        elseif InGroup(group, who) then why = "in deiner Gruppe"
        elseif shown and not Translate(p.map, p.x, p.y, shown) then why = "liegt nicht auf der Weltkarte"
        else why = "|cff40ff40wird gezeigt|r" end
        if zoneShown and not p.none and why ~= "zu alt" then
            why = why .. (Translate(p.map, p.x, p.y, zoneShown) and ", Gebietskarte: drauf"
                or ", Gebietskarte: |cffff4040nicht drauf|r")
        end
        if why then
            P(("  %s: %s %.3f / %.3f, vor %d s – %s"):format(who, MapName(p.map), p.x, p.y, math.floor(now - p.t), why))
        end
    end
    if not any then P("  Keine Positionen von anderen bekannt.") end
    -- Wer hat GuildPride gemeldet, aber nie etwas zur Karte geschickt?
    for who, v in pairs(ns.Versions or {}) do
        if not positions[who] then
            P(("  %s (%s): nichts zur Karte empfangen%s"):format(who, v,
                roster[who] and "" or " – nicht online in der Gildenliste"))
        end
    end
end

local origSlash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd = strtrim(arg or ""):lower()
    if cmd == "karte" or cmd == "map" then Diagnose() else origSlash(arg) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" or name == "Blizzard_WorldMap" or name == "Blizzard_BattlefieldMap" then
        SetupMaps()
    end
end)
