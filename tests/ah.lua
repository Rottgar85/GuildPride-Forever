-- Tests für den Auktionshaus-Teil (aus tests/run.lua aufgerufen)
return function(test, eq, W, ns)
    GuildPrideAHDB = {}
    W.Load("GuildPrideAHData.lua")
    local AH = ns.AH

    -----------------------------------------------------------------
    -- Preis-Speicher und Preisvorschlag
    -----------------------------------------------------------------
    test("AH: Schlüssel mit und ohne Suffix", function()
        eq(AH.Key(2589), "2589")
        eq(AH.Key(2589, 0), "2589")
        eq(AH.Key(15210, 1017), "15210.1017")
        eq(AH.KeyFromLink("|cff1eff00|Hitem:15210:0:0:0:0:0:1017:0|h[x]|h|r"), "15210.1017")
        eq(AH.KeyFromLink("|cffffffff|Hitem:2589:0:0:0:0:0:0:0|h[Leinen]|h|r"), "2589")
        eq(AH.KeyFromLink("|cffffffff|Hitem:2589::::::::|h[Leinen]|h|r"), "2589")
        eq(AH.KeyFromLink(nil), nil)
    end)

    test("AH: Serverpreis erst mit 2 Absendern innerhalb 25 %", function()
        AH.RecordServer("9", 100, 5, W.server, "Anna"); eq(AH.ServerConfirmed("9"), nil)
        AH.RecordServer("9", 200, 5, W.server, "Bert"); eq(AH.ServerConfirmed("9"), nil)
        AH.RecordServer("9", 110, 5, W.server, "Bert"); eq(AH.ServerConfirmed("9"), 105)
    end)

    test("AH: Vorschlag – fresh > own<1h > server > alt > nil", function()
        local p, tag = AH.Suggest("9", 500, W.server); eq(p, 499); eq(tag, "fresh")
        eq(AH.Suggest("9", 1, W.server), 1)
        eq(select(2, AH.Suggest("9", nil, W.server)), "server")
        AH.RecordOwn("9", 300, 2, W.server - 600)
        p, tag = AH.Suggest("9", nil, W.server); eq(p, 300); eq(tag, "own")
        AH.RecordOwn("8", 300, 2, W.server - 5 * 3600)
        eq(select(2, AH.Suggest("8", nil, W.server)), "old")
        eq(AH.Suggest("nix", nil, W.server), nil)
    end)

    test("AH: älterer Serverwert verdrängt neueren nicht; Aufräumen", function()
        AH.RecordServer("7", 50, 1, W.server, "Anna")
        eq(AH.RecordServer("7", 10, 1, W.server - 100, "Carl"), false)
        eq(AH.Store()["7"].srv.p, 50); eq(AH.Store()["7"].srv.from.Carl, 10)
        AH.Prune(W.server + 8 * 86400); eq(AH.PriceFor("7"), nil)
    end)

    test("AH: eigener Preis vor älterem Serverpreis, Verlauf max. 7 Tage", function()
        AH.RecordServer("6", 80, 1, W.server - 50, "Anna")
        AH.RecordOwn("6", 90, 1, W.server)
        local p, _, src = AH.PriceFor("6"); eq(p, 90); eq(src, "own")
        for d = 1, 10 do AH.RecordOwn("6", 100 + d, 1, W.server + d * 86400) end
        eq(#AH.Store()["6"].hist, 7)
    end)

    test("AH: Seiten getrennt", function()
        AH.SetSide("N"); eq(AH.PriceFor("6"), nil)
        AH.SetSide(nil); eq(AH.Side(), "A")
    end)

    -----------------------------------------------------------------
    -- Teilen (Weg C)
    -----------------------------------------------------------------
    W.Load("GuildPrideAHComm.lua")
    local out = {}
    AH.SendRaw = function(msg) out[#out + 1] = msg end

    test("AH-Comm: P kodieren/dekodieren, 250 Zeichen, max 8 Items", function()
        local items = {}
        for i = 1, 20 do items[i] = { key = tostring(1000 + i), p = 12345, q = 20, t = W.server } end
        local msgs = AH.EncodeP("A", items)
        eq(#msgs, 3)
        for _, m in ipairs(msgs) do eq(#m <= 250, true) end
        local side, got = AH.DecodeP(msgs[1]); eq(side, "A"); eq(#got, 8); eq(got[1].p, 12345)
        eq(got[1].key, "1001")
        local _, sfx = AH.DecodeP("P:A:15210.1017=5,1," .. W.server); eq(sfx[1].key, "15210.1017")
    end)

    test("AH-Comm: Unsinn wird verworfen", function()
        local _, a = AH.DecodeP("P:A:abc=1,1," .. W.server); eq(#a, 0)
        local _, b = AH.DecodeP("P:A:9=0,1," .. W.server .. ";10=5,1," .. (W.server + 3600)); eq(#b, 0)
        local _, c = AH.DecodeP("P:A:9=5,0," .. W.server .. ";10=5,1," .. (W.server - 8 * 86400)); eq(#c, 0)
        local _, d = AH.DecodeP("P:A:9=2000000000,1," .. W.server); eq(#d, 0)
        eq(select(2, AH.DecodeP("Müll")), nil)
    end)

    test("AH-Comm: Spammer bestätigt nichts", function()
        for _ = 1, 50 do AH.OnMessage("P:A:11=1,1," .. W.server, "Spam") end
        eq(AH.ServerConfirmed("11"), nil); eq(AH.stats.dropped > 0, true)
    end)

    test("AH-Comm: andere Seite wird nicht gespeichert", function()
        AH.OnMessage("P:H:12=100,1," .. W.server, "Horde1"); eq(AH.PriceFor("12"), nil)
    end)

    test("AH-Comm: fremder Preis wird gespeichert", function()
        AH.OnMessage("P:A:14=77,3," .. W.server, "Anna")
        local p, _, src = AH.PriceFor("14"); eq(p, 77); eq(src, "srv")
    end)

    test("AH-Comm: Q nur mit eigenem Preis < 6 Std.; fremdes P stoppt Antwort", function()
        AH.RecordOwn("13", 100, 1, W.server - 7 * 3600)
        AH.OnMessage("Q:A:13", "Anna"); eq(AH._answerPlanned("13"), false)
        AH.RecordOwn("13", 100, 1, W.server)
        AH.OnMessage("Q:A:13", "Bert"); eq(AH._answerPlanned("13"), true)
        AH.OnMessage("P:A:13=101,1," .. W.server, "Carl"); eq(AH._answerPlanned("13"), false)
    end)

    test("AH-Comm: geplante Antwort geht nach Ablauf raus", function()
        AH.RecordOwn("15", 100, 1, W.server)
        AH.OnMessage("Q:A:15", "Bert"); eq(AH._answerPlanned("15"), true)
        out = {}; AH._tick(GetTime() + 5)
        eq(AH._answerPlanned("15"), false); eq(#out, 1); eq(out[1]:find("15=100,1,", 1, true) ~= nil, true)
    end)

    test("AH-Comm: Share je Item höchstens alle 30 Min., Ask gebremst", function()
        AH.RecordOwn("16", 50, 1, W.server)
        out = {}; AH.Share({ "16" }); AH.Share({ "16" }); eq(#out, 1)
        out = {}; AH.Ask("17"); AH.Ask("17"); eq(#out, 1)
        for i = 1, 20 do AH.Ask(tostring(200 + i)) end
        eq(#out, 10, "höchstens 10 Nachfragen pro Minute")
    end)

    -----------------------------------------------------------------
    -- Scan
    -----------------------------------------------------------------
    W.Load("GuildPrideAHScan.lua")
    local LINK_2589 = "|cffffffff|Hitem:2589:0:0:0:0:0:0:0|h[Leinenstoff]|h|r"
    local LINK_15210_1017 = "|cff1eff00|Hitem:15210:0:0:0:0:0:1017:0|h[x]|h|r"
    local LINK_15210_0 = "|cff1eff00|Hitem:15210:0:0:0:0:0:0:0|h[x]|h|r"

    test("AH-Scan: eigene Auktionen und Angebote ohne Sofortkauf zählen nicht", function()
        W.auctions = {
            { "Leinen", 20, 100, 200, "Tester", LINK_2589 },
            { "Leinen", 10, 100, 0,   "Anna",   LINK_2589 },
            { "Leinen", 5,  100, 150, "Bert",   LINK_2589 },
        }
        local r = AH.ReadList(); eq(r["2589"].min, 30); eq(#r["2589"].offers, 3)
        eq(AH.PriceFor("2589"), 30)
    end)

    test("AH-Scan: Suffix-Items getrennt", function()
        W.auctions = { { "x", 1, 1, 500, "Anna", LINK_15210_1017 }, { "x", 1, 1, 900, "Anna", LINK_15210_0 } }
        local r = AH.ReadList(); eq(r["15210.1017"].min, 500); eq(r["15210"].min, 900)
    end)

    test("AH-Scan: mehrere Seiten kurz nacheinander behalten das Minimum", function()
        W.auctions = { { "Leinen", 1, 1, 20, "Bert", LINK_2589 } }; AH.ReadList()
        W.auctions = { { "Leinen", 1, 1, 90, "Carl", LINK_2589 } }; AH.ReadList()
        eq(AH.PriceFor("2589"), 20)
    end)

    test("AH-Scan: Suche über Seiten, Ergebnis zusammengeführt und geteilt", function()
        local res
        W.queries, out = 0, {}
        W.auctions = { { "Leinen", 1, 1, 25, "Bert", LINK_2589 } }
        AH.Search("Leinen", function(r) res = r end); eq(W.queries, 1)
        W.Advance(3600)
        W.Fire("AUCTION_ITEM_LIST_UPDATE")
        eq(res["2589"].min, 25); eq(#out, 1)
    end)

    test("AH-Scan: mit Auctionator keine eigene Suche, aber Mitlesen", function()
        W.addons.Auctionator = true; W.queries = 0
        AH.Search("Leinen", function() end); eq(W.queries, 0)
        W.Advance(3600)
        W.auctions = { { "Leinen", 1, 1, 40, "Bert", LINK_2589 } }
        W.Fire("AUCTION_ITEM_LIST_UPDATE"); eq(AH.PriceFor("2589"), 40)
        W.addons.Auctionator = nil
    end)

    test("AH-Scan: AH schließt mitten in der Suche", function()
        local called = false
        W.canQuery = false; AH.Search("Leinen", function() called = true end)
        W.Fire("AUCTION_HOUSE_CLOSED"); W.canQuery = true; W.Fire("AUCTION_ITEM_LIST_UPDATE")
        eq(called, false)
    end)

    test("AH-Scan: Komplett-Scan nur mit getAll, wird nicht rundgesendet", function()
        W.canGetAll, W.queries = false, 0
        eq(AH.FullScan(), false); eq(W.queries, 0)
        W.canGetAll, out = true, {}
        eq(AH.FullScan(), true); eq(W.queries, 1)
        W.Advance(3600)
        W.auctions = { { "Leinen", 1, 1, 33, "Bert", LINK_2589 } }
        W.Fire("AUCTION_ITEM_LIST_UPDATE")
        eq(AH.PriceFor("2589"), 33); eq(#out, 0)
        W.canGetAll = false
    end)

    -----------------------------------------------------------------
    -- Tooltip
    -----------------------------------------------------------------
    W.Load("GuildPrideAHTooltip.lua")

    test("AH-Tooltip: Zeile mit Herkunft und Alter", function()
        AH.RecordOwn("3000", 30, 5, W.server - 7200)
        local L3000 = "|cffffffff|Hitem:3000:0:0:0:0:0:0:0|h[x]|h|r"
        eq(AH.TooltipLine(L3000, 1, W.server, false), "GuildPride Auktionshaus: 30c (vor 2 Std.)")
        eq(AH.TooltipLine(L3000, 20, W.server, true), "GuildPride Auktionshaus: 600c (x20) (vor 2 Std.)")
        eq(AH.TooltipLine(L3000, 1, W.server - 7200 + 30, false), "GuildPride Auktionshaus: 30c (gerade eben)")
        AH.RecordServer("3001", 44, 1, W.server - 600, "Anna")
        eq(AH.TooltipLine("|Hitem:3001:0:0:0:0:0:0:0|h", 1, W.server, false), "GuildPride Auktionshaus: 44c (Server, vor 10 Min.)")
        eq(AH.TooltipLine("|Hitem:3002:0:0:0:0:0:0:0|h", 1, W.server, false), nil)
        AH.RecordOwn("3003", 5, 1, W.server - 3 * 86400)
        eq(AH.TooltipLine("|Hitem:3003:0:0:0:0:0:0:0|h", 1, W.server, false), "GuildPride Auktionshaus: 5c (vor 3 Tagen)")
    end)

    test("AH-Tooltip: seelengebunden/Quest/grau → nicht handelbar", function()
        W.itemInfo[5000] = { quality = 1, bindType = 1, classID = 0, sellPrice = 10 }
        W.itemInfo[5001] = { quality = 1, bindType = 0, classID = 12, sellPrice = 0 }
        W.itemInfo[5002] = { quality = 0, bindType = 0, classID = 0, sellPrice = 5 }
        W.itemInfo[5003] = { quality = 2, bindType = 2, classID = 4, sellPrice = 50 }
        eq(AH.Tradeable("|Hitem:5000:0:0:0:0:0:0:0|h"), false)
        eq(AH.Tradeable("|Hitem:5001:0:0:0:0:0:0:0|h"), false)
        eq(AH.Tradeable("|Hitem:5002:0:0:0:0:0:0:0|h"), false)
        eq(AH.Tradeable("|Hitem:5003:0:0:0:0:0:0:0|h"), true)
    end)

    -----------------------------------------------------------------
    -- Review-Fixes
    -----------------------------------------------------------------
    test("AH-Fix: 40 Nachrichten pro Minute (volle Sendebremse) sperren niemanden", function()
        local before = AH.stats.dropped
        for i = 1, 40 do AH.OnMessage("P:A:" .. (60000 + i) .. "=100,1," .. W.server, "Viel") end
        eq(AH.stats.dropped, before)
    end)

    test("AH-Fix: Spammer mit Zukunftszeit steuert Preis nicht und sperrt Ehrliche nicht aus", function()
        for _, n in ipairs({ "Hon1", "Hon2", "Hon3" }) do AH.RecordServer("4000", 100, 1, W.server - 100, n) end
        AH.OnMessage("P:A:4000=999999,1," .. (W.server + 60), "Spam2")
        eq(AH.PriceFor("4000"), 100)
        eq(AH.Store()["4000"].srv.t <= W.server, true)
        AH.OnMessage("P:A:4000=101,1," .. (W.server - 50), "Dora")
        eq(AH.Store()["4000"].srv.from.Dora, 101)
    end)

    test("AH-Fix: absurde Suffixe und Schlüssel-Flut werden verworfen", function()
        eq(#select(2, AH.DecodeP("P:A:123.99999=5,1," .. W.server)), 0)
        eq(#select(2, AH.DecodeP("P:A:123.1017=5,1," .. W.server)), 1)
        for m = 0, 29 do
            local parts = {}
            for i = 1, 8 do parts[i] = (70000 + m * 8 + i) .. "=5,1," .. W.server end
            AH.OnMessage("P:A:" .. table.concat(parts, ";"), "Flut")
        end
        local n = 0
        for k in pairs(AH.Store()) do local id = tonumber(k); if id and id > 70000 and id <= 70240 then n = n + 1 end end
        eq(n <= 200, true, "höchstens 200 neue Items je Absender und Stunde")
    end)

    test("AH-Fix: unvollständige Zeilen – Suche wartet auf vollständige Daten", function()
        local res
        W.Advance(3600)
        W.auctions = { { nil, 1, 1, 25, "Bert", LINK_2589 }, { "Leinen", 1, 1, 5, nil, LINK_2589 } }
        AH.Search("Leinen", function(r) res = r end)
        W.Fire("AUCTION_ITEM_LIST_UPDATE"); eq(res, nil)
        W.auctions = { { "Leinen", 1, 1, 25, "Bert", LINK_2589 }, { "Leinen", 1, 1, 5, "Tester", LINK_2589 } }
        W.Fire("AUCTION_ITEM_LIST_UPDATE")
        eq(res and res["2589"].min, 25)
    end)

    test("AH-Fix: Angebote merken ihre Seite, Seite kann nachgeladen werden", function()
        local res
        W.Advance(3600)
        W.auctions = {}
        for i = 1, 60 do W.auctions[i] = { "Leinen", 1, 1, 30 + i, "Bert", LINK_2589 } end
        AH.Search("Leinen", function(r) res = r end)
        W.Fire("AUCTION_ITEM_LIST_UPDATE"); W.Fire("AUCTION_ITEM_LIST_UPDATE")
        eq(res["2589"].offers[1].page, 0); eq(res["2589"].offers[61].page, 1)
        W.queries = 0; eq(AH.LoadPage("Leinen", 0), true); eq(W.queries, 1)
    end)

    test("AH-Fix: großes Auctionator-Ergebnis wird gedrosselt gelesen", function()
        W.addons.Auctionator = true
        W.Advance(3600)
        W.auctions = {}
        for i = 1, 250 do W.auctions[i] = { "Leinen", 1, 1, 40, "Bert", LINK_2589 } end
        W.Fire("AUCTION_ITEM_LIST_UPDATE"); W.Fire("AUCTION_ITEM_LIST_UPDATE")
        eq(AH.Store()["2589"].own.q, 250)
        W.addons.Auctionator = nil
    end)
    -----------------------------------------------------------------
    -- Neues Auktionshaus (C_AuctionHouse) – so läuft WoW Forever
    -----------------------------------------------------------------
    test("AH-Forever: unbekannte Events werden übersprungen statt Fehler", function()
        W.unknownEvents = { NEW_AUCTION_UPDATE = true }
        eq(AH.Listen("NEW_AUCTION_UPDATE", function() end), false)
        eq(AH.Listen("AUCTION_HOUSE_CLOSED", function() end), true)
        W.unknownEvents = {}
    end)

    W.Load("GuildPrideAHModern.lua")
    local M = { browse = {}, commodity = {}, items = {}, replicate = {}, replicated = 0, owned = {} }
    local function Modern(on)
        if not on then C_AuctionHouse = nil; return end
        C_AuctionHouse = {
            SendBrowseQuery = function() end,
            GetBrowseResults = function() return M.browse end,
            GetNumCommoditySearchResults = function(id) return #(M.commodity[id] or {}) end,
            GetCommoditySearchResultInfo = function(id, i) return (M.commodity[id] or {})[i] end,
            GetNumItemSearchResults = function() return #M.items end,
            GetItemSearchResultInfo = function(_, i) return M.items[i] end,
            ReplicateItems = function() M.replicated = M.replicated + 1 end,
            GetNumReplicateItems = function() return #M.replicate end,
            GetReplicateItemInfo = function(i)
                local a = M.replicate[i]
                return a.name, nil, a.count, 1, true, 1, 0, 0, 0, a.buyout, 0, false, nil, a.owner, nil, 0, a.id, a.hasAll ~= false
            end,
            GetReplicateItemLink = function(i) return M.replicate[i].link end,
        }
    end
    local function L(id) return "|cffffffff|Hitem:" .. id .. ":0:0:0:0:0:0:0|h[x]|h|r" end

    test("AH-Forever: Client mit C_AuctionHouse erkannt", function()
        Modern(false); eq(AH.IsModern(), false)
        Modern(true); eq(AH.IsModern(), true)
        IsUsingLegacyAuctionClient = function() return true end; eq(AH.IsModern(), false)
        IsUsingLegacyAuctionClient = nil
    end)

    test("AH-Forever: Übersicht wird gelesen und geteilt, eigene ausgelassen", function()
        Modern(true); W.Advance(3600); out = {}
        M.browse = {
            { itemKey = { itemID = 30001, itemSuffix = 0 }, totalQuantity = 20, minPrice = 40 },
            { itemKey = { itemID = 30002, itemSuffix = 0 }, totalQuantity = 3, minPrice = 99, containsOwnerItem = true },
        }
        W.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        eq(AH.PriceFor("30001"), 40); eq(AH.Store()["30001"].own.q, 20)
        eq(AH.Store()["30002"], nil)
        eq(#out, 1)
        Modern(false)
    end)

    test("AH-Forever: Waren-Suche nimmt den günstigsten fremden Preis", function()
        Modern(true); W.Advance(3600)
        M.commodity[30003] = {
            { unitPrice = 50, quantity = 5, numOwnerItems = 5 },
            { unitPrice = 60, quantity = 10, numOwnerItems = 0 },
            { unitPrice = 70, quantity = 4, numOwnerItems = 1 },
        }
        W.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 30003)
        eq(AH.PriceFor("30003"), 60); eq(AH.Store()["30003"].own.q, 13)
        Modern(false)
    end)

    test("AH-Forever: Item-Suche – Stückpreis, ohne eigene und ohne Sofortkauf", function()
        Modern(true); W.Advance(3600)
        M.items = {
            { buyoutAmount = 100, quantity = 1, itemLink = L(30004), containsOwnerItem = true },
            { buyoutAmount = 900, quantity = 3, itemLink = L(30004) },
            { bidAmount = 10, quantity = 1, itemLink = L(30004) },
            { buyoutAmount = 700, quantity = 1, itemLink = L(30004) },
        }
        W.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 30004, itemSuffix = 0 })
        eq(AH.PriceFor("30004"), 300); eq(AH.Store()["30004"].own.q, 4)
        Modern(false)
    end)

    test("AH-Forever: Auctionator-Mitlesen abschaltbar", function()
        Modern(true); W.Advance(3600)
        W.addons.Auctionator = true; GuildPrideDB.ahReadAuctionator = false
        M.browse = { { itemKey = { itemID = 30005, itemSuffix = 0 }, totalQuantity = 1, minPrice = 5 } }
        W.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"); eq(AH.Store()["30005"], nil)
        GuildPrideDB.ahReadAuctionator = true
        W.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED"); eq(AH.PriceFor("30005"), 5)
        W.addons.Auctionator = nil
        Modern(false)
    end)

    test("AH-Forever: Komplett-Scan über ReplicateItems, höchstens alle 15 Minuten", function()
        Modern(true); W.Advance(3600); out = {}
        M.replicated = 0
        M.replicate = {
            { name = "A", count = 2, buyout = 100, owner = "Anna", id = 30006, link = L(30006) },
            { name = "A", count = 1, buyout = 40, owner = W.me, id = 30006, link = L(30006) },
            { name = "A", count = 1, buyout = 10, owner = "Bert", id = 30006, link = L(30006), hasAll = false },
            { name = "B", count = 1, buyout = 0, owner = "Bert", id = 30007, link = L(30007) },
        }
        eq(AH.FullScan(), true); eq(M.replicated, 1)
        W.Fire("REPLICATE_ITEM_LIST_UPDATE")
        eq(AH.PriceFor("30006"), 50); eq(AH.Store()["30007"], nil); eq(#out, 0)
        -- ohne laufenden Scan (und ohne Auctionator) nicht erneut lesen
        M.replicate[1].buyout = 2
        W.Fire("REPLICATE_ITEM_LIST_UPDATE"); eq(AH.PriceFor("30006"), 50)
        W.Advance(60); eq(AH.FullScan(), false); eq(M.replicated, 1)
        W.Advance(900); eq(AH.FullScan(), true)
        Modern(false)
    end)

    test("AH-Forever: alte Suche bleibt im neuen Auktionshaus aus", function()
        Modern(true); W.queries = 0
        eq(AH.Search("Leinen", function() end), false)
        eq(AH.LoadPage("Leinen", 0), false); eq(W.queries, 0)
        Modern(false)
    end)
    test("AH-Forever: Suche schickt Blizzard-Anfrage, Liste nach Preis sortiert", function()
        Modern(true)
        local sent
        C_AuctionHouse.SendBrowseQuery = function(q) sent = q end
        C_AuctionHouse.GetItemKeyInfo = function(k) return { itemName = "Item" .. k.itemID } end
        eq(AH.ModernBrowse("Leinen"), true); eq(sent.searchString, "Leinen")
        M.browse = {
            { itemKey = { itemID = 30011, itemSuffix = 0 }, totalQuantity = 2, minPrice = 90 },
            { itemKey = { itemID = 30012, itemSuffix = 0 }, totalQuantity = 7, minPrice = 15, containsOwnerItem = true },
        }
        local rows = AH.BrowseRows()
        eq(#rows, 2); eq(rows[1].key, "30012"); eq(rows[1].mine, true); eq(rows[1].qty, 7)
        eq(rows[2].name, "Item30011"); eq(rows[2].min, 90)
        Modern(false); eq(AH.ModernBrowse("x"), false)
    end)

    test("AH-Forever: frischer Marktpreis für den Verkaufsvorschlag", function()
        Modern(true); W.Advance(3600)
        M.commodity[30013] = { { unitPrice = 80, quantity = 3, numOwnerItems = 0 } }
        W.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 30013)
        eq(AH.lastSeen["30013"], 80)
        eq(AH.Suggest("30013", AH.lastSeen["30013"], W.server), 79)
        Modern(false)
    end)

    test("AH-Forever: Einstellen übernimmt immer den niedrigsten Preis im Auktionshaus", function()
        eq(AH.LowestSellPrice({}), nil)
        -- fremdes Angebot ist das billigste: 1 Kupfer darunter
        eq(AH.LowestSellPrice({ { unit = 50, qty = 1 }, { unit = 70, qty = 2, mine = true } }), 49)
        -- eigenes Angebot ist schon das billigste: gleicher Preis, sich selbst nicht unterbieten
        eq(AH.LowestSellPrice({ { unit = 40, qty = 1, mine = true }, { unit = 50, qty = 1 } }), 40)
        eq(AH.LowestSellPrice({ { unit = 1, qty = 1 } }), 1)
    end)

    local function SellMock(commodity, posted)
        C_Item = {
            GetItemID = function() return 30014 end,
            GetItemLink = function() return L(30014) end,
            DoesItemExist = function() return true end,
        }
        C_AuctionHouse.GetItemCommodityStatus = function() return commodity and 2 or 1 end
        C_AuctionHouse.GetAvailablePostCount = function() return 20 end
        C_AuctionHouse.GetItemKeyFromItem = function() return { itemID = 30014, itemSuffix = 0 } end
        C_AuctionHouse.PostCommodity = function(...) posted.c = { ... } end
        C_AuctionHouse.PostItem = function(...) posted.i = { ... } end
        C_AuctionHouse.SendSearchQuery = function(k) posted.q = k end
        C_AuctionHouse.SendSellSearchQuery = function(k) posted.q = k end
    end

    test("AH-Forever: Verkaufen – Ware mit Menge, Ausrüstung immer einzeln", function()
        Modern(true)
        local posted = {}
        SellMock(true, posted)
        local info = AH.SellInfo("LOC")
        eq(info.key, "30014"); eq(info.commodity, true); eq(info.max, 20)
        AH.RequestPrice(info); eq(posted.q.itemID, 30014)
        eq(AH.PostModern(info, 55, 12, 2), true)
        eq(posted.c[1], "LOC"); eq(posted.c[2], 2); eq(posted.c[3], 12); eq(posted.c[4], 55)
        eq(AH.PostModern(info, 55, 21, 2), false)   -- mehr als vorhanden
        eq(AH.PostModern(info, 0, 1, 2), false)     -- kein Preis
        SellMock(false, posted)
        info = AH.SellInfo("LOC"); eq(info.commodity, false); eq(info.max, 1)
        eq(AH.PostModern(info, 700, 5, 3), true)
        eq(posted.i[2], 3); eq(posted.i[3], 1); eq(posted.i[4], nil); eq(posted.i[5], 700)
        C_Item = nil
        Modern(false)
    end)

    test("AH-Forever: Scanner-Status zeigt Wartezeit bis zum nächsten Komplett-Scan", function()
        Modern(true); W.Advance(3600)
        eq(AH.ScanStatus().wait, 0)
        eq(AH.FullScan(), true)
        local st = AH.ScanStatus(); eq(st.running, true); eq(st.wait, 900)
        M.replicate = { { name = "A", count = 1, buyout = 5, owner = "Anna", id = 30015, link = L(30015) } }
        W.Fire("REPLICATE_ITEM_LIST_UPDATE")
        st = AH.ScanStatus(); eq(st.running, false); eq(st.read, 1)
        W.Advance(300); eq(AH.ScanStatus().wait, 600)
        Modern(false)
    end)
    test("AH-Forever: aktuelle Angebote als Liste, billigste zuerst", function()
        Modern(true)
        M.commodity[30040] = {
            { unitPrice = 50, quantity = 5, numOwnerItems = 5 },
            { unitPrice = 40, quantity = 10, numOwnerItems = 0 },
        }
        local list = AH.CurrentOffers({ commodity = true, itemID = 30040 })
        eq(#list, 2); eq(list[1].unit, 40); eq(list[1].qty, 10); eq(list[1].mine, false)
        eq(list[2].unit, 50); eq(list[2].mine, true)
        M.items = {
            { buyoutAmount = 900, quantity = 3, itemLink = L(30041) },
            { bidAmount = 10, quantity = 1, itemLink = L(30041) },
            { buyoutAmount = 200, quantity = 1, itemLink = L(30041), containsOwnerItem = true },
        }
        list = AH.CurrentOffers({ commodity = false, itemID = 30041, itemKey = { itemID = 30041 } })
        eq(#list, 2); eq(list[1].unit, 200); eq(list[1].mine, true); eq(list[2].unit, 300); eq(list[2].qty, 3)
        eq(#AH.CurrentOffers(nil), 0)
        Modern(false)
    end)
    test("AH-Tooltip: ohne Preis ein grauer Hinweis, mit Preis die gelbe Zeile", function()
        eq(AH.TooltipText(L(30050), 1, W.server, false), "|cff808080GuildPride Auktionshaus: noch kein Preis bekannt|r")
        AH.RecordOwn("30051", 77, 1, W.server)
        eq(AH.TooltipText(L(30051), 1, W.server, false), "|cffffd100GuildPride Auktionshaus: 77c (gerade eben)|r")
        W.itemInfo[30052] = { quality = 0, bindType = 0, classID = 7, sellPrice = 1 }   -- grau: nichts
        eq(AH.TooltipText(L(30052), 1, W.server, false), nil)
    end)
    test("AH-Forever: Kategorien wie bei Blizzard, aufklappbar, Suche mit Filter", function()
        Modern(true)
        eq(#AH.CategoryRows({}), 0)   -- ohne Blizzards Tabelle: keine Kategorien, kein Fehler
        local swords = { name = "Schwerter", filters = { { classID = 2, subClassID = 7 } } }
        local weapons = { name = "Waffen", filters = { { classID = 2 } }, subCategories = { swords } }
        AuctionCategories = { weapons, { name = "Stoff", filters = { { classID = 7, subClassID = 5 } } } }
        local rows = AH.CategoryRows({})
        eq(#rows, 2); eq(rows[1].name, "Waffen"); eq(rows[1].depth, 0); eq(rows[1].hasSub, true)
        rows = AH.CategoryRows({ [weapons] = true })
        eq(#rows, 3); eq(rows[2].name, "Schwerter"); eq(rows[2].depth, 1); eq(rows[2].cat, swords)
        local sent
        C_AuctionHouse.SendBrowseQuery = function(q) sent = q end
        eq(AH.ModernBrowse("", swords.filters), true)
        eq(sent.itemClassFilters, swords.filters); eq(sent.searchString, "")
        AH.ModernBrowse("Erz")
        eq(#sent.itemClassFilters, 0)
        -- WoW-Marke wird nie angezeigt
        AuctionCategories = { { name = "WoW-Marke", flags = { WOW_TOKEN_FLAG = true } }, { name = "Stoff" } }
        rows = AH.CategoryRows({})
        eq(#rows, 1); eq(rows[1].name, "Stoff")
        AuctionCategories = nil
        Modern(false)
    end)
    test("AH-Forever: Kaufen – Kosten der billigsten Waren, Kauf von Ware und Einzel-Item", function()
        Modern(true)
        local offers = { { unit = 10, qty = 5, mine = true }, { unit = 20, qty = 3 }, { unit = 30, qty = 10 } }
        local total, have = AH.CommodityCost(offers, 5)
        eq(total, 20 * 3 + 30 * 2); eq(have, 5)
        total, have = AH.CommodityCost(offers, 50)
        eq(have, 13); eq(total, 20 * 3 + 30 * 10)
        local calls = {}
        C_AuctionHouse.StartCommoditiesPurchase = function(id, q) calls.start = { id, q } end
        C_AuctionHouse.ConfirmCommoditiesPurchase = function(id, q) calls.confirm = { id, q } end
        C_AuctionHouse.PlaceBid = function(id, amount) calls.bid = { id, amount } end
        eq(AH.BuyCommodity(30060, 4), true); eq(calls.start[1], 30060); eq(calls.start[2], 4)
        eq(AH.BuyCommodity(30060, 0), false)
        eq(AH.ConfirmCommodity(30060, 4), true); eq(calls.confirm[2], 4)
        eq(AH.BuyItem({ auctionID = 77, buyout = 900 }), true); eq(calls.bid[1], 77); eq(calls.bid[2], 900)
        eq(AH.BuyItem({ auctionID = 78, buyout = 900, mine = true }), false)
        eq(AH.BuyItem({ buyout = 900 }), false)
        -- Einzel-Items: Angebote tragen auctionID und Sofortkaufpreis
        M.items = { { buyoutAmount = 900, quantity = 3, itemLink = L(30061), auctionID = 5 } }
        local list = AH.CurrentOffers({ itemID = 30061, itemKey = { itemID = 30061 } })
        eq(list[1].auctionID, 5); eq(list[1].buyout, 900); eq(list[1].unit, 300)
        Modern(false)
    end)
    local function OwnedMock()
        local calls = { queried = 0 }
        M.owned = {
            -- Ware: buyoutAmount ist der Stückpreis
            { auctionID = 1, itemKey = { itemID = 30080, itemSuffix = 0 }, itemLink = L(30080), quantity = 20,
              buyoutAmount = 50, status = 0, timeLeftSeconds = 7200 },
            -- Einzel-Item: buyoutAmount ist der Gesamtpreis
            { auctionID = 2, itemKey = { itemID = 30081, itemSuffix = 0 }, itemLink = L(30081), quantity = 1,
              buyoutAmount = 3000, status = 0, timeLeftSeconds = 90000 },
            -- schon verkauft
            { auctionID = 3, itemKey = { itemID = 30082, itemSuffix = 0 }, itemLink = L(30082), quantity = 1,
              buyoutAmount = 400, status = 1 },
        }
        C_AuctionHouse.QueryOwnedAuctions = function() calls.queried = calls.queried + 1 end
        C_AuctionHouse.GetNumOwnedAuctions = function() return #M.owned end
        C_AuctionHouse.GetOwnedAuctionInfo = function(i) return M.owned[i] end
        C_AuctionHouse.GetItemKeyInfo = function(k) return { itemName = "Item" .. k.itemID, isCommodity = k.itemID == 30080 } end
        C_AuctionHouse.CanCancelAuction = function(id) return id ~= 3 end
        C_AuctionHouse.GetCancelCost = function() return 25 end
        C_AuctionHouse.CancelAuction = function(id) calls.canceled = id end
        return calls
    end

    test("AH-Forever: Meine Auktionen – Liste, Gesamtwert, Abbrechen", function()
        Modern(true)
        local calls = OwnedMock()
        eq(AH.QueryOwned(), true); eq(calls.queried, 1)
        local list = AH.OwnedAuctions()
        eq(#list, 3)
        -- aktive zuerst, teuerste oben
        eq(list[1].auctionID, 2); eq(list[1].total, 3000); eq(list[1].unit, 3000); eq(list[1].sold, false)
        eq(list[2].auctionID, 1); eq(list[2].total, 1000); eq(list[2].unit, 50); eq(list[2].qty, 20)
        eq(list[3].auctionID, 3); eq(list[3].sold, true)
        local sum = AH.OwnedSummary(list)
        eq(sum.active, 2); eq(sum.value, 4000); eq(sum.sold, 1); eq(sum.soldValue, 400)
        eq(AH.CancelOwned(list[2]), true); eq(calls.canceled, 1)
        calls.canceled = nil
        eq(AH.CancelOwned(list[3]), false); eq(calls.canceled, nil)   -- verkauft: nicht abbrechbar
        eq(AH.CancelCost(list[1]), 25)
        Modern(false)
        eq(#AH.OwnedAuctions(), 0); eq(AH.QueryOwned(), false)
    end)
    test("AH: Preise teilen ist Pflicht für alle", function()
        GuildPrideDB.ahShare = false
        eq(AH.Opt("ahShare"), true)
        GuildPrideDB.ahShare = nil
    end)
    W.Load("GuildPrideAHLists.lua")
    test("AH: Favoriten an/aus, auch in Blizzards Favoriten", function()
        Modern(true)
        GuildPrideDB.ahLists = nil
        local synced = {}
        C_AuctionHouse.SetFavoriteItem = function(k, on) synced[k.itemID] = on end
        eq(AH.IsFavorite(19019), false)
        eq(AH.ToggleFavorite(19019), true); eq(AH.IsFavorite(19019), true); eq(synced[19019], true)
        eq(AH.ToggleFavorite(19019), false); eq(AH.IsFavorite(19019), false); eq(synced[19019], false)
        -- Blizzard-Fehler stören nicht
        C_AuctionHouse.SetFavoriteItem = function() error("gesperrt") end
        eq(AH.ToggleFavorite(2589), true)
        C_AuctionHouse.SetFavoriteItem = nil
        local lists = AH.Lists()
        eq(lists[1].fav, true); eq(lists[1].name, "Favoriten"); eq(#lists[1].items, 1); eq(lists[1].items[1], 2589)
        Modern(false)
        eq(AH.ToggleFavorite(2589), false, "geht auch ohne Auktionshaus")
    end)
    test("AH: Item-IDs aus Text, Links und Wowhead-Adressen lesen", function()
        local ids = AH.ParseItemIDs("2589, 2592;  4306\n|cffffffff|Hitem:14047::::::::60:::::|h[Runenstoff]|h|r x 0 -5 abc 1234567")
        eq(#ids, 4); eq(ids[1], 14047); eq(ids[2], 2589); eq(ids[3], 2592); eq(ids[4], 4306)
        ids = AH.ParseItemIDs("https://www.wowhead.com/classic/item=19019/thunderfury")
        eq(#ids, 1); eq(ids[1], 19019)
        eq(#AH.ParseItemIDs(""), 0); eq(#AH.ParseItemIDs(nil), 0)
    end)
    test("AH: eigene Einkaufslisten anlegen, füllen, umbenennen, löschen", function()
        GuildPrideDB.ahLists = nil
        local l, why = AH.NewList("  Kräuter  ")
        eq(l.name, "Kräuter"); eq(why, nil)
        eq(select(2, AH.NewList("kräuter")) ~= nil, true, "doppelter Name")
        eq(select(2, AH.NewList("   ")) ~= nil, true, "leerer Name")
        eq(select(2, AH.NewList(string.rep("x", 31))) ~= nil, true, "zu lang")
        local added, dup = AH.AddItems(l, "2447, 765 2447")
        eq(added, 2); eq(dup, 0); eq(#l.items, 2)
        added, dup = AH.AddItems(l, "765 2449")
        eq(added, 1); eq(dup, 1, "schon in der Liste"); eq(AH.RemoveItem(l, 2449), true)
        eq(AH.AddItems(l, 765), 0)
        eq(AH.AddItems(l, "nichts"), 0)
        eq(AH.RemoveItem(l, 765), true); eq(#l.items, 1); eq(AH.RemoveItem(l, 765), false)
        eq(AH.RenameList(l, "Alchemie"), true); eq(l.name, "Alchemie")
        local l2 = AH.NewList("Stoff")
        eq(select(2, AH.RenameList(l2, "alchemie")) ~= nil, true)
        local lists = AH.Lists()
        eq(#lists, 3); eq(lists[2].name, "Alchemie"); eq(lists[3].name, "Stoff")
        eq(AH.DeleteList(lists[1]), false, "Favoriten bleiben")
        eq(AH.DeleteList(l), true); eq(#AH.Lists(), 2); eq(AH.Lists()[2].name, "Stoff")
        -- Favoriten-Liste: Hinzufügen per ID macht das Item zum Favoriten
        eq(AH.AddItems(AH.Lists()[1], "19019"), 1); eq(AH.IsFavorite(19019), true)
        eq(AH.RemoveItem(AH.Lists()[1], 19019), true); eq(AH.IsFavorite(19019), false)
        -- kaputte gespeicherte Daten werden repariert
        GuildPrideDB.ahLists = { fav = "x", lists = { 5, { name = "Ok" } } }
        lists = AH.Lists()
        eq(#lists, 2); eq(#lists[1].items, 0); eq(lists[2].name, "Ok"); eq(#lists[2].items, 0)
        GuildPrideDB.ahLists = nil
    end)
    test("AH: Mengen in Einkaufslisten", function()
        GuildPrideDB.ahLists = nil
        local l = AH.NewList("Schmied")
        eq(AH.AddReagents(l, { { 2840, 6 }, { 2880, 1 } }, 2), 2)
        eq(AH.ItemQty(l, 2840), 12); eq(AH.ItemQty(l, 2880), 2)
        eq(AH.AddReagents(l, { { 2840, 4 } }, 1), 1)
        eq(AH.ItemQty(l, 2840), 16); eq(#l.items, 2)
        eq(AH.SetItemQty(l, 2880, 5), true); eq(AH.ItemQty(l, 2880), 5)
        eq(AH.SetItemQty(l, 2880, 0), true); eq(AH.ItemQty(l, 2880), nil)
        eq(AH.SetItemQty(l, 9999, 3), false, "nicht in der Liste")
        eq(AH.RemoveItem(l, 2840), true); eq(AH.ItemQty(l, 2840), nil)
        local fav = AH.Lists()[1]
        eq(AH.AddReagents(fav, { { 2589, 3 } }, 2), 1); eq(AH.IsFavorite(2589), true)
        eq(AH.ItemQty(AH.Lists()[1], 2589), 6)
        eq(AH.AddReagents(l, { { 2840, 1 } }, 0), 1); eq(AH.ItemQty(l, 2840), 1, "mindestens einmal")
        GuildPrideDB.ahLists = nil
    end)
    test("AH: temporäre Einkaufsliste verschwindet, wenn alles gekauft ist", function()
        GuildPrideDB.ahLists = nil
        eq(AH.TempList(), nil)
        local t = AH.TempList(true)
        eq(t.temp, true); eq(AH.TempList(true), t, "nur eine")
        AH.NewList("Dauer")
        local lists = AH.Lists()
        eq(#lists, 3); eq(lists[2], t, "gleich unter den Favoriten"); eq(lists[3].name, "Dauer")
        AH.AddReagents(lists[3], { { 2840, 5 } }, 1)
        AH.AddReagents(t, { { 2840, 10 }, { 2880, 2 } }, 1)
        AH.AddItems(t, "765")
        eq(select(2, AH.RenameList(t, "Anders")) ~= nil, true, "nicht umbenennbar")
        eq(select(2, AH.NewList(t.name)) ~= nil, true, "Name ist reserviert")
        local changed, done = AH.Bought(2840, 4)
        eq(changed, true); eq(done, false); eq(AH.ItemQty(t, 2840), 6)
        eq(AH.ItemQty(AH.Lists()[3], 2840), 5, "feste Listen bleiben")
        AH.Bought(2840, 6); eq(#t.items, 2)
        AH.Bought(765, 1); eq(#t.items, 1, "ohne Menge reicht ein Kauf")
        eq(AH.Bought(9999, 1), false)
        changed, done = AH.Bought(2880, 5)
        eq(changed, true); eq(done, true); eq(AH.TempList(), nil); eq(#AH.Lists(), 2)
        eq(AH.Bought(2880, 1), false, "ohne temporäre Liste")
        -- letzte Zeile von Hand entfernt: Liste ist auch weg
        t = AH.TempList(true)
        AH.AddItems(t, "1")
        eq(AH.RemoveItem(t, 1), true); eq(AH.TempList(), nil)
        GuildPrideDB.ahLists = nil
    end)
    W.Load("GuildPrideAHCrafting.lua")
    local function RecipeMocks(count)
        C_TradeSkillUI = { GetRecipeSchematic = function(id)
            eq(id, 2660)
            return { outputItemID = 2870, quantityMin = 1, reagentSlotSchematics = {
                { reagentType = 1, quantityRequired = 2, reagents = { { itemID = 2840 } } },
                { reagentType = 0, quantityRequired = 1, reagents = { { itemID = 999 } } },   -- Zusatz: nicht nötig
                { reagentType = 1, quantityRequired = 1, reagents = { { itemID = 2880 } } },
                { reagentType = 1, quantityRequired = 1, reagents = { { itemID = 2840 } } },
                { reagentType = 1, quantityRequired = 1, reagents = {} } } }
        end }
        ProfessionsFrame = { CraftingPage = {
            SchematicForm = { GetRecipeInfo = function() return { recipeID = 2660, name = "Kupferkettenweste" } end },
            CreateMultipleInputBox = { GetValue = function() return count end } } }
    end
    test("AH: Rezept-Zutaten aus dem Berufsfenster", function()
        RecipeMocks(3)
        local r = AH.RecipeReagents(2660)
        eq(#r, 2); eq(r[1][1], 2840); eq(r[1][2], 3); eq(r[2][1], 2880); eq(r[2][2], 1)
        local rec = AH.CurrentRecipe()
        eq(rec.name, "Kupferkettenweste"); eq(#rec.reagents, 2); eq(AH.CraftCount(), 3)
        GuildPrideDB.ahLists = nil
        local l = AH.NewList("Schmied")
        eq(AH.CraftToList(l, 3), true); eq(AH.ItemQty(l, 2840), 9); eq(AH.ItemQty(l, 2880), 3)
        eq(AH.CraftToList(l, 1), true); eq(AH.ItemQty(l, 2840), 12, "zweites Rezept addiert")
        -- Suche nur bei offenem Auktionshaus
        local isOpen, show = AH.IsOpen, AH.ShowItemSearch
        AH.IsOpen = function() return false end
        eq(AH.CraftSearch(2), false)
        AH.IsOpen = function() return true end
        local got
        AH.ShowItemSearch = function(ids, need, title) got = { ids = ids, need = need, title = title }; return true end
        eq(AH.CraftSearch(2), true)
        eq(#got.ids, 2); eq(got.need[2840], 6); eq(got.need[2880], 2); eq(got.title, "Kupferkettenweste")
        AH.ShowItemSearch, AH.IsOpen = show, isOpen
        -- kein Rezept gewählt
        ProfessionsFrame = { CraftingPage = { SchematicForm = { GetRecipeInfo = function() return nil end } } }
        eq(AH.CurrentRecipe(), nil); eq(AH.CraftToList(l, 1), false); eq(AH.CraftCount(), 1)
        C_TradeSkillUI, ProfessionsFrame = nil, nil
        GuildPrideDB.ahLists = nil
    end)
    test("AH: Kosten und Gewinn eines Rezepts", function()
        RecipeMocks(1)
        local old = AH.PriceFor
        local P = { ["2840"] = 100, ["2880"] = 50, ["2870"] = 1000 }
        AH.PriceFor = function(k) return P[k] end
        local v = AH.RecipeValue(2660)
        eq(v.cost, 350); eq(v.missing, 0); eq(v.sell, 1000); eq(v.profit, 600); eq(v.output, 2870)
        eq(type(AH.RecipeValueText(v)), "string")
        P["2880"] = nil
        v = AH.RecipeValue(2660)
        eq(v.cost, 300); eq(v.missing, 1)
        P["2870"] = nil
        v = AH.RecipeValue(2660)
        eq(v.sell, nil); eq(v.profit, nil)
        eq(type(AH.RecipeValueText(v)), "string")
        AH.PriceFor = old
        C_TradeSkillUI, ProfessionsFrame = nil, nil
    end)
    test("AH: Einkaufsliste rechnet Bestand und Gesamtkosten", function()
        GuildPrideDB.ahLists = nil
        local l = AH.NewList("Calc")
        AH.AddReagents(l, { { 2840, 12 }, { 2880, 2 }, { 2589, 1 } }, 1)
        AH.AddItems(l, "765")
        C_Item = { GetItemCount = function(id) return ({ [2840] = 5, [2589] = 3 })[id] or 0 end }
        local old = AH.PriceFor
        AH.PriceFor = function(k) return ({ ["2840"] = 100, ["2589"] = 7, ["765"] = 9 })[k] end
        eq(AH.ItemCount(2840), 5)
        eq(AH.Remaining(l, 2840), 7); eq(AH.Remaining(l, 2589), 0); eq(AH.Remaining(l, 765), nil)
        local total, unknown = AH.ListCost(l)
        eq(total, 700); eq(unknown, 1, "2880 ohne Preis")
        AH.PriceFor = old
        C_Item = nil
        GuildPrideDB.ahLists = nil
    end)
    test("AH: Einkaufslisten exportieren und importieren", function()
        GuildPrideDB.ahLists = nil
        local l = AH.NewList("Schmied")
        AH.AddReagents(l, { { 2840, 12 } }, 1)
        AH.AddItems(l, "765")
        local text = AH.ExportList(l)
        eq(text, "GP-Liste:Schmied:2840x12,765")
        local l2, n = AH.ImportList(text)
        eq(l2.name, "Schmied (2)"); eq(n, 2); eq(AH.ItemQty(l2, 2840), 12); eq(AH.ItemQty(l2, 765), nil)
        local l3 = AH.ImportList("2589 2592")
        eq(l3.name, "Import"); eq(#l3.items, 2)
        -- Auctionator-Format: Items per Name, Menge am Ende
        local oldInfo = AH.ItemInfo
        AH.ItemInfo = function(x) if x == "Silberblatt" then return "Silberblatt", "|cff|Hitem:765::|h[Silberblatt]|h|r" end end
        local l4, n4, skipped = AH.ImportList('Kräuter^"Silberblatt";;0;0;0;0;0;0;0;0;;#;;5^"Unbekannt"')
        AH.ItemInfo = oldInfo
        eq(l4.name, "Kräuter"); eq(n4, 1); eq(skipped, 1); eq(AH.ItemQty(l4, 765), 5)
        eq(AH.ImportList(""), nil); eq(AH.ImportList("nichts"), nil)
        GuildPrideDB.ahLists = nil
    end)
    test("AH: zurückgekommene Auktionen erkennen", function()
        GuildPrideDB.ahPosted = nil
        eq(AH.WasPosted("2840"), false)
        AH.MarkPosted("2840"); eq(AH.WasPosted("2840"), true)
        eq(AH.WasPosted("2840", GetServerTime() + 15 * 86400), false, "nach 14 Tagen vergessen")
        eq(AH.WasPosted("2840"), false)
        GuildPrideDB.ahPosted = nil
    end)
    test("AH: Wer in der Gilde kann ein Item herstellen?", function()
        local old = ns.Crafts.Search
        ns.Crafts.Search = function()
            return { { name = "Anna", recipe = "Kupferkettenweste" }, { name = "Bert", recipe = "Kupferkettenweste der Stärke" },
                     { name = "Anna", recipe = "Kupferkettenweste" }, { name = "Carl" }, { name = "Bert", recipe = "kupferkettenweste" } }
        end
        local who = AH.GuildCrafters("Kupferkettenweste")
        eq(#who, 2); eq(who[1], "Anna"); eq(who[2], "Bert")
        eq(#AH.GuildCrafters(nil), 0)
        ns.Crafts.Search = old
    end)
    test("AH: Preisalarm und Preisverlauf", function()
        eq(AH.ParseMoney("1g 50s"), 15000); eq(AH.ParseMoney("2,5"), 25000); eq(AH.ParseMoney("75s 3c"), 7503)
        eq(AH.ParseMoney("12c"), 12); eq(AH.ParseMoney(""), nil); eq(AH.ParseMoney("abc"), nil); eq(AH.ParseMoney("0"), nil)
        GuildPrideDB.ahAlerts = nil
        AH.SetAlert(2840, 100); eq(AH.Alert(2840), 100)
        local printed = {}
        local oldPrint = AH.Print
        AH.Print = function(m) printed[#printed + 1] = m end
        eq(#AH.CheckAlerts({ { itemID = 2840, min = 150 } }), 0)
        eq(#AH.CheckAlerts({ { itemID = 2840, min = 90 } }), 1); eq(#printed, 1)
        eq(#AH.CheckAlerts({ { itemID = 2840, min = 80 } }), 0, "nicht gleich noch einmal")
        W.Advance(601)
        eq(#AH.CheckAlerts({ { itemID = 2840, min = 80 } }), 1)
        AH.SetAlert(2840, nil); eq(AH.Alert(2840), nil)
        -- Suchergebnisse lösen den Alarm aus
        Modern(true)
        AH.SetAlert(2447, 10)
        M.browse = { { itemKey = { itemID = 2447, itemSuffix = 0 }, totalQuantity = 1, minPrice = 5 } }
        local n = #printed
        W.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        eq(#printed, n + 1)
        M.browse = {}
        Modern(false)
        AH.Print = oldPrint
        GuildPrideDB.ahAlerts = nil
        -- Verlauf: Tagestiefstwerte
        AH.RecordOwn("777", 500, 1, 86400 * 10); AH.RecordOwn("777", 400, 1, 86400 * 11)
        local h = AH.History("777")
        eq(#h, 2); eq(h[1].p, 500); eq(h[2].p, 400)
        eq(#AH.History("778"), 0)
    end)
    test("AH-Forever: nur bestimmte Items suchen (Zutaten)", function()
        Modern(true)
        local asked = {}
        C_AuctionHouse.SendBrowseQuery = function(q) asked[#asked + 1] = q.searchString end
        local updates = 0
        local oldCb = AH.onMultiUpdate
        AH.onMultiUpdate = function() updates = updates + 1 end
        eq(AH.SearchItems({ 2447, 765 }), true)
        eq(asked[1], "Item2447"); eq(#asked, 1)
        M.browse = { { itemKey = { itemID = 2447, itemSuffix = 0 }, totalQuantity = 10, minPrice = 5 },
                     { itemKey = { itemID = 24470, itemSuffix = 0 }, totalQuantity = 1, minPrice = 9 } }
        W.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        eq(asked[2], "Item765")
        M.browse = {}
        W.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        eq(#asked, 2)
        local rows = AH.BrowseRows()
        eq(#rows, 1); eq(rows[1].itemKey.itemID, 2447)
        local st = AH.MultiState()
        eq(st.done, true); eq(#st.missing, 1); eq(st.missing[1], 765); eq(updates >= 2, true)
        -- eine normale Suche beendet die Zutaten-Suche
        AH.ModernBrowse("Erz")
        eq(AH.MultiState(), nil)
        eq(AH.SearchItems({}), false)
        AH.onMultiUpdate = oldCb
        Modern(false)
    end)
    W.Load("GuildPrideAHModernUI.lua")
    test("AH-Forever: GuildPride ersetzt Blizzards Auktionshaus, Knöpfe schalten um", function()
        Modern(true)
        GuildPrideDB.ahGuildPride = nil
        AuctionHouseFrame = CreateFrame()
        AuctionHouseFrame.GetFrameLevel = function() return 5 end
        AuctionHouseFrame.CloseButton = CreateFrame()
        AuctionHouseFrame.shown = true
        local scale, alpha = 1, 1
        AuctionHouseFrame.SetScale = function(_, v) scale = v end
        AuctionHouseFrame.GetScale = function() return scale end
        AuctionHouseFrame.SetAlpha = function(_, v) alpha = v end
        AuctionHouseFrame.GetAlpha = function() return alpha end
        local closed = 0
        HideUIPanel = function(f) if f == AuctionHouseFrame then closed = closed + 1 end end
        local before = #W.frames
        W.Fire("AUCTION_HOUSE_SHOW")
        eq(#W.frames > before + 20, true)
        local button, win = AH._ModernTab()
        eq(win:IsShown(), false, "Standard: Blizzard bleibt"); eq(scale, 1); eq(button:IsShown(), true)
        button.scripts.OnClick(button)
        eq(GuildPrideDB.ahGuildPride, true, "einmal GuildPride gewählt")
        eq(win:IsShown(), true, "GuildPride-Fenster statt Blizzard")
        eq(scale < 0.01, true); eq(alpha, 0)
        win.modeSell.scripts.OnClick(win.modeSell)
        win.modeScan.scripts.OnClick(win.modeScan)
        win.modeSearch.scripts.OnClick(win.modeSearch)
        local asked
        C_AuctionHouse.SendSearchQuery = function(k) asked = k end
        M.browse = { { itemKey = { itemID = 30070, itemSuffix = 0 }, totalQuantity = 4, minPrice = 25 } }
        W.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        local row = win.search.rows[1]
        row.scripts.OnClick(row)
        eq(asked.itemID, 30070, "Klick fragt die Angebote an")
        eq(win.search.detail:IsShown(), true, "Kaufansicht im GuildPride-Fenster")
        eq(scale < 0.01, true, "Blizzard bleibt unsichtbar")
        W.Fire("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 30070 })
        win.search.back.scripts.OnClick(win.search.back)
        eq(win.search.detail:IsShown(), false)
        -- Meine Auktionen: Reiter fragt an, Liste, Gesamtwert, Abbrechen mit Bestätigung
        local oc = OwnedMock()
        win.modeOwn.scripts.OnClick(win.modeOwn)
        eq(win.own:IsShown(), true); eq(oc.queried >= 1, true)
        W.Fire("OWNED_AUCTIONS_UPDATED")
        eq(win.own.rows[1]:IsShown(), true); eq(win.own.rows[3]:IsShown(), true)
        eq(win.own.rows[3].cancel:IsShown(), false, "verkauft: kein Abbrechen")
        eq(win.own.total:GetText() ~= "", true)
        local popup
        local oldShow = StaticPopup_Show
        StaticPopup_Show = function(name) popup = name end
        win.own.rows[1].cancel.scripts.OnClick(win.own.rows[1].cancel)
        eq(popup, "GUILDPRIDE_AH_CANCEL")
        StaticPopupDialogs.GUILDPRIDE_AH_CANCEL.OnAccept()
        eq(oc.canceled, 2)
        StaticPopup_Show = oldShow
        W.Fire("AUCTION_CANCELED", 2)
        win.modeSearch.scripts.OnClick(win.modeSearch)
        -- zu Blizzard wechseln: Fenster weg, Blizzard wieder sichtbar, Auktionshaus bleibt offen
        win.blizzard.scripts.OnClick(win.blizzard)
        eq(win:IsShown(), false); eq(scale, 1); eq(alpha, 1); eq(closed, 0)
        eq(GuildPrideDB.ahGuildPride, false, "Wahl wird gemerkt")
        -- zurück zu GuildPride
        button.scripts.OnClick(button)
        eq(win:IsShown(), true); eq(scale < 0.01, true); eq(GuildPrideDB.ahGuildPride, true)
        -- GuildPride-Fenster schließen (X/ESC) schließt das ganze Auktionshaus
        win:Hide(); win.scripts.OnHide(win)
        eq(closed, 1)
        W.Fire("AUCTION_HOUSE_CLOSED")
        eq(scale, 1); eq(alpha, 1)
        -- gemerkte Wahl Blizzard: beim nächsten Öffnen bleibt Blizzard sichtbar
        GuildPrideDB.ahGuildPride = false
        W.Fire("AUCTION_HOUSE_SHOW")
        eq(win:IsShown(), false); eq(scale, 1)
        W.Fire("AUCTION_HOUSE_CLOSED")
        GuildPrideDB.ahGuildPride = nil
        HideUIPanel = nil
        Modern(false)
    end)
    test("AH-Forever: GuildPride-Auktionshaus lässt sich sofort ausschalten", function()
        Modern(true)
        GuildPrideDB.ahGuildPride = true
        local scale, alpha = 1, 1
        AuctionHouseFrame.SetScale = function(_, v) scale = v end
        AuctionHouseFrame.GetScale = function() return scale end
        AuctionHouseFrame.SetAlpha = function(_, v) alpha = v end
        AuctionHouseFrame.GetAlpha = function() return alpha end
        local closed = 0
        HideUIPanel = function(f) if f == AuctionHouseFrame then closed = closed + 1 end end
        W.Fire("AUCTION_HOUSE_SHOW")
        local button, win = AH._ModernTab()
        eq(win:IsShown(), true)
        -- ausschalten, während das Auktionshaus offen ist: sofort Blizzard, AH bleibt offen
        AH.SetModernUI(false)
        eq(GuildPrideDB.ahTab, false); eq(win:IsShown(), false); eq(button:IsShown(), false, "kein Knopf")
        eq(scale, 1); eq(alpha, 1); eq(closed, 0)
        eq(GuildPrideDB.ahGuildPride, true, "Ausschalten ist nicht dieselbe Wahl wie der Blizzard-Knopf")
        W.Fire("AUCTION_HOUSE_CLOSED")
        W.Fire("AUCTION_HOUSE_SHOW")
        eq(win:IsShown(), false, "bleibt aus"); eq(scale, 1); eq(button:IsShown(), false)
        eq(AH.ToggleWindow(), false, "auch /gp ah fenster öffnet nichts")
        -- wieder einschalten: Knopf ist sofort da, beim nächsten Öffnen kommt GuildPride
        AH.SetModernUI(true)
        eq(GuildPrideDB.ahTab, true); eq(button:IsShown(), true); eq(win:IsShown(), false)
        W.Fire("AUCTION_HOUSE_CLOSED")
        W.Fire("AUCTION_HOUSE_SHOW")
        eq(win:IsShown(), true)
        W.Fire("AUCTION_HOUSE_CLOSED")
        -- Chatbefehle (stehen in GuildPrideAHUI.lua)
        SlashCmdList.GUILDPRIDE = SlashCmdList.GUILDPRIDE or function() end
        AuctionFrame = false   -- altes Auktionshaus gibt es in WoW Forever nicht
        W.Load("GuildPrideAHUI.lua")
        SlashCmdList.GUILDPRIDE("ah aus"); eq(GuildPrideDB.ahTab, false)
        SlashCmdList.GUILDPRIDE("ah an"); eq(GuildPrideDB.ahTab, true)
        HideUIPanel = nil
        Modern(false)
    end)
    test("AH-Forever: Favoriten-Stern und Einkaufsliste", function()
        Modern(true)
        GuildPrideDB.ahLists, GuildPrideDB.ahGuildPride, GuildPrideDB.ahTab = nil, true, true
        local asked
        C_AuctionHouse.SendSearchQuery = function(k) asked = k end
        AuctionHouseFrame.SetScale = function() end
        AuctionHouseFrame.SetAlpha = function() end
        W.Fire("AUCTION_HOUSE_SHOW")
        local _, win = AH._ModernTab()
        eq(win:IsShown(), true)
        win.modeSearch.scripts.OnClick(win.modeSearch)
        M.browse = { { itemKey = { itemID = 30070, itemSuffix = 0 }, totalQuantity = 4, minPrice = 25 } }
        W.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        -- Stern in der Suchliste
        local row = win.search.rows[1]
        row.fav.scripts.OnClick(row.fav)
        eq(AH.IsFavorite(30070), true)
        -- Stern in der Kaufansicht
        row.scripts.OnClick(row)
        eq(win.search.detail:IsShown(), true)
        win.search.dFav.scripts.OnClick(win.search.dFav)
        eq(AH.IsFavorite(30070), false)
        win.search.dFav.scripts.OnClick(win.search.dFav)
        eq(AH.IsFavorite(30070), true)
        win.search.back.scripts.OnClick(win.search.back)
        -- Reiter Einkaufsliste: Favoriten zuerst
        win.modeList.scripts.OnClick(win.modeList)
        local sp = win.lists
        eq(sp:IsShown(), true); eq(win.search:IsShown(), false)
        eq(sp.listRows[1]:IsShown(), true); eq(sp.listRows[2]:IsShown(), false)
        eq(sp.rows[1].itemID, 30070); eq(sp.rows[2]:IsShown(), false)
        -- neue Liste über das Namensfenster
        local popup
        local oldShow = StaticPopup_Show
        StaticPopup_Show = function(name) popup = name end
        local function Accept(name, text)
            local dlg = { editBox = { GetText = function() return text end } }
            StaticPopupDialogs[name].OnAccept(dlg)
        end
        sp.newBtn.scripts.OnClick(sp.newBtn)
        eq(popup, "GUILDPRIDE_AH_LIST_NAME")
        Accept("GUILDPRIDE_AH_LIST_NAME", "Kräuter")
        eq(#AH.Lists(), 2); eq(sp.listRows[2]:IsShown(), true)
        eq(sp.rows[1]:IsShown(), false, "neue Liste ist ausgewählt und leer")
        -- IDs eintragen
        sp.idBox.GetText = function() return "2447, 765" end
        sp.addBtn.scripts.OnClick(sp.addBtn)
        eq(#AH.Lists()[2].items, 2); eq(sp.rows[1].itemID, 2447); eq(sp.rows[2].itemID, 765)
        -- Zeile entfernen
        sp.rows[2].remove.scripts.OnClick(sp.rows[2].remove)
        eq(#AH.Lists()[2].items, 1); eq(sp.rows[2]:IsShown(), false)
        -- Suchen aus der Liste öffnet die Kaufansicht
        sp.rows[1].search.scripts.OnClick(sp.rows[1].search)
        eq(win.search:IsShown(), true); eq(win.search.detail:IsShown(), true); eq(asked.itemID, 2447)
        win.search.back.scripts.OnClick(win.search.back)
        -- umbenennen und löschen
        win.modeList.scripts.OnClick(win.modeList)
        sp.renameBtn.scripts.OnClick(sp.renameBtn)
        eq(popup, "GUILDPRIDE_AH_LIST_NAME")
        Accept("GUILDPRIDE_AH_LIST_NAME", "Alchemie")
        eq(AH.Lists()[2].name, "Alchemie"); eq(#AH.Lists(), 2)
        sp.deleteBtn.scripts.OnClick(sp.deleteBtn)
        eq(popup, "GUILDPRIDE_AH_LIST_DELETE")
        StaticPopupDialogs.GUILDPRIDE_AH_LIST_DELETE.OnAccept()
        eq(#AH.Lists(), 1); eq(sp.rows[1].itemID, 30070, "zurück bei den Favoriten")
        -- Favoriten lassen sich nicht löschen
        popup = nil
        sp.deleteBtn.scripts.OnClick(sp.deleteBtn)
        eq(popup, nil)
        StaticPopup_Show = oldShow
        W.Fire("AUCTION_HOUSE_CLOSED")
        GuildPrideDB.ahLists = nil
        Modern(false)
    end)
    test("AH-Forever: Zutaten-Suche im Fenster und Mengen in der Einkaufsliste", function()
        Modern(true)
        GuildPrideDB.ahLists, GuildPrideDB.ahGuildPride, GuildPrideDB.ahTab = nil, true, true
        local asked = {}
        C_AuctionHouse.SendBrowseQuery = function(q) asked[#asked + 1] = q.searchString end
        C_AuctionHouse.SendSearchQuery = function() end
        W.Fire("AUCTION_HOUSE_SHOW")
        local _, win = AH._ModernTab()
        eq(AH.ShowItemSearch({ 2447 }, { [2447] = 12 }, "Test"), true)
        eq(win.search:IsShown(), true); eq(asked[#asked], "Item2447")
        M.browse = { { itemKey = { itemID = 2447, itemSuffix = 0 }, totalQuantity = 10, minPrice = 5 } }
        W.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        eq(win.search.rows[1].entry.itemKey.itemID, 2447)
        eq(win.search.rows[2]:IsShown(), false, "nur die gesuchten Items")
        -- Einkaufsliste: Menge ändern, alles suchen
        local l = AH.NewList("Mats")
        AH.AddItems(l, "2447 765")
        win.modeList.scripts.OnClick(win.modeList)
        local sp = win.lists
        sp.listRows[2].scripts.OnClick(sp.listRows[2])
        eq(sp.rows[1].itemID, 2447)
        local box = sp.rows[1].qtyBox
        box.GetText = function() return "20" end
        box.scripts.OnEnterPressed(box)
        eq(AH.ItemQty(l, 2447), 20)
        local n = #asked
        sp.searchAllBtn.scripts.OnClick(sp.searchAllBtn)
        eq(win.search:IsShown(), true); eq(asked[n + 1], "Item2447")
        W.Fire("AUCTION_HOUSE_CLOSED")
        AuctionHouseFrame.shown = false
        eq(AH.ShowItemSearch({ 2447 }, {}, "Test"), false, "Auktionshaus zu")
        AuctionHouseFrame.shown = true
        GuildPrideDB.ahLists = nil
        M.browse = {}
        Modern(false)
    end)
    test("AH: Knöpfe im Berufsfenster – Zutaten in eine Einkaufsliste", function()
        RecipeMocks(2)
        ProfessionsFrame.CraftingPage.CreateAllButton = CreateFrame()
        W.Fire("ADDON_LOADED", "Blizzard_Professions")
        local bar = AH._CraftBar()
        eq(bar ~= nil, true)
        -- mit Material-Feldern: unter das unterste sichtbare
        local function Slot(b, shown)
            local s = CreateFrame(); s.shown = shown; s.GetBottom = function() return b end
            return s
        end
        local s1, s2, s3 = Slot(300, true), Slot(240, true), Slot(100, false)
        ProfessionsFrame.CraftingPage.SchematicForm.reagentSlots = { [1] = { s1, s2 }, [2] = { s3 } }
        bar.scripts.OnUpdate(bar, 0.1)
        eq(bar.anchor, s2, "unter dem untersten sichtbaren Material")
        s3.shown = true
        bar.scripts.OnUpdate(bar, 0.1)
        eq(bar.anchor, s3, "anderes Rezept mit mehr Materialien")
        GuildPrideDB.ahLists = nil
        local l = AH.NewList("Schmied")
        bar.listBtn.scripts.OnClick(bar.listBtn)
        local pk = AH._CraftPicker()
        eq(pk:IsShown(), true)
        eq(pk.buttons[1]:IsShown(), true); eq(pk.buttons[2]:IsShown(), true); eq(pk.buttons[3]:IsShown(), false)
        pk.qtyBox.GetText = function() return "4" end
        pk.buttons[2].scripts.OnClick(pk.buttons[2])
        eq(AH.ItemQty(l, 2840), 12); eq(AH.ItemQty(l, 2880), 4); eq(pk:IsShown(), false)
        -- neue Liste direkt aus der Auswahl (Anzahl wie im Berufsfenster)
        bar.listBtn.scripts.OnClick(bar.listBtn)
        pk.qtyBox.GetText = function() return tostring(AH.CraftCount()) end
        local popup
        local oldShow = StaticPopup_Show
        StaticPopup_Show = function(name) popup = name end
        pk.newBtn.scripts.OnClick(pk.newBtn)
        eq(popup, "GUILDPRIDE_AH_CRAFT_NEWLIST")
        StaticPopupDialogs.GUILDPRIDE_AH_CRAFT_NEWLIST.OnAccept({ editBox = { GetText = function() return "Weste" end } })
        StaticPopup_Show = oldShow
        local lists = AH.Lists()
        eq(#lists, 3); eq(lists[3].name, "Weste"); eq(AH.ItemQty(lists[3], 2840), 6, "Anzahl aus dem Berufsfenster"); eq(AH.ItemQty(lists[3], 2880), 2)
        -- direkt in die temporäre Liste
        bar.listBtn.scripts.OnClick(bar.listBtn)
        pk.qtyBox.GetText = function() return "1" end
        pk.tempBtn.scripts.OnClick(pk.tempBtn)
        eq(AH.TempList() ~= nil, true); eq(AH.ItemQty(AH.TempList(), 2840), 3); eq(pk:IsShown(), false)
        C_TradeSkillUI, ProfessionsFrame = nil, nil
        GuildPrideDB.ahLists = nil
    end)
    test("AH-Forever: Kauf hakt die temporäre Liste ab", function()
        Modern(true)
        GuildPrideDB.ahLists, GuildPrideDB.ahGuildPride, GuildPrideDB.ahTab = nil, true, true
        C_AuctionHouse.SendSearchQuery = function() end
        local confirmed = 0
        C_AuctionHouse.StartCommoditiesPurchase = function() end
        C_AuctionHouse.ConfirmCommoditiesPurchase = function() confirmed = confirmed + 1 end
        W.Fire("AUCTION_HOUSE_SHOW")
        local _, win = AH._ModernTab()
        win.modeList.scripts.OnClick(win.modeList)
        local sp = win.lists
        -- Knopf legt die temporäre Liste an und wählt sie
        sp.tempBtn.scripts.OnClick(sp.tempBtn)
        local t = AH.TempList()
        eq(t ~= nil, true); eq(sp.listRows[2]:IsShown(), true)
        AH.AddReagents(t, { { 2447, 6 } }, 1)
        local oldShow = StaticPopup_Show
        StaticPopup_Show = function() end
        local function BuyThree()
            win.modeList.scripts.OnClick(win.modeList)
            eq(sp.rows[1].itemID, 2447)
            sp.rows[1].search.scripts.OnClick(sp.rows[1].search)
            W.Fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2447)
            win.search.qty.GetText = function() return "3" end
            win.search.buyBtn.scripts.OnClick(win.search.buyBtn)
            W.Fire("COMMODITY_PRICE_UPDATED", 5, 15)
            StaticPopupDialogs.GUILDPRIDE_AH_MODERN_BUY.OnAccept()
            W.Fire("COMMODITY_PURCHASE_SUCCEEDED")
            W.Fire("AUCTION_HOUSE_PURCHASE_COMPLETED")   -- zweites Ereignis zählt nicht doppelt
        end
        BuyThree()
        eq(confirmed, 1); eq(AH.ItemQty(AH.TempList(), 2447), 3)
        BuyThree()
        eq(AH.TempList(), nil, "alles gekauft: Liste weg")
        StaticPopup_Show = oldShow
        W.Fire("AUCTION_HOUSE_CLOSED")
        GuildPrideDB.ahLists = nil
        Modern(false)
    end)
    test("AH-Forever: Liste kaufen nacheinander, Export und Import", function()
        Modern(true)
        GuildPrideDB.ahLists, GuildPrideDB.ahGuildPride, GuildPrideDB.ahTab = nil, true, true
        local asked = {}
        C_AuctionHouse.SendSearchQuery = function(k) asked[#asked + 1] = k.itemID end
        W.Fire("AUCTION_HOUSE_SHOW")
        local _, win = AH._ModernTab()
        local l = AH.NewList("Mats")
        AH.AddReagents(l, { { 2447, 4 }, { 765, 2 } }, 1)
        win.modeList.scripts.OnClick(win.modeList)
        local sp = win.lists
        sp.listRows[2].scripts.OnClick(sp.listRows[2])
        sp.buyListBtn.scripts.OnClick(sp.buyListBtn)
        eq(win.search.detail:IsShown(), true); eq(asked[#asked], 2447); eq(win.search.nextBtn:IsShown(), true)
        win.search.nextBtn.scripts.OnClick(win.search.nextBtn)
        eq(asked[#asked], 765)
        win.search.nextBtn.scripts.OnClick(win.search.nextBtn)
        eq(win.search.nextBtn:IsShown(), false, "fertig")
        -- Export zeigt den Text zum Kopieren
        local shown
        local oldCopy = ns.ShowCopy
        ns.ShowCopy = function(_, t) shown = t end
        win.modeList.scripts.OnClick(win.modeList)
        sp.exportBtn.scripts.OnClick(sp.exportBtn)
        ns.ShowCopy = oldCopy
        eq(shown, "GP-Liste:Mats:2447x4,765x2")
        -- Import über das Eingabefenster
        local oldShow = StaticPopup_Show
        StaticPopup_Show = function() end
        sp.importBtn.scripts.OnClick(sp.importBtn)
        StaticPopupDialogs.GUILDPRIDE_AH_LIST_IMPORT.OnAccept({ editBox = { GetText = function() return shown end } })
        StaticPopup_Show = oldShow
        eq(#AH.Lists(), 3); eq(AH.Lists()[3].name, "Mats (2)")
        W.Fire("AUCTION_HOUSE_CLOSED")
        GuildPrideDB.ahLists = nil
        Modern(false)
    end)
    test("AH-Forever: Zurückgekommene einstellen (leere Taschen)", function()
        Modern(true)
        GuildPrideDB.ahTab, GuildPrideDB.ahGuildPride = true, true
        W.Fire("AUCTION_HOUSE_SHOW")
        local _, win = AH._ModernTab()
        win.modeSell.scripts.OnClick(win.modeSell)
        win.sell.returnBtn.scripts.OnClick(win.sell.returnBtn)
        eq(win.sell:IsShown(), true)
        W.Fire("AUCTION_HOUSE_CLOSED")
        Modern(false)
    end)
    W.Load("GuildPrideAHMail.lua")
    test("AH: Briefkasten – Post nach Sorte abholen", function()
        AUCTION_EXPIRED_MAIL_SUBJECT = "Auktion abgelaufen: %s"
        AUCTION_REMOVED_MAIL_SUBJECT = "Auktion abgebrochen: %s"
        AUCTION_SOLD_MAIL_SUBJECT = "Auktion erfolgreich: %s"
        AUCTION_OUTBID_MAIL_SUBJECT = "Überboten für %s"
        AUCTION_WON_MAIL_SUBJECT = "Auktion gewonnen: %s"
        local mails
        local function Reset()
            mails = {
                { sender = "Auktionshaus", subject = "Auktion abgelaufen: Kupfererz", money = 0, cod = 0, items = 1 },
                { sender = "Auktionshaus", subject = "Auktion erfolgreich: Leinenstoff", money = 500, cod = 0, items = 0 },
                { sender = "Twink", subject = "Mats", money = 100, cod = 0, items = 2 },
                { sender = "Auktionshaus", subject = "Auktion gewonnen: Erz (3)", money = 0, cod = 0, items = 1 },
                { sender = "Fremder", subject = "Nachnahme", money = 0, cod = 50, items = 1 },
                { sender = "Auktionshaus", subject = "Auktion abgebrochen: Silberblatt", money = 0, cod = 0, items = 1 },
                { sender = "Auktionshaus", subject = "Überboten für Zinnerz", money = 70, cod = 0, items = 0 },
                { sender = "Freund", subject = "Hallo", money = 0, cod = 0, items = 0 },   -- nur Text: nichts abzuholen
            }
        end
        Reset()
        GetInboxNumItems = function() return #mails, #mails end
        GetInboxHeaderInfo = function(i)
            local m = mails[i]
            if not m then return end
            return nil, nil, m.sender, m.subject, m.money, m.cod, 10, m.items, false, false, false, true, false
        end
        local looted, moneyTaken = 0, 0
        AutoLootMailItem = function(i) looted = looted + 1; moneyTaken = moneyTaken + mails[i].money; table.remove(mails, i) end
        TakeInboxMoney = function(i)
            moneyTaken = moneyTaken + mails[i].money
            mails[i].money = 0
            if mails[i].items == 0 then table.remove(mails, i) end
        end
        local free = 10
        C_Container = { GetContainerNumFreeSlots = function(bag) return bag == 0 and free or 0 end }
        local printed = {}
        local oldPrint = AH.Print
        AH.Print = function(m) printed[#printed + 1] = m end

        local c = AH.MailCounts()
        eq(c.expired, 2); eq(c.gold, 2); eq(c.won, 1); eq(c.other, 1, "Twink ja, Nachnahme und reiner Text nein")
        eq(c.goldSum, 570)
        -- nur das Gold
        eq(AH.CollectMail("gold"), true)
        eq(#mails, 6); eq(moneyTaken, 570); eq(AH.MailRunning(), false)
        eq(#printed > 0, true)
        -- nur abgelaufene, aber Taschen voll: hält an
        free = 0
        eq(AH.CollectMail("expired"), true)
        eq(AH.MailCounts().expired, 2, "nichts genommen"); eq(AH.MailRunning(), false)
        free = 10
        AH.CollectMail("expired")
        eq(AH.MailCounts().expired, 0); eq(looted, 2)
        -- andere Post (Twink) mit Items und Gold, Nachnahme bleibt
        AH.CollectMail("other")
        eq(AH.MailCounts().other, 0); eq(moneyTaken, 670)
        eq(#mails, 3, "gewonnen, Nachnahme und reiner Text bleiben")
        eq(AH.CollectMail("nichts"), false)
        -- Leiste am Briefkasten
        Reset()
        W.Fire("MAIL_SHOW")
        local bar = AH._MailBar()
        eq(bar ~= nil, true)
        bar.buttons.won.scripts.OnClick(bar.buttons.won)
        eq(AH.MailCounts().won, 0)
        W.Fire("MAIL_CLOSED")
        AH.Print = oldPrint
        GetInboxNumItems, GetInboxHeaderInfo, AutoLootMailItem, TakeInboxMoney, C_Container = nil, nil, nil, nil, nil
    end)
    test("AH: Briefkasten – Twinks als Empfänger wählen", function()
        UnitFactionGroup = function() return "Alliance" end
        GuildPrideDB.ahChars = { Alliance = { ["Anna Stern"] = { game = "Anna-Stern", class = "MAGE" } },
                                 Horde = { ["Hordi"] = { game = "Hordi" } } }
        local oldMine = ns.IsMyChar
        ns.IsMyChar = function(n) return n == "Bert" end      -- per Ausweis erkannter Twink in der Gilde
        AH.RememberChar()
        eq(GuildPrideDB.ahChars.Alliance[ns.Me()] ~= nil, true, "eigener Charakter gemerkt")
        local chars = AH.MyChars()
        eq(#chars, 2, "ohne mich selbst, nur gleiche Fraktion"); eq(chars[1].show, "Anna Stern"); eq(chars[1].game, "Anna-Stern")
        eq(chars[2].show, "Bert")
        -- Menü am Empfänger-Feld
        local typed
        SendMailNameEditBox = CreateFrame()
        SendMailNameEditBox.SetText = function(_, v) typed = v end
        W.Fire("MAIL_SHOW")
        local btn = AH._TwinkButton()
        btn.scripts.OnClick(btn)
        local menu = AH._TwinkMenu()
        eq(menu:IsShown(), true); eq(menu.buttons[1]:IsShown(), true); eq(menu.buttons[3]:IsShown(), false)
        menu.buttons[1].scripts.OnClick(menu.buttons[1], "LeftButton")
        eq(typed, "Anna-Stern"); eq(menu:IsShown(), false)
        -- Rechtsklick vergisst einen Charakter
        btn.scripts.OnClick(btn)
        menu.buttons[1].scripts.OnClick(menu.buttons[1], "RightButton")
        eq(#AH.MyChars(), 1); eq(AH.MyChars()[1].show, "Bert")
        W.Fire("MAIL_CLOSED")
        ns.IsMyChar = oldMine
        GuildPrideDB.ahChars, UnitFactionGroup, SendMailNameEditBox = nil, nil, nil
    end)
    W.Load("GuildPrideAHOrders.lua")
    test("AH: Gildenaufträge – einstellen, abgleichen, annehmen", function()
        local function msg(kind, ...) return kind .. ":" .. table.concat({ ... }, "\031") end
        local function Find(owner, id)
            for _, o in ipairs(AH.Orders()) do if o.owner == owner and o.id == id then return o end end
        end
        local function Count(owner, now)
            local n = 0
            for _, o in ipairs(AH.Orders(now)) do if o.owner == owner then n = n + 1 end end
            return n
        end
        W.sent = {}
        local o = AH.AddOrder("2870", 3)
        eq(o.qty, 3); eq(o.item, 2870); eq(o.owner, ns.Me())
        local sent
        for _, m in ipairs(W.sent) do if m.kind == "ORD" then sent = m end end
        eq(sent ~= nil, true, "an die Gilde"); eq(sent.target, nil)
        eq(select(2, AH.AddOrder("abc", 1)) ~= nil, true, "keine Item-ID")
        eq(AH.AddOrder("2871", 5000).qty, 999)
        -- Aufträge anderer
        W.Receive("Anna", msg("ORD", W.server, "a1:765:20:" .. W.server .. ",a2:2447:5:" .. W.server))
        eq(Count("Anna"), 2); eq(Find("Anna", "a1").qty, 20); eq(Find("Anna", "a1").item, 765)
        W.Receive("Fremd", msg("ORD", W.server, "x1:1:1:" .. W.server), "WHISPER")
        eq(Count("Fremd"), 0, "kein Mitglied")
        W.Receive("Bert", msg("FWD", "Carl", "9", msg("ORD", W.server, "c1:1:1:" .. W.server)))
        eq(Count("Carl"), 0, "weitergeleitet")
        W.Receive("Anna", msg("ORD", W.server - 100, "a1:765:1:" .. W.server))
        eq(Find("Anna", "a1").qty, 20, "älterer Stand überschreibt nicht")
        -- annehmen und abgeben
        W.sent = {}
        eq(AH.TakeOrder("Anna", "a1", true), true)
        local ora
        for _, m in ipairs(W.sent) do if m.kind == "ORA" then ora = m end end
        eq(ora ~= nil, true); eq(Find("Anna", "a1").by, ns.Me())
        eq(AH.TakeOrder(ns.Me(), o.id, true), false, "eigenen Auftrag nicht annehmen")
        W.Receive("Bert", msg("ORA", "Anna", "a2", "1"))
        eq(Find("Anna", "a2").by, "Bert")
        W.Receive("Carl", msg("ORA", "Anna", "a2", "1"))
        eq(Find("Anna", "a2").by, "Bert", "schon vergeben")
        W.Receive("Carl", msg("ORA", "Anna", "a2", "0"))
        eq(Find("Anna", "a2").by, "Bert", "nur Bert kann abgeben")
        W.Receive("Bert", msg("ORA", "Anna", "a2", "0"))
        eq(Find("Anna", "a2").by, nil)
        W.Receive("Bert", msg("FWD", "Carl", "9", msg("ORA", "Anna", "a2", "1")))
        eq(Find("Anna", "a2").by, nil, "Annahme nie weitergeleitet")
        -- Anfrage: Antwort mit den eigenen Aufträgen per Flüstern
        W.sent = {}
        W.Receive("Carl", msg("ORQ", "1"))
        local reply
        for _, m in ipairs(W.sent) do if m.kind == "ORD" then reply = m end end
        eq(reply ~= nil, true); eq(reply.target, "Carl")
        -- löschen, Liste leeren, verfallen
        eq(AH.RemoveOrder(o.id), true); eq(Count(ns.Me()), 1)
        W.Receive("Anna", msg("ORD", W.server + 10, ""))
        eq(Count("Anna"), 0, "Liste geleert")
        eq(Count(ns.Me(), W.server + 15 * 86400), 0, "nach 14 Tagen verfallen")
    end)
    test("AH-Forever: Reiter Aufträge und Preis an Discord", function()
        local function msg(kind, ...) return kind .. ":" .. table.concat({ ... }, "\031") end
        Modern(true)
        GuildPrideDB.ahTab, GuildPrideDB.ahGuildPride, GuildPrideDB.discordBridge = true, true, true
        local posted = {}
        local oldDiscord = ns.Discord
        ns.Discord = { Post = function(text) posted[#posted + 1] = text end }
        C_AuctionHouse.SendSearchQuery = function() end
        W.Fire("AUCTION_HOUSE_SHOW")
        local _, win = AH._ModernTab()
        win.modeOrders.scripts.OnClick(win.modeOrders)
        local op = win.orders
        eq(op:IsShown(), true); eq(win.search:IsShown(), false)
        -- eigenen Auftrag einstellen
        op.itemBox.GetText = function() return "2870" end
        op.qtyBox.GetText = function() return "3" end
        op.addBtn.scripts.OnClick(op.addBtn)
        local mine
        for _, o in ipairs(AH.Orders()) do if o.mine and o.item == 2870 then mine = o end end
        eq(mine ~= nil, true); eq(mine.qty, 3)
        eq(posted[#posted], "Auftrag: 3x Item2870 (von " .. ns.Me() .. ")")
        -- fremden Auftrag annehmen
        W.Receive("Anna", msg("ORD", W.server + 50, "q1:765:20:" .. W.server))
        local row
        for _, r in ipairs(op.rows) do if r.order and r.order.owner == "Anna" then row = r end end
        eq(row ~= nil, true)
        row.action.scripts.OnClick(row.action)
        local taken
        for _, o in ipairs(AH.Orders()) do if o.owner == "Anna" then taken = o end end
        eq(taken.by, ns.Me())
        eq(posted[#posted], "Auftrag angenommen: 20x Item765 für Anna – macht " .. ns.Me())
        -- eigenen Auftrag löschen
        local own
        for _, r in ipairs(op.rows) do if r.order and r.order.mine and r.order.item == 2870 then own = r end end
        own.action.scripts.OnClick(own.action)
        for _, o in ipairs(AH.Orders()) do eq(o.mine and o.item == 2870, false) end
        -- Preis an Discord aus der Kaufansicht
        local oldPrice = AH.PriceFor
        AH.PriceFor = function() return 1234 end
        win.modeSearch.scripts.OnClick(win.modeSearch)
        M.browse = { { itemKey = { itemID = 30070, itemSuffix = 0 }, totalQuantity = 4, minPrice = 25 } }
        W.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        win.search.rows[1].scripts.OnClick(win.search.rows[1])
        win.search.discordBtn.scripts.OnClick(win.search.discordBtn)
        eq(posted[#posted]:match("^Preis: Item30070 – [%dgsc ]+ je Stück$") ~= nil, true, posted[#posted])
        AH.PriceFor = oldPrice
        ns.Discord = oldDiscord
        W.Fire("AUCTION_HOUSE_CLOSED")
        M.browse = {}
        GuildPrideDB.discordBridge = nil
        Modern(false)
    end)
    test("AH-Forever: Geldanzeige ohne globales GetCoinTextureString", function()
        local old = GetCoinTextureString
        GetCoinTextureString = nil
        C_CurrencyInfo = { GetCoinTextureString = function(c) return "cc" .. c end }
        eq(AH.Money(5), "cc5")
        C_CurrencyInfo = nil
        local s = AH.Money(10203)
        GetCoinTextureString = old
        eq(type(s), "string"); eq(s:find("UI%-GoldIcon") ~= nil, true); eq(s:find("^1") ~= nil, true)
    end)
    test("AH-Forever: ohne globales GetItemInfo (nur C_Item) kein Fehler", function()
        local oldInfo, oldIcon, oldInstant, oldItem = GetItemInfo, GetItemIcon, GetItemInfoInstant, C_Item
        C_Item = { GetItemInfo = oldInfo, GetItemInfoInstant = oldInstant, GetItemIconByID = function() return 123 end }
        GetItemInfo, GetItemIcon, GetItemInfoInstant = nil, nil, nil
        local ok, err = pcall(function()
            eq(AH.Tradeable(L(30020)), true)
            eq(AH.ItemIcon(30020), 123)
            eq(AH.ItemName(30020), "Item30020")
        end)
        GetItemInfo, GetItemIcon, GetItemInfoInstant, C_Item = oldInfo, oldIcon, oldInstant, oldItem
        assert(ok, err)
    end)
    test("AH-Forever: Taschen-Liste – nur handelbare Items, zusammengefasst", function()
        local oldC, oldLoc = C_Container, ItemLocation
        local bags = {
            [0] = { [1] = { hyperlink = L(30030), stackCount = 5, itemID = 30030 },
                    [2] = { hyperlink = L(30031), stackCount = 1, itemID = 30031, isBound = true } },
            [1] = { [3] = { hyperlink = L(30030), stackCount = 15, itemID = 30030 },
                    [4] = { hyperlink = L(30032), stackCount = 1, itemID = 30032 } },
        }
        W.itemInfo[30032] = { quality = 0, bindType = 0, classID = 7, sellPrice = 1 }   -- grau
        C_Container = {
            GetContainerNumSlots = function(b) return bags[b] and 4 or 0 end,
            GetContainerItemInfo = function(b, s) return bags[b] and bags[b][s] end,
        }
        ItemLocation = { CreateFromBagAndSlot = function(_, b, s) return { bag = b, slot = s } end }
        local ok, err = pcall(function()
            local list = AH.BagItems()
            eq(#list, 1); eq(list[1].key, "30030"); eq(list[1].count, 20)
            eq(list[1].loc.bag, 0); eq(list[1].loc.slot, 1)
        end)
        C_Container, ItemLocation = oldC, oldLoc
        assert(ok, err)
    end)
end
