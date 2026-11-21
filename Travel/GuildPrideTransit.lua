-- GuildPride: Fahrpläne der Schiffe, Zeppeline, Luftschiffe und der Tiefenbahn – wann legt das nächste an,
-- wann fährt es ab (für das Fenster am Anleger, GuildPrideTransitUI.lua).
--
-- Übernommen aus Polestar (Nav/Transit.lua, Copyright (c) 2026 The Polestar authors, GPL-3.0-only),
-- das es wiederum aus Shortest Path Forever von Cillian Berragan portiert hat
-- (Transport/Model.lua, Timetable.lua, Observer.lua, Sync.lua; GPL-3.0-or-later, mit Erlaubnis).
-- Portions Copyright (C) 2026 Cillian Berragan (Shortest Path Forever, GPL-3.0-or-later).
-- Für GuildPride Forever gekürzt (ohne Aufzüge und Teleporte) und auf die Gilden-Nachrichten
-- von GuildPride umgestellt, 2026-11-17.
--
-- Jedes Schiff fährt eine feste Runde (GuildPrideTransitData.lua); WO es in der Runde gerade ist,
-- hängt aber davon ab, wie lange der Server läuft – das sagt keine Schnittstelle. Darum wird
-- gemessen: Fährt man mit, werden die Positionen mit der Strecke verglichen; die Stelle, auf die
-- sich die meisten Messungen einigen, datiert die Runde (epoch = Server-ms bei Phase 0).
-- Eine Messung gilt bis zum nächsten wöchentlichen Reset (die Wartung startet die Server neu und
-- setzt die Runden zurück), höchstens 7 Tage.
--
-- Ohne Layer: Seit Blizzards Hotfix vom 20.11.2026 verraten Kreaturen-GUIDs keinen Layer mehr.
-- Layer fahren ihre Schiffe zwar versetzt, aber erkennen lässt sich das nicht mehr. Darum gilt:
-- deine eigene Messung zuerst (jeder speichert sie bei sich), sonst die Zeit, die die meisten
-- selbst gemessen haben. Messungen mit gleicher Phase bilden eine Gruppe.
-- Je Realm gespeichert in GuildPrideDB.transit[realm][route] =
--   { { epoch, seen, source = "you"|"player"|"public", by = { [Name] = Zeit } }, … }
--   by: wer diese Zeit selbst gemessen hat (Bestätigungen)
-- Ungemessen gibt es nur die mittlere Wartezeit. Gibt es diese Woche noch keine Messung, zeigt
-- der Zähler die der letzten Woche als Vermutung (gleicher Abstand zum Reset).
--
-- Teilen ist Pflicht (kein Schalter), mit der Gilde und serverweit:
-- Gilden-Nachrichten (nie weitergeleitet):
--   TRS  realm · "route:seen:phase:[:o];…"       Messungen (an die Gilde oder als Antwort geflüstert)
--   TRQ  1                                       Messungen anfragen (beim Einloggen)
-- Serverweit (offener GuildPride-Kanal, immer – unabhängig von der Gruppensuche):
--   TPS  F · realm · "route:seen:phase:[:o];…"   eigene Messung an alle bzw. Antwort (Flüstern)
--   TPQ  F · realm · "" · "route,route"          am Anleger: wer hat diese Strecken?
-- Das leere vierte Feld hieß früher Layer; ältere Versionen schicken dort noch Layer mit, die
-- hier überlesen werden. ":o" = selbst gemessen; nur das zählt als Bestätigung.
local ADDON, GP = ...
local T = {}
GP.Transit = T
local L = GP.L or setmetatable({}, { __index = function(_, k) return k end })
local SEP = GP.SEP or "\031"

local floor, ceil, max, min, huge, sqrt = math.floor, math.ceil, math.max, math.min, math.huge, math.sqrt
local format = string.format

local MAX_AGE = 7 * 86400      -- s: höchstens so alt; vor dem letzten Wochen-Reset gilt sie ohnehin nicht
local WEEK = 7 * 86400
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
local MAX_GROUPS = 12          -- je Strecke so viele Gruppen (verschiedene Phasen) merken
local PUBLIC_LEN = 240         -- Byte: serverweite Nachrichten sind immer einteilig
local CONFIRM_WINDOW = 12 * 3600   -- s: Bestätigungen so nah an der neuesten zählen
local MAX_BY = 10              -- je Gruppe so viele Bestätiger merken

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
-- Seit Blizzards Hotfix vom 20.11.2026 fehlt oft der Realm-Name: dann der zuletzt bekannte
-- (GP.RealmName, GuildPride.lua); was solange unter „?“ lag, kommt dazu
local function Realm()
    local r = GP.RealmName and GP.RealmName() or (GetRealmName and GetRealmName())
    return type(r) == "string" and r ~= "" and r or "?"
end

local function Store()
    if type(GuildPrideDB) ~= "table" then GuildPrideDB = {} end
    if type(GuildPrideDB.transit) ~= "table" then GuildPrideDB.transit = {} end
    local realm = Realm()
    if type(GuildPrideDB.transit[realm]) ~= "table" then GuildPrideDB.transit[realm] = {} end
    local orphan = realm ~= "?" and GuildPrideDB.transit["?"]
    if type(orphan) == "table" and GP.MergeSaved then
        GP.MergeSaved(GuildPrideDB.transit[realm], orphan)
        GuildPrideDB.transit["?"] = nil
    end
    return GuildPrideDB.transit[realm]
end

-- Zeitpunkt (Server-s) des letzten wöchentlichen Resets – die Wartung startet die Server neu
local function LastReset(now)
    local f = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset
    if not f then return nil end
    local ok, left = pcall(f)
    if not ok or type(left) ~= "number" or left <= 0 or left > WEEK then return nil end
    return now + left - WEEK
end
T._LastReset = LastReset   -- für Tests

local function Fresh(anchor, now)
    if type(anchor) ~= "table" or type(anchor.epoch) ~= "number" or type(anchor.seen) ~= "number" then return nil end
    if now - anchor.seen > MAX_AGE then return nil end
    local reset = LastReset(now)
    if reset and anchor.seen < reset then return nil end
    return anchor
end

-- Aus der Woche vor dem letzten Reset: gilt nicht mehr, taugt aber als Vermutung
local function LastWeek(anchor, now)
    if type(anchor) ~= "table" or type(anchor.epoch) ~= "number" or type(anchor.seen) ~= "number" then return nil end
    local reset = LastReset(now)
    if not reset or anchor.seen >= reset or anchor.seen < reset - WEEK then return nil end
    return anchor
end
local function Kept(anchor, now) return Fresh(anchor, now) or LastWeek(anchor, now) end

---------------------------------------------------------------------
-- Bestätigungen: wer dieselbe Zeit selbst gemessen hat
---------------------------------------------------------------------
local function Confirm(g, who, at)
    if type(who) ~= "string" or who == "" or type(at) ~= "number" then return false end
    if type(g.by) ~= "table" then g.by = {} end
    local had = g.by[who]
    if had and had >= at then return false end
    g.by[who] = at
    local n, oldest = 0, nil
    for k, t in pairs(g.by) do
        n = n + 1
        if not oldest or t < g.by[oldest] then oldest = k end
    end
    if n > MAX_BY then g.by[oldest] = nil end
    return not had
end

-- Wie viele haben sie bestätigt? (mindestens 1: die Messung selbst)
local function Count(g)
    local newest, n = 0, 0
    for _, t in pairs(type(g.by) == "table" and g.by or {}) do if t > newest then newest = t end end
    for _, t in pairs(type(g.by) == "table" and g.by or {}) do if newest - t <= CONFIRM_WINDOW then n = n + 1 end end
    return max(n, 1)
end
T._Count = Count   -- für Tests

-- Welche von zwei Gruppen gilt? Eigene junge Messung vor mehr Bestätigungen vor neuerer.
-- So verdrängt eine einzelne abweichende Meldung keine mehrfach bestätigte Zeit.
local function Better(a, b, now)
    if not b then return true end
    local ao = a.source == "you" and now - a.seen < OWN_TRUST
    local bo = b.source == "you" and now - b.seen < OWN_TRUST
    if ao ~= bo then return ao end
    local ca, cb = Count(a), Count(b)
    if ca ~= cb then return ca > cb end
    return a.seen > b.seen
end

---------------------------------------------------------------------
-- Gruppen je Strecke (eine Gruppe = eine Phase)
---------------------------------------------------------------------
local function Groups(route)
    local s = Store()
    local v = s[route]
    if type(v) ~= "table" then v = {}; s[route] = v end
    if v.epoch then v = { v }; s[route] = v end   -- alte Speicherform: eine einzelne Messung
    return v
end

local function SamePhase(a, b, period)
    local d = (a.epoch - b.epoch) % period
    return d <= AGREE / 2 or d >= period - AGREE / 2
end

-- Gültige Gruppen einer Strecke; mit prune fliegen abgelaufene raus (nur beim Eintragen und Einloggen,
-- nicht beim bloßen Anzeigen)
local function FreshGroups(route, now, prune)
    local list, out = Groups(route), {}
    for i = #list, 1, -1 do
        if Fresh(list[i], now) then table.insert(out, 1, list[i])
        elseif prune and not Kept(list[i], now) then table.remove(list, i) end
    end
    return out
end

-- Die Gruppe für den Anleger: eigene junge Messung, sonst die meistbestätigte, sonst die neueste
local function AnchorOf(route, now)
    local best
    for _, a in ipairs(FreshGroups(route, now)) do
        if Better(a, best, now) then best = a end
    end
    return best
end

-- Übernimmt die neue Messung die Zeit der Gruppe? Die eigene Fahrt gewinnt gegen fremde;
-- eine fremde ersetzt keine eigene unter einer Stunde; sonst zählt nur eine neuere.
local function Newer(incoming, held, now)
    if not Fresh(held, now) then return true end
    if incoming.source == "you" and held.source ~= "you" then return true end
    if held.source == "you" and incoming.source ~= "you" and now - held.seen < OWN_TRUST then return false end
    return incoming.seen > held.seen
end

-- Messung eintragen: in die Gruppe mit gleicher Phase oder als neue Gruppe.
-- true, wenn sich etwas geändert hat.
local function Sighted(route, anchor, now)
    local r = routes[route]
    if not r or type(anchor.epoch) ~= "number" or type(anchor.seen) ~= "number" then return false end
    local list = Groups(route)
    FreshGroups(route, now, true)
    -- selbst gemessen (eigene Fahrt oder ":o" vom Absender): zählt als Bestätigung
    local who = anchor.own and anchor.from or nil
    for _, g in ipairs(list) do
        -- nur Gruppen dieser Woche; die der letzten Woche bleiben als Vermutung stehen
        if Fresh(g, now) and SamePhase(g, anchor, r.period) then
            local changed = false
            if who and Confirm(g, who, anchor.seen) then changed = true end
            if Newer(anchor, g, now) and (anchor.seen ~= g.seen or anchor.epoch ~= g.epoch or anchor.source ~= g.source) then
                g.epoch, g.seen, g.source = anchor.epoch, anchor.seen, anchor.source
                changed = true
            end
            return changed, g
        end
    end
    local g = { epoch = anchor.epoch, seen = anchor.seen, source = anchor.source, by = {} }
    if who then Confirm(g, who, anchor.seen) end
    list[#list + 1] = g
    -- zu viele Gruppen: die am längsten nicht bestätigte fällt weg
    while #list > MAX_GROUPS do
        local oldest = 1
        for i, x in ipairs(list) do if x.seen < list[oldest].seen then oldest = i end end
        table.remove(list, oldest)
    end
    return true, g
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
        return 0, stay - since, period - since, stay
    end
    local arriveIn = (arrive - phase) % period
    return arriveIn, arriveIn + stay, arriveIn + period, stay
end

local OTHER = { a = "b", b = "a" }

-- Fahrplan einer Verbindung ab Seite `side` ("a"|"b"):
--   { timed = true, arriveIn, departIn, nextIn, stay = Liegezeit, period = Runde (s; arriveIn 0 = liegt am Steg) }
--   ungemessen: { timed = false, wait = mittlere Wartezeit (s) }
function T.Board(id, side, now)
    local s = services[id]
    if not s or not OTHER[side] then return nil end
    now = now or T.Now()
    local pre = s.pre or 0
    local t = (now + pre) * 1000
    local best
    local function Take(part, route, anchor, guess)
        local phase = (t - anchor.epoch) % route.period
        for _, i in ipairs(part[side] or {}) do
            local a, d, n, st = Visit(route.period, route.stops[i], phase)
            if not best or d < best.d then
                best = { a = a, d = d, n = n, s = st, p = route.period, seen = anchor.seen, source = anchor.source,
                         count = Count(anchor), guess = guess }
            end
        end
    end
    for _, part in ipairs(s.routes or {}) do
        local route = routes[part.route]
        local anchor = route and AnchorOf(part.route, now)
        if anchor then Take(part, route, anchor) end
    end
    if not best then
        -- Diese Woche noch nichts: die Messung der letzten Woche, um eine Woche weitergerückt
        for _, part in ipairs(s.routes or {}) do
            local route = routes[part.route]
            local last
            for _, g in ipairs(route and Groups(part.route) or {}) do
                if LastWeek(g, now) and Better(g, last, now) then last = g end
            end
            if last then
                Take(part, route, { epoch = last.epoch + WEEK * 1000, seen = last.seen, source = last.source, by = last.by }, true)
            end
        end
    end
    if best then
        -- own: selbst gemessen; confirmed: so viele haben die Zeit selbst gemessen; guess: von letzter Woche vermutet
        return { timed = true, arriveIn = pre + best.a / 1000, departIn = pre + best.d / 1000, nextIn = pre + best.n / 1000,
                 stay = best.s / 1000, period = best.p / 1000, age = max(0, now - best.seen), own = best.source == "you",
                 confirmed = best.count, guess = best.guess or nil }
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

local Share, SharePublic   -- weiter unten

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
    local me = GP.Me and GP.Me() or "you"
    local changed, group = Sighted(id, { epoch = fits[id].epoch, seen = floor(now), source = "you",
        from = me, own = true }, now)
    if changed then
        ride.announced = id
        if not routine then
            if GP.Print then GP.Print(L["Schiffs-Zähler: Fahrplan durch deine Fahrt gemessen – die Gilde und andere GuildPride-Spieler bekommen ihn auch."]) end
            Share(id, nil, group)
            SharePublic(id, group)
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
                    if not ride then ride = { samples = {}, count = 0 } end
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
-- "route:seen:phase:[:o]" – das leere vierte Feld trug früher Layer (ältere Versionen lesen es weiter)
local function Encode(id, anchor)
    local route = routes[id]
    if not route then return nil end
    return format("%s:%d:%d:%s", id, anchor.seen, floor((anchor.seen * 1000 - anchor.epoch) % route.period),
        anchor.source == "you" and ":o" or "")
end

-- Liste von { id, anchor } (eine Strecke kann mehrfach vorkommen: mehrere Phasen).
-- Layer, die ältere Versionen im vierten Feld mitschicken, werden überlesen.
local function Decode(text, now, source)
    local out = {}
    for id, seenText, phaseText, ownText in tostring(text or ""):gmatch("([%w%-]+):(%d+):(%d+):?[%d%.,]*(:?o?)") do
        local route, seen, phase = routes[id], tonumber(seenText), tonumber(phaseText)
        if route and seen and phase and phase < route.period and seen <= now + CLOCK_SLACK and now - seen <= MAX_AGE then
            out[#out + 1] = { id = id, anchor = { epoch = seen * 1000 - phase, seen = min(seen, floor(now)), source = source or "player",
                own = ownText == ":o" } }
            if #out >= MAX_ROUTES_MSG then break end
        end
    end
    return out
end
T._Encode, T._Decode = Encode, Decode   -- für Tests

-- Teilen ist Pflicht für alle (wie Rares und Auktionshaus), es gibt keinen Schalter mehr
local function Enabled() return true end

local function OwnEntries(now)
    local list = {}
    for id in pairs(Store()) do
        if routes[id] then
            for _, g in ipairs(FreshGroups(id, now)) do
                if g.source == "you" then list[#list + 1] = Encode(id, g) end
            end
        end
    end
    table.sort(list)
    return list
end

-- An die Gilde: eine Gruppe (gerade gemessen) oder alle eigenen Messungen
Share = function(id, target, group)
    if not GP.Queue or not Enabled() then return end
    local entries
    if id then
        local anchor = group or AnchorOf(id, T.Now())
        entries = { anchor and Encode(id, anchor) }
    else
        entries = OwnEntries(T.Now())
    end
    if #entries == 0 then return end
    GP.Queue("TRS", target, Realm(), table.concat(entries, ";"))
end

---------------------------------------------------------------------
-- Serverweit: alle mit GuildPride im offenen Kanal (immer, auch ohne Gruppensuche)
---------------------------------------------------------------------
local function PublicOn()
    return Enabled() and GP.IS_FOREVER and GP.Queue and GP.PublicChannelId and GP.PublicChannelId()
        and not GP.PUBLIC_VIA_CHAT and true or false
end

SharePublic = function(id, group)
    if not PublicOn() or not group then return end
    local e = Encode(id, group)
    if e then GP.Queue("TPS", "@PUBLIC", GP.CLIENT_TAG, Realm(), e) end
end

-- Am Anleger: Messungen für diese Strecken erfragen, höchstens alle 5 Min.
local publicAsked = {}
function T.RequestPublic(ids)
    if not PublicOn() or type(ids) ~= "table" or #ids == 0 then return false end
    local list = {}
    for _, id in ipairs(ids) do if routes[id] then list[#list + 1] = id end end
    if #list == 0 then return false end
    table.sort(list)
    local key = table.concat(list, ",")
    if publicAsked[key] and GetTime() - publicAsked[key] < 300 then return false end
    publicAsked[key] = GetTime()
    GP.Queue("TPQ", "@PUBLIC", GP.CLIENT_TAG, Realm(), "", key)
    return true
end

-- Strecken einer Verbindung (für die Anfrage am Anleger)
function T.RoutesOf(serviceId)
    local out, s = {}, services[serviceId]
    for _, part in ipairs(s and s.routes or {}) do out[#out + 1] = part.route end
    return out
end

-- Antwort per Flüstern: nur eigene Messungen dieser Strecken
local answeredPublic = {}
local function AnswerPublic(sender, idsText)
    if answeredPublic[sender] and GetTime() - answeredPublic[sender] < 120 then return end
    local now, entries, len = T.Now(), {}, 0
    local n = 0
    for id in tostring(idsText or ""):gmatch("[%w%-]+") do
        n = n + 1
        if n > 12 then break end
        if routes[id] then
            for _, g in ipairs(FreshGroups(id, now)) do
                local e = g.source == "you" and Encode(id, g)
                if e and len + #e + 1 <= PUBLIC_LEN - 20 then entries[#entries + 1] = e; len = len + #e + 1 end
            end
        end
    end
    if #entries == 0 then return end
    answeredPublic[sender] = GetTime()
    local function send() GP.QueuePublicTo(sender, "TPS", GP.CLIENT_TAG, Realm(), table.concat(entries, ";")) end
    if C_Timer and C_Timer.After then C_Timer.After(0.5 + math.random() * 4, send) else send() end
end

-- Aus GuildPride.lua: Nachrichten aus dem offenen Kanal (TPS/TPQ) und geflüsterte Antworten (TPS)
function GP.OnTransitPublic(message, sender, whisper)
    if not PublicOn() or type(message) ~= "string" or type(sender) ~= "string" then return end
    if #sender > 60 or sender:find("|", 1, true) or (GP.Me and sender == GP.Me()) then return end
    local kind, value = message:match("^(TP%u):(.*)$")
    if not kind then return end
    local f = { strsplit(SEP, value) }
    if f[1] ~= GP.CLIENT_TAG or f[2] ~= Realm() then return end
    if kind == "TPS" then
        local now, any = T.Now(), false
        for _, e in ipairs(Decode(f[3], now, "public")) do
            e.anchor.from = sender
            if Sighted(e.id, e.anchor, now) then any = true end
        end
        if any then Changed() end
    elseif kind == "TPQ" and not whisper then
        AnswerPublic(sender, f[4])
    end
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
        for _, e in ipairs(Decode(list, now, "player")) do
            e.anchor.from = sender
            if Sighted(e.id, e.anchor, now) then any = true end
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
    for id in pairs(s) do
        if not routes[id] then s[id] = nil
        else
            FreshGroups(id, now, true)
            if #Groups(id) == 0 then s[id] = nil end
        end
    end
    -- Reste der Layer-Zeit (vor dem Hotfix vom 20.11.2026) wegräumen
    for _, list in pairs(s) do
        for _, g in ipairs(type(list) == "table" and list or {}) do
            if type(g) == "table" then g.tags = nil end
        end
    end
    GuildPrideDB.transitStarts, GuildPrideDB.transitCalib = nil, nil
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, T.Sample) end
    if C_Timer and C_Timer.After then C_Timer.After(20, function() if IsInGuild and IsInGuild() then T.Request() end end) end
end)
