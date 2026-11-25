-- Tests: Rezept-Verzeichnis (Crafting/GuildPrideCraftCatalog.lua) und Rezept-Lücken (Crafting/GuildPrideCraftGaps.lua)
return function(test, eq, W, ns)
    if not ns.CraftGuides then W.Load("GuildPrideCraftGuides.lua") end
    if not ns.ListWindow then W.Load("GuildPrideListWindow.lua") end
    W.Load("GuildPrideCraftCatalog.lua"); W.Load("GuildPrideCraftGaps.lua")
    local K, P = ns.CraftCatalog, ns.CraftGaps
    local LINK = "trade:Player-6941-0000000B:2108:165"

    local function gaptest(name, fn)
        test(name, function()
            local db, saved = ns.GuildTable("crafts"), {}
            local roster, savedRoster = ns.GuildTable("craftsRoster"), {}
            for k, v in pairs(db) do saved[k] = v end
            for k, v in pairs(roster) do savedRoster[k] = v end
            local old = { GuildPrideDB.craftAll, GuildPrideDB.craftCatalog, GuildPrideDB.craftChars, C_TradeSkillUI, GetBuildInfo, InCombatLockdown, ns.Crafts.RecipeName }
            local oldAfter, timers = C_Timer.After, {}
            wipe(db); wipe(roster)
            GuildPrideDB.craftAll, GuildPrideDB.craftCatalog, GuildPrideDB.craftChars = nil, nil, nil
            C_Timer.After = function(_, f) timers[#timers + 1] = f end
            local names = { [101] = "Zwirn", [102] = "Axt", [103] = "Umhang", [104] = "Bohrer" }
            ns.Crafts.RecipeName = function(id) return names[id] end
            local function Step() local t = timers; timers = {}; for _, f in ipairs(t) do f() end end
            local ok, err = pcall(fn, { db = db, roster = roster, step = Step })
            C_Timer.After = oldAfter
            GuildPrideDB.craftAll, GuildPrideDB.craftCatalog, GuildPrideDB.craftChars, C_TradeSkillUI, GetBuildInfo, InCombatLockdown, ns.Crafts.RecipeName = unpack(old, 1, 7)
            wipe(db); wipe(roster)
            for k, v in pairs(saved) do db[k] = v end
            for k, v in pairs(savedRoster) do roster[k] = v end
            if not ok then error(err, 0) end
        end)
    end

    gaptest("Rezept-Verzeichnis: sammelt aus allen Quellen, ohne Doppelte und Rang-Zauber", function(t)
        GuildPrideDB.craftAll = { [165] = { [2149] = true, [900001] = true, [2108] = true } }
        GuildPrideDB.craftCatalog = { build = "x", lines = { [165] = { 2149, 900002 } } }
        t.db["Bert"] = { profs = {}, rec = { ["Lederverarbeitung"] = { 900003, 2149 }, ["Alchemie"] = { 900004 } }, links = { ["Lederverarbeitung"] = LINK } }
        local seen = {}
        for _, id in ipairs(K.Ids(165)) do eq(seen[id], nil, "doppelt"); seen[id] = true end
        eq(seen[900001] and seen[900002] and seen[900003], true); eq(seen[900004], nil, "anderer Beruf"); eq(seen[2108], nil, "Rang")
        eq(#K.Ids(999), 0)
    end)

    gaptest("Rezept-Verzeichnis: fragt das Spiel einmal je Spielversion, nie im Kampf, in kleinen Stücken", function(t)
        local build, calls, fight, done = "1", 0, true, 0
        GetBuildInfo = function() return "1.60.1", build end
        InCombatLockdown = function() return fight end
        C_TradeSkillUI = { GetProfessionInfoByRecipeID = function(id)
            calls = calls + 1
            if id == 2149 then return { professionID = 2900, parentProfessionID = 165 } end
            if id == 2329 then return { professionID = 171 } end
            return { professionID = 0 }
        end }
        eq(K.Scan(function() done = done + 1 end), true); eq(K.Running(), true)
        t.step(); eq(calls, 0, "im Kampf nicht")
        fight = false
        t.step(); eq(calls > 0 and calls < 5000, true, "ein Stück")
        for _ = 1, 400 do t.step() end
        eq(done, 1); eq(K.Running(), false)
        eq(GuildPrideDB.craftCatalog.build, "1.60.1.1"); eq(GuildPrideDB.craftCatalog.lines[165][1], 2149); eq(GuildPrideDB.craftCatalog.lines[171][1], 2329)
        calls = 0; eq(K.Scan(), false); t.step(); eq(calls, 0, "nur einmal")
        -- liefert das Spiel zu allem denselben Beruf, ist die Antwort unbrauchbar
        build = "2"
        C_TradeSkillUI.GetProfessionInfoByRecipeID = function() return { professionID = 165 } end
        K.Scan(); for _ = 1, 400 do t.step() end
        eq(GuildPrideDB.craftCatalog.lines[165], nil)
    end)

    gaptest("Rezept-Lücken: was niemand kann, wer den Beruf hat, wie viele geteilt haben", function(t)
        GuildPrideDB.craftCatalog = { build = "x", lines = { [165] = { 101, 102, 103, 104, 105 } } }
        t.db["Anna"] = { profs = { { n = "Lederverarbeitung", l = 225, m = 225 } }, rec = { ["Lederverarbeitung"] = { 101 } }, links = { ["Lederverarbeitung"] = LINK } }
        t.db["Bert"] = { profs = { { n = "Leatherworking", l = 90, m = 150 } }, rec = {}, links = {} }           -- englisches Spiel, noch nichts geteilt
        t.roster["Carl"] = { { n = "Lederverarbeitung", l = 1, id = 165 } }                                        -- ohne GuildPride
        t.roster["Anna"] = { { n = "Lederverarbeitung", l = 1, id = 165 } }
        t.roster["Dora"] = { { n = "Schneiderei", l = 1, id = 197 } }
        GuildPrideDB.craftChars = { Tester = { profs = {}, known = { [165] = { [103] = true } } } }                -- eigener Twink
        local r = P.Report(165)
        eq(r.total >= 5, true); eq(r.known, 2)
        local has = {}
        for _, x in ipairs(r.list) do has[x.id] = x.name end
        eq(has[102], "Axt"); eq(has[104], "Bohrer"); eq(has[101], nil); eq(has[103], nil, "kann der Twink"); eq(has[105], nil, "ohne Namen nicht zeigen")
        local low = {}
        for _, x in ipairs(P.Report(165, "AX").list) do low[#low + 1] = x.name end
        eq(table.concat(low, ","), "Axt")
        eq(#r.crafters, 3); eq(r.crafters[1].name, "Anna"); eq(r.crafters[1].level, 225); eq(r.crafters[1].shared, true)
        eq(r.shared, 1)
        eq(P.Report(999).total, 0)
    end)

    gaptest("Rezept-Lücken: Zeilen nennen Stand und Handwerker, leerer Beruf erklärt sich", function(t)
        GuildPrideDB.craftCatalog = { build = "x", lines = { [165] = { 101, 102 } } }
        t.db["Anna"] = { profs = { { n = "Lederverarbeitung", l = 225, m = 225 } }, rec = { ["Lederverarbeitung"] = { 101 } }, links = { ["Lederverarbeitung"] = LINK } }
        local lines = P.Lines(165)
        eq(lines[1].text:find("Anna", 1, true) ~= nil, true); eq(lines[1].id, nil)
        local n = 0
        for _, l in ipairs(lines) do if l.id then n = n + 1 end end
        eq(n >= 1, true)
        eq(#P.Lines(999) >= 1, true)
    end)
end
