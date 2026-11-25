-- GuildPride: gespeicherte Daten klein halten
-- Rezepte aus den Berufsfenstern als kurzer Text ("2|2589:3,2840:1" = macht 2, braucht 3 und 1),
-- stille Chat-Kanäle vergessen, in Sicherungen weglassen, was sich von selbst neu lernt.
local ADDON, ns = ...

local C = {}
ns.Cleanup = C

-- Das lernt GuildPride von selbst neu: gehört nicht in die Datensicherung
C.RELEARN = { ahCraft = true, craftReagents = true, craftCatalog = true, craftAll = true, clubCache = true }

local function Whole(n) return type(n) == "number" and n >= 1 and n == math.floor(n) end

-- { made, r = { { itemID, Menge }, … } } → Text; nil, wenn etwas nicht passt (dann bleibt die alte Form)
function C.PackRecipe(e)
    if type(e) ~= "table" or type(e.r) ~= "table" or #e.r == 0 or not Whole(e.made or 1) then return nil end
    local out = {}
    for i, p in ipairs(e.r) do
        if type(p) ~= "table" or not Whole(p[1]) or not Whole(p[2]) then return nil end
        out[i] = ("%d:%d"):format(p[1], p[2])
    end
    return (e.made or 1) .. "|" .. table.concat(out, ",")
end

-- Text oder alte Tabelle → Anzahl, { { itemID, Menge }, … }; nil bei Unsinn
function C.Recipe(e)
    if type(e) == "table" then
        if type(e.r) ~= "table" then return nil end
        return e.made or 1, e.r
    end
    if type(e) ~= "string" then return nil end
    local made, list = e:match("^(%d+)|(.+)$")
    if not made then return nil end
    local r = {}
    for id, n in list:gmatch("(%d+):(%d+)") do r[#r + 1] = { tonumber(id), tonumber(n) } end
    if #r == 0 then return nil end
    return tonumber(made), r
end

function C.PackRecipes()
    local db, n = type(GuildPrideDB) == "table" and GuildPrideDB.ahCraft, 0
    for id, e in pairs(type(db) == "table" and db or {}) do
        local text = type(e) == "table" and C.PackRecipe(e)
        if text then db[id] = text; n = n + 1 end   -- vorhandenen Schlüssel ändern ist beim Durchgehen erlaubt
    end
    return n
end

-- Chat-Zwischenspeicher: Kanäle, in denen 60 Tage nichts war, fallen weg; höchstens die 12 neuesten bleiben
local CHAT_DAYS, CHAT_MAX = 60, 12
function C.TrimChat(cache, now)
    if type(cache) ~= "table" then return 0 end
    local list, n = {}, 0
    for key, entries in pairs(cache) do
        local newest = 0
        for _, e in ipairs(type(entries) == "table" and entries or {}) do
            if type(e) == "table" and type(e.t) == "number" and e.t > newest then newest = e.t end
        end
        list[#list + 1] = { key = key, t = newest }
    end
    table.sort(list, function(a, b) return a.t > b.t end)
    for i, e in ipairs(list) do
        if i > CHAT_MAX or e.t < now - CHAT_DAYS * 86400 then cache[e.key] = nil; n = n + 1 end
    end
    return n
end

-- Vorhandene Sicherungen schlanker machen
function C.TrimBackups()
    local n = 0
    for _, s in ipairs(type(GuildPrideBackupDB) == "table" and type(GuildPrideBackupDB.snaps) == "table" and GuildPrideBackupDB.snaps or {}) do
        for key in pairs(C.RELEARN) do
            if type(s.data) == "table" and s.data[key] ~= nil then s.data[key] = nil; n = n + 1 end
        end
    end
    return n
end

local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    -- in Ruhe nach dem Einloggen, eins nach dem anderen
    C_Timer.After(25, function() ns.Try(C.PackRecipes) end)
    C_Timer.After(27, function()
        if type(GuildPrideDB) == "table" then ns.Try(C.TrimChat, GuildPrideDB.clubCache, GetServerTime()) end
        ns.Try(C.TrimBackups)
    end)
end)
