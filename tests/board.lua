-- Tests: Schwarzes Brett nur für bestimmte Ränge (aus tests/run.lua aufgerufen)
-- Gildenliste hier: Tester (ich, Rang 3), Gm (0), Offi (1), Anna (3)
return function(test, eq, W, ns)
    local B = ns.Board
    local function msg(kind, ...) return kind .. ":" .. table.concat({ ... }, "\031") end
    local oldRoster = W.roster
    W.roster = { { "Tester", 3 }, { "Gm", 0 }, { "Offi", 1 }, { "Anna", 3 }, { "Bert", 3 } }
    -- Rangrechte wie in wow.lua (ein früherer Test setzt C_GuildInfo auf nil):
    -- Rang 0 und 1 dürfen die Gildennachricht ändern = Offiziere
    local oldGI = C_GuildInfo
    C_GuildInfo = { GuildRoster = function() end,
        GuildControlGetRankFlags = function(rankOrder) return { [9] = rankOrder <= 2 } end }
    W.Advance(61); W.Fire("GUILD_ROSTER_UPDATE")
    local n = 0
    local function post(sender, ranks, text)
        n = n + 1
        local id = sender .. "-" .. W.server .. "-" .. n
        W.Receive(sender, msg("BRD", id, W.server, sender, W.server, 0, text, ranks))
        return id
    end

    test("Brett mit Rängen: Testaufbau (Gildenliste)", function()
        eq(ns.RankIndexOf("Gm"), 0); eq(ns.RankIndexOf("Tester"), 3)
        eq(ns.IsOfficerName("Offi"), true); eq(ns.IsOfficerName("Anna"), false)
    end)

    test("Brett mit Rängen: mein Rang gewählt -> sichtbar", function()
        local id = post("Offi", "03", "Raid heute")
        local b = B.Current()
        eq(b and b.id, id)
        eq(b.ranks, "03")
    end)

    test("Brett mit Rängen: mein Rang nicht gewählt -> nicht sichtbar, aber gespeichert", function()
        local id = post("Offi", "01", "Nur Offiziere")
        eq(B.Current(), nil, "für mich unsichtbar")
        eq(B.Current(true).id, id, "zum Weitergeben gespeichert")
        eq(ns.BoardText(), nil, "nicht in der Übersicht")
    end)

    test("Brett mit Rängen: ohne Feld (ältere Version) oder leer -> alle", function()
        n = n + 1
        local id = "Offi-" .. W.server .. "-" .. n
        W.Receive("Offi", msg("BRD", id, W.server, "Offi", W.server, 0, "Alte Version"))
        eq(B.Current() and B.Current().id, id)
        local id2 = post("Offi", "", "Für alle")
        eq(B.Current() and B.Current().id, id2)
        eq(B.Current().ranks, nil)
    end)

    test("Brett mit Rängen: Unsinn im Rangfeld wird bereinigt", function()
        eq(B.CleanRanks("9,3;3|0x"), "039")
        eq(B.CleanRanks({ [4] = true, [1] = true, x = true }), "14")
        post("Offi", "|cff1|r;9", "Seltsam")
        eq(B.Current(), nil, "nur Rang 1 und 9")
        eq(B.Current(true).ranks, "19")
    end)

    test("Brett mit Rängen: Nicht-Offizier kann weiterhin nicht aushängen", function()
        local before = B.Current(true).id
        post("Anna", "3", "Freibier")
        eq(B.Current(true).id, before)
    end)

    test("Brett mit Rängen: Aushängen schickt die Ränge mit, Discord nur bei allen", function()
        local oldMe, oldMotd, oldD = W.me, W.canMotd, ns.Discord
        local posted = 0
        ns.Discord = { Post = function() posted = posted + 1 end }
        W.me, W.canMotd = "Offi", true
        W.sent = {}
        eq(B.Post("Nur Ränge 3 und 4", true, { [3] = true, [4] = true }), true)
        eq(#W.sent, 1)
        eq(W.sent[1].msg:sub(-3), "\03134", "Ränge am Ende der Nachricht")
        eq(posted, 0, "nicht nach Discord")
        eq(B.Post("Für alle", true, ""), true)
        eq(posted, 1)
        W.canMotd = false
        local ok, why = B.Post("Ohne Recht", false, "")
        eq(ok, false); eq(why, "rang")
        W.me, W.canMotd, ns.Discord = oldMe, oldMotd, oldD
    end)

    W.roster, C_GuildInfo = oldRoster, oldGI
    W.Advance(61); W.Fire("GUILD_ROSTER_UPDATE")
end
