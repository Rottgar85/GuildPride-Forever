-- Tests: Testliste des Entwicklers (Core/GuildPrideDevTest.lua)
return function(test, eq, W, ns)
    W.Load("GuildPrideDevTest.lua")
    local T = ns.DevTest
    local function devtest(name, fn)
        test(name, function()
            local old, oldV = GuildPrideDB.devTests, ns.VERSION
            GuildPrideDB.devTests, ns.VERSION = nil, "2.43.1"
            local ok, err = pcall(fn)
            GuildPrideDB.devTests, ns.VERSION = old, oldV
            if not ok then error(err, 0) end
        end)
    end

    devtest("Testliste: Kennungen eindeutig, Angaben vollständig", function()
        local seen = {}
        for _, i in ipairs(T.ITEMS) do
            eq(seen[i[1]], nil, "doppelt: " .. i[1]); seen[i[1]] = true
            eq(type(i[2]) == "string" and type(i[3]) == "string" and i[4]:match("^%d+%.%d+%.%d+$") ~= nil, true, i[1])
        end
        local open, ok, bad = T.Counts()
        eq(open, #T.ITEMS); eq(ok, 0); eq(bad, 0)
    end)

    devtest("Testliste: Klick schaltet offen, geht, geht nicht; Notiz bleibt; Bericht nennt nur Probleme", function()
        eq(T.Click("start"), "ok"); eq(T.Click("start"), "bad")
        T.Note("start", "  Fehler beim Laden  ")
        local open, ok, bad = T.Counts()
        eq(bad, 1); eq(ok, 0); eq(open, #T.ITEMS - 1)
        eq(T.Lines(true)[2].id, "start", "was nicht geht, steht oben")
        eq(T.Text():find("Fehler beim Laden", 1, true) ~= nil, true); eq(T.Text():find("Gruppensuche", 1, true), nil)
        eq(T.Click("start"), nil); eq(GuildPrideDB.devTests.start.note, "Fehler beim Laden", "Notiz bleibt")
        T.Note("start", ""); eq(GuildPrideDB.devTests.start, nil)
        eq(T.Click("gibt es nicht"), nil)
    end)

    devtest("Testliste: Haken gilt nicht mehr, wenn der Punkt in einer neueren Fassung geändert wurde", function()
        local item = { "start", "x", "y", "2.43.1" }
        GuildPrideDB.devTests = { start = { s = "ok", v = "2.42.0" } }
        eq(T.State(item), nil)
        GuildPrideDB.devTests.start.v = "2.43.1"; eq(T.State(item), "ok")
        GuildPrideDB.devTests.start.v = "2.100.0"; eq(T.State(item), "ok", "Zahlen, nicht Text")
        GuildPrideDB.devTests.start = { s = "bad", v = "2.1.0" }; eq(T.State(item), "bad", "Fehler bleibt stehen, bis er behoben ist")
    end)

    devtest("Testliste: Punkte der kommenden Fassung lassen sich schon vor dem Hochladen abhaken", function()
        local item
        for _, i in ipairs(T.ITEMS) do if i[4] ~= "2.1.0" then item = i; break end end
        ns.VERSION = "2.1.0"
        eq(T.Click(item[1]), "ok"); eq(T.State(item), "ok")
        T.Note(item[1], "x"); eq(T.State(item), "ok", "Notiz ändert nichts")
        eq(T.Click(item[1]), "bad"); eq(T.Click(item[1]), nil)
        ns.VERSION = "9.0.0"; T.Click(item[1]); eq(GuildPrideDB.devTests[item[1]].v, "9.0.0")
    end)

    devtest("Testliste: nur für den Entwickler", function()
        local oldDev, oldWin, made = ns.IsDev, ns.ListWindow, 0
        ns.IsDev = function() return false end
        ns.ListWindow = function() made = made + 1 end
        T.Open()
        ns.IsDev, ns.ListWindow = oldDev, oldWin
        eq(made, 0)
    end)
end
