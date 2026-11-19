-- GuildPride Auktionshaus: neues Auktionshaus (C_AuctionHouse, wie Retail).
-- WoW Forever nutzt dieses. GuildPride liest still mit, was Blizzards
-- Auktionshaus oder Auctionator gerade anzeigt, und teilt die Preise.
-- Eigene Auktionen zählen nie als Marktpreis.
local ADDON, GP = ...
local AH = GP.AH

local SHARE_MAX = 200           -- größere Listen gelten als Komplett-Scan: nicht rundsenden
local SCAN_GAP = 15 * 60        -- Blizzard erlaubt den Komplett-Scan nur alle 15 Minuten
local CHUNK = 400               -- Komplett-Scan stückweise lesen (je Bild), damit das Spiel nicht ruckelt
local BIG_READ_GAP = 30         -- Auctionators Komplett-Scan höchstens alle 30 s lesen
local FOREIGN_READS = 2         -- einen fremden Komplett-Scan höchstens so oft lesen

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

-- Preisalarm (GuildPrideAHLists.lua): bei jeder Suche prüfen, egal wer sucht (auch Blizzard/Auctionator)
local function AlertRows(list)
    local rows = {}
    for _, b in ipairs(list or {}) do
        local k = b.itemKey
        if k and k.itemID and b.minPrice and not b.containsOwnerItem then rows[#rows + 1] = { itemID = k.itemID, min = b.minPrice } end
    end
    return rows
end
AH.Listen("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
    if AH.CheckAlerts and AH.IsModern() then AH.CheckAlerts(AlertRows(C_AuctionHouse.GetBrowseResults())) end
end)
AH.Listen("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(added)
    if AH.CheckAlerts and AH.IsModern() then AH.CheckAlerts(AlertRows(added)) end
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
local scanning, reading, lastBigRead, scanRead = false, false, -BIG_READ_GAP, 0
local foreignReads = 0          -- wie oft ein fremder Scan (Auctionator) noch gelesen werden darf

-- Sperre: Zeit des letzten Komplett-Scans als Serverzeit in GuildPrideDB. Sie übersteht
-- /reload und Neustart und gilt für alle Charaktere des Accounts. Auch Scans anderer
-- Addons (Auctionator) zählen, weil Blizzard ohnehin nur alle 15 Minuten scannen lässt.
local function MarkScan()
    if type(GuildPrideDB) == "table" then GuildPrideDB.ahLastScan = GetServerTime() end
end

-- Sekunden bis zum nächsten erlaubten Komplett-Scan (0 = jetzt erlaubt)
function AH.ScanWait()
    local last = type(GuildPrideDB) == "table" and tonumber(GuildPrideDB.ahLastScan)
    if not last then return 0 end
    local wait = SCAN_GAP - (GetServerTime() - last)
    return math.max(0, math.min(SCAN_GAP, math.ceil(wait)))   -- Zeit aus der Zukunft: höchstens 15 Min.
end

-- Fertige Liste stückweise speichern: Tausende Items auf einmal ließen das Spiel stocken
local function RecordChunked(res, onDone)
    local keys = {}
    for key in pairs(res) do keys[#keys + 1] = key end
    local now, i = GetServerTime(), 1
    local function Step()
        local last = math.min(#keys, i + CHUNK - 1)
        for j = i, last do
            local key, r = keys[j], res[keys[j]]
            AH.RecordOwn(key, r.min, r.qty, now)
            AH.lastSeen[key] = r.min
        end
        i = last + 1
        if i <= #keys then C_Timer.After(0, Step); return end
        if onDone then onDone() end
    end
    Step()
end

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
        RecordChunked(res, function()
            if not report then return end
            reading, scanRead = false, n
            AH.Print((GP.L and GP.L["Auktionshaus: Komplett-Scan fertig, %d Angebote gelesen."] or "%d"):format(n))
        end)
    end
    Step()
end

local legacyFullScan = AH.FullScan
function AH.FullScan()
    if AH.ScanWait() > 0 then return false end
    if not AH.IsModern() then
        if not legacyFullScan() then return false end
        MarkScan()
        return true
    end
    MarkScan()
    scanning = true
    C_AuctionHouse.ReplicateItems()
    return true
end

-- Komplett-Scans anderer Addons (Auctionator) erkennen: sperren und höchstens zweimal mitlesen
if C_AuctionHouse and type(C_AuctionHouse.ReplicateItems) == "function" and hooksecurefunc then
    hooksecurefunc(C_AuctionHouse, "ReplicateItems", function()
        MarkScan()
        if not scanning then foreignReads = FOREIGN_READS end
    end)
end

AH.Listen("REPLICATE_ITEM_LIST_UPDATE", function()
    if not AH.IsModern() then return end
    if scanning then
        scanning = false
        ReadReplicate(true)
        return
    end
    -- Auctionators Komplett-Scan still mitlesen: nur nach einem neuen Scan, gedrosselt.
    -- Blizzard meldet die Liste noch lange immer wieder – sie ständig neu zu lesen ruckelte.
    if foreignReads > 0 and AH.AuctionatorLoaded() and AH.Opt("ahReadAuctionator")
        and GetTime() - lastBigRead >= BIG_READ_GAP then
        foreignReads = foreignReads - 1
        lastBigRead = GetTime()
        ReadReplicate(false)
    end
end)

AH.Listen("AUCTION_HOUSE_CLOSED", function() scanning = false end)

-- Stand des Komplett-Scans für die Anzeige im Scanner
function AH.ScanStatus()
    return { running = scanning or reading, wait = AH.ScanWait(), read = scanRead }
end

---------------------------------------------------------------------
-- Für den eigenen Reiter: Suchen, Liste, Verkaufen
---------------------------------------------------------------------
-- Stufenbereich aus zwei Eingaben: Zahlen 1–999, leer = offen; vertauscht = getauscht
function AH.LevelRange(minText, maxText)
    local function Num(v)
        v = tonumber(v)
        if not v or v < 1 then return nil end
        return math.min(999, math.floor(v))
    end
    local lo, hi = Num(minText), Num(maxText)
    if lo and hi and lo > hi then lo, hi = hi, lo end
    return lo, hi
end

-- filters: itemClassFilters einer Kategorie ({ { classID, subClassID, inventoryType }, … });
-- minLevel/maxLevel: benötigte Stufe der Items (nil = ohne Grenze)
function AH.ModernBrowse(text, filters, minLevel, maxLevel)
    if not AH.IsModern() then return false end
    AH.StopItemSearch()
    local query = { searchString = text or "", sorts = Sorts(), filters = {},
        itemClassFilters = filters or {} }
    if minLevel then query.minLevel = minLevel end
    if maxLevel then query.maxLevel = maxLevel end
    C_AuctionHouse.SendBrowseQuery(query)
    return true
end

-- WoW-Marke: wird in GuildPride nicht angeboten
local TOKEN_IDS = { [122270] = true, [122284] = true }
function AH.IsTokenCategory(cat)
    if type(cat.flags) == "table" and cat.flags.WOW_TOKEN_FLAG then return true end
    return type(TOKEN_FILTER_LABEL) == "string" and cat.name == TOKEN_FILTER_LABEL
end

-- Blizzards Kategorien (AuctionCategories, wie links im Blizzard-Auktionshaus) als flache Liste.
-- expanded[cat] = true: Unterkategorien dieser Kategorie zeigen.
function AH.CategoryRows(expanded)
    local out = {}
    local function Add(list, depth)
        if type(list) ~= "table" then return end
        for _, cat in ipairs(list) do
            if type(cat) == "table" and cat.name and not AH.IsTokenCategory(cat) then
                local subs = type(cat.subCategories) == "table" and #cat.subCategories > 0
                out[#out + 1] = { cat = cat, name = cat.name, depth = depth, hasSub = subs and true or false }
                if subs and expanded and expanded[cat] then Add(cat.subCategories, depth + 1) end
            end
        end
    end
    Add(AuctionCategories, 0)
    return out
end

local function BrowseRow(b)
    local k = b.itemKey
    if not (k and k.itemID) or TOKEN_IDS[k.itemID] then return nil end
    local info = C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.GetItemKeyInfo(k)
    return {
        result = b, itemKey = k, key = AH.Key(k.itemID, k.itemSuffix),
        min = b.minPrice, qty = b.totalQuantity or 0, mine = b.containsOwnerItem and true or false,
        name = info and info.itemName or AH.ItemName(k.itemID),
        icon = info and info.iconFileID, quality = info and info.quality,
        commodity = info and info.isCommodity,   -- nil: noch unbekannt
    }
end

---------------------------------------------------------------------
-- Nur bestimmte Items suchen (Rezept-Zutaten, Einkaufsliste): wie Auctionator nacheinander
-- je Item eine Suche nach seinem Namen; behalten werden nur Treffer mit genau dieser Item-ID.
---------------------------------------------------------------------
local multi   -- { queue, want, rows, missing, total, current, done }
local MULTI_WAIT = 6            -- Sekunden ohne Antwort: nächstes Item

local function MultiChanged()
    if AH.onMultiUpdate then AH.onMultiUpdate(multi) end
end

local NextMulti
local function SendMulti(id)
    local name = AH.ItemName(id)
    if not name then
        multi.missing[#multi.missing + 1] = id
        return NextMulti()
    end
    multi.current = id
    C_AuctionHouse.SendBrowseQuery({ searchString = name, sorts = Sorts(), filters = {}, itemClassFilters = {} })
    if multi.timer and multi.timer.Cancel then multi.timer:Cancel() end
    local m = multi
    multi.timer = C_Timer and C_Timer.NewTimer and C_Timer.NewTimer(MULTI_WAIT, function()
        if multi == m and m.current == id then m.missing[#m.missing + 1] = id; NextMulti() end
    end)
end

NextMulti = function()
    if not multi then return end
    multi.current = nil
    local id = table.remove(multi.queue, 1)
    if not id then
        multi.done = true
        MultiChanged()
        return
    end
    MultiChanged()
    -- Blizzard drosselt Suchen: warten, bis wieder eine erlaubt ist
    local ready = C_AuctionHouse.IsThrottledMessageSystemReady
    if ready and not ready() then multi.waitingFor = id return end
    SendMulti(id)
end

function AH.SearchItems(ids)
    if not AH.IsModern() or type(ids) ~= "table" or #ids == 0 then return false end
    multi = { queue = {}, want = {}, rows = {}, missing = {}, total = 0 }
    for _, id in ipairs(ids) do
        id = tonumber(id)
        if id and not multi.want[id] then
            multi.want[id] = true
            multi.queue[#multi.queue + 1] = id
            multi.total = multi.total + 1
        end
    end
    NextMulti()
    return true
end

-- Stand der Item-Suche (nil = gerade keine): done, total, missing = { itemID, … }, found = Anzahl
function AH.MultiState()
    if not multi then return nil end
    return { done = multi.done and true or false, total = multi.total, missing = multi.missing,
             found = #multi.rows, left = #multi.queue + (multi.current and 1 or 0) }
end

AH.Listen("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
    if multi and multi.waitingFor then
        local id = multi.waitingFor
        multi.waitingFor = nil
        SendMulti(id)
    end
end)

local function OnMultiResults()
    if not multi or not multi.current then return end
    local id = multi.current
    local hit = false
    for _, b in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
        local k = b.itemKey
        if k and k.itemID == id then
            local row = BrowseRow(b)
            if row then multi.rows[#multi.rows + 1] = row; hit = true end
        end
    end
    if not hit then multi.missing[#multi.missing + 1] = id end
    if multi.timer and multi.timer.Cancel then multi.timer:Cancel() end
    NextMulti()
end
AH.Listen("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", OnMultiResults)

-- Item-Suche beenden (normale Suche, Auktionshaus zu)
function AH.StopItemSearch()
    if multi and multi.timer and multi.timer.Cancel then multi.timer:Cancel() end
    multi = nil
end
AH.Listen("AUCTION_HOUSE_CLOSED", function() AH.StopItemSearch() end)

-- Aktuelle Übersicht als Zeilen, billigste zuerst (während einer Item-Suche: deren Treffer)
function AH.BrowseRows()
    local rows = {}
    if not AH.IsModern() then return rows end
    if multi then
        for _, r in ipairs(multi.rows) do rows[#rows + 1] = r end
    else
        for _, b in ipairs(C_AuctionHouse.GetBrowseResults() or {}) do
            rows[#rows + 1] = BrowseRow(b)
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

-- Angebote, die gerade im Auktionshaus für das Verkaufs-Item stehen (nach AH.RequestPrice),
-- billigste zuerst: { unit, qty, mine }
function AH.CurrentOffers(info)
    local out = {}
    if not info or not AH.IsModern() then return out end
    if info.commodity then
        for i = 1, tonumber(C_AuctionHouse.GetNumCommoditySearchResults(info.itemID)) or 0 do
            local r = C_AuctionHouse.GetCommoditySearchResultInfo(info.itemID, i)
            if r and r.unitPrice and r.unitPrice > 0 then
                out[#out + 1] = { unit = r.unitPrice, qty = r.quantity or 0, mine = (r.numOwnerItems or 0) > 0 }
            end
        end
    elseif info.itemKey then
        for i = 1, tonumber(C_AuctionHouse.GetNumItemSearchResults(info.itemKey)) or 0 do
            local r = C_AuctionHouse.GetItemSearchResultInfo(info.itemKey, i)
            if r and r.buyoutAmount and r.buyoutAmount > 0 then
                local q = (r.quantity and r.quantity > 0) and r.quantity or 1
                out[#out + 1] = { unit = math.floor(r.buyoutAmount / q), qty = q, mine = r.containsOwnerItem and true or false,
                                  auctionID = r.auctionID, buyout = r.buyoutAmount, link = r.itemLink }
            end
        end
    end
    table.sort(out, function(a, b) return a.unit < b.unit end)
    return out
end

-- Preis zum Einstellen: das billigste Angebot im Auktionshaus (offers aufsteigend sortiert).
-- Fremd: 1 Kupfer darunter, damit man selbst der Niedrigste ist; eigenes: gleicher Preis.
function AH.LowestSellPrice(offers)
    local o = offers and offers[1]
    if not o then return nil end
    if o.mine then return o.unit end
    return math.max(1, o.unit - 1)
end

---------------------------------------------------------------------
-- Meine Auktionen: was gerade im Auktionshaus steht, was es wert ist, abbrechen
---------------------------------------------------------------------
function AH.QueryOwned()
    if not AH.IsModern() or not C_AuctionHouse.QueryOwnedAuctions then return false end
    C_AuctionHouse.QueryOwnedAuctions({})
    return true
end

-- Liste: aktive zuerst, darin die wertvollsten oben; verkaufte (warten auf Post) unten.
-- Bei Waren ist buyoutAmount der Stückpreis, bei Einzel-Items der Gesamtpreis.
function AH.OwnedAuctions()
    local out = {}
    if not AH.IsModern() or not C_AuctionHouse.GetNumOwnedAuctions then return out end
    for i = 1, tonumber(C_AuctionHouse.GetNumOwnedAuctions()) or 0 do
        local r = C_AuctionHouse.GetOwnedAuctionInfo(i)
        if r and r.itemKey then
            local info = C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.GetItemKeyInfo(r.itemKey)
            local qty = (r.quantity and r.quantity > 0) and r.quantity or 1
            local price = r.buyoutAmount or r.bidAmount or 0
            local commodity = info and info.isCommodity
            local unit = commodity and price or math.floor(price / qty)
            local total = commodity and price * qty or price
            out[#out + 1] = {
                auctionID = r.auctionID, itemKey = r.itemKey, link = r.itemLink, qty = qty,
                unit = unit, total = total, sold = r.status == 1, timeLeft = r.timeLeftSeconds,
                name = info and info.itemName or AH.ItemName(r.itemKey.itemID),
                icon = info and info.iconFileID, commodity = commodity and true or false,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.sold ~= b.sold then return not a.sold end
        if a.total ~= b.total then return a.total > b.total end
        return (a.auctionID or 0) < (b.auctionID or 0)
    end)
    return out
end

function AH.OwnedSummary(list)
    local s = { active = 0, value = 0, sold = 0, soldValue = 0 }
    for _, a in ipairs(list or {}) do
        if a.sold then s.sold, s.soldValue = s.sold + 1, s.soldValue + a.total
        else s.active, s.value = s.active + 1, s.value + a.total end
    end
    return s
end

function AH.CanCancel(a)
    if not a or a.sold or not a.auctionID or not AH.IsModern() or not C_AuctionHouse.CancelAuction then return false end
    if C_AuctionHouse.CanCancelAuction and not C_AuctionHouse.CanCancelAuction(a.auctionID) then return false end
    return true
end

function AH.CancelCost(a)
    if not a or not a.auctionID or not AH.IsModern() or not C_AuctionHouse.GetCancelCost then return nil end
    return C_AuctionHouse.GetCancelCost(a.auctionID)
end

-- nur aus einem Klick aufrufen
function AH.CancelOwned(a)
    if not AH.CanCancel(a) then return false end
    C_AuctionHouse.CancelAuction(a.auctionID)
    return true
end

---------------------------------------------------------------------
-- Kaufen (nur aus einem Klick aufrufen)
---------------------------------------------------------------------
-- Was kosten qty Stück einer Ware, wenn die billigsten fremden Angebote zuerst gekauft werden?
-- Liefert Gesamtpreis und die tatsächlich verfügbare Menge.
function AH.CommodityCost(offers, qty)
    local total, have = 0, 0
    for _, o in ipairs(offers or {}) do
        if have >= qty then break end
        if not o.mine then
            local take = math.min(o.qty, qty - have)
            total, have = total + take * o.unit, have + take
        end
    end
    return total, have
end

-- Ware: Blizzard meldet danach den genauen Preis (COMMODITY_PRICE_UPDATED), erst dann bestätigen
function AH.BuyCommodity(itemID, qty)
    qty = math.floor(tonumber(qty) or 0)
    if not itemID or qty < 1 or not AH.IsModern() or not C_AuctionHouse.StartCommoditiesPurchase then return false end
    C_AuctionHouse.StartCommoditiesPurchase(itemID, qty)
    return true
end

function AH.ConfirmCommodity(itemID, qty)
    if not itemID or not AH.IsModern() or not C_AuctionHouse.ConfirmCommoditiesPurchase then return false end
    C_AuctionHouse.ConfirmCommoditiesPurchase(itemID, qty)
    return true
end

-- Einzel-Item zum Sofortkaufpreis; eigene Angebote nie
function AH.BuyItem(offer)
    if not offer or offer.mine or not offer.auctionID or not offer.buyout or not AH.IsModern() then return false end
    if not C_AuctionHouse.PlaceBid then return false end
    C_AuctionHouse.PlaceBid(offer.auctionID, offer.buyout)
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
