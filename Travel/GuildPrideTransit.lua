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
-- Eine Messung gilt bis zum nächsten wöchentlichen Reset (die Wartung startet die Server neu und
-- setzt die Runden zurück), höchstens 7 Tage.
--
-- Layer: Jeder Layer ist eine eigene Server-Instanz und fährt seine Schiffe versetzt. Darum trägt
-- jede Messung die Layer, auf denen sie gemacht wurde („Karte.Layer“ aus der Kreatur-GUID, siehe
-- GuildPrideLayer.lua; die Zahl gilt je Zone, darum mit Karte). Messungen mit gleicher Phase und
-- ohne widersprüchliche Layer gehören zusammen (eine Gruppe = ein Layer) und sammeln die Layer
-- aller, die sie gemessen haben – so kennt eine Gruppe am Ende beide Anleger. Am Steg zählt die
-- Gruppe mit deinem Layer; wechselst du den Layer, wechselt die Anzeige mit.
-- Je Realm gespeichert in GuildPrideDB.transit[realm][route] =
--   { { epoch, seen, source = "you"|"player"|"public", tags = { "1437.123", … },
--       by = { [Name] = Zeit } }, … }      by: wer diese Zeit selbst gemessen hat (Bestätigungen)
-- Ungemessen gibt es nur die mittlere Wartezeit. Gibt es diese Woche noch keine Messung, zeigt
-- der Zähler die der letzten Woche als Vermutung (gleicher Abstand zum Reset).
-- Versuch (geschätzt): Kreaturen-GUIDs tragen ihre Entstehungszeit; die früheste je Layer ist
-- etwa dessen Start. Passt der Abstand Start → Fahrplan bei zwei Layern mit verschiedenem Start
-- zusammen, schätzt der Zähler auch Layer, auf denen noch niemand mitgefahren ist.
--
-- Teilen ist Pflicht (kein Schalter), mit der Gilde und serverweit:
-- Gilden-Nachrichten (nie weitergeleitet):
--   TRS  realm · "route:seen:phase:tags[:o];…"   Messungen (an die Gilde oder als Antwort geflüstert)
--   TRQ  1                                       Messungen anfragen (beim Einloggen)
-- Serverweit (offener GuildPride-Kanal, immer – unabhängig von der Gruppensuche):
--   TPS  F · realm · "route:seen:phase:tags[:o];…"   eigene Messung an alle bzw. Antwort (Flüstern)
--   TPQ  F · realm · Layer · "route,route"           am Anleger: wer hat diese Strecken (für meinen Layer)?
-- ":o" = selbst gemessen; nur das zählt als Bestätigung.
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
local MAX_GROUPS = 12          -- je Strecke so viele Layer-Gruppen merken
local MAX_TAGS = 8             -- je Gruppe so viele Layer merken
local MSG_TAGS = 3             -- je Eintrag so viele Layer verschicken (Nachrichtengrenze 255 Byte)
local PUBLIC_LEN = 240         -- Byte: serverweite Nachrichten sind immer einteilig
local TAG_WINDOW = 300         -- s: so lange vor dem Ablegen bzw. nach der Ankunft zählt der Layer zur Fahrt
local CONFIRM_WINDOW = 12 * 3600   -- s: Bestätigungen so nah an der neuesten zählen
local MAX_BY = 10              -- je Gruppe so viele Bestätiger merken
local SPAWN_MOD = 2 ^ 23       -- s: Kreaturen-GUIDs tragen die Entstehungszeit modulo 2^23
local MAX_CALIB = 6            -- je Strecke so viele Eichungen (Start → Fahrplan) merken
local START_SLACK = 3600       -- s: Layer-Start so lange vor dem Reset zählt noch (Wartung)

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
-- Layer: "Karte.Layer" (Layer-Zahl aus der Kreatur-GUID gilt nur innerhalb einer Zone)
---------------------------------------------------------------------
local function ValidTag(tag)
    if type(tag) ~= "string" then return nil end
    local map, id = tag:match("^(%d+)%.(%d+)$")
    map = tonumber(map)
    if not map or map <= 0 or map > 999999 or #id > 10 or id == "0" then return nil end
    return tag
end

local function TagMap(tag) return tag:match("^(%d+)%.") end

-- Mein Layer hier, sofern bekannt (eine Kreatur in dieser Zone hat ihn verraten)
local function CurrentTag()
    local Ly = GP.Layer
    if type(Ly) ~= "table" or not Ly.id or not Ly.map then return nil end
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if type(map) ~= "number" or map ~= Ly.map then return nil end
    return ValidTag(map .. "." .. tostring(Ly.id))
end
T.CurrentTag = CurrentTag

local function HasTag(anchor, tag)
    for _, t in ipairs(anchor.tags or {}) do if t == tag then return true end end
    return false
end

-- Widersprechen sich zwei Layer-Listen? (gleiche Zone, andere Layer-Zahl = anderer Layer)
local function Conflicts(tagsA, tagsB)
    for _, a in ipairs(tagsA or {}) do
        local ma = TagMap(a)
        for _, b in ipairs(tagsB or {}) do
            if a ~= b and TagMap(b) == ma then return true end
        end
    end
    return false
end

-- Layer anhängen (neueste zuletzt, höchstens MAX_TAGS); true, wenn etwas dazukam
local function AddTags(anchor, tags)
    anchor.tags = anchor.tags or {}
    local added = false
    for _, t in ipairs(tags or {}) do
        if ValidTag(t) and not HasTag(anchor, t) then
            anchor.tags[#anchor.tags + 1] = t
            added = true
        end
    end
    while #anchor.tags > MAX_TAGS do table.remove(anchor.tags, 1) end
    return added
end

---------------------------------------------------------------------
-- Gruppen je Strecke (eine Gruppe = eine Phase = ein Layer)
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

-- Die Gruppe für den Anleger: die mit meinem Layer; ist mein Layer unbekannt, die neueste.
-- Zweiter Wert: true = auf deinem Layer gemessen, false = nur andere Layer bekannt, nil = unklar
local function AnchorOf(route, now, tag)
    local best, bestTagged
    local others = false
    for _, a in ipairs(FreshGroups(route, now)) do
        if tag and HasTag(a, tag) then
            if Better(a, bestTagged, now) then bestTagged = a end
        elseif tag and Conflicts({ tag }, a.tags) then
            others = true
        elseif Better(a, best, now) then
            best = a
        end
    end
    if bestTagged then return bestTagged, true end
    if best then return best, nil end
    if others then return nil, false end
    return nil, nil
end

-- Übernimmt die neue Messung die Zeit der Gruppe? Die eigene Fahrt gewinnt gegen fremde;
-- eine fremde ersetzt keine eigene unter einer Stunde; sonst zählt nur eine neuere.
local function Newer(incoming, held, now)
    if not Fresh(held, now) then return true end
    if incoming.source == "you" and held.source ~= "you" then return true end
    if held.source == "you" and incoming.source ~= "you" and now - held.seen < OWN_TRUST then return false end
    return incoming.seen > held.seen
end

-- Messung eintragen: in die passende Gruppe (gleiche Phase, keine widersprüchlichen Layer)
-- oder als neue Gruppe. true, wenn sich etwas geändert hat.
local function Sighted(route, anchor, now)
    local r = routes[route]
    if not r or type(anchor.epoch) ~= "number" or type(anchor.seen) ~= "number" then return false end
    local list = Groups(route)
    FreshGroups(route, now, true)
    local tags = {}
    for _, t in ipairs(anchor.tags or {}) do if ValidTag(t) then tags[#tags + 1] = t end end
    -- selbst gemessen (eigene Fahrt oder ":o" vom Absender): zählt als Bestätigung
    local who = anchor.own and anchor.from or nil
    for _, g in ipairs(list) do
        -- nur Gruppen dieser Woche; die der letzten Woche bleiben als Vermutung stehen
        if Fresh(g, now) and SamePhase(g, anchor, r.period) and not Conflicts(g.tags, tags) then
            local changed = AddTags(g, tags)
            if who and Confirm(g, who, anchor.seen) then changed = true end
            if Newer(anchor, g, now) and (anchor.seen ~= g.seen or anchor.epoch ~= g.epoch or anchor.source ~= g.source) then
                g.epoch, g.seen, g.source = anchor.epoch, anchor.seen, anchor.source
                changed = true
            end
            return changed, g
        end
    end
    local g = { epoch = anchor.epoch, seen = anchor.seen, source = anchor.source, tags = {}, by = {} }
    AddTags(g, tags)
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
    local tag = CurrentTag()
    local best, otherLayer
    local function Take(part, route, anchor, mine, extra)
        local phase = (t - anchor.epoch) % route.period
        for _, i in ipairs(part[side] or {}) do
            local a, d, n, st = Visit(route.period, route.stops[i], phase)
            if not best or d < best.d then
                best = { a = a, d = d, n = n, s = st, p = route.period, seen = anchor.seen, source = anchor.source,
                         mine = mine, count = Count(anchor), estimated = extra == "estimated", guess = extra == "guess" }
            end
        end
    end
    for _, part in ipairs(s.routes or {}) do
        local route = routes[part.route]
        local anchor, mine
        if route then anchor, mine = AnchorOf(part.route, now, tag) end
        -- Auf meinem Layer noch nicht gemessen: Schätzung aus dem Layer-Start, sofern geeicht
        local est = route and tag and mine ~= true and T.Estimate(part.route, tag, now)
        if est then Take(part, route, est, true, "estimated")
        elseif anchor then Take(part, route, anchor, mine) end
        if mine == false and not est then otherLayer = true end
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
                Take(part, route, { epoch = last.epoch + WEEK * 1000, seen = last.seen, source = last.source, by = last.by }, nil, "guess")
            end
        end
    end
    if best then
        -- layer: true = auf deinem Layer gemessen, nil = dein Layer ist unbekannt bzw. die Messung ohne Layer
        -- confirmed: so viele haben die Zeit selbst gemessen; estimated/guess: nur geschätzt bzw. vermutet
        return { timed = true, arriveIn = pre + best.a / 1000, departIn = pre + best.d / 1000, nextIn = pre + best.n / 1000,
                 stay = best.s / 1000, period = best.p / 1000, age = max(0, now - best.seen), own = best.source == "you",
                 layer = best.mine, layerKnown = tag ~= nil, confirmed = best.count,
                 estimated = best.estimated or nil, guess = best.guess or nil }
    end
    -- otherLayer: es gibt Messungen, aber nur von anderen Layern
    return { timed = false, wait = (s.wait or {})[side], otherLayer = otherLayer, layerKnown = tag ~= nil }
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

local Share, SharePublic, ShareSoon   -- weiter unten
local lastTag     -- { tag, at }: zuletzt erkannter Layer (am Anleger vor dem Ablegen)
local afterRide   -- { id, group, untilT }: nach der Ankunft den Layer der Zielzone nachtragen

local function RideTags()
    local out = {}
    for t in pairs(ride and ride.tags or {}) do out[#out + 1] = t end
    table.sort(out)
    return out
end

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
    local held = AnchorOf(id, now, CurrentTag())
    local routine = held and held.source == "you" and now - held.seen < QUIET
    local me = GP.Me and GP.Me() or "you"
    local tags = RideTags()
    local changed, group = Sighted(id, { epoch = fits[id].epoch, seen = floor(now), source = "you", tags = tags,
        from = me, own = true }, now)
    if group then ride.group, ride.groupId = group, id end
    T.Calibrate(id, fits[id].epoch, tags, now)
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

-- Nach der Ankunft: den Layer der Zielzone an die eigene Messung hängen (dann kennt sie beide Anleger)
local function TagAfterRide(tag, now)
    if not afterRide or now > afterRide.untilT then afterRide = nil; return end
    local g = afterRide.group
    if HasTag(g, tag) or Conflicts(g.tags, { tag }) then return end
    if AddTags(g, { tag }) then
        T.Calibrate(afterRide.id, g.epoch, { tag }, now)
        Changed()
        ShareSoon(afterRide.id, g)
    end
end

function T.Sample()
    local nowMs = T.Now() * 1000
    local tag = CurrentTag()
    if tag then
        lastTag = { tag = tag, at = nowMs / 1000 }
        if ride then ride.tags[tag] = true end
        if afterRide then TagAfterRide(tag, nowMs / 1000) end
    end
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
                    if not ride then
                        ride = { samples = {}, count = 0, tags = {} }
                        -- Layer am Anleger, kurz vor dem Ablegen
                        if lastTag and nowMs / 1000 - lastTag.at <= TAG_WINDOW then ride.tags[lastTag.tag] = true end
                    end
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
        if ride.group then afterRide = { id = ride.groupId, group = ride.group, untilT = nowMs / 1000 + TAG_WINDOW } end
        ride = nil
    end
end

---------------------------------------------------------------------
-- Versuch: Layer-Start aus Kreaturen-GUIDs, daraus geschätzte Fahrpläne
---------------------------------------------------------------------
-- Entstehungszeit (Server-s) einer Kreatur: die letzten 23 Bit der Spawn-Kennung
-- (letztes Feld der GUID) zählen Sekunden modulo 2^23
function T.SpawnTime(guid, now)
    if type(guid) ~= "string" then return nil end
    local spawnUID = select(7, strsplit("-", guid))
    if type(spawnUID) ~= "string" or #spawnUID ~= 10 then return nil end
    local low = tonumber(spawnUID:sub(5), 16)
    if not low then return nil end
    low = low % SPAWN_MOD
    return now - ((now % SPAWN_MOD - low) % SPAWN_MOD)
end

local function Sub(key, realm)
    if type(GuildPrideDB) ~= "table" then GuildPrideDB = {} end
    if type(GuildPrideDB[key]) ~= "table" then GuildPrideDB[key] = {} end
    local t = GuildPrideDB[key]
    if realm then
        local r = Realm()
        if type(t[r]) ~= "table" then t[r] = {} end
        t = t[r]
    end
    return t
end
-- transitStarts[realm][tag] = { t = Start, at = zuletzt gesehen } · transitCalib[route] = { { off, start }, … }
local function Starts() return Sub("transitStarts", true) end
local function Calib() return Sub("transitCalib") end

-- Kreatur gesehen (aus GuildPrideLayer.lua): die früheste Entstehung je Layer merken
function T.SawCreature(guid, tag, now)
    tag = ValidTag(tag)
    if not tag then return end
    now = floor(now or T.Now())
    local st = T.SpawnTime(guid, now)
    if not st or st > now then return end
    local reset = LastReset(now)
    if reset and st < reset - START_SLACK then return end   -- vor der Wartung: passt nicht
    local s = Starts()
    local cur = s[tag]
    if type(cur) ~= "table" or type(cur.t) ~= "number" or st < cur.t or (reset and cur.t < reset - START_SLACK) then
        s[tag] = { t = st, at = now }
    else
        cur.at = now
    end
end

-- Nach einer Messung: Abstand Layer-Start → Fahrplan merken
function T.Calibrate(route, epoch, tags, now)
    local r = routes[route]
    if not r or type(epoch) ~= "number" then return end
    local s, c = Starts(), Calib()
    local list = type(c[route]) == "table" and c[route] or {}
    c[route] = list
    for _, tag in ipairs(tags or {}) do
        local st = s[tag]
        if type(st) == "table" and type(st.t) == "number" then
            local off = floor((epoch - st.t * 1000) % r.period)
            for i = #list, 1, -1 do
                if math.abs(list[i].start - st.t) < 5 then table.remove(list, i) end
            end
            list[#list + 1] = { off = off, start = st.t, at = floor(now or T.Now()) }
            while #list > MAX_CALIB do table.remove(list, 1) end
        end
    end
end

-- Geeicht ist eine Strecke erst, wenn zwei Layer mit verschiedenem Start denselben Abstand zeigen
local function Offset(route)
    local r, list = routes[route], Calib()[route]
    if not r or type(list) ~= "table" then return nil end
    for i = #list, 1, -1 do
        for j = i - 1, 1, -1 do
            local a, b = list[i], list[j]
            local d = (a.off - b.off + r.period / 2) % r.period - r.period / 2
            if math.abs(a.start - b.start) > 60 and math.abs(d) <= AGREE then
                return (b.off + d / 2) % r.period
            end
        end
    end
    return nil
end
T._Offset = Offset   -- für Tests

-- Geschätzte Messung für meinen Layer (nil, wenn nicht geeicht oder Start unbekannt)
function T.Estimate(route, tag, now)
    local off = Offset(route)
    local st = tag and Starts()[tag]
    if not off or type(st) ~= "table" or type(st.t) ~= "number" then return nil end
    local reset = LastReset(now or T.Now())
    if reset and st.t < reset - START_SLACK then return nil end
    return { epoch = st.t * 1000 + off, seen = st.at or st.t, source = "estimate" }
end

---------------------------------------------------------------------
-- Mit der Gilde teilen (nur derselbe Realm: die Runden hängen am Server)
---------------------------------------------------------------------
-- "route:seen:phase:Layer,Layer" (die neuesten MSG_TAGS Layer; ältere Versionen lesen nur die ersten drei Felder)
local function Encode(id, anchor)
    local route = routes[id]
    if not route then return nil end
    local list, tags = anchor.tags or {}, {}
    for i = max(1, #list - MSG_TAGS + 1), #list do tags[#tags + 1] = list[i] end
    return format("%s:%d:%d:%s%s", id, anchor.seen, floor((anchor.seen * 1000 - anchor.epoch) % route.period),
        table.concat(tags, ","), anchor.source == "you" and ":o" or "")
end

-- Liste von { id, anchor } (eine Strecke kann mehrfach vorkommen: mehrere Layer)
local function Decode(text, now, source)
    local out = {}
    for id, seenText, phaseText, tagText, ownText in tostring(text or ""):gmatch("([%w%-]+):(%d+):(%d+):?([%d%.,]*)(:?o?)") do
        local route, seen, phase = routes[id], tonumber(seenText), tonumber(phaseText)
        if route and seen and phase and phase < route.period and seen <= now + CLOCK_SLACK and now - seen <= MAX_AGE then
            local tags = {}
            for t in tagText:gmatch("[^,]+") do
                if ValidTag(t) and #tags < MAX_TAGS then tags[#tags + 1] = t end
            end
            out[#out + 1] = { id = id, anchor = { epoch = seen * 1000 - phase, seen = min(seen, floor(now)), source = source or "player",
                tags = tags, own = ownText == ":o" } }
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
        local anchor = group or AnchorOf(id, T.Now(), CurrentTag())
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

-- Neue Layer an einer Messung: gesammelt nach kurzer Zeit noch einmal teilen
local soonPending = false
ShareSoon = function(id, group)
    if soonPending then return end
    soonPending = true
    local function go()
        soonPending = false
        Share(id, nil, group)
        SharePublic(id, group)
    end
    if C_Timer and C_Timer.After then C_Timer.After(20, go) else go() end
end

-- Am Anleger: Messungen für diese Strecken (und meinen Layer) erfragen, je Layer höchstens alle 5 Min.
local publicAsked = {}
function T.RequestPublic(ids)
    if not PublicOn() or type(ids) ~= "table" or #ids == 0 then return false end
    local list = {}
    for _, id in ipairs(ids) do if routes[id] then list[#list + 1] = id end end
    if #list == 0 then return false end
    table.sort(list)
    local tag = CurrentTag() or ""
    local key = tag .. "|" .. table.concat(list, ",")
    if publicAsked[key] and GetTime() - publicAsked[key] < 300 then return false end
    publicAsked[key] = GetTime()
    GP.Queue("TPQ", "@PUBLIC", GP.CLIENT_TAG, Realm(), tag, table.concat(list, ","))
    return true
end

-- Strecken einer Verbindung (für die Anfrage am Anleger)
function T.RoutesOf(serviceId)
    local out, s = {}, services[serviceId]
    for _, part in ipairs(s and s.routes or {}) do out[#out + 1] = part.route end
    return out
end

-- Antwort per Flüstern: eigene Messungen dieser Strecken, passender Layer zuerst;
-- fremde nur, wenn sie genau den Layer des Fragenden tragen
local answeredPublic = {}
local function AnswerPublic(sender, tag, idsText)
    if answeredPublic[sender] and GetTime() - answeredPublic[sender] < 120 then return end
    local now, first, rest = T.Now(), {}, {}
    local n = 0
    for id in tostring(idsText or ""):gmatch("[%w%-]+") do
        n = n + 1
        if n > 12 then break end
        if routes[id] then
            for _, g in ipairs(FreshGroups(id, now)) do
                local exact = tag and HasTag(g, tag)
                if exact then first[#first + 1] = Encode(id, g)
                elseif g.source == "you" and not (tag and Conflicts({ tag }, g.tags)) then rest[#rest + 1] = Encode(id, g) end
            end
        end
    end
    local entries, len = {}, 0
    for _, list in ipairs({ first, rest }) do
        for _, e in ipairs(list) do
            if len + #e + 1 <= PUBLIC_LEN - 20 then entries[#entries + 1] = e; len = len + #e + 1 end
        end
    end
    if #entries == 0 then return end
    -- Viele GuildPride-Spieler im Kanal: nicht alle antworten (genau passende immer)
    local count = 0
    if type(GP.Layer) == "table" and type(GP.Layer.public) == "table" then
        for _ in pairs(GP.Layer.public) do count = count + 1 end
    end
    if #first == 0 and count > 6 and math.random() > 6 / count then return end
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
        AnswerPublic(sender, ValidTag(f[3]), f[4])
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
    local starts = Starts()
    for tag, st in pairs(starts) do
        if type(st) ~= "table" or type(st.at) ~= "number" or now - st.at > MAX_AGE then starts[tag] = nil end
    end
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(1, T.Sample) end
    if C_Timer and C_Timer.After then C_Timer.After(20, function() if IsInGuild and IsInGuild() then T.Request() end end) end
end)
