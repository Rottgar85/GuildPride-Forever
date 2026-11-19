-- GuildPride: Flugzeit am Flugmeister. Auf der Flugkarte steht im Tooltip jedes Ziels, wie lange
-- der Flug dauert. Geschätzt wie bei Polestar: die geflogenen Yards jedes Teilflugs (Daten aus
-- Polestars TravelData.lua, siehe GuildPrideFlightData.lua) durch 30 yd/s plus 2 s je Teilflug für
-- Start und Landung. Jeder eigene Flug wird gestoppt und je Strecke gespeichert
-- (GuildPrideDB.flightLog); gemessene Strecken zeigen die echte Zeit, sonst steht „ca.“ davor.
-- Im Flug zeigt GuildPrideFlightUI.lua die Restzeit bis zur Landung (F.Status).
-- Aus: Einstellungen › „Flugzeit am Flugmeister im Tooltip zeigen“.
-- Nur Tooltip-Zeilen und Nach-Hooks (hooksecurefunc, HookScript): Blizzards Flugkarte wird weder
-- geöffnet noch geschlossen noch verändert.
local ADDON, GP = ...
local F = {}
GP.Flight = F
local L = GP.L or setmetatable({}, { __index = function(_, k) return k end })

local floor, sqrt = math.floor, math.sqrt
local format, lower = string.format, string.lower

F.SPEED = 30          -- yd/s entlang der Flugstrecke (Greif, Windreiter; wie Polestar)
F.STOP = 2            -- s je Teilflug für Start und Landung (wie Polestar)
local MIN_SECS, MAX_SECS = 5, 3600   -- gemessene Flüge außerhalb gelten nicht
local LAND_NEAR = 500                -- yd: so nah am Ziel gelandet = Flug wurde zu Ende geflogen
local TAKEOFF_WAIT = 15              -- s: so lange nach dem Klick muss der Flug begonnen haben
local TICK = 0.25

local data = GP.FlightData or { nodes = {}, flights = {} }
local direct = {}     -- direct[von][nach] = Yards
for from, list in pairs(data.flights) do
    local t = {}
    for i = 1, #list - 1, 2 do t[list[i]] = list[i + 1] end
    direct[from] = t
end

local function Readable(v)
    if v ~= nil and issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function Enabled() return not (type(GuildPrideDB) == "table" and GuildPrideDB.flightTimes == false) end

local function Log()
    if type(GuildPrideDB) ~= "table" then return nil end
    if type(GuildPrideDB.flightLog) ~= "table" then GuildPrideDB.flightLog = {} end
    return GuildPrideDB.flightLog
end

function F.Node(id) return data.nodes[id] end
function F.Yards(from, to) return direct[from] and direct[from][to] end

-- Schlüssel einer Strecke: die Flugpunkte von Start bis Ziel, z. B. "2-12-5"
function F.Key(chain)
    if type(chain) ~= "table" or #chain < 2 then return nil end
    return table.concat(chain, "-")
end

-- Geschätzte Dauer eines Teilflugs bzw. einer Strecke in s (nil: ein Teilflug ist unbekannt)
function F.HopEstimate(from, to)
    local yd = F.Yards(from, to)
    return yd and (yd / F.SPEED + F.STOP) or nil
end

function F.Estimate(chain)
    if type(chain) ~= "table" or #chain < 2 then return nil end
    local s = 0
    for i = 1, #chain - 1 do
        local h = F.HopEstimate(chain[i], chain[i + 1])
        if not h then return nil end
        s = s + h
    end
    return s
end

-- Dauer einer Strecke: gemessen (true) oder geschätzt (false). Ungemessene Strecken nehmen für
-- Teilflüge, die schon einzeln gemessen sind, deren Zeit, sonst die Schätzung.
function F.Time(chain)
    local key = F.Key(chain)
    if not key then return nil end
    local log = Log() or {}
    if type(log[key]) == "number" then return log[key], true end
    -- Rückflug gemessen: gleiche Strecke, gleiche Dauer
    local back = {}
    for i = #chain, 1, -1 do back[#back + 1] = chain[i] end
    if type(log[F.Key(back)]) == "number" then return log[F.Key(back)], true end
    local s = 0
    for i = 1, #chain - 1 do
        local h = log[chain[i] .. "-" .. chain[i + 1]]
        if type(h) ~= "number" then h = log[chain[i + 1] .. "-" .. chain[i]] end
        if type(h) ~= "number" then h = F.HopEstimate(chain[i], chain[i + 1]) end
        if not h then return nil end
        s = s + h
    end
    return s, false
end

-- Gemessene Flugzeit speichern; true, wenn sie gilt
function F.Record(chain, secs)
    local key = F.Key(chain)
    local log = Log()
    if not (key and log and type(secs) == "number") then return false end
    if secs < MIN_SECS or secs > MAX_SECS then return false end
    log[key] = floor(secs + 0.5)
    return true
end

function F.Countdown(secs)
    secs = floor((secs or 0) + 0.5)
    if secs < 0 then secs = 0 end
    return format("%d:%02d", floor(secs / 60), secs % 60)
end

-- Tooltip-Zeile und Farbe
function F.Text(secs, measured)
    if not secs then return nil end
    if measured then return format(L["Flugzeit: %s"], F.Countdown(secs)), 1, 0.82, 0.2 end
    return format(L["Flugzeit: ca. %s"], F.Countdown(secs)), 0.75, 0.75, 0.75
end

---------------------------------------------------------------------------
-- Flugkarte: Platz (slot) → Flugpunkt-ID, Strecke zu einem Platz
---------------------------------------------------------------------------

local byName   -- englischer Name (klein) → ID, für Clients ohne C_TaxiMap
local function NameToID(name)
    if type(name) ~= "string" then return nil end
    if not byName then
        byName = {}
        for id, n in pairs(data.nodes) do
            local k = lower(n[4])
            if not byName[k] or id < byName[k] then byName[k] = id end
        end
    end
    return byName[lower(name)]
end

-- slots[slot] = Flugpunkt-ID der offenen Flugkarte
function F.SlotIDs()
    local ids = {}
    local map = GetTaxiMapID and Readable(GetTaxiMapID())
    local nodes = map and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and C_TaxiMap.GetAllTaxiNodes(map)
    if type(nodes) == "table" and #nodes > 0 then
        for _, n in ipairs(nodes) do
            if type(n) == "table" and n.slotIndex and n.nodeID then ids[n.slotIndex] = n.nodeID end
        end
        return ids
    end
    for slot = 1, (NumTaxiNodes and NumTaxiNodes() or 0) do
        ids[slot] = NameToID(TaxiNodeName and TaxiNodeName(slot))
    end
    return ids
end

-- Flugpunkte von hier bis zum Ziel-Platz, z. B. { 2, 12, 5 }, oder nil
function F.Chain(slot, ids)
    if not (slot and GetNumRoutes and TaxiGetNodeSlot) then return nil end
    ids = ids or F.SlotIDs()
    local hops = Readable(GetNumRoutes(slot)) or 0
    if hops < 1 then return nil end
    local chain = { ids[TaxiGetNodeSlot(slot, 1, true)] }
    for hop = 1, hops do
        chain[#chain + 1] = ids[TaxiGetNodeSlot(slot, hop, false)]
    end
    if #chain ~= hops + 1 then return nil end
    return chain
end

local chains = {}   -- Strecken der offenen Flugkarte je Platz (für den Klick)

function F.SlotTime(slot)
    if TaxiNodeGetType and TaxiNodeGetType(slot) ~= "REACHABLE" then return nil end
    local chain = chains[slot] or F.Chain(slot)
    if not chain then return nil end
    chains[slot] = chain
    local secs, measured = F.Time(chain)
    return secs, measured, chain
end

function F.AddTooltip(slot, tip)
    if not (Enabled() and slot and tip) then return false end
    local text, r, g, b = F.Text(F.SlotTime(slot))
    if not text then return false end
    tip:AddLine(text, r, g, b)
    tip:Show()
    return true
end

---------------------------------------------------------------------------
-- Messen: Klick aufs Ziel (TakeTaxiNode) → Abflug (UnitOnTaxi) → Landung
---------------------------------------------------------------------------

local pending   -- { chain, name = Ziel, at = Klick, start = Abflug }
local ticker
F.onTick = nil  -- GuildPrideFlightUI.lua: nach jedem Tick neu zeichnen

local function OnTaxi() return Readable(UnitOnTaxi and UnitOnTaxi("player")) and true or false end

-- Am Ziel gelandet? Beide Achsen-Reihenfolgen zählen: UnitPosition liefert je nach Client y, x oder x, y.
local function Landed(chain)
    local node = F.Node(chain[#chain])
    if not (node and UnitPosition) then return true end
    local ok, x, y, _, instance = pcall(UnitPosition, "player")
    x, y, instance = Readable(x), Readable(y), Readable(instance)
    if not ok or type(x) ~= "number" or type(y) ~= "number" then return true end
    if instance ~= nil and instance ~= node[1] then return false end
    local function Dist(a, b) local dx, dy = a - node[2], b - node[3]; return sqrt(dx * dx + dy * dy) end
    return math.min(Dist(x, y), Dist(y, x)) <= LAND_NEAR
end

-- Laufender Flug in GuildPrideDB.flightNow, damit er ein /reload übersteht (Serverzeit des Abflugs)
local function Save(now)
    if type(GuildPrideDB) ~= "table" then return end
    if pending and pending.start then
        GuildPrideDB.flightNow = { chain = pending.chain, name = pending.name,
            started = GetServerTime() - floor((now or GetTime()) - pending.start + 0.5) }
    else
        GuildPrideDB.flightNow = nil
    end
end

-- Kurzer Name eines Flugpunkts: „Lakeshire, Redridge“ → „Lakeshire“
function F.ShortName(name)
    if type(name) ~= "string" then return nil end
    return name:match("^([^,]+),") or name
end

function F.Begin(chain, now, name)
    if not F.Key(chain) then return false end
    local node = F.Node(chain[#chain])
    pending = { chain = chain, at = now or GetTime(), name = name or (node and F.ShortName(node[4])) }
    if ticker then ticker:Show() end
    return true
end

-- Nach /reload oder Neu-Einloggen mitten im Flug: den gespeicherten Flug weiterzählen
function F.Restore(now)
    now = now or GetTime()
    local s = type(GuildPrideDB) == "table" and GuildPrideDB.flightNow
    if pending or not OnTaxi() or type(s) ~= "table" or not F.Key(s.chain) or type(s.started) ~= "number" then return false end
    local ago = GetServerTime() - s.started
    if ago < 0 or ago > MAX_SECS then return false end
    pending = { chain = s.chain, name = s.name, at = now - ago, start = now - ago }
    if ticker then ticker:Show() end
    return true
end

-- Der Flug gerade: { to, total (s, nil: unbekannt), elapsed, left, measured, fill (0–1) } oder nil
function F.Status(now)
    if not (pending and pending.start) then return nil end
    now = now or GetTime()
    local total, measured = F.Time(pending.chain)
    local elapsed = math.max(0, now - pending.start)
    local st = { to = pending.name, total = total, elapsed = elapsed, measured = measured and true or false }
    if total and total > 0 then
        st.left = math.max(0, total - elapsed)
        st.fill = math.min(1, elapsed / total)
    end
    return st
end

-- Einmal je TICK, solange ein Flug ansteht; gibt die gespeicherte Zeit zurück, wenn er endet
function F.Tick(now)
    if not pending then return nil end
    now = now or GetTime()
    local on = OnTaxi()
    if not pending.start then
        if on then pending.start = now; Save(now)
        elseif now - pending.at > TAKEOFF_WAIT then pending = nil end
        return nil
    end
    if on then return nil end
    local p, secs = pending, now - pending.start
    pending = nil
    Save(now)
    if Landed(p.chain) and F.Record(p.chain, secs) then return floor(secs + 0.5) end
    return nil
end

function F.Pending() return pending end
function F.Cancel() pending = nil; Save() end

function F.OnMapOpened()
    wipe(chains)
    local ids = F.SlotIDs()
    for slot = 1, (NumTaxiNodes and NumTaxiNodes() or 0) do
        chains[slot] = F.Chain(slot, ids)
    end
end

function F.OnTakeTaxiNode(slot)
    local chain = chains[slot] or F.Chain(slot)
    if chain then F.Begin(chain, nil, F.ShortName(Readable(TaxiNodeName and TaxiNodeName(slot)))) end
end

---------------------------------------------------------------------------
-- Haken in Blizzards Flugkarte (nur danach, nichts wird ersetzt)
---------------------------------------------------------------------------

local hookedPins = setmetatable({}, { __mode = "k" })
local function HookFlightMapPins()
    local fm = FlightMapFrame
    if not (fm and fm.EnumeratePinsByTemplate) then return end
    for pin in fm:EnumeratePinsByTemplate("FlightMap_FlightPointPinTemplate") do
        if not hookedPins[pin] and pin.HookScript then
            hookedPins[pin] = true
            pin:HookScript("OnEnter", function(self)
                local d = self.taxiNodeData
                if d and d.slotIndex then F.AddTooltip(d.slotIndex, GameTooltip) end
            end)
        end
    end
end

if hooksecurefunc then
    if TaxiNodeOnButtonEnter then
        hooksecurefunc("TaxiNodeOnButtonEnter", function(button)
            if button and button.GetID then F.AddTooltip(button:GetID(), GameTooltip) end
        end)
    end
    if TakeTaxiNode then hooksecurefunc("TakeTaxiNode", function(slot) F.OnTakeTaxiNode(slot) end) end
end

local ev = CreateFrame("Frame")
ticker = CreateFrame("Frame")
ticker:Hide()
local elapsed = 0
ticker:SetScript("OnUpdate", function(self, dt)
    elapsed = elapsed + (dt or 0)
    if elapsed < TICK then return end
    elapsed = 0
    F.Tick()
    if F.onTick then F.onTick() end
    if not pending then self:Hide() end
end)
ev:RegisterEvent("TAXIMAP_OPENED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(_, event)
    if event == "TAXIMAP_OPENED" then
        F.OnMapOpened()
        -- FlightMapFrame legt seine Punkte im selben Event an: danach einhaken
        if C_Timer and C_Timer.After then C_Timer.After(0, HookFlightMapPins) else HookFlightMapPins() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if OnTaxi() then
            F.Restore()
        else
            -- Ladebildschirm oder neu eingeloggt am Boden: eine angefangene Messung gilt nicht mehr
            pending = nil
            Save()
        end
        if F.onTick then F.onTick() end
    end
end)
