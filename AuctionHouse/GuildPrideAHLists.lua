-- GuildPride Auktionshaus: Favoriten und Einkaufslisten
-- Gespeichert in GuildPrideDB.ahLists = { fav = { itemID, … }, lists = { { name = "…", items = { itemID, … } }, … } }
-- Favoriten werden zusätzlich in Blizzards eigene Auktionshaus-Favoriten übernommen (wenn erlaubt).
local ADDON, GP = ...
GP.AH = GP.AH or {}
local AH = GP.AH
local L = GP.L or setmetatable({}, { __index = function(_, k) return k end })

local MAX_NAME = 30          -- Zeichen (UTF-8)
local MAX_ID = 999999

local function CleanIDs(t)
    local out, seen = {}, {}
    if type(t) == "table" then
        for _, v in ipairs(t) do
            local id = tonumber(v)
            if id and id >= 1 and id <= MAX_ID and id == math.floor(id) and not seen[id] then
                seen[id] = true; out[#out + 1] = id
            end
        end
    end
    return out
end

-- Gespeicherte Daten holen und dabei reparieren
local function DB()
    if type(GuildPrideDB) ~= "table" then GuildPrideDB = {} end
    local d = GuildPrideDB.ahLists
    if type(d) ~= "table" then d = {}; GuildPrideDB.ahLists = d end
    if type(d.fav) ~= "table" then d.fav = {} end
    if type(d.favQty) ~= "table" then d.favQty = {} end
    if type(d.lists) ~= "table" then d.lists = {} end
    for i = #d.lists, 1, -1 do
        local l = d.lists[i]
        if type(l) ~= "table" or type(l.name) ~= "string" or l.name == "" then table.remove(d.lists, i)
        else
            if type(l.items) ~= "table" then l.items = {} end
            if type(l.qty) ~= "table" then l.qty = {} end
        end
    end
    return d
end

local function Find(t, id)
    for i, v in ipairs(t) do if v == id then return i end end
end

local function SyncBlizzard(id, on)
    local f = C_AuctionHouse and C_AuctionHouse.SetFavoriteItem
    if f then pcall(f, { itemID = id, itemLevel = 0, itemSuffix = 0, battlePetSpeciesID = 0 }, on and true or false) end
end

function AH.IsFavorite(id)
    id = tonumber(id)
    return id ~= nil and Find(DB().fav, id) ~= nil
end

function AH.SetFavorite(id, on)
    id = tonumber(id)
    if not id then return false end
    local fav = DB().fav
    local i = Find(fav, id)
    if on and not i then fav[#fav + 1] = id
    elseif not on and i then table.remove(fav, i) end
    SyncBlizzard(id, on)
    return on and true or false
end

function AH.ToggleFavorite(id)
    return AH.SetFavorite(id, not AH.IsFavorite(id))
end

-- Alle Listen: zuerst die Favoriten (fav = true), dann die eigenen in der angelegten Reihenfolge
function AH.Lists()
    local d = DB()
    d.fav = CleanIDs(d.fav)
    local out = { { fav = true, name = L["Favoriten"], items = d.fav, qty = d.favQty } }
    for _, l in ipairs(d.lists) do out[#out + 1] = l end
    return out
end

local function Utf8Len(s) return #(s:gsub("[\128-\191]", "")) end

-- Name prüfen: nicht leer, höchstens 30 Zeichen, keinen anderen Listennamen doppelt (ohne Groß/klein)
local function CheckName(name, except)
    name = strtrim(tostring(name or ""))
    if name == "" then return nil, L["Bitte einen Namen eingeben."] end
    if Utf8Len(name) > MAX_NAME then return nil, (L["Der Name darf höchstens %d Zeichen haben."]):format(MAX_NAME) end
    if name:lower() == L["Favoriten"]:lower() or name:lower() == L["Temporäre Liste"]:lower() then
        return nil, L["Diese Liste gibt es schon."]
    end
    for _, l in ipairs(DB().lists) do
        if l ~= except and l.name:lower() == name:lower() then return nil, L["Diese Liste gibt es schon."] end
    end
    return name
end

function AH.NewList(name)
    local ok, why = CheckName(name)
    if not ok then return nil, why end
    local l = { name = ok, items = {}, qty = {} }
    local lists = DB().lists
    lists[#lists + 1] = l
    return l
end

function AH.RenameList(list, name)
    if not list or list.fav then return nil, L["Die Favoriten lassen sich nicht umbenennen."] end
    if list.temp then return nil, L["Die temporäre Liste lässt sich nicht umbenennen."] end
    local ok, why = CheckName(name, list)
    if not ok then return nil, why end
    list.name = ok
    return true
end

function AH.DeleteList(list)
    if not list or list.fav then return false end
    local lists = DB().lists
    for i, l in ipairs(lists) do
        if l == list then table.remove(lists, i); return true end
    end
    return false
end

-- Item-IDs aus beliebigem Text: Item-Links, Wowhead-Adressen (item=123) und einzelne Zahlen
function AH.ParseItemIDs(text)
    local ids, seen = {}, {}
    local function Add(v)
        local id = tonumber(v)
        if id and id >= 1 and id <= MAX_ID and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
    end
    if type(text) == "number" then Add(text); return ids end
    if type(text) ~= "string" then return ids end
    for id in text:gmatch("item[:=](%d+)") do Add(id) end
    local rest = text:gsub("|H.-|h.-|h", " "):gsub("item[:=][%-%d:]*", " ")
    -- nur alleinstehende Zahlen: nicht Teil eines Wortes, keine negativen Zahlen
    for id in (" " .. rest .. " "):gmatch("[^%w%-](%d+)%f[^%w]") do Add(id) end
    return ids
end

-- Items in eine Liste eintragen. Gibt zurück: neu eingetragen, schon vorhanden
function AH.AddItems(list, text)
    if not list then return 0, 0 end
    local added, dup = 0, 0
    for _, id in ipairs(AH.ParseItemIDs(text)) do
        if Find(list.items, id) then dup = dup + 1
        else
            list.items[#list.items + 1] = id
            added = added + 1
            if list.fav then SyncBlizzard(id, true) end
        end
    end
    return added, dup
end

function AH.RemoveItem(list, id)
    id = tonumber(id)
    local i = list and id and Find(list.items, id)
    if not i then return false end
    table.remove(list.items, i)
    if list.qty then list.qty[id] = nil end
    if list.fav then SyncBlizzard(id, false) end
    if list.temp and #list.items == 0 then AH.DeleteList(list) end   -- erledigt: verschwindet
    return true
end

---------------------------------------------------------------------
-- Preisalarm: Hinweis, wenn ein Item höchstens zum Wunschpreis im Auktionshaus steht
-- GuildPrideDB.ahAlerts = { [itemID] = Kupfer je Stück }
---------------------------------------------------------------------
local ALERT_GAP = 600            -- dasselbe Item höchstens alle 10 Minuten melden
local alerted = {}

-- Geldbetrag aus Text: „1g 50s 3c“, „75s“, „12c“ oder Gold als Zahl („2,5“ = 2g 50s)
function AH.ParseMoney(text)
    text = strtrim(tostring(text or "")):lower()
    if text == "" then return nil end
    local c, any = 0, false
    for n, u in text:gmatch("(%d+)%s*([gsck])") do
        any = true
        n = tonumber(n)
        if u == "g" then c = c + n * 10000 elseif u == "s" then c = c + n * 100 else c = c + n end
    end
    if not any then
        local g = tonumber((text:gsub(",", ".")))
        if not g then return nil end
        c = math.floor(g * 10000 + 0.5)
    end
    return c > 0 and c or nil
end

local function Alerts()
    if type(GuildPrideDB) ~= "table" then GuildPrideDB = {} end
    if type(GuildPrideDB.ahAlerts) ~= "table" then GuildPrideDB.ahAlerts = {} end
    return GuildPrideDB.ahAlerts
end

function AH.Alert(id) return Alerts()[tonumber(id) or 0] end

function AH.SetAlert(id, copper)
    id, copper = tonumber(id), tonumber(copper)
    if not id then return end
    Alerts()[id] = (copper and copper > 0) and math.floor(copper) or nil
    alerted[id] = nil
end

-- rows = { { itemID, min = Stückpreis }, … }; meldet Treffer im Chat (mit Ton). Gibt die Treffer zurück.
function AH.CheckAlerts(rows)
    local hits, a = {}, Alerts()
    if not next(a) then return hits end
    local now = GetTime()
    for _, r in ipairs(rows or {}) do
        local want = a[r.itemID]
        if want and r.min and r.min <= want and (not alerted[r.itemID] or now - alerted[r.itemID] >= ALERT_GAP) then
            alerted[r.itemID] = now
            hits[#hits + 1] = r
            local name = AH.ItemName(r.itemID) or ("#" .. r.itemID)
            AH.Print((L["|cffffd100Preisalarm:|r %s für %s je Stück (dein Alarm: höchstens %s)"]):format(name, AH.Money(r.min), AH.Money(want)))
            if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
        end
    end
    return hits
end

---------------------------------------------------------------------
-- Teilen: Liste als Text („GP-Liste:Name:2840x12,765“) und wieder einlesen.
-- Eingelesen wird auch das Auctionator-Format (Name^"Item";…;#;;Menge^…) und reine Item-IDs.
---------------------------------------------------------------------
function AH.ExportList(list)
    local parts = {}
    for _, id in ipairs(list and list.items or {}) do
        local q = AH.ItemQty(list, id)
        parts[#parts + 1] = q and (id .. "x" .. q) or tostring(id)
    end
    return "GP-Liste:" .. (list and list.name or ""):gsub("[:\n]", " ") .. ":" .. table.concat(parts, ",")
end

-- Freien Namen finden: „Name“, sonst „Name (2)“, „Name (3)“ …
local function FreeName(name)
    name = strtrim(name or "")
    name = name:match("^" .. ("[%z\1-\127\194-\244][\128-\191]*"):rep(MAX_NAME - 4)) or name
    if name == "" then name = L["Import"] end
    if CheckName(name) then return name end
    for i = 2, 99 do
        local n = ("%s (%d)"):format(name, i)
        if CheckName(n) then return n end
    end
end

local function ItemIDByName(name)
    local _, link = AH.ItemInfo(name)
    return type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
end

-- Gibt die neue Liste, die Zahl der eingetragenen und der nicht erkannten Items zurück (nil bei leerem Text)
function AH.ImportList(text)
    text = strtrim(tostring(text or ""))
    if text == "" then return nil end
    local name, entries, skipped = nil, {}, 0
    local gpName, body = text:match("^GP%-Liste:([^:]*):(.*)$")
    if gpName then
        name = gpName
        for part in body:gmatch("[^,%s]+") do
            local id, q = part:match("^(%d+)x(%d+)$")
            id = tonumber(id or part:match("^(%d+)$"))
            if id then entries[#entries + 1] = { id, tonumber(q) } end
        end
    elseif text:find("^", 1, true) then
        local first = true
        for term in (text .. "^"):gmatch("([^%^]*)%^") do
            if first then name, first = term, false
            elseif term ~= "" then
                local iname = term:match('^"([^"]+)"') or term:match("^([^;]+)")
                local id = iname and ItemIDByName(iname)
                if id then entries[#entries + 1] = { id, tonumber(term:match(";#;;(%d+)")) }
                else skipped = skipped + 1 end
            end
        end
    else
        for _, id in ipairs(AH.ParseItemIDs(text)) do entries[#entries + 1] = { id } end
    end
    if #entries == 0 then return nil end
    local list = AH.NewList(FreeName(name))
    if not list then return nil end
    for _, e in ipairs(entries) do
        AH.AddItems(list, e[1])
        if e[2] then AH.SetItemQty(list, e[1], e[2]) end
    end
    return list, #list.items, skipped
end

---------------------------------------------------------------------
-- Zurückgekommene Auktionen: was dieser Charakter eingestellt hat (14 Tage gemerkt).
-- Liegt so ein Item wieder in den Taschen, kam es meist unverkauft per Post zurück.
-- GuildPrideDB.ahPosted = { ["Name-Realm"] = { [Item-Schlüssel] = Zeit } }
---------------------------------------------------------------------
local POSTED_KEEP = 14 * 86400
local function Posted()
    if type(GuildPrideDB) ~= "table" then GuildPrideDB = {} end
    local all = GuildPrideDB.ahPosted
    if type(all) ~= "table" then all = {}; GuildPrideDB.ahPosted = all end
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or "?"
    local me = (UnitName("player") or "?") .. "-" .. realm
    if type(all[me]) ~= "table" then all[me] = {} end
    return all[me]
end

function AH.MarkPosted(key)
    if key then Posted()[key] = GetServerTime() end
end

function AH.WasPosted(key, now)
    local t = key and Posted()[key]
    if not t then return false end
    if (now or GetServerTime()) - t > POSTED_KEEP then Posted()[key] = nil; return false end
    return true
end

-- Wie viele hast du schon (Taschen und Bank)?
function AH.ItemCount(id)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    if not (f and id) then return 0 end
    local ok, n = pcall(f, id, true)
    return ok and tonumber(n) or 0
end

-- Noch zu kaufen: gewünschte Menge minus Bestand (nil = keine Menge angegeben)
function AH.Remaining(list, id)
    local want = AH.ItemQty(list, id)
    if not want then return nil end
    return math.max(0, want - AH.ItemCount(id))
end

-- Was die Liste ungefähr noch kostet (nur Items mit Menge): Summe, Zahl der Items ohne bekannten Preis
function AH.ListCost(list)
    local total, unknown = 0, 0
    for _, id in ipairs(list and list.items or {}) do
        local left = AH.Remaining(list, id)
        if left and left > 0 then
            local p = AH.PriceFor(AH.Key(id))
            if p then total = total + p * left else unknown = unknown + 1 end
        end
    end
    return total, unknown
end

-- Temporäre Einkaufsliste (genau eine, gleich unter den Favoriten). create = true legt sie an.
-- Käufe im GuildPride-Auktionshaus haken sie ab; ist alles gekauft, verschwindet sie.
function AH.TempList(create)
    local lists = DB().lists
    for _, l in ipairs(lists) do if l.temp then return l end end
    if not create then return nil end
    local l = { name = L["Temporäre Liste"], items = {}, qty = {}, temp = true }
    table.insert(lists, 1, l)
    return l
end

-- Gekauft: von der temporären Liste abziehen. Gibt zurück: etwas geändert, Liste fertig (und weg)
function AH.Bought(id, qty)
    id = tonumber(id)
    local t = AH.TempList()
    if not (t and id and Find(t.items, id)) then return false, false end
    local left = t.qty and t.qty[id]
    if left then
        left = left - math.max(1, math.floor(tonumber(qty) or 1))
        if left > 0 then t.qty[id] = left; return true, false end
    end
    AH.RemoveItem(t, id)
    return true, AH.TempList() == nil
end

-- Gewünschte Menge eines Items in der Liste (nil = keine Menge angegeben)
function AH.ItemQty(list, id)
    return list and list.qty and list.qty[tonumber(id)]
end

-- Menge setzen; 0 oder leer löscht die Menge. Nur für Items, die in der Liste stehen
function AH.SetItemQty(list, id, n)
    id = tonumber(id)
    if not (list and id and Find(list.items, id)) then return false end
    list.qty = list.qty or {}
    n = tonumber(n)
    list.qty[id] = (n and n >= 1) and math.min(math.floor(n), 999999) or nil
    return true
end

-- Zutaten eines Rezepts eintragen: reagents = { { itemID, Menge je Herstellung }, … }, crafts = wie oft.
-- Mengen werden zu schon eingetragenen addiert (mehrere Rezepte in einer Liste). Gibt die Zahl der Zutaten zurück.
function AH.AddReagents(list, reagents, crafts)
    if not list or type(reagents) ~= "table" then return 0 end
    crafts = math.max(1, math.min(math.floor(tonumber(crafts) or 1), 9999))
    list.qty = list.qty or {}
    local n = 0
    for _, r in ipairs(reagents) do
        local id, per = tonumber(r[1]), tonumber(r[2]) or 1
        if id and id >= 1 and id <= MAX_ID then
            if not Find(list.items, id) then
                list.items[#list.items + 1] = id
                if list.fav then SyncBlizzard(id, true) end
            end
            list.qty[id] = math.min((list.qty[id] or 0) + per * crafts, 999999)
            n = n + 1
        end
    end
    return n
end
