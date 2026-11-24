-- Tests: Verbesserungen an Werkzeugen (Material, Boss-Notizen, Loot, Quiz, Paten, Bereitschaft, Abklingzeiten, Farben)
local SEP = "\031"

return function(test, eq, W, ns)
    local oldRoster, oldGuildInfo = W.roster, C_GuildInfo
    W.roster = { { "Tester", 3 }, { "Gm", 0 }, { "Offi", 1 }, { "Anna", 3 }, { "Bert", 3 }, { "Carl", 3 } }
    C_GuildInfo = { GuildRoster = function() end, GuildControlGetRankFlags = function(rankOrder) return { [9] = rankOrder <= 2 } end }
    W.Advance(61); W.Fire("GUILD_ROSTER_UPDATE")
    local function msg(kind, ...) return kind .. ":" .. table.concat({ ... }, SEP) end

    test("Material: Item über Link, ID oder Namen finden; Bestand der Gildenbank zählt mit", function()
        local M, oldItem, oldCraft = ns.Stock, C_Item, GuildPrideDB.ahCraft
        local oldBags, oldCont = NUM_BAG_SLOTS, C_Container
        NUM_BAG_SLOTS, C_Container = 0, { GetContainerNumSlots = function() return 0 end }
        C_Item = { GetItemInfo = function(x)
            local names = { [13444] = "Mächtiger Manatrank", [2589] = "Leinenstoff" }
            if names[tonumber(x)] then return names[tonumber(x)], "|Hitem:" .. x .. "::|h[x]|h" end
        end }
        GuildPrideDB.ahCraft = { [13444] = { made = 1, r = { { 2589, 2 } } } }
        eq(M.Resolve("|cffffffff|Hitem:13444::::|h[x]|h|r"), 13444); eq(M.Resolve(" 2589 "), 2589)
        eq(M.Resolve("Mächtiger Manatrank"), 13444); eq(M.Resolve("leinen"), 2589, "Teil des Namens")
        eq(M.Resolve("gibt es nicht"), nil); eq(M.Resolve(""), nil)
        C_Item, GuildPrideDB.ahCraft = oldItem, oldCraft
        NUM_BAG_SLOTS, C_Container = oldBags, oldCont
        W.canMotd = true
        for _, g in ipairs(M.List()) do M.Remove(g.id) end
        M.Add(13444, 20)
        W.canMotd = false
        M.SetBank({ [13444] = 15, [2589] = 3 })
        local g = M.List()[1]
        eq(g.bank, 15); eq(g.sum, 0); eq(g.open, 5, "fehlt noch")
        M.Pledge(g.id, 9); eq(M.List()[1].open, 0, "nie unter null")
    end)

    test("Boss-Notizen: mehrere Zeilen und Vorlage", function()
        local B = ns.BossNotes
        W.canMotd = true
        eq(B.Save(nil, "dm", "Zeilenboss", "Tank: links\nHeiler: hinten"), true)
        W.canMotd = false
        local e
        for _, x in ipairs(B.For("dm")) do if x.boss == "Zeilenboss" then e = x end end
        eq(e.text, "Tank: links // Heiler: hinten"); eq(B.Show(e.text), "Tank: links\nHeiler: hinten")
        eq(type(B.TEMPLATE), "string")
    end)

    test("Loot: Abgleich nur von Offizieren, ohne Doppelte, nicht aus der Zukunft", function()
        local Lo = ns.Loot
        wipe(ns.GuildTable("loot"))
        local t = W.server - 100
        W.Receive("Anna", msg("LTL", t, "Bert", "19019", "4")); eq(#Lo.Find(""), 0, "kein Offizier")
        W.Receive("Offi", msg("LTL", t, "Bert", "19019", "4")); eq(#Lo.Find(""), 1)
        W.Receive("Offi", msg("LTL", t + 30, "Bert", "19019", "4")); eq(#Lo.Find(""), 1, "gleiche Beute")
        W.Receive("Offi", msg("LTL", W.server + 99999, "Bert", "18832", "4")); eq(#Lo.Find(""), 1, "Zukunft")
        W.Receive("Offi", msg("LTL", t - 500, "Anna", "18832", "9")); eq(#Lo.Find(""), 1, "unbekannte Qualität")
        W.Receive("Offi", msg("LTL", t - 500, "Anna", "18832", "3")); eq(Lo.Find("")[1].who, "Bert", "nach Zeit sortiert")
        -- Antworten schickt nur ein Offizier
        W.sent = {}
        W.Receive("Carl", msg("LTQ", "0"))
        for _, m in ipairs(W.sent) do eq(m.kind ~= "LTL", true, "Tester ist kein Offizier") end
        W.roster[1][2] = 1; W.Advance(61); W.Fire("GUILD_ROSTER_UPDATE"); W.sent = {}
        W.Receive("Carl", msg("LTQ", "0"))
        local n = 0
        for _, m in ipairs(W.sent) do if m.kind == "LTL" then n = n + 1 end end
        eq(n, 2)
        W.roster[1][2] = 3; W.Advance(61); W.Fire("GUILD_ROSTER_UPDATE")
    end)

    test("Quiz: Rangliste nur von Offizieren übernehmen, der höhere Stand gilt", function()
        local Q = ns.Quiz
        wipe(ns.GuildTable("quizPoints"))
        W.Receive("Anna", msg("QPL", "Anna=99")); eq(Q.Points("Anna"), 0)
        W.Receive("Offi", msg("QPL", "Anna=3,Bert=1,Fremder=7,Carl=abc")); eq(Q.Points("Anna"), 3); eq(Q.Points("Fremder"), 0); eq(Q.Points("Carl"), 0)
        W.Receive("Offi", msg("QPL", "Anna=2")); eq(Q.Points("Anna"), 3)
    end)

    test("Paten: Hinweis auf Neue einmal je Sitzung, nur für Paten", function()
        local M, said, oldPrint = ns.Mentor, {}, ns.Print
        local h = ns.GuildTable("history")
        local keep = h.Bert
        h.Bert = { first = W.server - 2 * 86400, joins = {}, leaves = {}, ranks = {} }
        ns.Print = function(t) said[#said + 1] = t end
        M.Set(false); M.CheckNew(); eq(#said, 0)
        M.Set(true); M.CheckNew(); eq(#said, 1); M.CheckNew(); eq(#said, 1, "nur einmal")
        M.Set(false)
        ns.Print, h.Bert = oldPrint, keep
    end)

    test("Bereitschaft: Item-Art schlägt Namen, Mindestmenge einstellbar", function()
        local R = ns.Ready
        eq(R.KindOf("Komischer Name", 0, 1), "pot"); eq(R.KindOf("Komischer Name", 0, 2), "elix"); eq(R.KindOf("Komischer Name", 0, 3), "elix")
        eq(R.KindOf("Großer Heiltrank", 0, 0), "pot", "Unterart unbekannt: Name"); eq(R.KindOf("Großer Heiltrank", 9, 0), nil, "Rezept (Klasse 9)")
        local s = { dur = 100, broken = 0, food = true, pots = 4, elix = 0, foods = 0 }
        GuildPrideDB.readyMinPots = nil; eq(#R.Problems(s), 0)
        GuildPrideDB.readyMinPots = 5; eq(#R.Problems(s), 1)
        GuildPrideDB.readyMinPots = nil
    end)

    test("Abklingzeiten: echte Zeit aus dem Spiel, sonst Tabelle; nie länger als die Tabelle", function()
        local C, old = ns.Cooldowns, C_Spell
        C_Spell = { GetSpellCooldown = function() return { startTime = 1, duration = 1200 } end }
        eq(C.Duration(20484, 20484), 1200)
        C_Spell = { GetSpellCooldown = function() return { startTime = 1, duration = 1.5 } end }
        eq(C.Duration(20484, 20484), 1800, "nur globale Abklingzeit")
        C_Spell = { GetSpellCooldown = function() return { startTime = 1, duration = 99999 } end }
        eq(C.Duration(20484, 20484), 1800)
        C_Spell = old
    end)

    test("Antworten gebündelt: viele Anfragen, eine Antwort je Minute, keine geht verloren", function()
        local old, waiting = C_Timer.After, {}
        C_Timer.After = function(sec, fn) waiting[#waiting + 1] = { sec, fn } end
        local n = 0
        local ok, err = pcall(function()
            for _ = 1, 5 do ns.AnswerSoon("T1", function() n = n + 1 end) end
            eq(#waiting, 1); eq(waiting[1][1] <= 10, true, "erste Antwort bald")
            waiting[1][2](); eq(n, 1)
            W.Advance(5); ns.AnswerSoon("T1", function() n = n + 1 end)
            eq(#waiting, 2); eq(waiting[2][1] >= 50, true, "nächste erst nach der Minute: " .. waiting[2][1])
            waiting[2][2](); eq(n, 2, "aber sie kommt")
            ns.AnswerSoon("T2", function() end); eq(waiting[3][1] <= 10, true, "andere Art unabhängig")
        end)
        C_Timer.After = old
        if not ok then error(err, 0) end
    end)

    test("Aufräumen: gelöschte Einträge nach 60 Tagen weg, lebende bleiben", function()
        local db = { a = { deleted = true, ver = W.server - 61 * 86400 }, b = { deleted = true, ver = W.server - 10 * 86400 }, c = { ver = 5 } }
        eq(ns.PruneDeleted(db), 1); eq(db.a, nil); eq(db.b ~= nil, true); eq(db.c ~= nil, true)
    end)

    test("Gemeinsamer Takt: jede Aufgabe in ihrem Abstand, ein Fehler stört die anderen nicht", function()
        local n, oldEH, caught = 0, geterrorhandler, 0
        geterrorhandler = function() return function() caught = caught + 1 end end
        local on = true
        ns.Every(1, function() if on then error("kaputt") end end)
        ns.Every(3, function() if on then n = n + 1 end end)
        for _ = 1, 9 do ns.Beat() end
        on = false
        geterrorhandler = oldEH
        eq(n, 3); eq(caught, 9)
    end)

    test("Befehle: gemeinsame Liste, Groß/klein egal, Rest wird übergeben, Unbekanntes geht weiter", function()
        local got
        ns.Command({ "probe", "try" }, function(rest) got = rest end)
        eq(ns.RunCommand("Probe Hallo Welt"), true); eq(got, "Hallo Welt")
        eq(ns.RunCommand("try"), true); eq(got, ""); eq(ns.RunCommand("unbekanntxyz"), false); eq(ns.RunCommand(""), false); eq(ns.RunCommand(nil), false)
    end)

    W.roster, C_GuildInfo = oldRoster, oldGuildInfo
    W.Advance(61); W.Fire("GUILD_ROSTER_UPDATE")
end
