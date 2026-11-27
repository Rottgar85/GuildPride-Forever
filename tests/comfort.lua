-- Tests: Komfort (Comfort/): Leveln, Ruf, Vorrat, Taschen, Reparatur
return function(test, eq, W, ns)
    W.Load("GuildPrideLeveling.lua")
    W.Load("GuildPrideSupplies.lua")
    W.Load("GuildPrideQoL.lua")
    local Lv, S, Q = ns.Level, ns.Supplies, ns.QoL

    ---------------------------------------------------------------------
    -- Kleine Helfer (QoL)
    ---------------------------------------------------------------------
    test("/gp qol: Menü nimmt genau die Schalter aus dem Abschnitt „Komfort“", function()
        local list = {
            { header = "Allgemein" }, { key = "sound", label = "Ton" },
            { header = "Komfort" }, { key = "levelInfo", label = "Leveln" }, { key = "sellJunk", label = "Plunder" },
            { header = "Buffs & Erholung" }, { key = "buffFood", label = "Buff-Food" },
        }
        local opts = Q.MenuOptions(list)
        eq(#opts, 2); eq(opts[1].key, "levelInfo"); eq(opts[2].key, "sellJunk")
        eq(#Q.MenuOptions(nil), 0, "ohne Einstellungsliste leer, kein Absturz")
    end)

    test("Plunder: nur Graues mit Händlerpreis, nicht gesperrt; Summe stimmt", function()
        local list, total = Q.JunkList({
            { bag = 0, slot = 1, quality = 0, price = 12, count = 3 },
            { bag = 0, slot = 2, quality = 1, price = 50, count = 1 },
            { bag = 1, slot = 4, quality = 0, price = 0, count = 1 },
            { bag = 1, slot = 5, quality = 0, price = 7, count = 1, locked = true },
            { bag = 2, slot = 1, quality = 0, price = 100, count = 2 },
        })
        eq(#list, 2); eq(list[1].slot, 1); eq(list[2].bag, 2)
        eq(total, 12 * 3 + 100 * 2)
    end)

    test("Quests: Abgabe nur ohne Auswahl, ohne Kosten und ohne Umschalt", function()
        eq(select(1, Q.RewardChoice(0)), true); eq(select(2, Q.RewardChoice(0)), nil)
        eq(select(1, Q.RewardChoice(1)), true); eq(select(2, Q.RewardChoice(1)), 1)
        eq(Q.RewardChoice(3), false, "mehrere Belohnungen: du wählst")
        eq(Q.CanAutoComplete(true, 0, false), true)
        eq(Q.CanAutoComplete(true, 500, false), false, "kostet Gold")
        eq(Q.CanAutoComplete(true, 0, true), false, "Umschalt gedrückt")
        eq(Q.CanAutoComplete(false, 0, false), false)
    end)

    test("Einladungen und Duelle: Bekannte erkennen", function()
        eq(Q.AcceptInvite(true, true, false), true, "Gilde")
        eq(Q.AcceptInvite(true, false, true), true, "Freund")
        eq(Q.AcceptInvite(true, false, false), false, "Fremde fragt das Spiel")
        eq(Q.AcceptInvite(false, true, true), false, "Schalter aus")
        eq(Q.DeclineDuel(true, true, false, false), true, "Fremder")
        eq(Q.DeclineDuel(true, true, true, false), false, "Gildenmitglied darf")
        eq(Q.DeclineDuel(true, false, true, false), true, "alle ablehnen")
        eq(Q.DeclineDuel(false, true, false, false), false)
    end)

    test("Ruhestein: Ort und wann er bereit ist", function()
        eq(Q.HearthText("Goldhain", 0), "Ruhestein: Goldhain – bereit")
        eq(Q.HearthText("Goldhain", 23 * 60), "Ruhestein: Goldhain – bereit in 23 Min.")
        eq(Q.HearthText(nil, 0), nil)
    end)

    test("Links: Webadressen im Chat finden, ohne Doppelte, höchstens 20", function()
        local u = Q.FindURLs("Komm in unseren Discord: https://discord.gg/abc123 und www.example.org/x!")
        eq(#u, 2); eq(u[1], "https://discord.gg/abc123"); eq(u[2], "www.example.org/x")
        eq(#Q.FindURLs("Kein Link hier, nur 3.5 Gold"), 0)
        eq(Q.FindURLs("discord.gg/gilde")[1], "discord.gg/gilde")
        local list = {}
        for i = 1, 25 do Q.Remember(list, { url = "https://a.de/" .. i, who = "X" }) end
        Q.Remember(list, { url = "https://a.de/25", who = "Y" })
        eq(#list, 20); eq(list[1].url, "https://a.de/25", "neueste oben, nicht doppelt"); eq(list[1].who, "Y")
    end)

    ---------------------------------------------------------------------
    -- Leveln
    ---------------------------------------------------------------------
    test("Leveln: EP-Gewinn mit Ruhebonus, auch über einen Levelaufstieg", function()
        local g, r = Lv.Gain({ xp = 100, max = 1000, rest = 500, level = 10 }, { xp = 300, max = 1000, rest = 400, level = 10 })
        eq(g, 200); eq(r, 100, "Ruhebonus = was vom Ruhezustand verbraucht wurde")
        g, r = Lv.Gain({ xp = 900, max = 1000, rest = 0, level = 10 }, { xp = 50, max = 1200, rest = 0, level = 11 })
        eq(g, 150, "Rest bis zum Aufstieg + neue EP"); eq(r, 0)
        g = Lv.Gain({ xp = 300, max = 1000, level = 10 }, { xp = 300, max = 1000, level = 10 })
        eq(g, 0)
    end)

    test("Leveln: EP pro Stunde, Zeit bis zum Aufstieg, heute geschaffte Level", function()
        local st = Lv.NewState("20261126")
        Lv.Record(st, 1000, 600, 300, 1200, "20261126")
        Lv.Record(st, 1600, 600, 0, 1200, "20261126")   -- 10 Min. später
        eq(Lv.Rate(st, 1600), 7200, "1200 EP in 10 Min.")
        eq(Lv.Rate(st, 1000 + 30), nil, "zu kurz gemessen")
        eq(st.day.levels, 1, "2 × 600 von 1200")
        eq(st.day.rested, 300)
        local line = Lv.Line(st, 1600, 400, 1200, 900)
        eq(line:find("7.200 EP/Std.", 1, true) ~= nil, true, line)
        eq(line:find("nächstes Level in 7 Min.", 1, true) ~= nil, true, line)
        eq(line:find("Ruhebonus 900 EP", 1, true) ~= nil, true, line)
        eq(line:find("heute 1,0 Level", 1, true) ~= nil, true, line)
        Lv.Record(st, 2000, 100, 0, 1200, "20261127")
        eq(st.day.key, "20261127", "neuer Tag fängt bei null an"); eq(st.day.xp, 100)
    end)

    test("Leveln als Balken: Anteile, Text und wann er sichtbar ist", function()
        local xp, restEnd = Lv.BarValues(300, 1200, 600)
        eq(xp, 0.25); eq(restEnd, 0.75, "Ruhebonus reicht bis 900 von 1200")
        local _, full = Lv.BarValues(1000, 1200, 5000)
        eq(full, 1, "Ruhebonus höchstens bis zum Levelende")
        eq(select(1, Lv.BarValues(0, 0, 0)), 0, "ohne Levelbedarf kein Absturz")
        eq(Lv.BarText(23, 300, 1200, nil), "Level 23 · 25 %")
        eq(Lv.BarText(23, 300, 1200, 7200), "Level 23 · 25 % · 7.200 EP/Std. · 8 Min.")
        eq(Lv.BarWanted(true, true, 23, 60), true)
        eq(Lv.BarWanted(true, false, 23, 60), false, "Schalter Balken aus")
        eq(Lv.BarWanted(false, true, 23, 60), false, "Leveln ganz aus")
        eq(Lv.BarWanted(true, true, 60, 60), false, "Höchststufe")
    end)

    test("Ruf: Meldung erkennen und die Fraktion in der Liste finden", function()
        local pat = Lv.RepPattern("Reputation with %s increased by %d.")
        eq(Lv.RepName("Reputation with Stormwind increased by 25.", { pat }), "Stormwind")
        eq(Lv.RepName("Reputation with Stormwind decreased by 25.", { pat }), nil)
        local de = Lv.RepPattern("Euer Ruf bei der Fraktion '%s' hat sich um %d verbessert.")
        eq(Lv.RepName("Euer Ruf bei der Fraktion 'Darnassus' hat sich um 10 verbessert.", { pat, de }), "Darnassus")
        local list = { { name = "Allianz", isHeader = true }, { name = "Sturmwind", factionID = 72 }, { name = "Darnassus", factionID = 69 } }
        local i, id = Lv.FindFaction(list, "Darnassus")
        eq(i, 3); eq(id, 69)
        eq(Lv.FindFaction(list, "Allianz"), nil, "Überschriften nie")
    end)

    ---------------------------------------------------------------------
    -- Vorrat
    ---------------------------------------------------------------------
    test("Vorrat: je Klasse, nur für bekannte Zauber, Wiedergeburt nur höchster Rang", function()
        local known = { [20484] = true, [20739] = true, [21849] = true }
        local have = { [17034] = 0, [17035] = 1, [17021] = 9 }
        local list = S.Needs("DRUID", function(s) return known[s] end, function(i) return have[i] or 0 end)
        eq(#list, 1, "nur Saat für Rang 2; Wildbeeren reichen")
        eq(list[1].item, 17035); eq(list[1].have, 1); eq(list[1].min, 2)
        list = S.Needs("WARLOCK", function() return false end, function() return 1 end)
        eq(list[1] and list[1].item, 6265, "Seelensplitter ohne Zauber-Bedingung")
        list = S.Needs("HUNTER", function() return false end, function() return 0 end, 120)
        eq(list[1] and list[1].ammo, true); eq(list[1].have, 120)
        eq(#S.Needs("HUNTER", function() return false end, function() return 0 end, nil), 0, "ohne Munition im Platz nichts")
        eq(#S.Needs("WARRIOR", function() return true end, function() return 0 end), 0)
    end)

    ---------------------------------------------------------------------
    -- Taschen
    ---------------------------------------------------------------------
    test("Taschen: Warnung einmal beim Unterschreiten, Vorschläge zum Verkaufen", function()
        eq(S.BagCheck(2, 5), true); eq(S.BagCheck(2, 2), false, "schon gewarnt"); eq(S.BagCheck(1, nil), true)
        eq(S.BagCheck(6, 2), false)
        local pick = S.Suggest({
            { id = 1, name = "Grauer Kram", quality = 0, price = 50, count = 1 },
            { id = 2, name = "Teures Grünes", quality = 2, price = 5000, count = 1 },
            { id = 3, name = "Billiges Weißes", quality = 1, price = 3, count = 2 },
            { id = 4, name = "Questgegenstand", quality = 1, price = 0, count = 1 },
        })
        eq(pick[1].id, 1, "Graues zuerst"); eq(pick[2].id, 3, "dann das Billigste mit Preis")
        eq(#pick, 3); eq(pick[3].id, 2)
    end)

    ---------------------------------------------------------------------
    -- Reparatur
    ---------------------------------------------------------------------
    test("Reparatur: Gildenbank nur wenn gewünscht und erlaubt, sonst eigenes Gold", function()
        eq(S.RepairChoice(0, 100, true, true), nil, "nichts kaputt")
        eq(S.RepairChoice(50, 100, true, true), "guild")
        eq(S.RepairChoice(50, 100, false, true), "own")
        eq(S.RepairChoice(50, 100, true, false), "own")
        eq(S.RepairChoice(500, 100, false, false), "poor")
    end)
end
