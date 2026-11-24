-- Tests: Loot-Verlauf, Album, Abklingzeiten, Paten, Quiz, Schnitzeljagd, Suche, Pakete, Lesbarkeit
local SEP = "\031"

return function(test, eq, W, ns)
    local oldRoster, oldGuildInfo = W.roster, C_GuildInfo
    W.roster = { { "Tester", 3 }, { "Gm", 0 }, { "Offi", 1 }, { "Anna", 3 }, { "Bert", 3 }, { "Carl", 3 } }
    C_GuildInfo = { GuildRoster = function() end, GuildControlGetRankFlags = function(rankOrder) return { [9] = rankOrder <= 2 } end }
    W.Advance(61); W.Fire("GUILD_ROSTER_UPDATE")
    for _, f in ipairs({ "Loot", "Album", "Cooldowns", "Mentor", "Quiz", "Hunt", "Search", "Readable" }) do W.Load("GuildPride" .. f .. ".lua") end
    local function msg(kind, ...) return kind .. ":" .. table.concat({ ... }, SEP) end

    test("Loot: eigene und fremde Beute lesen, erst ab selten, Filter nach Name", function()
        local old = { LOOT_ITEM, LOOT_ITEM_MULTIPLE, LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE }
        LOOT_ITEM, LOOT_ITEM_MULTIPLE = "%s bekommt Beute: %s.", "%s bekommt Beute: %sx%d."
        LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE = "Ihr erhaltet Beute: %s.", "Ihr erhaltet Beute: %sx%d."
        local link = "|cffa335ee|Hitem:19019::::::::60|h[Donnerzorn]|h|r"
        local Lo = ns.Loot
        local who, id = Lo.Parse("Anna bekommt Beute: " .. link .. ".")
        eq(who, "Anna"); eq(id, 19019)
        who, id = Lo.Parse("Ihr erhaltet Beute: " .. link .. "x2.")
        eq(who, ns.Me()); eq(id, 19019)
        eq(Lo.Parse("Anna lacht."), nil)
        eq(Lo.Add("Anna", 19019, 4, "MC"), true); eq(Lo.Add("Bert", 2589, 1, "MC"), false, "gewöhnlich")
        eq(Lo.Add("Bert", 18832, 3, "MC"), true)
        eq(#Lo.Find(""), 2); eq(#Lo.Find("ann"), 1); eq(Lo.Find("")[1].who, "Bert", "neueste zuerst")
        LOOT_ITEM, LOOT_ITEM_MULTIPLE, LOOT_ITEM_SELF, LOOT_ITEM_SELF_MULTIPLE = unpack(old, 1, 4)
    end)

    test("Album: nur der erste Sieg je Boss, neueste zuerst", function()
        eq(ns.Album.Add("Onyxia", "Hort", 100), true); eq(ns.Album.Add("Onyxia", "Hort", 200), false)
        eq(ns.Album.Add("Ragnaros", "MC", 300), true); eq(ns.Album.Add("", "MC"), false)
        local lines = ns.Album.Lines()
        eq(#lines, 2); eq(lines[1]:find("Ragnaros", 1, true) ~= nil, true)
    end)

    test("Abklingzeiten: bekannte Zauber, geprüfte Meldungen, läuft ab", function()
        local C = ns.Cooldowns
        wipe(C.data)
        W.Receive("Anna", msg("CDN", "20484", "1800"))
        eq(C.Left("Anna", 20484) > 1700, true)
        W.Receive("Bert", msg("CDN", "1", "99999")); eq(C.data.Bert, nil, "unbekannter Zauber")
        W.Receive("Bert", msg("CDN", "20484", "999999")); eq(C.Left("Bert", 20484) <= 1800, true, "höchstens die echte Zeit")
        W.Advance(1900); eq(C.Left("Anna", 20484), 0)
        W.Receive("Carl", msg("FWD", "Anna", "c1", msg("CDN", "20484", "1800"))); eq(C.Left("Anna", 20484), 0, "nie weitergeleitet")
    end)

    test("Paten: melden, zurückziehen, nur für sich selbst; Neue nach Beitrittsdatum", function()
        local M = ns.Mentor
        W.sent = {}
        M.Set(true); eq(M.Is(ns.Me()), true); eq(W.sent[1].kind, "PAT")
        W.Receive("Anna", msg("PAT", W.server, "1")); eq(M.Is("Anna"), true)
        W.Receive("Anna", msg("PAT", W.server - 500, "0")); eq(M.Is("Anna"), true, "ältere Meldung")
        W.Advance(5); W.Receive("Anna", msg("PAT", W.server, "0")); eq(M.Is("Anna"), false)
        W.Receive("Carl", msg("FWD", "Bert", "p1", msg("PAT", W.server, "1"))); eq(M.Is("Bert"), false)
        M.Set(false); eq(M.Is(ns.Me()), false)
        local h = ns.GuildTable("history")
        local keep = h.Bert
        h.Bert = { first = W.server - 5 * 86400, joins = {}, leaves = {}, ranks = {} }
        eq(M.IsNew("Bert"), true)
        h.Bert.first = W.server - 60 * 86400; eq(M.IsNew("Bert"), false)
        h.Bert = keep
    end)

    test("Quiz: Offizier startet, erste richtige Antwort gewinnt, Punkte nur vom Starter", function()
        local Q = ns.Quiz
        local sent, old = {}, ns.SendAddonMsg
        ns.SendAddonMsg = function(_, m, channel, to) sent[#sent + 1] = { msg = m, channel = channel, to = to }; return 0 end
        local ok, err = pcall(function()
            W.canMotd = false; eq(Q.Start("Hauptstadt?", "Sturmwind"), false)
            W.canMotd = true; W.sent = {}
            eq(Q.Start("Hauptstadt der Allianz?", "Sturmwind"), true)
            W.canMotd = false
            eq(W.sent[1].msg:find("Sturmwind", 1, true), nil, "Antwort wird nicht verschickt")
            local id = Q.own.id
            W.Receive("Anna", msg("QZA", id, "Eisenschmiede"), "WHISPER"); eq(Q.Points("Anna"), 0)
            W.Receive("Bert", msg("QZA", id, "  sturmwind "), "WHISPER"); eq(Q.Points("Bert"), 1, "Groß/klein egal")
            W.Receive("Carl", msg("QZA", id, "Sturmwind"), "WHISPER"); eq(Q.Points("Carl"), 0, "zu spät")
            -- Frage eines anderen
            W.Receive("Anna", msg("QZQ", "Anna-1", "60", "Trick?")); eq(Q.cur, nil, "Anna ist kein Offizier")
            W.Receive("Offi", msg("QZQ", "Offi-1", "60", "Wer bin ich?")); eq(Q.cur.text, "Wer bin ich?")
            sent = {}
            Q.Answer("Offi"); eq(sent[1].channel, "WHISPER"); eq(sent[1].to, "Offi")
            W.Receive("Anna", msg("QZR", "Offi-1", "Anna", "x")); eq(Q.Points("Anna"), 0, "nur der Starter verkündet")
            W.Receive("Offi", msg("QZR", "Offi-1", "Carl", "Offi")); eq(Q.Points("Carl"), 1); eq(Q.cur, nil)
        end)
        ns.SendAddonMsg = old
        W.canMotd = false
        if not ok then error(err, 0) end
    end)

    test("Schnitzeljagd: nur Offiziere, Stationen der Reihe nach, Ziel melden", function()
        local H = ns.Hunt
        local oldZ, dist = ns.Zettel, 999
        ns.Zettel = { Distance = function() return dist end }
        H.cur = nil
        W.Receive("Anna", msg("HNT", "Anna-1", "1", "1", "1429", "100", "200", "hier")); eq(H.cur, nil)
        W.Receive("Offi", msg("HNT", "Offi-9", "2", "2", "1429", "300", "400", "zwei")); H.Check(); eq(H.cur.at, 1, "noch unvollständig")
        W.Receive("Offi", msg("HNT", "Offi-9", "1", "2", "1429", "100", "200", "eins")); eq(H.cur.told, true)
        H.Check(); eq(H.cur.at, 1, "zu weit weg")
        dist = 10; H.Check(); eq(H.cur.at, 2)
        W.sent = {}; H.Check(); eq(H.cur.at, 3); eq(W.sent[1].kind, "HNF")
        W.Receive("Anna", msg("HNF", "Offi-9")); eq(H.cur.done.Anna, true)
        W.Receive("Anna", msg("HNX", "Offi-9")); eq(H.cur ~= nil, true, "nur Offiziere beenden")
        W.Receive("Offi", msg("HNX", "Offi-9")); eq(H.cur, nil)
        W.Receive("Offi", msg("HNT", "Offi-10", "1", "99", "1429", "1", "1", "x")); eq(H.cur, nil, "zu viele Stationen")
        ns.Zettel = oldZ
    end)

    test("Suche: findet Mitglieder, Befehle, Einstellungen und Werkzeuge; leere Suche ist leer", function()
        local S = ns.Search
        local oldOpt = ns.SettingOptions
        ns.SettingOptions = { { header = "Kopf" }, { key = "minimap", label = "Minimap-Knopf anzeigen" } }
        eq(#S.Find(""), 0); eq(#S.Find("x"), 0, "ein Zeichen reicht nicht")
        local function has(list, kind, text)
            for _, r in ipairs(list) do if r.kind == kind and r.text:find(text, 1, true) then return true end end
            return false
        end
        eq(has(S.Find("ann"), "member", "Anna"), true)
        eq(has(S.Find("minimap"), "setting", "Minimap"), true)
        eq(has(S.Find("handwerk"), "command", "/gp handwerk"), true)
        eq(#S.Find("gibtesnichtxyz"), 0)
        eq(#S.Find("er") <= 40, true)
        ns.SettingOptions = oldOpt
    end)

    test("Pakete: schalten passend um und lassen den Rest in Ruhe", function()
        local keep = {}
        for k, v in pairs(GuildPrideDB) do keep[k] = v end
        GuildPrideDB.chatFont = 15
        eq(ns.ApplyPreset("guild"), true)
        eq(GuildPrideDB.craftCard, false); eq(GuildPrideDB.ahTooltip, false); eq(GuildPrideDB.memberAlerts, true); eq(GuildPrideDB.raidReady, false)
        eq(ns.ApplyPreset("raid"), true); eq(GuildPrideDB.raidReady, true); eq(GuildPrideDB.buffFood, true); eq(GuildPrideDB.craftCard, false)
        eq(ns.ApplyPreset("all"), true); eq(GuildPrideDB.craftCard, true); eq(GuildPrideDB.raidReady, true)
        eq(GuildPrideDB.chatFont, 15, "Schrift bleibt"); eq(GuildPrideDB.errorShare, keep.errorShare, "Zustimmung bleibt")
        eq(ns.ApplyPreset("quatsch"), false)
        for k in pairs(GuildPrideDB) do GuildPrideDB[k] = nil end
        for k, v in pairs(keep) do GuildPrideDB[k] = v end
    end)

    test("Lesbarkeit: Farben nur mit Schalter umsetzen", function()
        GuildPrideDB.colorSafe = nil
        eq(ns.ColorSafe("|cff40ff40ja|r"), "|cff40ff40ja|r")
        GuildPrideDB.colorSafe = true
        eq(ns.ColorSafe("|cff40ff40ja|r |cffFF6060nein|r |cffffd100gold|r"), "|cff56b4e9ja|r |cffe69f00nein|r |cffffd100gold|r")
        GuildPrideDB.colorSafe = nil
    end)

    W.roster, C_GuildInfo = oldRoster, oldGuildInfo
    W.Advance(61); W.Fire("GUILD_ROSTER_UPDATE")
end
