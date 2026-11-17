-- GuildPride: Fahrpläne der Schiffe, Zeppeline und Luftschiffe – wann legt das nächste an,
-- wann fährt es ab (für das Fenster am Anleger, GuildPrideTransitUI.lua).
--
-- Übernommen aus Polestar (Nav/Transit.lua, Copyright (c) 2026 The Polestar authors, GPL-3.0-only),
-- das es wiederum aus Shortest Path Forever von Cillian Berragan portiert hat
-- (Transport/Model.lua, Timetable.lua, Observer.lua, Sync.lua; GPL-3.0-or-later, mit Erlaubnis).
-- Portions Copyright (C) 2026 Cillian Berragan (Shortest Path Forever, GPL-3.0-or-later).
-- Für GuildPride Forever gekürzt (ohne Aufzüge, Bahn, Teleporte) und auf die Gilden-Nachrichten
-- von GuildPride umgestellt, 2026-11-17.
--
-- Jedes Schiff fährt eine feste Runde (GuildPrideTransitData.lua); WO es in der Runde gerade ist,
-- hängt aber davon ab, wie lange der Server läuft – das sagt keine Schnittstelle. Darum wird
-- gemessen: Fährt man mit, werden die Positionen mit der Strecke verglichen; die Stelle, auf die
-- sich die meisten Messungen einigen, datiert die Runde (epoch = Server-ms bei Phase 0).
-- Eine Messung gilt 6 Stunden (ein Neustart setzt die Runden zurück), je Realm gespeichert in
-- GuildPrideDB.transit[realm][route] = { epoch, seen, source = "you"|"player" }
-- und mit der Gilde geteilt (gleicher Realm). Ungemessen gibt es nur die mittlere Wartezeit.
--
-- Gilden-Nachrichten (nie weitergeleitet):
--   TRS  realm · "route:seen:phase;…"   eigene Messungen (an die Gilde oder als Antwort geflüstert)
--   TRQ  1                               Messungen anfragen (beim Einloggen)
local ADDON, GP = ...
local T = {}
GP.Transit = T
local L = GP.L or setmetatable({}, { __index = function(_, k) return k end })
local SEP = GP.SEP or "\031"

local floor, ceil, max, min, huge, sqrt = math.floor, math.ceil, math.max, math.min, math.huge, math.sqrt
local format = string.format

local MAX_AGE = 6 * 3600       -- s: ältere Messungen verfallen (Neustart setzt die Runden zurück)
local OWN_TRUST = 3600         -- s: eigene Messung so jung wird nicht von fremden ersetzt
local CLOCK_SLACK = 5          -- s: so weit darf eine fremde Messung in der Zukunft liegen
local NEAR = 40                -- yd: so nah an einem fahrenden Streckenstück = darauf
local AGREE = 8000             -- ms: so nahe Phasen gehören zu einem Schiff
local CLEAR_LEAD = 1.25        -- Vorsprung der besten Strecke vor der zweitbesten
local RIDE_GAP = 30000         -- ms: so lange keine passende Messung beendet eine Fahrt
local FIT_EVERY = 10           -- Messungen zwischen zwei Auswertungen während der Fahrt
local MAX_SAMPLES = 300        -- je Strecke und Fahrt
local QUIET = 600              -- s: eigene Wiederholung so bald ist Routine (keine Meldung)
local MAX_ROUTES_MSG = 20

local routes, services = {}, {}

function T.Register(d)
    if type(d) ~= "table" then return end
    routes, services = d.routes or {}, d.services or {}
end
T.Register(GP.TransitData)

function T.Routes() return routes end
function T.Services() return services end

---------------------------------------------------------------------
-- Uhr: Server-Sekunden mit Bruchteil (GetServerTime ganze s, GetTime den Bruchteil)
---------------------------------------------------------------------
local clockOffset
function T.Now()
    local server = GetServerTime and GetServerTime()
    local t = GetTime and GetTime()
    if not (server and t) then return server or 0 end
    local lead = server - t
    if not clockOffset or lead > clockOffset or clockOffset - lead > 2 then clockOffset = lead end
    return t + clockOffset
end

---------------------------------------------------------------------
-- Messungen
---------------------------------------------------------------------
local function Realm()
    local r = GetRealmName and GetRealmName()
    return type(r) == "string" and r ~= "" and r or "?"
end

local function Store()
    if type(GuildPrideDB) ~= "table" then GuildPrideDB = {} end
    if type(GuildPrideDB.transit) ~= "table" then GuildPrideDB.transit = {} end
    local realm = Realm()
    if type(GuildPrideDB.transit[realm]) ~= "table" then GuildPrideDB.transit[realm] = {} end
    return GuildPrideDB.transit[realm]
end

local function Fresh(anchor, now)
    return type(anchor) == "table" and type(anchor.epoch) == "number" and type(anchor.seen) == "number"
        and now - anchor.seen <= MAX_AGE and anchor or nil
end

local function AnchorOf(route, now) return Fresh(Store()[route], now) end

-- Ersetzt die neue Messung die gespeicherte? Die eigene Fahrt gewinnt immer gegen fremde;
-- eine fremde ersetzt keine eigene unter einer Stunde; sonst zählt nur eine neuere.
local function Newer(incoming, held, now)
    if not Fresh(held, now) then return true end
    if incoming.source == "you" and held.source ~= "you" then return true end
    if held.source == "you" and incoming.source ~= "you" and now - held.seen < OWN_TRUST then return false end
    return incoming.seen > held.seen
end

local function Sighted(route, anchor, now)
    local s = Store()
    if not routes[route] or not Newer(anchor, s[route], now) then return false end
    s[route] = { epoch = anchor.epoch, seen = anchor.seen, source = anchor.source }
    return true
end

local function Changed()
    if T.onChanged then T.onChanged() end
end

-- Tests: eine Messung { epoch, seen, source } eintragen wie gesehen oder empfangen
function T.Sighted(route, anchor)
    if type(anchor) ~= "table" or not Sighted(route, anchor, T.Now()) then return false end
    Changed()
    return true
end

function T.Forget()
    if type(GuildPrideDB) == "table" and type(GuildPrideDB.transit) == "table" then GuildPrideDB.transit[Realm()] = nil end
    Changed()
end

---------------------------------------------------------------------
-- Rechnen im Umlauf (ms)
---------------------------------------------------------------------
-- Nächster Besuch eines Halts bei `phase`: liegt gerade an (arriveIn 0) oder kommt in arriveIn;
-- departIn so oder so; nextIn = der Besuch danach (eine Runde später).
local function Visit(period, stop, phase)
    local arrive = stop[1]
    local stay = (stop[2] - arrive) % period
    local since = (phase - arrive) % period
    if since < stay then
        return 0, stay - since, period - since
    end
    local arriveIn = (arrive - phase) % period
    return arriveIn, arriveIn + stay, arriveIn + period
end

local OTHER = { a = "b", b = "a" }

-- Fahrplan einer Verbindung ab Seite `side` ("a"|"b"):
--   { timed = true, arriveIn, departIn, nextIn (s; arriveIn 0 = liegt am Steg) }
--   ungemessen: { timed = false, wait = mittlere Wartezeit (s) }
function T.Board(id, side, now)
    local s = services[id]
    if not s or not OTHER[side] then return nil end
    now = now or T.Now()
    local pre = s.pre or 0
    local t = (now + pre) * 1000
    local best
    for _, part in ipairs(s.routes or {}) do
        local route = routes[part.route]
        local anchor = route and AnchorOf(part.route, now)
        if anchor then
            local phase = (t - anchor.epoch) % route.period
            for _, i in ipairs(part[side] or {}) do
                local a, d, n = Visit(route.period, route.stops[i], phase)
                if not best or d < best.d then best = { a = a, d = d, n = n } end
            end
        end
    end
    if best then
        return { timed = true, arriveIn = pre + best.a / 1000, departIn = pre + best.d / 1000, nextIn = pre + best.n / 1000 }
    end
    return { timed = false, wait = (s.wait or {})[side] }
end

function T.Countdown(seconds)
    seconds = max(0, ceil(seconds or 0))
    return format("%d:%02d", floor(seconds / 60), seconds % 60)
end

-- Name eines Ziels in der Sprache des Spiels (AreaTable), sonst der englische aus den Daten
function T.EndName(id, side)
    local s = services[id]
    if not s then return nil end
    local k = side == "a" and 1 or 2
    local area = s.areas and s.areas[k]
    if area and C_Map and C_Map.GetAreaInfo then
        local ok, name = pcall(C_Map.GetAreaInfo, area)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return s.ends and s.ends[k] or id
end

-- Anleger in der Nähe: { { id, side, kind, to = Zielname, yards } }, nach Ziel sortiert.
-- map = Kontinent (Instanz aus UnitPosition), wx/wy = Weltkoordinaten
function T.DocksNear(map, wx, wy, yards)
    local out = {}
    if map == nil or not wx or not wy then return out end
    local reach = (yards or 120) ^ 2
    for id, s in pairs(services) do
        for _, side in ipairs({ "a", "b" }) do
            local bestD
            for _, part in ipairs(s.routes or {}) do
                local route = routes[part.route]
                for _, i in ipairs(route and part[side] or {}) do
                    local st = route.stops[i]
                    if st and st[3] == map then
                        local d = (st[4] - wx) ^ 2 + (st[5] - wy) ^ 2
                        if d <= reach and (not bestD or d < bestD) then bestD = d end
                    end
                end
            end
            if bestD then
                out[#out + 1] = { id = id, side = side, kind = s.kind, to = T.EndName(id, OTHER[side]), yards = sqrt(bestD) }
            end
        end
    end
    table.sort(out, function(x, y)
        if x.to ~= y.to then return tostring(x.to) < tostring(y.to) end
        return x.id < y.id
    end)
    return out
end

---------------------------------------------------------------------
-- Mitmessen während der Fahrt (Shortest Path Forevers Beobachter)
---------------------------------------------------------------------
-- Jede Phase (ms), in der die Strecke fahrend nah an der Position vorbeikommt
local function Phases(route, map, x, y, z, out)
    for i = #out, 1, -1 do out[i] = nil end
    local frames = route.frames
    for i = 1, #frames - 1 do
        local a, b = frames[i], frames[i + 1]
        if a[3] == map and (a[6] or 0) == 0 then
            local dx, dy = b[4] - a[4], b[5] - a[5]
            local dz, oz = 0, 0
            if z and a[7] and b[7] then dz, oz = b[7] - a[7], z - a[7] end
            local length = dx * dx + dy * dy + dz * dz
            local t = 0
            if length > 0 then t = min(1, max(0, ((x - a[4]) * dx + (y - a[5]) * dy + oz * dz) / length)) end
            local px, py, pz = a[4] + t * dx - x, a[5] + t * dy - y, t * dz - oz
            if t > 0 and t < 1 and px * px + py * py + pz * pz <= NEAR * NEAR then
                out[#out + 1] = a[2] + t * (b[1] - a[2])
            end
        end
    end
    return out
end

-- Die Epoche, auf die sich die meisten Messungen einer Fahrt einigen (nil bei zu wenigen
-- oder zu kurzer Zeitspanne: wer neben der Strecke steht, driftet mit der Zeit)
local function FitEpoch(route, samples)
    local period, offsets = route.period, {}
    local fit = route.fit or {}
    for _, sample in ipairs(samples) do
        for _, p in ipairs(sample.phases) do
            offsets[#offsets + 1] = { offset = (sample.now - p) % period, now = sample.now }
        end
    end
    local best, support = nil, 0
    for _, center in ipairs(offsets) do
        local members, sum, first, last = 0, 0, huge, -huge
        for _, other in ipairs(offsets) do
            local delta = (other.offset - center.offset + period / 2) % period - period / 2
            if delta <= AGREE / 2 and delta >= -AGREE / 2 then
                members, sum = members + 1, sum + delta
                if other.now < first then first = other.now end
                if other.now > last then last = other.now end
            end
        end
        if members > support and last - first >= (fit.span or 30000) then
            best, support = (center.offset + sum / members) % period, members
        end
    end
    if support < (fit.samples or 10) then return nil, support end
    return best, support
end

-- Die Strecke der Fahrt: die am besten gestützte, klar vor allen anderen
local function RideRoute(fits)
    local best, runnerUp
    for id, fit in pairs(fits) do
        if not best or fit.support > fits[best].support or (fit.support == fits[best].support and id < best) then
            if best and (not runnerUp or fits[best].support > runnerUp) then runnerUp = fits[best].support end
            best = id
        elseif not runnerUp or fit.support > runnerUp then
            runnerUp = fit.support
        end
    end
    if best and (not runnerUp or fits[best].support >= CLEAR_LEAD * runnerUp) then return best end
    return nil
end
T._FitEpoch, T._RideRoute, T._Phases = FitEpoch, RideRoute, Phases   -- für Tests

local ride, previous, scratch = nil, {}, {}

local function Readable(v)
    if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function Position()
    if not UnitPosition then return nil end
    local ok, x, y, z, instance = pcall(UnitPosition, "player")
    if not ok then return nil end
    x, y, z, instance = Readable(x), Readable(y), Readable(z), Readable(instance)
    if type(x) ~= "number" or type(y) ~= "number" or instance == nil then return nil end
    return x, y, type(z) == "number" and z ~= 0 and z or nil, instance
end
T.Position = Position

local function SpeedOf(nowMs, x, y, z, map)
    local speed = 0
    if previous.map == map and previous.now and nowMs > previous.now then
        local dx, dy, dz = x - previous.x, y - previous.y, z - previous.z
        speed = sqrt(dx * dx + dy * dy + dz * dz) * 1000 / (nowMs - previous.now)
    end
    previous.now, previous.x, previous.y, previous.z, previous.map = nowMs, x, y, z, map
    return speed
end

local Share   -- weiter unten

local function Record()
    if not ride then return end
    local fits = {}
    for id, samples in pairs(ride.samples) do
        local epoch, support = FitEpoch(routes[id], samples)
        if epoch then fits[id] = { epoch = epoch, support = support } end
    end
    local id = RideRoute(fits)
    if not id then return end
    local now = T.Now()
    local held = AnchorOf(id, now)
    local routine = held and held.source == "you" and now - held.seen < QUIET
    if Sighted(id, { epoch = fits[id].epoch, seen = floor(now), source = "you" }, now) then
        ride.announced = id
        if not routine then
            if GP.Print then GP.Print(L["Schiffs-Zähler: Fahrplan durch deine Fahrt gemessen – die Gilde bekommt ihn auch."]) end
            Share(id)
        end
        Changed()
    end
end

function T.Sample()
    local nowMs = T.Now() * 1000
    local x, y, z, map = Position()
    local onTaxi = UnitOnTaxi and Readable(UnitOnTaxi("player"))
    local speed = x and not onTaxi and SpeedOf(nowMs, x, y, z or 0, map) or 0
    if speed > 0 then
        for id, route in pairs(routes) do
            local fit = route.fit or {}
            if speed >= (fit.speed or 12) then
                local found = Phases(route, map, x, y, z, scratch)
                if #found > 0 then
                    scratch = {}
                    ride = ride or { samples = {}, count = 0 }
                    local list = ride.samples[id] or {}
                    ride.samples[id] = list
                    list[#list + 1] = { now = nowMs, phases = found }
                    if #list > MAX_SAMPLES then table.remove(list, 1) end
                    ride.last = nowMs
                end
            end
        end
        if ride and ride.last == nowMs then
            ride.count = ride.count + 1
            if not ride.announced and ride.count % FIT_EVERY == 0 then Record() end
        end
    end
    if ride and nowMs - ride.last > RIDE_GAP then
        Record()
        ride = nil
    end
end

---------------------------------------------------------------------
-- Mit der Gilde teilen (nur derselbe Realm: die Runden hängen am Server)
---------------------------------------------------------------------
local function Encode(id, anchor)
    local route = routes[id]
    if not route then return nil end
    return format("%s:%d:%d", id, anchor.seen, floor((anchor.seen * 1000 - anchor.epoch) % route.period))
end

local function Decode(text, now)
    local out, n = {}, 0
    for id, seenText, phaseText in tostring(text or ""):gmatch("([%w%-]+):(%d+):(%d+)") do
        local route, seen, phase = routes[id], tonumber(seenText), tonumber(phaseText)
        if route and seen and phase and phase < route.period and seen <= now + CLOCK_SLACK and now - seen <= MAX_AGE then
            out[id] = { epoch = seen * 1000 - phase, seen = min(seen, floor(now)), source = "player" }
            n = n + 1
            if n >= MAX_ROUTES_MSG then break end
        end
    end
    return out
end
T._Encode, T._Decode = Encode, Decode   -- für Tests

local function Enabled() return not (type(GuildPrideDB) == "table" and GuildPrideDB.transitShare == false) end

local function OwnEntries(now)
    local list = {}
    for id, anchor in pairs(Store()) do
        if Fresh(anchor, now) and anchor.source == "you" then list[#list + 1] = Encode(id, anchor) end
    end
    table.sort(list)
    return list
end

Share = function(id, target)
    if not GP.Queue or not Enabled() then return end
    local entries
    if id then
        local anchor = AnchorOf(id, T.Now())
        entries = { anchor and Encode(id, anchor) }
    else
        entries = OwnEntries(T.Now())
    end
    if #entries == 0 then return end
    GP.Queue("TRS", target, Realm(), table.concat(entries, ";"))
end

local asked = -120
function T.Request()
    if not GP.Queue or not Enabled() or GetTime() - asked < 120 then return end
    asked = GetTime()
    GP.Queue("TRQ", nil, 1)
end

if GP.On then
    GP.On("TRS", function(payload, sender)
        if not Enabled() or sender == GP.Me() or not (GP.IsDirect and GP.IsDirect(sender, sender)) or not GP.IsGuildMember(sender) then return end
        local realm, list = strsplit(SEP, payload)
        if realm ~= Realm() then return end
        local now, any = T.Now(), false
        for id, anchor in pairs(Decode(list, now)) do
            if Sighted(id, anchor, now) then any = true end
        end
        if any then Changed() end
    end)
    local answered = {}
    GP.On("TRQ", function(_, sender)
        if not Enabled() or sender == GP.Me() or not GP.IsGuildMember(sender) then return end
        local now = GetTime()
        if answered[sender] and now - answered[sender] < 1800 then return end
        answered[sender] = now
        if C_Timer and C_Timer.After then
            C_Timer.After(2 + math.random() * 8, function() Share(nil, sender) end)
        else
            Share(nil, sender)
        end
    end)
end

---------------------------------------------------------------------
-- Anschluss: jede Sekunde messen; alte Messungen beim Einloggen wegräumen
---------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LEAVING_WORLD")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LEAVING_WORLD" then
        if ride then Record() end   -- /reload an Bord würde die Fahrt sonst verlieren
        return
    end
    local s, now = Store(), T.Now()
    for id, anchor in pairs(s) do
        if not Fresh(anchor, now) or not routes[id] then s[id] = nil end
    end
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, T.Sample) end
    if C_Timer and C_Timer.After then C_Timer.After(20, function() if IsInGuild and IsInGuild() then T.Request() end end) end
end)
