-- Tests: Fehler an den Entwickler senden (Core/GuildPrideErrorShare.lua)
local SEP = "\031"

return function(test, eq, W, ns)
    local S, sent, dev, printed
    -- Neuer Spielstart: Datei frisch laden
    local function Load() W.Load("GuildPrideErrorShare.lua"); S = ns.ErrorShare end
    local function Fresh(share, errors)
        sent, printed = {}, {}
        GuildPrideDB.errorShare, GuildPrideDB.errors, GuildPrideDB.dev = share, errors, nil
        Load()
    end
    local function Err(msg) return { msg = msg, stack = "[Interface/AddOns/GuildPrideForever/Core/X.lua]:1: in main chunk", n = 2, v = "9.9.9", t = 5 } end
    local function sharetest(name, fn)
        test(name, function()
            local old = { ns.IsMarked, ns.IsDev, ns.SendAddonMsg, ns.VERSION, ns.Print, GuildPrideDB.errors }
            ns.IsMarked = function(n) return n == "Chef" end
            ns.IsDev = function() return dev end
            ns.SendAddonMsg = function(_, msg, channel, target) sent[#sent + 1] = { msg = msg, channel = channel, to = target }; return 0 end
            ns.VERSION, dev = "9.9.9", false
            ns.Print = function(t) printed[#printed + 1] = t end
            local ok, err = pcall(fn)
            ns.IsMarked, ns.IsDev, ns.SendAddonMsg, ns.VERSION, ns.Print, GuildPrideDB.errors = unpack(old, 1, 6)
            GuildPrideDB.errorShare, GuildPrideDB.dev = nil, nil
            if not ok then error(err, 0) end
        end)
    end
    local function Hello(sender, channel) W.Receive(sender or "Chef", "DVA:" .. ns.CLIENT_TAG, channel or "GUILD") end

    sharetest("Fehler senden: ohne Zustimmung geht nichts raus", function()
        Fresh(nil, { Err("a") }); Hello(); eq(#sent, 0, "nicht gefragt")
        Fresh(false, { Err("a") }); Hello(); eq(#sent, 0, "abgelehnt")
    end)

    sharetest("Fehler senden: nur an den Entwickler, nie an andere, nur per Flüstern", function()
        Fresh(true, { Err("a") })
        Hello("Fremder"); eq(#sent, 0, "fremder Absender")
        Hello("Anna"); eq(#sent, 0, "Gildenmitglied")
        Hello("Chef"); eq(#sent > 0, true)
        for _, m in ipairs(sent) do
            eq(m.channel, "WHISPER"); eq(m.to, "Chef"); eq(#m.msg <= 255, true, "Länge")
        end
    end)

    sharetest("Fehler senden: andere Spielversion fragt vergeblich", function()
        Fresh(true, { Err("a") })
        W.Receive("Chef", "DVA:X9", "GUILD"); eq(#sent, 0)
    end)

    sharetest("Fehler senden: höchstens fünf Fehler je Anfrage, zweite Anfrage gleich danach bleibt still", function()
        local list = {}
        for i = 1, 8 do list[i] = Err("fehler" .. i) end
        Fresh(true, list); Hello()
        eq(#sent, 5)   -- kurze Fehler: je ein Stück
        Hello(); eq(#sent, 5, "Sperre")
        W.Advance(700); Hello(); eq(#sent, 10, "nach der Sperre wieder")
    end)

    -- Entwickler empfängt: gesendete Stücke an ihn weiterreichen
    local function Deliver(from, list)
        dev = true
        local pieces = list or sent
        sent = {}
        for _, m in ipairs(pieces) do W.Receive(from, m.msg, "WHISPER") end
        dev = false
        return sent
    end
    local function Collected()
        local out = {}
        for _, g in pairs(GuildPrideDB.dev or {}) do out[#out + 1] = g end
        return out
    end

    sharetest("Fehler senden: kommt vollständig an, auch lang, mehrzeilig und mit Sonderzeichen", function()
        local msg = "Core/X.lua:1: Müller|cffff0000 " .. ("ä"):rep(150)
        local e = Err(msg)
        e.stack = "Zeile1\nZeile2 " .. ("x"):rep(400) .. "\nEnde"
        Fresh(true, { e }); Hello()
        eq(#sent > 1, true, "mehrere Stücke")
        Deliver("Anna")
        local c = Collected()
        eq(#c, 1)
        eq(c[1].msg, (msg:gsub("|", "/")), "Text ohne Farbcodes")
        eq(c[1].stack, e.stack); eq(c[1].v, "9.9.9"); eq(c[1].players, 1); eq(c[1].n, 2)
    end)

    sharetest("Fehler senden: Umstände kommen mit, Unsinn darin wird verworfen", function()
        local e = Err("a"); e.ctx = "combat=yes inst=party win=GuildPrideBankLog"
        Fresh(true, { e }); Hello(); Deliver("Anna")
        eq(Collected()[1].ctx, "combat=yes inst=party win=GuildPrideBankLog")
        local e2 = Err("b"); e2.ctx = "|cffff0000böse"
        Fresh(true, { e2 }); Hello(); Deliver("Anna")
        eq(#Collected(), 0)
    end)

    sharetest("Fehler senden: nach der Bestätigung nicht noch einmal", function()
        local e = Err("a")
        Fresh(true, { e }); Hello()
        local ack = Deliver("Anna")
        eq(#ack, 1); eq(ack[1].channel, "WHISPER"); eq(ack[1].to, "Anna")
        W.Receive("Fremder", ack[1].msg, "WHISPER"); eq(e.sent, nil, "fremde Bestätigung zählt nicht")
        W.Receive("Chef", ack[1].msg, "WHISPER"); eq(e.sent, true)
        sent = {}; W.Advance(700); Hello(); eq(#sent, 0)
    end)

    sharetest("Entwickler: gleicher Fehler von zwei Spielern ist ein Eintrag, doppelt gesendet zählt einmal", function()
        Fresh(true, { Err("a") }); Hello()
        local pieces = sent
        Deliver("Anna", pieces); Deliver("Anna", pieces); Deliver("Bert", pieces)
        local c = Collected()
        eq(#c, 1); eq(c[1].players, 2); eq(c[1].n, 4, "2x je Spieler")
    end)

    sharetest("Entwickler: Charakternamen werden nicht gespeichert", function()
        Fresh(true, { Err("a") }); Hello(); Deliver("Annabella")
        eq(#Collected(), 1)
        local function Has(t)
            for k, v in pairs(t) do
                if tostring(k):lower():find("annabella") or tostring(v):lower():find("annabella") then return true end
                if type(v) == "table" and Has(v) then return true end
            end
        end
        eq(Has(GuildPrideDB.dev), nil)
    end)

    sharetest("Entwickler: wer keiner ist, speichert nichts; nur Flüstern zählt", function()
        Fresh(true, { Err("a") }); Hello()
        local pieces = sent
        eq(#pieces, 1)
        for _, m in ipairs(pieces) do W.Receive("Anna", m.msg, "WHISPER") end
        eq(GuildPrideDB.dev, nil, "kein Entwickler")
        dev = true
        for _, m in ipairs(pieces) do W.Receive("Anna", m.msg, "GUILD") end
        eq(#Collected(), 0, "Gildenkanal")
    end)

    sharetest("Entwickler: Müll und Fluten werden begrenzt", function()
        Fresh(true, {})
        dev = true
        W.Receive("Boese", "DVE:" .. table.concat({ "abc", "1", "99", "x" }, SEP), "WHISPER")
        W.Receive("Boese", "DVE:" .. table.concat({ "abc", "2", "1", "x" }, SEP), "WHISPER")
        W.Receive("Boese", "DVE:Unsinn", "WHISPER")
        W.Receive("Boese", "DVE:" .. table.concat({ "abc", "1", "1", "ohne Felder" }, SEP), "WHISPER")
        eq(#Collected(), 0)
        -- ein Absender, viele verschiedene Fehler
        for i = 1, 60 do
            W.Receive("Boese", "DVE:" .. table.concat({ "id" .. i, "1", "1",
                table.concat({ "9.9.9", "1.16.0", "deDE", "1", "", "Fehler " .. i, "" }, "\029") }, SEP), "WHISPER")
        end
        eq(#Collected() <= 20, true, "je Absender begrenzt: " .. #Collected())
        eq(#Collected() > 0, true)
    end)

    sharetest("Entwickler: erledigte Einträge verschwinden aus der Liste, neue Version taucht wieder auf", function()
        Fresh(true, { Err("a") }); Hello(); Deliver("Anna")
        eq(#S.List(), 1)
        S.Done(S.List()[1].key); eq(#S.List(), 0)
        local e = Err("a"); e.v = "9.9.10"; ns.VERSION = "9.9.10"
        GuildPrideDB.errors = { e }; Load(); sent = {}
        Hello(); Deliver("Anna")
        eq(#S.List(), 1); eq(S.List()[1].v, "9.9.10")
    end)

    sharetest("Frage: nur mit eigenem Fehler und nur, solange nicht entschieden", function()
        Fresh(nil, {}); eq(S.ShouldAsk(), false, "kein Fehler")
        Fresh(nil, { Err("a") }); eq(S.ShouldAsk(), true)
        dev = true; eq(S.ShouldAsk(), false, "Entwickler selbst"); dev = false
        Fresh(true, { Err("a") }); eq(S.ShouldAsk(), false)
        Fresh(false, { Err("a") }); eq(S.ShouldAsk(), false)
        S.Choose(true); eq(GuildPrideDB.errorShare, true)
        S.Choose(false); eq(GuildPrideDB.errorShare, false)
    end)
end
