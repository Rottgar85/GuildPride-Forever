-- Tests für die Liste der GuildPride-Spieler (aus tests/run.lua aufgerufen)
return function(test, eq, W, ns)
    W.Load("GuildPridePlayers.lua")
    local P = ns.Players
    local function msg(kind, ...) return kind .. ":" .. table.concat({ ... }, "\031") end

    -- offenen Kanal nachbilden (wie in tests/transit.lua)
    local old = { ns.PublicChannelId, ns.IS_FOREVER, ns.PUBLIC_VIA_CHAT, ns.IsPublicChannel, ns.HAS_PUBLIC_LFG, IsInInstance }
    local function publicOn()
        ns.IS_FOREVER, ns.PUBLIC_VIA_CHAT, ns.HAS_PUBLIC_LFG = true, false, true
        IsInInstance = function() return false end
        ns.IsPublicChannel = function(localID) return ns.PublicChannelId and ns.PublicChannelId() == localID end
        GuildPrideDB.publicLFG = true
        ns.PublicChannelId = function() return 7 end
    end
    local function publicOff()
        ns.PublicChannelId, ns.IS_FOREVER, ns.PUBLIC_VIA_CHAT, ns.IsPublicChannel = old[1], old[2], old[3], old[4]
        ns.HAS_PUBLIC_LFG, IsInInstance = old[5], old[6]
        GuildPrideDB.publicLFG = nil
    end
    local function chan(sender, m)
        W.Advance(1)
        W.Fire("CHAT_MSG_ADDON", "GuildPride", m, "CHANNEL", sender, "", 0, 7, "GuildPrideF")
    end

    test("GuildPride-Spieler: Meldungen im offenen Kanal werden gezählt, auch von älteren Versionen", function()
        publicOn()
        P.public = {}
        eq(P.Count(), 1, "nur du")
        chan("Neu-Realm", msg("LYS", "F", "1453", ""))
        chan("Alt-Realm", msg("LYS", "F", "1429", "12777279"))   -- ältere Version schickt noch einen Layer
        chan("Retail-Realm", msg("LYS", "R", "1453", ""))       -- andere Spielversion
        chan("Quatsch|Realm", msg("LYS", "F", "1453", ""))      -- ungültiger Name
        eq(P.Count(), 3, "du + zwei andere")
        local names = {}
        for _, e in ipairs(P.List()) do names[e.name] = e end
        eq(names["Neu"] ~= nil and names["Alt"] ~= nil, true)
        eq(names["Neu"].map, 1453)
        eq(names["Retail"], nil, "andere Spielversion zählt nicht")
        -- nach 25 Minuten ohne Meldung fällt man heraus
        W.Advance(26 * 60)
        eq(P.Count(), 1, "veraltete Meldungen weg")
        publicOff()
    end)

    test("GuildPride-Spieler: selbst melden ohne Layer, nur mit serverweiter Gruppensuche", function()
        publicOn()
        W.sent = {}
        W.Advance(60)
        P.Share(true)
        local lys
        for _, m in ipairs(W.sent) do if m.kind == "LYS" then lys = m end end
        eq(lys ~= nil, true, "gemeldet"); eq(lys.target, "@PUBLIC")
        eq(lys.msg:sub(-1), "\031", "drittes Feld (früher Layer) bleibt leer")
        -- ohne serverweite Gruppensuche: keine Meldung
        GuildPrideDB.publicLFG = nil
        W.sent = {}
        W.Advance(60)
        P.Share(true)
        local any = false
        for _, m in ipairs(W.sent) do if m.kind == "LYS" then any = true end end
        eq(any, false, "Gruppensuche aus: nichts senden")
        publicOff()
    end)
end
