-- GuildPride Auktionshaus: neues Auktionshaus (C_AuctionHouse, wie Retail).
-- WoW Forever nutzt dieses. GuildPride liest still mit, was Blizzards
-- Auktionshaus oder Auctionator gerade anzeigt, und teilt die Preise.
-- Eigene Auktionen zählen nie als Marktpreis.
local ADDON, GP = ...
local AH = GP.AH

local SHARE_MAX = 200           -- größere Listen gelten als Komplett-Scan: nicht rundsenden
local SCAN_GAP = 15 * 60        -- Blizzard erlaubt den Komplett-Scan nur alle 15 Minuten
local CHUNK = 2000              -- Komplett-Scan stückweise lesen, damit das Spiel nicht ruckelt
local BIG_READ_GAP = 30         -- Auctionators Komplett-Scan höchstens alle 30 s lesen

-- Zuletzt gesehener fremder Mindestpreis je Item (für den Verkaufsvorschlag)
AH.lastSeen = {}

-- Blizzard-Sortierung: billigste zuerst
local function Sorts()
    local o = Enum and Enum.AuctionHouseSortOrder
    if not o then return {} end
    return { { sortOrder = o.Price, reverseSort = false }, { sortOrder = o.Name, reverseSort = false } }
end

local function Reading()
    if not AH.IsModern() then return false end
    if AH.AuctionatorLoaded() and not AH.Opt("ahReadAuctionator") then return false end
    return true
end

local function Add(res, key, unit, qty)
    if not key or not unit or unit < 1 then return end
    local r = res[key]
    if not r then res[key] = { min = unit, qty = qty or 0 }; return end
    if unit < r.min then r.min = unit end
    r.qty = r.qty + (qty or 0)
end

local function RecordAll(res, share)
    local now, keys = GetServerTime(), {}
    for key, r in pairs(res) do
        AH.RecordOwn(key, r.min, r.qty, now)
        AH.lastSeen[key] = r.min
        keys[#keys + 1] = key
    end
    if share and #keys > 0 and #keys <= SHARE_MAX then AH.Share(keys) end
end

---------------------------------------------------------------------
-- Übersicht (Suchergebnisse): ein Eintrag je Item mit Mindestpreis
---------------------------------------------------------------------
local function ReadBrowse(list)
    local res = {}
    for _, b in ipairs(list or {}) do
        local k = b.itemKey
        if k and k.itemID and not b.containsOwnerItem and (k.battlePetSpeciesID or 0) == 0 then
            Add(res, AH.Key(k.itemID, k.itemSuffix), b.minPrice, b.totalQuantity)
        end
    end
    RecordAll(res, true)
end

AH.Listen("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
    if Reading() then ReadBrowse(C_AuctionHouse.GetBrowseResults()) end
end)
AH.Listen("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(added)
    if Reading() then ReadBrowse(added) end
end)

---------------------------------------------------------------------
-- Waren (stapelbar, z. B. Stoff, Kräuter): Stückpreise, aufsteigend
---------------------------------------------------------------------
AH.Listen("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
    if not itemID or not Reading() then return end
    local res, key = {}, AH.Key(itemID)
    for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0 do
        local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
        local others = r and (r.quantity or 0) - (r.numOwnerItems or 0) or 0
        if others > 0 then Add(res, key, r.unitPrice, others) end
    end
    RecordAll(res, true)
end)

---------------------------------------------------------------------
-- Einzelne Items (Ausrüstung): Sofortkaufpreis je Stück
---------------------------------------------------------------------
AH.Listen("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
    if type(itemKey) ~= "table" or not Reading() then return end
    local res = {}
    for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0 do
        local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
        if r and not r.containsOwnerItem and r.buyoutAmount and r.buyoutAmount > 0 then
            local q = (r.quantity and r.quantity > 0) and r.quantity or 1
            local key = AH.KeyFromLink(r.itemLink) or AH.Key(itemKey.itemID, itemKey.itemSuffix)
            Add(res, key, math.floor(r.buyoutAmount / q), q)
        end
    end
    RecordAll(res, true)
end)

---------------------------------------------------------------------
-- Komplett-Scan (ReplicateItems): nur speichern, nicht rundsenden –
-- andere bekommen die Preise auf Nachfrage
---------------------------------------------------------------------
local scanning, reading, lastScan, lastBigRead, scanRead = false, false, nil, -BIG_READ_GAP, 0

local function ReadReplicate(report)
    local n = C_AuctionHouse.GetNumReplicateItems() or 0
    local me, res, i = UnitName("player"), {}, 1
    reading = report
    local function Step()
        if not AH.IsModern() then reading = false; return end
        local last = math.min(n, i + CHUNK - 1)
        for j = i, last do
            local name, _, count, _, _, _, _, _, _, buyout, _, _, _, owner, _, _, _, hasAll = C_AuctionHouse.GetReplicateItemInfo(j)
            -- Zeilen ohne vollständige Daten auslassen (Suffix wäre unsicher)
            if name and hasAll ~= false and buyout and buyout > 0 and owner ~= me then
                count = (count and count > 0) and count or 1
                Add(res, AH.KeyFromLink(C_AuctionHouse.GetReplicateItemLink(j)), math.floor(buyout / count), count)
            end
        end
        i = last + 1
        if i <= n then C_Timer.After(0, Step); return end
        RecordAll(res, false)
        if report then reading, scanRead = false, n end
        if report then
            AH.Print((GP.L and GP.L["Auktionshaus: Komplett-Scan fertig, %d Angebote gelesen."] or "%d"):format(n))
        end
    end
    Step()
end

local legacyFullScan = AH.FullScan
function AH.FullScan()
    if not AH.IsModern() then return legacyFullScan() end
    if lastScan and GetTime() - lastScan < SCAN_GAP then return false end
    lastScan, scanning = GetTime(), true
    C_AuctionHouse.ReplicateItems()
    return true
end

AH.Listen("REPLICATE_ITEM_LIST_UPDATE", function()
    if not AH.IsModern() then return end
    if scanning then
        scanning = false
        ReadReplicate(true)
        return
    end
    -- Auctionators Komplett-Scan still mitlesen (gedrosselt)
    if AH.AuctionatorLoaded() and AH.Opt("ahReadAuctionator") and GetTime() - lastBigRead >= BIG_READ_GAP then
        lastBigRead = GetTime()
        ReadReplicate(false)
    end
end)

AH.Listen("AUCTION_HOUSE_CLOSED", function() scanning = false end)

-- Stand des Komplett-Scans für die Anzeige im Scanner
function AH.ScanStatus()
    local wait = lastScan and math.max(0, math.ceil(SCAN_GAP - (GetTime() - lastScan))) or 0
    return { running = scanning or reading, wait = wait, read = scanRead }
end

---------------------------------------------------------------------
-- Für den eigenen Reiter: Suchen, Liste, Verkaufen
---------------------------------------------------------------------
function AH.ModernBrowse(text)
    if not AH.IsModern() then return false end
    C_AuctionHouse.SendBrowseQuery({ searchString = text or "", sorts = Sorts(), filters = {}, itemClassFilters = {} })
    return true
end

-- Aktuelle Übersicht als Zeilen, billigste zuerst
function AH.BrowseRows()
    local rows = {}
    if not AH.IsModern() then return rows end
    for _, b in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
        local k = b.itemKey
        if k and k.itemID then
            local info = C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.GetItemKeyInfo(k)
            rows[#rows + 1] = {
                result = b, itemKey = k, key = AH.Key(k.itemID, k.itemSuffix),
                min = b.minPrice, qty = b.totalQuantity or 0, mine = b.containsOwnerItem and true or false,
                name = info and info.itemName or AH.ItemName(k.itemID),
                icon = info and info.iconFileID, quality = info and info.quality,
            }
        end
    end
    table.sort(rows, function(a, b)
        if (a.min or math.huge) ~= (b.min or math.huge) then return (a.min or math.huge) < (b.min or math.huge) end
        return tostring(a.name) < tostring(b.name)
    end)
    return rows
end

local function CommodityStatus()
    local st = Enum and Enum.ItemCommodityStatus
    return (st and type(st.Commodity) == "number") and st.Commodity or 2
end

-- Alle handelbaren Items aus den Taschen, je Item zusammengefasst (Menge über alle Stapel).
-- loc zeigt auf den ersten Stapel; gebundene, graue und Quest-Items fehlen.
function AH.BagItems()
    local out, byKey = {}, {}
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then return out end
    local last = tonumber(NUM_TOTAL_EQUIPPED_BAG_SLOTS) or tonumber(NUM_BAG_SLOTS) or 4
    for bag = 0, last do
        for slot = 1, tonumber(C_Container.GetContainerNumSlots(bag)) or 0 do
            local it = C_Container.GetContainerItemInfo(bag, slot)
            local link = type(it) == "table" and it.hyperlink
            local key = type(link) == "string" and not it.isBound and AH.KeyFromLink(link)
            if key and (byKey[key] or AH.Tradeable(link)) then
                local e = byKey[key]
                if not e then
                    e = { key = key, link = link, itemID = it.itemID, count = 0, icon = it.iconFileID,
                          name = AH.ItemName(link) or link,
                          loc = ItemLocation and ItemLocation.CreateFromBagAndSlot and ItemLocation:CreateFromBagAndSlot(bag, slot) }
                    byKey[key] = e
                    out[#out + 1] = e
                end
                e.count = e.count + (tonumber(it.stackCount) or 1)
            end
        end
    end
    table.sort(out, function(a, b) return tostring(a.name) < tostring(b.name) end)
    return out
end

-- Item aus den Taschen (ItemLocation) zum Verkaufen vorbereiten
function AH.SellInfo(loc)
    if not loc or not AH.IsModern() or not C_Item or not C_Item.GetItemLink then return nil end
    if C_Item.DoesItemExist and not C_Item.DoesItemExist(loc) then return nil end
    local link, id = C_Item.GetItemLink(loc), C_Item.GetItemID(loc)
    if not id then return nil end
    local commodity = C_AuctionHouse.GetItemCommodityStatus(loc) == CommodityStatus()
    local max = 1
    if commodity and C_AuctionHouse.GetAvailablePostCount then max = C_AuctionHouse.GetAvailablePostCount(loc) or 1 end
    return {
        loc = loc, link = link, itemID = id, key = AH.KeyFromLink(link) or AH.Key(id),
        commodity = commodity, max = math.max(1, max),
        itemKey = C_AuctionHouse.GetItemKeyFromItem and C_AuctionHouse.GetItemKeyFromItem(loc),
    }
end

-- Aktuelle Angebote für das Verkaufs-Item anfragen (Ergebnis landet in AH.lastSeen)
function AH.RequestPrice(info)
    if not info or not info.itemKey or not AH.IsModern() then return false end
    C_AuctionHouse.SendSearchQuery(info.itemKey, Sorts(), true)
    return true
end

function AH.Deposit(info, qty, duration)
    if not info or not AH.IsModern() then return nil end
    local ok, dep
    if info.commodity and C_AuctionHouse.CalculateCommodityDeposit then
        ok, dep = pcall(C_AuctionHouse.CalculateCommodityDeposit, info.itemID, duration, qty)
    elseif C_AuctionHouse.CalculateItemDeposit then
        ok, dep = pcall(C_AuctionHouse.CalculateItemDeposit, info.loc, duration, 1)
    end
    return ok and type(dep) == "number" and dep or nil
end

-- Einstellen (nur aus einem Klick aufrufen). Ware: Stückpreis × Menge.
-- Ausrüstung immer einzeln – so kann der Preis nie versehentlich für einen Stapel gelten.
function AH.PostModern(info, unit, qty, duration)
    if not info or not AH.IsModern() then return false end
    unit = math.floor(tonumber(unit) or 0)
    if unit < 1 then return false end
    if info.commodity then
        qty = math.floor(tonumber(qty) or 0)
        if qty < 1 or qty > info.max then return false end
        C_AuctionHouse.PostCommodity(info.loc, duration, qty, unit)
    else
        C_AuctionHouse.PostItem(info.loc, duration, 1, nil, unit)
    end
    return true
end

-- Ist das Auktionshaus (alt oder neu) gerade offen?
function AH.IsOpen()
    if AuctionHouseFrame and AuctionHouseFrame.IsShown and AuctionHouseFrame:IsShown() then return true end
    return AuctionFrame and AuctionFrame.IsShown and AuctionFrame:IsShown() and true or false
end
