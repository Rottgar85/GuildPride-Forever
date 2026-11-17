-- GuildPride Rares: Rares und Weltbosse finden
-- 1. Minikarten-Symbole (Vignetten), falls WoW Forever sie für Rares zeigt
-- 2. Ziel, Maus-über und Namensplaketten: Einstufung "rare", "rareelite", "worldboss"
-- Keine Zielwechsel per Code, kein Abfragen geschützter Kampfwerte.
local ADDON, GP = ...
-- Rare-Scanner läuft in einem eigenen Unter-Namensraum, damit sich nichts mit GuildPride beißt
GP.Rares = GP.Rares or {}
local ns = GP.Rares

local REPORT_EVERY = 60   -- s: denselben Gegner höchstens so oft melden
local lastReport = {}     -- [npcId] = GetTime()
ns.scanStats = { vignettes = 0, units = 0, lastVignette = nil }

local function PlayerPos()
    local map = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not map or ns.Secret(map) then return end
    local pos = C_Map.GetPlayerMapPosition(map, "player")
    if not pos or ns.Secret(pos) then return end
    local x, y = pos:GetXY()
    if not x or ns.Secret(x) or ns.Secret(y) or (x == 0 and y == 0) then return end
    return map, x, y
end

-- Gefunden: lokal eintragen, Alarm, an alle melden
local function Found(npcId, name, map, x, y, hp, layer, source, elite)
    if not (npcId and name and map and x) or not ns.Enabled() then return end
    local me = UnitName("player")
    local isNew = ns.AddSighting(npcId, name, map, x, y, hp, layer, me, nil, elite)
    if isNew and ns.LocalAlert then ns.LocalAlert(npcId, source) end
    local now = GetTime()
    if lastReport[npcId] and now - lastReport[npcId] < REPORT_EVERY then return end
    lastReport[npcId] = now
    ns.Send("S", npcId, ns.Clean(name, 40), map, math.floor(x * 1000 + 0.5), math.floor(y * 1000 + 0.5),
            hp or "", layer or "", GetServerTime(), elite and 1 or "")
end

---------------------------------------------------------------------
-- Einheiten (Ziel, Maus-über, Namensplaketten)
---------------------------------------------------------------------
local RARE = { rare = true, rareelite = true, worldboss = true }

local function CheckUnit(unit, source)
    if not ns.Enabled() then return end
    if not UnitExists(unit) or UnitIsPlayer(unit) then return end
    local guid = UnitGUID(unit)
    local npcId, layer = ns.ParseGUID(guid)
    if not npcId then return end
    if layer then ns.myLayer = layer end
    local class = UnitClassification(unit)
    if ns.Secret(class) then return end
    if not (RARE[class] or ns.WORLD_BOSSES[npcId] or ns.StaticInfo(npcId)) then return end
    local name = UnitName(unit)
    if not name or ns.Secret(name) then return end
    ns.scanStats.units = ns.scanStats.units + 1
    -- Tot? Dann als getötet melden
    local dead = UnitIsDead(unit)
    if not ns.Secret(dead) and dead then
        if ns.DB().seen[npcId] and ns.AddKill(npcId) then ns.Send("K", npcId, "", layer or "", GetServerTime()) end
        return
    end
    -- Leben in Prozent nur, wenn der Wert nicht geschützt ist
    local hp
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    if not ns.Secret(cur) and not ns.Secret(max) and max and max > 0 then hp = math.floor(cur / max * 100 + 0.5) end
    local map, x, y = PlayerPos()   -- Gegner ist in Reichweite: eigene Position genügt
    Found(npcId, name, map, x, y, hp, layer, source, class == "rareelite" or class == "worldboss" or (ns.StaticInfo(npcId) and ns.StaticInfo(npcId)[2] == 1))
end

ns.Listen("PLAYER_TARGET_CHANGED", function() CheckUnit("target", "Ziel") end)
ns.Listen("UPDATE_MOUSEOVER_UNIT", function() CheckUnit("mouseover", "Maus") end)
ns.Listen("NAME_PLATE_UNIT_ADDED", function(unit) CheckUnit(unit, "Namensplakette") end)
-- Ziel stirbt: Tod sofort melden
ns.Listen("UNIT_FLAGS", function(unit) if unit == "target" then CheckUnit("target", "Ziel") end end)

---------------------------------------------------------------------
-- Vignetten (Minikarten-Symbole)
---------------------------------------------------------------------
local V = C_VignetteInfo
local function ScanVignettes()
    if not (V and V.GetVignettes and V.GetVignetteInfo) then return end
    local map = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not map or ns.Secret(map) then return end
    for _, vguid in ipairs(V.GetVignettes() or {}) do
        local info = V.GetVignetteInfo(vguid)
        if info and not ns.Secret(info.objectGUID) then
            local npcId, layer = ns.ParseGUID(info.objectGUID)
            ns.scanStats.vignettes = ns.scanStats.vignettes + 1
            ns.scanStats.lastVignette = tostring(info.name) .. " (" .. tostring(info.atlasName) .. ")"
            if npcId and info.name and not ns.Secret(info.name) then
                if layer then ns.myLayer = layer end
                if info.isDead then
                    if ns.DB().seen[npcId] and ns.AddKill(npcId) then ns.Send("K", npcId, map, layer or "", GetServerTime()) end
                else
                    local pos = V.GetVignettePosition and V.GetVignettePosition(vguid, map)
                    local x, y
                    if pos and not ns.Secret(pos) then x, y = pos:GetXY() end
                    if not x then map, x, y = PlayerPos() end
                    local hp = V.GetHealthPercent and V.GetHealthPercent(vguid)
                    if ns.Secret(hp) then hp = nil end
                    Found(npcId, info.name, map, x, y, hp and math.floor(hp * (hp <= 1 and 100 or 1)), layer, "Minikarte")
                end
            end
        end
    end
end
ns.ScanVignettes = ScanVignettes

local pending = false
local function Soon()
    if pending then return end
    pending = true
    C_Timer.After(0.5, function() pending = false; pcall(ScanVignettes) end)
end
ns.Listen("VIGNETTES_UPDATED", Soon)
ns.Listen("VIGNETTE_MINIMAP_UPDATED", Soon)

ns.Listen("PLAYER_ENTERING_WORLD", function() C_Timer.After(5, Soon) end)
