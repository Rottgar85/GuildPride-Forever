-- Tests für die Notizzettel auf der Karte (aus tests/run.lua aufgerufen)
return function(test, eq, W, ns)
    local oldMap = C_Map
    C_Map = { GetMapInfo = function(id) return id == 1429 and { mapType = 3 } or nil end }
    W.Load("GuildPrideZettel.lua")
    local Z = ns.Zettel
    local SEP = "\031"
    local function msg(kind, ...) return kind .. ":" .. table.concat({ ... }, SEP) end
    local function count()
        local n = 0
        for _ in pairs(GuildPrideDB.zettel or {}) do n = n + 1 end
        return n
    end
    local function chan(sender, m)
        W.Advance(1)
        ns.OnZettelPublic(m, ns.Normalize(sender))   -- wie in GuildPride.lua
    end

    test("Zettel: Gildenzettel über den Gildenkanal, blau, mit Unterschrift", function()
        GuildPrideDB.zettel = {}
        W.Receive("Anna", msg("ZTG", 3, 1429, 4123, 6650, W.server, "Hier liegt Kupfer"))
        local n = GuildPrideDB.zettel["g:Anna#3"]
        eq(n ~= nil, true, "angenommen")
        eq(n.guild, true); eq(n.by, "Anna"); eq(n.text, "Hier liegt Kupfer")
        eq(math.floor(n.x * 10000 + 0.5), 4123)
        -- Abreißen geht nur für den Schreiber selbst
        W.Receive("Bert", msg("ZTX", 3))
        eq(GuildPrideDB.zettel["g:Anna#3"] ~= nil, true, "Fremder kann nicht abreißen")
        W.Receive("Anna", msg("ZTX", 3))
        eq(GuildPrideDB.zettel["g:Anna#3"], nil, "Schreiberin reißt ab")
    end)

    test("Zettel: offener Kanal, weiß, geprüft und begrenzt", function()
        GuildPrideDB.zettel = {}
        chan("Fremd", msg("ZTP", ns.CLIENT_TAG, 1, 1429, 100, 200, W.server, "Vorsicht, Elite!"))
        eq(GuildPrideDB.zettel["p:Fremd#1"] ~= nil, true)
        eq(GuildPrideDB.zettel["p:Fremd#1"].guild, nil, "nicht blau")
        chan("Fremd", msg("ZTP", "X", 2, 1429, 100, 200, W.server, "andere Spielversion"))
        chan("Fremd", msg("ZTP", ns.CLIENT_TAG, 3, 9999, 100, 200, W.server, "unbekannte Karte"))
        chan("Fremd", msg("ZTP", ns.CLIENT_TAG, 4, 1429, 100, 200, W.server, "|||"))
        chan("Fremd", msg("ZTP", ns.CLIENT_TAG, 5, 1429, 100, 200, W.server - 8 * 86400, "zu alt"))
        eq(count(), 1, "Unsinn verworfen")
        eq(GuildPrideDB.zettel["p:Fremd#1"].text, "Vorsicht, Elite!")
        for i = 10, 20 do chan("Spam", msg("ZTP", ns.CLIENT_TAG, i, 1429, 1, 1, W.server, "x" .. i)) end
        eq(count(), 1 + 5, "höchstens 5 fremde Zettel je Absender")
    end)

    test("Zettel: eigener Zettel wird verschickt, Gilde und offen getrennt", function()
        GuildPrideDB.zettel = {}
        W.sent = {}
        local oldChan = ns.PublicChannelId
        ns.PublicChannelId = function() return 7 end
        local kg = Z.Write(1429, 0.5, 0.25, "Treffpunkt Raid", true)
        local kp = Z.Write(1429, 0.1, 0.1, "Für alle", false)
        eq(kg ~= kp and kg ~= nil and kp ~= nil, true)
        while Z.SendNext() do end
        eq(#W.sent, 2)
        eq(W.sent[1].kind, "ZTG"); eq(W.sent[1].target, "@CHANNEL")
        eq(W.sent[2].kind, "ZTP"); eq(W.sent[2].target, "@PUBLIC")
        eq(W.sent[1].msg:find("Treffpunkt Raid", 1, true) ~= nil, true)
        eq(#W.sent[2].msg <= 255, true)
        W.sent = {}
        eq(Z.Tear(kp), true)
        while Z.SendNext() do end
        eq(W.sent[1].kind, "ZTD")
        ns.PublicChannelId = oldChan
    end)

    test("Zettel: Unterschrift mit Vor- und Nachname", function()
        GuildPrideDB.zettel = {}
        local oldF, oldMe = ns.IS_FOREVER, W.me
        ns.IS_FOREVER = true
        W.Receive("Anna-Eichenherz", msg("ZTG", 1, 1429, 1, 1, W.server, "Gruß"))
        eq(GuildPrideDB.zettel["g:Anna Eichenherz#1"].by, "Anna Eichenherz")
        chan("Bert-Steinfaust", msg("ZTP", ns.CLIENT_TAG, 1, 1429, 1, 1, W.server, "Hallo"))
        eq(GuildPrideDB.zettel["p:Bert Steinfaust#1"].by, "Bert Steinfaust")
        local oldFull = UnitFullName
        UnitFullName = function() return "Tester", "Langbart" end
        local k = Z.Write(1429, 0.5, 0.5, "Mein Zettel", true)
        eq(GuildPrideDB.zettel[k].by, "Tester Langbart", "eigener Zettel mit Nachnamen")
        UnitFullName, ns.IS_FOREVER, W.me = oldFull, oldF, oldMe
        GuildPrideDB.zettel = {}
    end)

    test("Zettel: Text wird auf 140 Byte gekürzt, ohne Umlaute zu zerschneiden", function()
        local s = Z.Cut(("ä"):rep(100), 140)
        eq(#s, 140); eq(s, ("ä"):rep(70))
        eq(#Z.Cut(("ä"):rep(100), 139), 138)
    end)

    test("Zettel: ausgeschaltet nimmt nichts an", function()
        GuildPrideDB.zettel = {}
        GuildPrideDB.mapNotes = false
        W.Receive("Anna", msg("ZTG", 9, 1429, 1, 1, W.server, "aus"))
        chan("Fremd2", msg("ZTP", ns.CLIENT_TAG, 9, 1429, 1, 1, W.server, "aus"))
        eq(count(), 0)
        GuildPrideDB.mapNotes = nil
    end)

    test("Zettel: Abgleich in der Gilde – Mitglied reicht bekannten Zettel weiter", function()
        GuildPrideDB.zettel, GuildPrideDB.zettelGone = {}, {}
        W.Receive("Anna", msg("ZTG", 4, 1429, 100, 100, W.server, "Erz hier"))
        W.sent = {}
        W.Receive("Bert", msg("ZTQ", 1))          -- Bert fragt beim Einloggen
        while Z.SendNext() do end
        local relay
        for _, s in ipairs(W.sent) do if s.kind == "ZTR" then relay = s end end
        eq(relay ~= nil, true, "Annas Zettel weitergereicht")
        eq(relay.target, "@CHANNEL")
        eq(relay.msg:find("Anna" .. SEP .. "4" .. SEP, 1, true) ~= nil, true, "mit Schreiberin")
        -- Empfänger: Zettel von Carl, weitergereicht durch Bert
        GuildPrideDB.zettel = {}
        W.Receive("Bert", msg("ZTR", "Carl", 9, 1429, 200, 200, W.server, "Treffpunkt"))
        local n = GuildPrideDB.zettel["g:Carl#9"]
        eq(n ~= nil and n.by, "Carl", "unterschrieben von Carl, nicht von Bert")
        -- abgerissen bleibt abgerissen, auch wenn ihn jemand weiterreicht
        W.Receive("Carl", msg("ZTX", 9))
        W.Receive("Bert", msg("ZTR", "Carl", 9, 1429, 200, 200, W.server - 5, "Treffpunkt"))
        eq(GuildPrideDB.zettel["g:Carl#9"], nil, "kommt nicht wieder")
    end)

    test("Zettel: Weitergabe im offenen Kanal braucht zwei Fremde oder ein Gildenmitglied", function()
        GuildPrideDB.zettel, GuildPrideDB.zettelGone = {}, {}
        local T = W.server
        local function relay(from, author, num, text)
            chan(from, msg("ZTS", ns.CLIENT_TAG, author, num, 1429, 300, 300, T, text))
        end
        relay("Fremd1", "Opfer", 1, "Gefälscht")
        eq(GuildPrideDB.zettel["p:Opfer#1"], nil, "ein Fremder allein reicht nicht")
        relay("Fremd2", "Opfer", 1, "Gefälscht")
        eq(GuildPrideDB.zettel["p:Opfer#1"] ~= nil, true, "zwei verschiedene bestätigen")
        relay("Anna", "Wanderer", 2, "Gruß")
        eq(GuildPrideDB.zettel["p:Wanderer#2"] ~= nil, true, "Gildenmitglied gilt sofort")
    end)

    test("Zettel: ausblenden, Spieler ausblenden, nur Gilde zeigen", function()
        GuildPrideDB.zettel, GuildPrideDB.zettelGone, GuildPrideDB.zettelMuted = {}, {}, {}
        local T = W.server
        chan("Laut", msg("ZTP", ns.CLIENT_TAG, 1, 1429, 1, 1, T, "eins"))
        chan("Laut", msg("ZTP", ns.CLIENT_TAG, 2, 1429, 1, 1, W.server, "zwei"))
        eq(Z.Hide("p:Laut#1"), true)
        eq(GuildPrideDB.zettel["p:Laut#1"], nil)
        chan("Laut", msg("ZTP", ns.CLIENT_TAG, 1, 1429, 1, 1, T, "eins"))
        eq(GuildPrideDB.zettel["p:Laut#1"], nil, "ausgeblendeter kommt nicht wieder")
        eq(Z.Mute("Laut"), true)
        eq(GuildPrideDB.zettel["p:Laut#2"], nil, "alle vom Spieler weg")
        chan("Laut", msg("ZTP", ns.CLIENT_TAG, 3, 1429, 1, 1, W.server, "drei"))
        eq(GuildPrideDB.zettel["p:Laut#3"], nil, "künftige auch nicht")
        Z.Unmute("Laut")
        GuildPrideDB.mapNotesPublic = false
        chan("Leise", msg("ZTP", ns.CLIENT_TAG, 1, 1429, 1, 1, W.server, "hallo"))
        eq(GuildPrideDB.zettel["p:Leise#1"], nil, "Zettel für alle aus")
        W.Receive("Anna", msg("ZTG", 7, 1429, 1, 1, W.server, "Gilde geht"))
        eq(GuildPrideDB.zettel["g:Anna#7"] ~= nil, true, "Gildenzettel weiter da")
        GuildPrideDB.mapNotesPublic = nil
    end)

    test("Zettel: Zeichen zählen Umlaute einfach", function()
        eq(Z.Chars("Grüße"), 5)
        eq(Z.Chars(""), 0)
    end)

    C_Map = oldMap
end
