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
local scanning, lastScan, lastBigRead = false, nil, -BIG_READ_GAP

local function ReadReplicate(report)
    local n = C_AuctionHouse.GetNumReplicateItems() or 0
    local me, res, i = UnitName("player"), {}, 1
    local function Step()
        if not AH.IsModern() then return end
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
        if report then
            AH.Print((GP.L and GP.L["Auktionshaus: Komplett-Scan fertig, %d Angebote gelesen."] or "%d"):format(n))
        end
    end
    Step()
end

local legacyFullScan = AH.FullScan
function AH.FullScan()
    if not AH.IsModern() then return legacyFullScan() end
    if AH.AuctionatorLoaded() then return false end
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

-- Ist das Auktionshaus (alt oder neu) gerade offen?
function AH.IsOpen()
    if AuctionHouseFrame and AuctionHouseFrame.IsShown and AuctionHouseFrame:IsShown() then return true end
    return AuctionFrame and AuctionFrame.IsShown and AuctionFrame:IsShown() and true or false
end
