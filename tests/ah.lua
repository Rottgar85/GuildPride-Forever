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
end
