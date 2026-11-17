-- GuildPride Auktionshaus: Ergebnislisten lesen, Suchen, Komplett-Scan,
-- stilles Mitlesen bei Auctionator (altes Auktionshaus wie Classic)
local ADDON, GP = ...
local AH = GP.AH

local PAGE_SIZE = 50
local SHARE_MAX_PAGE = 200      -- größere Listen gelten als Komplett-Scan: nicht rundsenden

-- Goblin-Auktionshäuser stehen in diesen Zonen (Classic-Karten-IDs)
local NEUTRAL_ZONES = {
    [1446] = true,   -- Tanaris (Gadgetzan)
    [1434] = true,   -- Schlingendorntal (Beutebucht)
    [1452] = true,   -- Winterquell (Ewige Warte)
}

function AH.AuctionatorLoaded()
    if C_AddOns and C_AddOns.IsAddOnLoaded then return C_AddOns.IsAddOnLoaded("Auctionator") and true or false end
    return IsAddOnLoaded and IsAddOnLoaded("Auctionator") and true or false
end

function AH.RecordList(res)
    local now = GetServerTime()
    for key, r in pairs(res) do
        if r.min then AH.RecordOwn(key, r.min, r.qty, now) end
    end
end

-- Aktuelle Ergebnisseite lesen. Eigene Auktionen zählen nie als Marktpreis,
-- Angebote ohne Sofortkauf nur in der Angebotsliste. Zeilen, deren Daten der
-- Client noch nicht hat (Name, Link oder Verkäufer fehlt), machen die Seite
-- „unvollständig“; sie zählen nicht mit.
function AH.ReadList(page, noRecord)
    local me = UnitName("player")
    local res, n, complete = {}, GetNumAuctionItems("list") or 0, true
    for i = 1, n do
        local name, _, count, _, _, _, _, minBid, _, buyout, _, _, _, owner, _, _, _, hasAll = GetAuctionItemInfo("list", i)
        local link = GetAuctionItemLink("list", i)
        local key = AH.KeyFromLink(link)
        if hasAll == false or not name or not key or (buyout and buyout > 0 and owner == nil) then
            complete = false
        else
            count = (count and count > 0) and count or 1
            local r = res[key]
            if not r then r = { qty = 0, n = 0, link = link, name = name, offers = {} }; res[key] = r end
            r.offers[#r.offers + 1] = { owner = owner, count = count, bid = minBid or 0, buyout = buyout or 0, index = i, page = page }
            if buyout and buyout > 0 and owner ~= me then
                local unit = math.floor(buyout / count)
                if not r.min or unit < r.min then r.min = unit end
                r.qty, r.n = r.qty + count, r.n + 1
            end
        end
    end
    if not noRecord then AH.RecordList(res) end
    return res, n, complete
end

local function Merge(into, page)
    for key, r in pairs(page) do
        local m = into[key]
        if not m then into[key] = r
        else
            if r.min and (not m.min or r.min < m.min) then m.min = r.min end
            m.qty, m.n = m.qty + r.qty, m.n + r.n
            for _, o in ipairs(r.offers) do m.offers[#m.offers + 1] = o end
        end
    end
end

local function Keys(t)
    local out = {}
    for key, r in pairs(t) do if r.min then out[#out + 1] = key end end
    return out
end

---------------------------------------------------------------------
-- Suche (nur ohne Auctionator) und Komplett-Scan
---------------------------------------------------------------------
local search, full   -- search = { text, page, results, onDone, waiting, incompleteAt }
local lastBigRead = 0
local INCOMPLETE_WAIT = 2       -- s auf fehlende Zeilendaten warten, dann nehmen, was da ist
local BIG_READ_GAP = 30         -- große Auctionator-Listen höchstens alle 30 s lesen

local ProcessPage
local function TrySend()
    if search and search.waiting and search.incompleteAt and GetTime() - search.incompleteAt > INCOMPLETE_WAIT then
        ProcessPage(true)
        return
    end
    if not search or search.waiting or not CanSendAuctionQuery() then return end
    search.waiting = true
    QueryAuctionItems(search.text, nil, nil, search.page, false, nil, false, false)
end

function AH.Search(text, onDone)
    if AH.AuctionatorLoaded() or AH.IsModern() then return false end
    search = { text = text or "", page = 0, results = {}, onDone = onDone, waiting = false }
    TrySend()
    return true
end
function AH.Searching() return search ~= nil end

-- Eine bestimmte Ergebnisseite erneut laden (zum Kaufen eines Angebots von dort)
function AH.LoadPage(text, page)
    if AH.AuctionatorLoaded() or AH.IsModern() or not CanSendAuctionQuery() then return false end
    search = nil
    QueryAuctionItems(text or "", nil, nil, page or 0, false, nil, false, false)
    return true
end
function AH.CancelSearch() search = nil end

function AH.FullScan()
    if AH.AuctionatorLoaded() then return false end
    local ok, all = CanSendAuctionQuery()
    if not ok or not all then return false end
    search, full = nil, true
    QueryAuctionItems("", nil, nil, 0, false, nil, true, false)
    return true
end

C_Timer.NewTicker(0.3, TrySend)

AH.Listen("AUCTION_ITEM_LIST_UPDATE", function()
    if full then
        full = nil
        local _, n = AH.ReadList()
        AH.Print((GP.L and GP.L["Auktionshaus: Komplett-Scan fertig, %d Angebote gelesen."] or "%d"):format(n))
        return
    end
    if search and search.waiting then
        ProcessPage(false)
        return
    end
    -- Auctionator sucht: Ergebnisse still mitlesen und teilen. Große Listen
    -- (Komplett-Scan) nur gedrosselt lesen, sonst ruckelt das Spiel bei jedem Ereignis.
    if AH.AuctionatorLoaded() and AH.Opt("ahReadAuctionator") then
        local n = GetNumAuctionItems("list") or 0
        if n > SHARE_MAX_PAGE then
            if GetTime() - lastBigRead < BIG_READ_GAP then return end
            lastBigRead = GetTime()
        end
        local page = AH.ReadList()
        if n <= SHARE_MAX_PAGE then AH.Share(Keys(page)) end
    end
end)

ProcessPage = function(force)
    local s = search
    local page, _, complete = AH.ReadList(s.page, true)
    if not complete and not force then
        s.incompleteAt = s.incompleteAt or GetTime()
        return
    end
    s.incompleteAt = nil
    AH.RecordList(page)
    Merge(s.results, page)
    local _, total = GetNumAuctionItems("list")
    total = total or 0
    if (s.page + 1) * PAGE_SIZE < total then
        s.page, s.waiting = s.page + 1, false
        TrySend()
        return
    end
    search = nil
    AH.Share(Keys(s.results))
    if s.onDone then s.onDone(s.results) end
end

AH.Listen("AUCTION_HOUSE_SHOW", function()
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local neutral = false
    for _ = 1, 4 do
        if not map then break end
        if NEUTRAL_ZONES[map] then neutral = true; break end
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
        map = info and info.parentMapID
    end
    AH.SetSide(neutral and "N" or nil)
end)

AH.Listen("AUCTION_HOUSE_CLOSED", function()
    search, full = nil, nil
    AH.SetSide(nil)
end)
