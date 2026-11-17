-- GuildPride: Schlüsselsteine und M+-Wertung der Gilde (nur Retail)
-- Jeder mit GuildPride meldet seinen Schlüssel und seine Wertung ("KEY").
-- In WoW Forever gibt es kein Mythisch+: dort bleibt das Modul aus, und
-- Mitgliederliste und Gruppensuche zeigen keine Schlüssel.
local ADDON, ns = ...
if not ns.IS_RETAIL then return end
local L = ns.L
local SEP = ns.SEP

local keys       -- GuildPrideDB.keys: [Name-Realm] = { map, level, rating, t }
local lastMine   -- zuletzt gesendeter eigener Stand

local function Store()
    GuildPrideDB.keys = GuildPrideDB.keys or {}
    return GuildPrideDB.keys
end

-- Schlüssel aus der Vorwoche gelten nicht mehr (Wochenreset)
local function Current(e)
    return e and (e.t or 0) >= ns.WeekStart()
end

local function MapName(map)
    if not map or map == 0 or not (C_ChallengeMode and C_ChallengeMode.GetMapUIInfo) then return nil end
    local name = C_ChallengeMode.GetMapUIInfo(map)
    return type(name) == "string" and name or nil
end

local function Mine()
    local map = C_MythicPlus.GetOwnedKeystoneChallengeMapID and C_MythicPlus.GetOwnedKeystoneChallengeMapID() or 0
    local level = C_MythicPlus.GetOwnedKeystoneLevel and C_MythicPlus.GetOwnedKeystoneLevel() or 0
    local rating = C_ChallengeMode.GetOverallDungeonScore and C_ChallengeMode.GetOverallDungeonScore() or 0
    return tonumber(map) or 0, tonumber(level) or 0, math.floor(tonumber(rating) or 0)
end

local function SendMine(target)
    local map, level, rating = Mine()
    keys[ns.Me()] = { map = map, level = level, rating = rating, t = GetServerTime() }
    ns.Queue("KEY", target, map, level, rating)
    if not target then lastMine = map .. ":" .. level .. ":" .. rating end
end

ns.On("KEY", function(payload, sender)
    if sender == ns.Me() or not keys then return end
    local map, level, rating = strsplit(SEP, payload)
    -- Fremde Zahlen begrenzen (keine Riesenwerte oder Kommazahlen)
    keys[sender] = { map = ns.Num(map, 0, 99999) or 0, level = ns.Num(level, 0, 999) or 0,
                     rating = ns.Num(rating, 0, 99999) or 0, t = GetServerTime() }
    if ns.RefreshUI then ns.RefreshUI() end
end)

-- REQ: Login-Abgleich · KEYQ: jemand hat die Schlüssel-Ansicht geöffnet
for _, k in ipairs({ "REQ", "KEYQ" }) do
    ns.On(k, function(_, sender)
        if keys and sender ~= ns.Me() then SendMine(sender) end
    end)
end

---------------------------------------------------------------------
-- Für Mitgliederliste und Gruppensuche
---------------------------------------------------------------------
-- Kurztext für die Mitgliederzeile, z. B. "+12 Nebel von Tirna Scithe"
function ns.KeyText(full)
    local e = keys and keys[full]
    if not Current(e) or (e.level or 0) == 0 then return nil end
    return ("|cffa335ee+%d %s|r"):format(e.level, MapName(e.map) or "")
end

function ns.KeyTooltip(tt, full)
    local e = keys and keys[full]
    if not Current(e) then return end
    if (e.level or 0) > 0 then
        tt:AddLine((L["Schlüssel: +%d %s"]):format(e.level, MapName(e.map) or ""), 0.64, 0.21, 0.93)
    end
    if (e.rating or 0) > 0 then tt:AddLine((L["M+-Wertung: %d"]):format(e.rating), 1, 0.82, 0) end
end

-- Eigener Schlüssel für die Gruppensuche: map, level, Name (nil ohne Schlüssel)
function ns.MyKey()
    local map, level = Mine()
    if map == 0 or level == 0 then return nil end
    return map, level, MapName(map)
end
ns.KeyMapName = MapName

-- Alle bekannten Schlüssel dieser Woche, höchste Stufe zuerst
function ns.GuildKeys()
    local list = {}
    if not keys then return list end
    for name, e in pairs(keys) do
        if Current(e) then
            list[#list + 1] = { name = name, level = e.level or 0, rating = e.rating or 0,
                                map = MapName(e.map), t = e.t }
        end
    end
    table.sort(list, function(a, b)
        if a.level ~= b.level then return a.level > b.level end
        if a.rating ~= b.rating then return a.rating > b.rating end
        return a.name < b.name
    end)
    return list
end

-- Ansicht geöffnet: Stände der anderen anfragen (höchstens einmal pro Minute)
local lastAsk = 0
function ns.AskKeys()
    local now = GetServerTime()
    if not keys or now - lastAsk < 60 then return end
    lastAsk = now
    SendMine()
    ns.Queue("KEYQ", nil, "1")
end

---------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------
local pending
local function Changed()
    if not keys or pending then return end
    pending = C_Timer.NewTimer(5, function()
        pending = nil
        local map, level, rating = Mine()
        if map .. ":" .. level .. ":" .. rating ~= lastMine and IsInGuild() then SendMine() end
    end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "BAG_UPDATE_DELAYED", "CHALLENGE_MODE_COMPLETED", "CHALLENGE_MODE_MAPS_UPDATE" }) do
    pcall(f.RegisterEvent, f, e)
end
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        keys = Store()
        -- Einträge aus früheren Wochen entfernen
        for name, e in pairs(keys) do
            if not Current(e) then keys[name] = nil end
        end
        if C_MythicPlus.RequestMapInfo then C_MythicPlus.RequestMapInfo() end
        return
    end
    Changed()
end)
