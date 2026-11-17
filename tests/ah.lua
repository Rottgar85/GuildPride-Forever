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
        eq(AH.TooltipLine(L3000, 1, W.server, false), "Auktionshaus: 30c (vor 2 Std.)")
        eq(AH.TooltipLine(L3000, 20, W.server, true), "Auktionshaus: 600c (x20) (vor 2 Std.)")
        eq(AH.TooltipLine(L3000, 1, W.server - 7200 + 30, false), "Auktionshaus: 30c (gerade eben)")
        AH.RecordServer("3001", 44, 1, W.server - 600, "Anna")
        eq(AH.TooltipLine("|Hitem:3001:0:0:0:0:0:0:0|h", 1, W.server, false), "Auktionshaus: 44c (Server, vor 10 Min.)")
        eq(AH.TooltipLine("|Hitem:3002:0:0:0:0:0:0:0|h", 1, W.server, false), nil)
        AH.RecordOwn("3003", 5, 1, W.server - 3 * 86400)
        eq(AH.TooltipLine("|Hitem:3003:0:0:0:0:0:0:0|h", 1, W.server, false), "Auktionshaus: 5c (vor 3 Tagen)")
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
    local M = { browse = {}, commodity = {}, items = {}, replicate = {}, replicated = 0 }
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
    W.Load("GuildPrideAHModernUI.lua")
    test("AH-Forever: Reiter wird beim Öffnen ohne Fehler aufgebaut", function()
        Modern(true)
        AuctionHouseFrame = CreateFrame()
        AuctionHouseFrame.GetFrameLevel = function() return 5 end
        AuctionHouseFrame.Tabs = { CreateFrame(), CreateFrame() }
        -- wie im Spiel: die Reiter-Vorlage trägt sich selbst in AuctionHouseFrame.Tabs ein
        local realCreate = CreateFrame
        CreateFrame = function(kind, name, parent, tpl)
            local f = realCreate(kind, name, parent, tpl)
            if parent == AuctionHouseFrame and kind == "Button" and tpl then table.insert(AuctionHouseFrame.Tabs, f) end
            return f
        end
        local before = #W.frames
        W.Fire("AUCTION_HOUSE_SHOW")
        eq(#W.frames > before + 20, true)
        CreateFrame = realCreate
        local tab, panel = AH._ModernTab()
        tab.scripts.OnClick(tab)
        eq(panel:IsShown(), true, "Klick auf GuildPride zeigt das Fenster")
        AuctionHouseFrame.Tabs[1].scripts.OnClick(AuctionHouseFrame.Tabs[1])
        eq(panel:IsShown(), false, "anderer Reiter blendet es aus")
        W.Fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
        W.Fire("AUCTION_HOUSE_CLOSED")
        Modern(false)
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
end
