-- GuildPride Rares: Grundgerüst, gespeicherte Daten, Hilfsfunktionen
-- Aufbau wie GuildPride (ns-Namespace, ns.On für Nachrichten), damit die
-- Dateien später ohne Umbau ins Gildenaddon wandern können.
local ADDON, GP = ...
-- Rare-Scanner läuft in einem eigenen Unter-Namensraum, damit sich nichts mit GuildPride beißt
GP.Rares = GP.Rares or {}
local ns = GP.Rares
ns.ADDON = ADDON

local defaults = {
    seen = {},      -- [npcId] = { name, map, x, y, t, layer, hp, by, boss, reporters = { [Name] = t } }
    killed = {},    -- [npcId] = Serverzeit des letzten bekannten Todes
    fav = {},       -- [npcId] = true
    spawns = {},    -- [npcId] = { name, elite, boss, pts = { {map, x, y}, … } }  gelernte Fundorte
    opts = { enabled = true, share = true, sound = true, alertAll = true, alertBoss = true, pins = true },
}

local function Fill(db, def)
    for k, v in pairs(def) do
        if db[k] == nil then
            db[k] = type(v) == "table" and Fill({}, v) or v
        elseif type(v) == "table" and type(db[k]) == "table" then
            Fill(db[k], v)
        end
    end
    return db
end

function ns.DB() return GuildPrideDB and GuildPrideDB.rares end
-- Teilen ist Pflicht für alle (wie beim Auktionshaus, kein Schalter mehr)
local FORCED = { share = true }
function ns.Opt(k)
    if FORCED[k] then return true end
    local db = ns.DB(); return db and db.opts[k]
end

-- Geschützte Werte ("secret values") nie vergleichen oder auswerten
function ns.Secret(v) return issecretvalue and issecretvalue(v) or false end

function ns.Print(msg) if GP.Print then GP.Print("Rares: " .. tostring(msg)) else print("GuildPride Rares: " .. tostring(msg)) end end

-- Codes und Trennzeichen aus fremden Texten entfernen
function ns.Clean(s, max) return (tostring(s or ""):gsub("[%c|:~]", "")):sub(1, max or 40) end

-- NPC-ID aus einer Kreatur-GUID ("Creature-0-<server>-<instanz>-<zone>-<npcId>-<spawn>").
-- Die Zone verriet früher den Layer; seit Blizzards Hotfix vom 20.11.2026 nicht mehr.
function ns.ParseGUID(guid)
    if type(guid) ~= "string" or ns.Secret(guid) then return end
    local kind, _, _, _, _, npcId = strsplit("-", guid)
    if kind ~= "Creature" and kind ~= "Vehicle" then return end
    return tonumber(npcId)
end

function ns.Ago(t)
    if not t then return "–" end
    local d = GetServerTime() - t
    if d < 60 then return "jetzt" end
    if d < 3600 then return ("vor %d Min."):format(d / 60) end
    if d < 86400 then return ("vor %d Std."):format(d / 3600) end
    return ("vor %d T."):format(d / 86400)
end

function ns.MapName(id)
    local info = id and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
    return info and info.name or "?"
end

-- Kleiner Ereignis-Verteiler
local handlers = {}
function ns.Listen(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        ns.frame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end
ns.frame = CreateFrame("Frame")
ns.frame:SetScript("OnEvent", function(_, event, ...)
    for _, fn in ipairs(handlers[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then geterrorhandler()(err) end
    end
end)

-- Beim Laden der eigenen gespeicherten Daten
ns.Listen("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    GuildPrideDB = GuildPrideDB or {}
    -- Daten aus dem früheren Test-Addon GuildPrideRares einmal übernehmen
    if not GuildPrideDB.rares and type(GuildPrideRaresDB) == "table" then GuildPrideDB.rares = GuildPrideRaresDB end
    GuildPrideRaresDB = nil
    local db = Fill(GuildPrideDB.rares or {}, defaults)
    GuildPrideDB.rares = db
    -- Alte Sichtungen (älter als 14 Tage) aufräumen
    local now = GetServerTime()
    for id, e in pairs(db.seen) do
        if not e.t or now - e.t > 14 * 86400 then db.seen[id] = nil end
    end
    if ns.OnReady then ns.OnReady() end
end)

-- Eintrag zu einer Sichtung anlegen/aktualisieren; gibt true zurück, wenn sie neu ist
function ns.AddSighting(npcId, name, map, x, y, hp, layer, by, t, elite)
    local db = ns.DB()
    if not db then return end
    t = t or GetServerTime()
    local e = db.seen[npcId]
    local isNew = not e or (t - (e.t or 0)) > ns.FRESH
    if not e then e = { reporters = {} }; db.seen[npcId] = e end
    if isNew then wipe(e.reporters) end
    e.name, e.map, e.x, e.y, e.hp, e.layer, e.by = name, map, x, y, hp, layer, by
    e.t = math.max(e.t or 0, t)
    e.boss = ns.WORLD_BOSSES[npcId] and true or nil
    e.reporters[by] = t
    if elite then e.elite = true end
    ns.LearnSpawn(npcId, name, map, x, y, elite)
    if ns.RefreshUI then ns.RefreshUI() end
    return isNew
end

-- Fundort merken: nahe beieinander liegende Punkte zählen als einer
local MAX_POINTS, NEAR = 25, 0.02
function ns.LearnSpawn(npcId, name, map, x, y, elite)
    local db = ns.DB()
    if not (db and npcId and map and x and y) then return end
    local s = db.spawns[npcId]
    if not s then s = { pts = {} }; db.spawns[npcId] = s end
    s.name = name or s.name
    if elite then s.elite = true end
    s.boss = ns.WORLD_BOSSES[npcId] and true or nil
    for _, p in ipairs(s.pts) do
        if p[1] == map and math.abs(p[2] - x) < NEAR and math.abs(p[3] - y) < NEAR then return end
    end
    if #s.pts >= MAX_POINTS then table.remove(s.pts, 1) end
    s.pts[#s.pts + 1] = { map, math.floor(x * 1000 + 0.5) / 1000, math.floor(y * 1000 + 0.5) / 1000 }
end

-- Startliste entpacken (einmal, beim ersten Bedarf): [npc] = { {map, x, y}, … }
local static
function ns.StaticPoints()
    if static then return static end
    static = {}
    for npc, r in pairs(ns.RARE_SPAWNS or {}) do
        local pts = {}
        for map, packed in pairs(r[4]) do
            for i = 1, #packed - 5, 6 do
                local x, y = tonumber(packed:sub(i, i + 2)), tonumber(packed:sub(i + 3, i + 5))
                if x and y then pts[#pts + 1] = { map, x / 1000, y / 1000 } end
            end
        end
        static[npc] = pts
    end
    return static
end
function ns.StaticInfo(npc) return ns.RARE_SPAWNS and ns.RARE_SPAWNS[npc] end

function ns.Enabled() return ns.Opt("enabled") and true or false end

function ns.Confirmations(e)
    local n, now = 0, GetServerTime()
    for _, t in pairs(e and e.reporters or {}) do if now - t <= ns.FRESH then n = n + 1 end end
    return n
end

function ns.AddKill(npcId, t)
    local db = ns.DB()
    if not db then return end
    t = t or GetServerTime()
    if (db.killed[npcId] or 0) >= t - 30 then return false end
    db.killed[npcId] = t
    local e = db.seen[npcId]
    if e then e.dead = t end
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end
