-- Tests: „Heute“ auf der Übersicht (Guild/GuildPrideToday.lua)
return function(test, eq, W, ns)
    W.Load("GuildPrideToday.lua")
    local T = ns.Today
    local function has(lines, text)
        for _, l in ipairs(lines) do if l:find(text, 1, true) then return true end end
        return false
    end
    local function todaytest(name, fn)
        test(name, function()
            local old = { GuildPrideDB.ahOwned, HasNewMail, ns.CraftMini, ns.Questions, ns.IsOfficer, ns.AH and ns.AH.Orders }
            local events, apps = ns.GuildTable("events"), ns.GuildTable("apps")
            local keepE, keepA = {}, {}
            for k, v in pairs(events) do keepE[k] = v end
            for k, v in pairs(apps) do keepA[k] = v end
            wipe(events); wipe(apps)
            GuildPrideDB.ahOwned, HasNewMail, ns.CraftMini, ns.Questions = nil, function() return false end, nil, nil
            ns.IsOfficer = function() return false end
            ns.AH.Orders = function() return {} end
            local ok, err = pcall(fn, math.floor(W.server), events, apps)
            wipe(events); wipe(apps)
            for k, v in pairs(keepE) do events[k] = v end
            for k, v in pairs(keepA) do apps[k] = v end
            GuildPrideDB.ahOwned, HasNewMail, ns.CraftMini, ns.Questions, ns.IsOfficer, ns.AH.Orders = unpack(old, 1, 6)
            if not ok then error(err, 0) end
        end)
    end

    todaytest("Heute: nichts los ergibt keine Zeile; eine kaputte Quelle stört die anderen nicht", function()
        eq(#T.Lines(), 0)
        local text, n0 = T.Text(); eq(text:find(ns.L["Heute steht nichts an."], 1, true) ~= nil, true); eq(n0, 1)
        HasNewMail = function() return true end
        ns.CraftMini = { CooldownList = function() error("kaputt", 0) end }
        local n = #W.swallowed
        eq(#T.Lines(), 1); eq(#W.swallowed, n + 1)
        W.swallowed[#W.swallowed] = nil
    end)

    todaytest("Heute: Events der nächsten 24 Stunden mit eigener Antwort, nach Zeit", function(now, events)
        events.a = { id = "a", title = "Später Raid", t = now + 7200, signups = { [ns.Me()] = { s = "yes" } } }
        events.b = { id = "b", title = "Früher Raid", t = now + 3600, signups = {} }
        events.c = { id = "c", title = "Übermorgen", t = now + 2 * 86400, signups = {} }
        events.d = { id = "d", title = "Gelöscht", t = now + 3600, deleted = true }
        events.e = { id = "e", title = "Vorbei", t = now - 60, signups = {} }
        local l = T.Lines()
        eq(#l, 2); eq(l[1]:find("Früher Raid", 1, true) ~= nil, true)
        eq(has(l, ns.L["du bist dabei"]), true); eq(l[1]:find(ns.L["noch keine Antwort von dir"], 1, true) ~= nil, true)
    end)

    todaytest("Heute: fertige Abklingzeiten nennen den Twink, laufende nicht", function()
        ns.CraftMini = { CooldownList = function()
            return { { name = "Twinki", what = "Arkanit", ready = true }, { name = "Twinki", what = "Mondstoff", ready = false } }
        end }
        local l = T.Lines()
        eq(#l, 1); eq(has(l, "Arkanit"), true); eq(has(l, "Twinki"), true); eq(has(l, "Mondstoff"), false)
    end)

    todaytest("Heute: Auktionen – laufen ab, abgelaufen, verkauft; Briefkasten räumt auf", function(now)
        T.NoteOwned({ { auctionID = 1, timeLeft = 3600 }, { auctionID = 2, timeLeft = 2 * 86400 }, { auctionID = 3, timeLeft = 60 },
            { auctionID = 4, sold = true }, { auctionID = 5 } }, now)
        local a = T.Auctions(now); eq(a.soon, 2); eq(a.over, 0); eq(a.sold, 1)
        a = T.Auctions(now + 120); eq(a.soon, 1); eq(a.over, 1)
        T.Sold(1); a = T.Auctions(now + 120); eq(a.soon, 0); eq(a.sold, 2, "verkauft zählt nicht mehr als ablaufend")
        T.Sold(nil); eq(T.Auctions(now).sold, 3)
        eq(#T.Lines(), 1)
        T.MailOpened(now + 120); a = T.Auctions(now + 120); eq(a.sold, 0); eq(a.over, 0); eq(a.soon, 0)
        GuildPrideDB.ahOwned = { Twink = { ends = { [9] = now + 10 }, sold = 1 }, Kaputt = 5 }
        a = T.Auctions(now); eq(a.soon, 1); eq(a.sold, 1, "Twinks zählen mit")
        a = T.Auctions(now + 40 * 86400); eq(a.over, 0, "uralte Auktionen zählen nicht mehr")
    end)

    todaytest("Heute: Offiziere sehen offene Fragen und neue Bewerbungen, alle die Gildenaufträge", function(_, _, apps)
        ns.Questions = { OpenCount = function() return 2 end }
        apps.x = { id = "x", status = "new" }; apps.y = { id = "y", status = "declined" }
        ns.AH.Orders = function() return { { owner = "A" }, { owner = "B", by = "C" }, { owner = ns.Me(), mine = true } } end
        eq(#T.Lines(), 1, "nur der offene fremde Auftrag")
        ns.IsOfficer = function() return true end
        eq(#T.Lines(), 3)
    end)
end
