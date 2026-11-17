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
        eq(AH.PriceFor("7"), 50)
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
        for _ = 1, 12 do AH.OnMessage("P:A:11=1,1," .. W.server, "Spam") end
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
end
