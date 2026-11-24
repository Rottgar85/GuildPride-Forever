-- Tests: Nutzungs-Statistik (Core/GuildPrideUsage.lua), auf dem Weg des Fehler-Versands
return function(test, eq, W, ns)
    local sent, dev
    local function usagetest(name, fn)
        test(name, function()
            local old = { ns.IsMarked, ns.IsDev, ns.SendAddonMsg, ns.VERSION, ns.Print, GuildPrideDB.usageShare, GuildPrideDB.usage, GuildPrideDB.usageSent, GuildPrideDB.devUsage, UISpecialFrames }
            ns.IsMarked = function(n) return n == "Chef" end
            ns.IsDev = function() return dev end
            ns.SendAddonMsg = function(_, m, channel, to) sent[#sent + 1] = { msg = m, channel = channel, to = to }; return 0 end
            ns.VERSION, ns.Print, dev, sent = "9.9.9", function() end, false, {}
            GuildPrideDB.usageShare, GuildPrideDB.usage, GuildPrideDB.usageSent, GuildPrideDB.devUsage = nil, nil, nil, nil
            UISpecialFrames = { "GuildPrideLoot", "FremdesFenster" }
            W.Load("GuildPrideErrorShare.lua"); W.Load("GuildPrideUsage.lua")
            local ok, err = pcall(fn, ns.Usage)
            ns.IsMarked, ns.IsDev, ns.SendAddonMsg, ns.VERSION, ns.Print, GuildPrideDB.usageShare, GuildPrideDB.usage, GuildPrideDB.usageSent,
                GuildPrideDB.devUsage, UISpecialFrames = unpack(old, 1, 10)
            if not ok then error(err, 0) end
        end)
    end
    local function Hello() W.Receive("Chef", "DVA:" .. ns.CLIENT_TAG, "GUILD") end
    local function Deliver(from)
        local pieces = sent
        dev, sent = true, {}
        for _, m in ipairs(pieces) do W.Receive(from, m.msg, "WHISPER") end
        dev = false
        return sent
    end

    usagetest("Nutzung: ohne Ja wird weder gezählt noch gesendet", function(U)
        eq(U.Count("tab:30"), false); Hello(); eq(#sent, 0)
        GuildPrideDB.usageShare = false
        eq(U.Count("tab:30"), false); Hello(); eq(#sent, 0); eq(GuildPrideDB.usage, nil)
    end)

    usagetest("Nutzung: zählt nur Kurznamen, begrenzt, Ausschalten löscht", function(U)
        GuildPrideDB.usageShare = true
        eq(U.Count("tab:30"), true); eq(U.Count("tab:30"), true); eq(GuildPrideDB.usage.use["tab:30"], 2)
        eq(U.Count("cmd:Hallo Anna"), false, "kein freier Text"); eq(U.Count("x"), false); eq(U.Count(nil), false)
        for i = 1, 100 do U.Count("win:F" .. i) end
        local n = 0
        for _ in pairs(GuildPrideDB.usage.use) do n = n + 1 end
        eq(n, 60)
        GuildPrideDB.usageShare = false; U.Changed(); eq(GuildPrideDB.usage, nil)
    end)

    usagetest("Nutzung: nur an den Entwickler, per Flüstern, einmal am Tag; Bestätigung zieht ab", function(U)
        GuildPrideDB.usageShare = true
        U.Count("tab:30"); U.Count("win:GuildPrideLoot"); U.Count("win:GuildPrideLoot")
        W.Receive("Anna", "DVA:" .. ns.CLIENT_TAG, "GUILD"); eq(#sent, 0, "Anna ist nicht der Entwickler")
        Hello()
        eq(#sent > 0, true)
        for _, m in ipairs(sent) do eq(m.channel, "WHISPER"); eq(m.to, "Chef"); eq(#m.msg <= 255, true); eq(m.msg:sub(1, 4), "DVU:") end
        U.Count("tab:30")   -- nach dem Senden, vor der Bestätigung
        local ack = Deliver("Anna")
        W.Receive("Fremder", ack[1].msg, "WHISPER"); eq(GuildPrideDB.usage.use["tab:30"], 2, "fremde Bestätigung")
        W.Receive("Chef", ack[1].msg, "WHISPER")
        eq(GuildPrideDB.usage.use["tab:30"], 1, "Neues bleibt"); eq(GuildPrideDB.usage.use["win:GuildPrideLoot"], nil)
        sent = {}; W.Advance(700); Hello(); eq(#sent, 0, "erst nach einem Tag")
        W.Advance(21 * 3600); Hello(); eq(#sent > 0, true)
    end)

    usagetest("Entwickler: Auswertung nach Spielern, nie Benutztes mit 0, keine Namen", function(U)
        GuildPrideDB.usageShare = true
        U.Count("tab:30"); U.Count("cmd:loot")
        Hello()
        local pieces = sent
        Deliver("Annabella"); sent = pieces; Deliver("Bert")
        local r = U.Report()
        eq(r.players, 2)
        local by = {}
        for _, x in ipairs(r.list) do by[x.key] = x end
        eq(by["tab:30"].players, 2); eq(by["cmd:loot"].n, 2); eq(by["win:GuildPrideLoot"].players, 0, "nie benutzt")
        eq(by["win:FremdesFenster"], nil); eq(r.list[#r.list].players, 0); eq(r.versions["9.9.9"], 2)
        eq(#U.Lines() > 3, true)
        local function Has(t)
            for k, v in pairs(t) do
                if tostring(k):lower():find("annabella") or tostring(v):lower():find("annabella") then return true end
                if type(v) == "table" and Has(v) then return true end
            end
        end
        eq(Has(GuildPrideDB.devUsage), nil)
        W.Advance(70 * 86400); eq(U.Report().players, 0, "alte fallen heraus")
    end)

    usagetest("Entwickler: wer keiner ist, speichert nichts; Unsinn wird verworfen", function(U)
        GuildPrideDB.usageShare = true
        U.Count("tab:30"); Hello()
        for _, m in ipairs(sent) do W.Receive("Anna", m.msg, "WHISPER") end
        eq(GuildPrideDB.devUsage, nil)
        local F = "\029"
        eq(U.Collect("Unsinn", "c1"), false); eq(U.Collect(table.concat({ "9.9.9", "1", "", "" }, F), "c1"), false, "leer")
        eq(U.Collect(table.concat({ "x", "1", "tab:30=1", "" }, F), "c1"), false, "Version")
        eq(U.Collect(table.concat({ "9.9.9", "9999", "tab:30=1", "" }, F), "c1"), false, "Tage")
        eq(U.Collect(table.concat({ "9.9.9", "1", "tab:30=99999999,tab:40=2", "+a,-b,böse" }, F), "c1"), true)
        eq(GuildPrideDB.devUsage.c1.use["tab:30"], nil, "zu groß"); eq(GuildPrideDB.devUsage.c1.use["tab:40"], 2); eq(#GuildPrideDB.devUsage.c1.off >= 2, true)
    end)

    usagetest("Nutzung: gefragt wird einmal, nie der Entwickler, nie vor der Einführung", function(U)
        local oldIntro = GuildPrideDB.introSeen
        GuildPrideDB.introSeen = nil; eq(U.ShouldAsk(), false)
        GuildPrideDB.introSeen = 5; eq(U.ShouldAsk(), true)
        dev = true; eq(U.ShouldAsk(), false); dev = false
        U.Choose(false); eq(U.ShouldAsk(), false); eq(GuildPrideDB.usageShare, false)
        U.Choose(true); eq(GuildPrideDB.usageShare, true)
        GuildPrideDB.introSeen = oldIntro
    end)
end
