-- Tests für den Schiffs-Zähler (aus tests/run.lua aufgerufen)
return function(test, eq, W, ns)
    W.Load("GuildPrideTransitData.lua")
    W.Load("GuildPrideTransit.lua")
    W.Load("GuildPrideTransitUI.lua")
    local T = ns.Transit
    local ID, ROUTE = "boat-menethil-theramore", "path-292"
    local function msg(kind, ...) return kind .. ":" .. table.concat({ ... }, "\031") end
    local function near(a, b, tol) return math.abs(a - b) <= (tol or 0.01) end

    test("Schiffe: Fahrplandaten aus Polestar sind da", function()
        local s = T.Services()[ID]
        eq(s ~= nil, true); eq(s.kind, "boat")
        eq(T.Routes()[ROUTE].period, 329313)
        local kinds = {}
        for _, v in pairs(T.Services()) do kinds[v.kind] = true end
        eq(kinds.boat and kinds.zeppelin and kinds.airship and true, true)
        eq(kinds.lift, nil, "keine Aufzüge")
    end)

    test("Schiffe: ungemessen nur die mittlere Wartezeit, gemessen der Zähler", function()
        GuildPrideDB.transit = nil
        local b = T.Board(ID, "a")
        eq(b.timed, false); eq(b.wait, 174.7)
        -- Schiff liegt seit 10 s am Steg in Menethil (Halt 1: 54297–114325 ms)
        local now = T.Now()
        eq(T.Sighted(ROUTE, { epoch = now * 1000 - 54297 - 10000, seen = math.floor(now), source = "player" }), true)
        b = T.Board(ID, "a", now)
        eq(b.timed, true); eq(b.arriveIn, 0)
        eq(near(b.departIn, 50.028), true, "legt ab in ~50 s")
        eq(near(b.nextIn, 329.313 - 10), true, "nächstes eine Runde später")
        eq(T.StatusText(b):find("liegt am Steg", 1, true) ~= nil, true)
        local clock, label, color, fill = T.Clock(b)
        eq(clock, "0:51"); eq(label, "legt ab"); eq(color[2] > color[1], true, "grün")
        eq(near(fill, 50.028 / 60.028, 0.001), true, "Balken: Rest der Liegezeit")
        -- 30 s bevor es ankommt
        T.Forget()
        T.Sighted(ROUTE, { epoch = now * 1000 - 54297 + 30000, seen = math.floor(now), source = "player" })
        b = T.Board(ID, "a", now)
        eq(near(b.arriveIn, 30), true); eq(near(b.nextIn, 30 + 329.313), true)
        eq(T.StatusText(b):find("kommt in", 1, true) ~= nil, true)
        clock, label = T.Clock(b)
        eq(clock, "0:30"); eq(label, "kommt an")
        eq(select(1, T.Clock({ timed = false, wait = 174.7 })), "–")
        eq(T.Countdown(65.2), "1:06")
        -- gilt länger als 6 Stunden, mit Alter der Messung …
        local late = T.Board(ID, "a", now + 6 * 3600 + 10)
        eq(late.timed, true, "nach 6 Std. noch gültig")
        eq(T.AgeText(late), "vor 6 Std.")
        eq(T.AgeText(T.Board(ID, "a", now + 2 * 86400 + 5)), "vor 2 Tag(en)")
        -- … verfällt aber nach 7 Tagen
        eq(T.Board(ID, "a", now + 7 * 86400 + 10).timed, false, "nach 7 Tagen verfallen")
        -- … und mit dem wöchentlichen Reset (Wartung startet die Server neu)
        C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 3600 end }   -- Reset vor 6 Tagen 23 Std.
        eq(T.Board(ID, "a", now).timed, true, "nach dem Reset gemessen")
        C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 7 * 86400 - 60 end }   -- Reset vor 1 Min.
        local guess = T.Board(ID, "a", now + 120)
        eq(guess.guess, true, "vor dem Reset gemessen: nur noch Vermutung")
        -- eine Woche weitergerückt (gleicher Abstand zum Reset)
        local b0 = T.Board(ID, "a", now + 120 - 7 * 86400)
        eq(near(guess.arriveIn, b0.arriveIn) and near(guess.departIn, b0.departIn), true, "gleicher Abstand zum Reset")
        C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 60 end }   -- vorletzter Reset: zu alt
        eq(T.Board(ID, "a", now + 15 * 86400).timed, false, "vor dem vorletzten Reset: weg")
        C_DateAndTime = nil
        T.Forget()
    end)

    test("Schiffe: Anleger in der Nähe", function()
        local docks = T.DocksNear(0, -3905.2, -585.8)
        local found
        for _, d in ipairs(docks) do if d.id == ID then found = d end end
        eq(found ~= nil, true); eq(found.side, "a"); eq(found.to, "Theramore")
        eq(#T.DocksNear(1, -3905.2, -585.8), 0, "anderer Kontinent")
        eq(#T.DocksNear(0, -3905.2 + 500, -585.8), 0, "zu weit weg")
    end)

    test("Schiffe: Mitfahren misst den Fahrplan und teilt ihn mit der Gilde", function()
        T.Forget()
        local route = T.Routes()[ROUTE]
        local start = T.Now() * 1000
        local epoch = start - 128093
        local function at(phase)
            local f = route.frames
            for i = 1, #f - 1 do
                local a, b = f[i], f[i + 1]
                if phase >= a[2] and phase <= b[1] and a[3] == b[3] then
                    local t = (phase - a[2]) / math.max(1, b[1] - a[2])
                    return a[4] + t * (b[4] - a[4]), a[5] + t * (b[5] - a[5]), a[3]
                end
            end
        end
        local x, y, map
        UnitPosition = function() return x, y, 0, map end
        UnitOnTaxi = function() return false end
        W.sent = {}
        for _ = 1, 80 do
            x, y, map = at(T.Now() * 1000 - epoch)
            T.Sample()
            W.Advance(1)
        end
        UnitPosition, UnitOnTaxi = nil, nil
        local a = GuildPrideDB.transit.Realm[ROUTE][1]
        eq(a ~= nil, true, "gemessen"); eq(a.source, "you")
        local d = (a.epoch - epoch + route.period / 2) % route.period - route.period / 2
        eq(math.abs(d) < 4000, true, "Epoche stimmt")
        local trs
        for _, m in ipairs(W.sent) do if m.kind == "TRS" then trs = m end end
        eq(trs ~= nil, true, "an die Gilde"); eq(trs.target, nil)
        eq(trs.msg:find("Realm\031" .. ROUTE .. ":", 1, true) ~= nil, true)
        T.Forget()
    end)

    test("Schiffe: Messungen der Gilde – nur Mitglieder, gleicher Realm, nicht weitergeleitet", function()
        T.Forget()
        W.roster = { { W.me, 3 }, { "Anna", 2 }, { "Bert", 2 } }
        W.Fire("GUILD_ROSTER_UPDATE")
        W.Receive("Fremd", msg("TRS", "Realm", ROUTE .. ":" .. W.server .. ":1000"), "WHISPER")
        eq(T.Board(ID, "a").timed, false, "kein Mitglied")
        W.Receive("Anna", msg("TRS", "Anderer", ROUTE .. ":" .. W.server .. ":1000"))
        eq(T.Board(ID, "a").timed, false, "anderer Realm")
        W.Receive("Bert", msg("FWD", "Anna", "9", msg("TRS", "Realm", ROUTE .. ":" .. W.server .. ":1000")))
        eq(T.Board(ID, "a").timed, false, "weitergeleitet")
        W.Receive("Anna", msg("TRS", "Realm", ROUTE .. ":" .. (W.server + 999) .. ":1000"))
        eq(T.Board(ID, "a").timed, false, "aus der Zukunft")
        W.Receive("Anna", msg("TRS", "Realm", ROUTE .. ":" .. W.server .. ":999999999"))
        eq(T.Board(ID, "a").timed, false, "Phase außerhalb der Runde")
        W.Receive("Anna", msg("TRS", "Realm", ROUTE .. ":" .. W.server .. ":1000;unbekannt:1:1"))
        eq(T.Board(ID, "a").timed, true, "gültig")
        eq(GuildPrideDB.transit.Realm[ROUTE][1].source, "player")
        -- Anfrage: eigene Messungen werden per Flüstern beantwortet, fremde nicht
        W.sent = {}
        W.Receive("Bert", msg("TRQ", "1"))
        local any = false
        for _, m in ipairs(W.sent) do if m.kind == "TRS" then any = true end end
        eq(any, false, "nur eigene Messungen werden weitergegeben")
        local now = T.Now()
        T.Sighted(ROUTE, { epoch = now * 1000 - 5000, seen = math.floor(now), source = "you" })
        W.sent = {}
        W.Receive("Anna", msg("TRQ", "1"))
        local reply
        for _, m in ipairs(W.sent) do if m.kind == "TRS" then reply = m end end
        eq(reply ~= nil, true); eq(reply.target, "Anna")
        -- Teilen ist Pflicht: auch mit dem alten Schalter aus wird übernommen
        GuildPrideDB.transitShare = false
        T.Forget()
        W.Receive("Bert", msg("TRS", "Realm", ROUTE .. ":" .. W.server .. ":1000"))
        eq(T.Board(ID, "a").timed, true, "alter Schalter wirkt nicht mehr")
        GuildPrideDB.transitShare = nil
        T.Forget()
    end)

    -- Layer und serverweiten Kanal nachbilden
    ns.Layer = ns.Layer or {}
    local function setLayer(map, id)
        ns.Layer.map, ns.Layer.id = map, id
        C_Map = map and { GetBestMapForUnit = function() return map end } or nil
    end
    local pubSent = {}
    local oldPub, oldTo, oldF, oldChat = ns.PublicChannelId, ns.QueuePublicTo, ns.IS_FOREVER, ns.PUBLIC_VIA_CHAT
    local oldIsPub = ns.IsPublicChannel
    local function publicOn()
        ns.IS_FOREVER, ns.PUBLIC_VIA_CHAT = true, false
        -- GuildPrideEvents.lua wird im Test nicht geladen: offener Kanal = Nummer 7
        ns.IsPublicChannel = function(localID) return ns.PublicChannelId and ns.PublicChannelId() == localID end
        GuildPrideDB.publicLFG = true
        ns.PublicChannelId = function() return 7 end
        ns.QueuePublicTo = function(to, kind, ...) pubSent[#pubSent + 1] = { to = to, kind = kind, msg = kind .. ":" .. table.concat({ ... }, "\031") } end
    end
    local function publicOff()
        ns.PublicChannelId, ns.QueuePublicTo = oldPub, oldTo
        ns.IS_FOREVER, ns.PUBLIC_VIA_CHAT = oldF, oldChat
        ns.IsPublicChannel = oldIsPub
        GuildPrideDB.publicLFG = nil
    end
    local function chan(sender, m)
        W.Advance(31)
        W.Fire("CHAT_MSG_ADDON", "GuildPride", m, "CHANNEL", sender, "", 0, 7, "GuildPrideF")
    end

    test("Schiffe: je Layer eine eigene Zeit – Layer-Wechsel wechselt die Anzeige", function()
        T.Forget()
        local route = T.Routes()[ROUTE]
        local now = T.Now()
        local e1 = now * 1000 - 54297 - 10000          -- Layer 111: liegt seit 10 s am Steg
        local e2 = now * 1000 - 54297 + 30000          -- Layer 222: kommt in 30 s
        T.Sighted(ROUTE, { epoch = e1, seen = math.floor(now), source = "player", tags = { "1437.111" } })
        T.Sighted(ROUTE, { epoch = e2, seen = math.floor(now) - 60, source = "player", tags = { "1437.222" } })
        eq(#GuildPrideDB.transit.Realm[ROUTE], 2, "zwei Layer = zwei Gruppen")
        setLayer(1437, "111")
        local b = T.Board(ID, "a", now)
        eq(b.timed, true); eq(b.layer, true, "dein Layer"); eq(b.arriveIn, 0, "Layer 111: liegt am Steg")
        eq(T.LayerText(b):find("dein Layer", 1, true) ~= nil, true)
        setLayer(1437, "222")
        b = T.Board(ID, "a", now)
        eq(b.layer, true); eq(near(b.arriveIn, 30), true, "Layer 222: kommt in 30 s")
        setLayer(1437, "333")
        b = T.Board(ID, "a", now)
        eq(b.timed, false, "anderer Layer: keine falsche Zeit"); eq(b.otherLayer, true)
        setLayer(nil, nil)
        b = T.Board(ID, "a", now)
        eq(b.timed, true, "Layer unbekannt: neueste Messung"); eq(b.layer, nil); eq(b.arriveIn, 0)
        eq(T.LayerText(b):find("Layer ?", 1, true) ~= nil, true)
        -- gleiche Phase, Layer vom anderen Anleger: gehört zur Gruppe von Layer 111
        T.Sighted(ROUTE, { epoch = e1 + 2000, seen = math.floor(now), source = "player", tags = { "1445.999" } })
        eq(#GuildPrideDB.transit.Realm[ROUTE], 2, "zusammengeführt")
        setLayer(1445, "999")
        eq(T.Board(ID, "b", now).layer, true, "auch am anderen Anleger erkannt")
        -- gleiche Phase, aber widersprüchlicher Layer: eigene Gruppe
        T.Sighted(ROUTE, { epoch = e1, seen = math.floor(now), source = "player", tags = { "1437.444" } })
        eq(#GuildPrideDB.transit.Realm[ROUTE], 3, "Widerspruch = neue Gruppe")
        -- alte Speicherform (eine Messung) wird übernommen
        GuildPrideDB.transit.Realm[ROUTE] = { epoch = e1, seen = math.floor(now), source = "you" }
        setLayer(nil, nil)
        eq(T.Board(ID, "a", now).timed, true, "alte Speicherform")
        eq(#GuildPrideDB.transit.Realm[ROUTE], 1)
        -- Kodieren mit Layern; ältere Nachrichten ohne Layer werden weiter gelesen
        local enc = T._Encode(ROUTE, { epoch = e1, seen = math.floor(now), tags = { "1437.111", "1445.999" } })
        eq(enc:find(":1437.111,1445.999$") ~= nil, true, "Layer im Eintrag")
        local dec = T._Decode(enc .. ";" .. ROUTE .. ":" .. math.floor(now) .. ":5000", now)
        eq(#dec, 2); eq(dec[1].anchor.tags[2], "1445.999"); eq(#dec[2].anchor.tags, 0, "alte Form ohne Layer")
        T.Forget()
    end)

    test("Schiffe: serverweit – empfangen, am Anleger fragen, per Flüstern antworten", function()
        T.Forget()
        publicOn()
        local now = T.Now()
        setLayer(1437, "111")
        -- Messung eines Fremden im offenen Kanal
        chan("Fremd", msg("TPS", "F", "Realm", ROUTE .. ":" .. W.server .. ":1000:1437.111"))
        local b = T.Board(ID, "a")
        eq(b.timed, true, "von allen mit GuildPride"); eq(b.layer, true)
        eq(GuildPrideDB.transit.Realm[ROUTE][1].source, "public")
        T.Forget()
        chan("Fremd", msg("TPS", "R", "Realm", ROUTE .. ":" .. W.server .. ":1000:1437.111"))
        eq(T.Board(ID, "a").timed, false, "andere Spielversion")
        chan("Fremd", msg("TPS", "F", "Anderer", ROUTE .. ":" .. W.server .. ":1000:1437.111"))
        eq(T.Board(ID, "a").timed, false, "anderer Realm")
        -- Antwort per Flüstern (auch von Fremden)
        W.Receive("Fremd2", msg("TPS", "F", "Realm", ROUTE .. ":" .. W.server .. ":2000:1437.111"), "WHISPER")
        eq(T.Board(ID, "a").timed, true, "geflüsterte Antwort")
        T.Forget()
        -- am Anleger fragen: höchstens alle 5 Minuten je Layer
        W.sent = {}
        eq(T.RequestPublic({ ROUTE }), true)
        local q
        for _, m in ipairs(W.sent) do if m.kind == "TPQ" then q = m end end
        eq(q ~= nil, true, "Anfrage gesendet"); eq(q.target, "@PUBLIC")
        eq(q.msg, msg("TPQ", "F", "Realm", "1437.111", ROUTE))
        eq(T.RequestPublic({ ROUTE }), false, "nicht gleich noch einmal")
        setLayer(1437, "222")
        eq(T.RequestPublic({ ROUTE }), true, "nach Layer-Wechsel neu fragen")
        -- Anfrage beantworten: eigene Messung mit passendem Layer
        T.Sighted(ROUTE, { epoch = now * 1000 - 5000, seen = math.floor(now), source = "you", tags = { "1437.111" } })
        chan("Anna2", msg("TPQ", "F", "Realm", "1437.111", ROUTE))
        eq(#pubSent, 1, "geantwortet"); eq(pubSent[1].kind, "TPS")
        eq(pubSent[1].msg:find(":1437.111", 1, true) ~= nil, true, "mit Layer")
        eq(pubSent[1].to, "Anna2", "per Flüstern an den Fragenden")
        chan("Anna3", msg("TPQ", "F", "Realm", "1437.555", ROUTE))
        eq(#pubSent, 1, "anderer Layer: keine Antwort")
        chan("Anna2", msg("TPQ", "F", "Realm", "1437.111", ROUTE))
        eq(#pubSent, 1, "derselbe Fragende nicht gleich noch einmal")
        -- Gruppensuche aus: Schiffszeiten gehen trotzdem (Teilen ist Pflicht)
        GuildPrideDB.publicLFG = nil
        T.Forget()
        setLayer(1437, "111")
        chan("Fremd", msg("TPS", "F", "Realm", ROUTE .. ":" .. W.server .. ":1000:1437.111"))
        eq(T.Board(ID, "a").timed, true, "auch ohne Gruppensuche")
        T.Forget()
        publicOff()
        chan("Fremd", msg("TPS", "F", "Realm", ROUTE .. ":" .. W.server .. ":1000:1437.111"))
        eq(T.Board(ID, "a").timed, false, "serverweite Gruppensuche aus")
        setLayer(nil, nil)
        T.Forget()
    end)

    test("Schiffe: Fahrt merkt sich Abfahrts- und Ankunfts-Layer und geht an alle", function()
        -- offene Fahrt aus dem vorigen Test abschließen (und deren Nachtrag-Fenster ablaufen lassen)
        W.Advance(40); T.Sample()
        W.Advance(400); T.Sample()
        T.Forget()
        W.Advance(700)   -- keine „Routine“-Wiederholung
        publicOn()
        local route = T.Routes()[ROUTE]
        local start = T.Now() * 1000
        local epoch = start - 128093
        local function at(phase)
            local f = route.frames
            for i = 1, #f - 1 do
                local a, b = f[i], f[i + 1]
                if phase >= a[2] and phase <= b[1] and a[3] == b[3] then
                    local t = (phase - a[2]) / math.max(1, b[1] - a[2])
                    return a[4] + t * (b[4] - a[4]), a[5] + t * (b[5] - a[5]), a[3]
                end
            end
        end
        -- am Steg: Layer erkannt
        setLayer(1437, "111")
        T.Sample()
        setLayer(nil, nil)
        local x, y, map
        UnitPosition = function() return x, y, 0, map end
        UnitOnTaxi = function() return false end
        W.sent = {}
        for _ = 1, 80 do
            x, y, map = at(T.Now() * 1000 - epoch)
            T.Sample()
            W.Advance(1)
        end
        -- angekommen: stehen bleiben, bis die Fahrt endet
        for _ = 1, 35 do T.Sample(); W.Advance(1) end
        local g = GuildPrideDB.transit.Realm[ROUTE][1]
        eq(g.source, "you"); eq(g.tags[1], "1437.111", "Abfahrts-Layer")
        local tps
        for _, m in ipairs(W.sent) do if m.kind == "TPS" and m.target == "@PUBLIC" then tps = m end end        eq(tps ~= nil, true, "an alle im offenen Kanal")
        eq(tps.msg:find(":1437.111", 1, true) ~= nil, true)
        -- Ziel-Anleger: Layer erkannt -> wird nachgetragen und noch einmal geteilt
        W.sent = {}
        setLayer(1445, "777")
        T.Sample()
        eq(g.tags[2], "1445.777", "Ankunfts-Layer")
        local again
        for _, m in ipairs(W.sent) do if m.kind == "TPS" and m.msg:find("1445.777", 1, true) then again = m end end
        eq(again ~= nil, true, "mit neuem Layer erneut geteilt")
        UnitPosition, UnitOnTaxi = nil, nil
        setLayer(nil, nil)
        publicOff()
        T.Forget()
    end)

    test("Schiffe: Fenster am Anleger", function()
        T.Forget()
        local x, y = -3905.2, -585.8
        UnitPosition = function() return x, y, 0, 0 end
        T.UpdateWindow()
        local f = T._Window()
        eq(f:IsShown(), true)
        local row
        for _, r in ipairs(f.rows) do if r:IsShown() and r.dock and r.dock.to == "Theramore" then row = r end end
        eq(row ~= nil, true, "Verbindung nach Theramore")
        eq(row.board.timed, false, "noch nicht gemessen")
        eq(f.untimed, true, "Hinweis: einmal mitfahren")
        -- X: bleibt weg, solange du am Anleger bist
        f.close.scripts.OnClick(f.close)
        T.UpdateWindow()
        eq(f:IsShown(), false)
        -- weggehen und wiederkommen: wieder da
        x = x + 1000
        T.UpdateWindow()
        eq(f:IsShown(), false)
        x = x - 1000
        T.UpdateWindow()
        eq(f:IsShown(), true)
        -- ausschalten
        T.SetWindow(false)
        eq(f:IsShown(), false); eq(GuildPrideDB.transitUI, false)
        T.SetWindow(true)
        eq(f:IsShown(), true)
        UnitPosition = nil
        T.UpdateWindow()
        eq(f:IsShown(), false)
    end)

    test("Schiffe: Bestätigungen – mehrfach gemessene Zeit schlägt einzelne abweichende", function()
        T.Forget()
        local now = T.Now()
        local e1 = now * 1000 - 54297 - 10000          -- liegt seit 10 s am Steg
        local e2 = now * 1000 - 54297 + 60000          -- abweichend: kommt in 60 s
        for i, who in ipairs({ "Anna", "Bert", "Carl" }) do
            T.Sighted(ROUTE, { epoch = e1 + i * 100, seen = math.floor(now) - 300, source = "player",
                tags = { "1437.111" }, from = who, own = true })
        end
        T.Sighted(ROUTE, { epoch = e2, seen = math.floor(now), source = "player", tags = { "1437.111" }, from = "Fremd", own = true })
        eq(#GuildPrideDB.transit.Realm[ROUTE], 2, "abweichende Phase = eigene Gruppe")
        setLayer(1437, "111")
        local b = T.Board(ID, "a", now)
        eq(b.arriveIn, 0, "die dreifach bestätigte Zeit gilt"); eq(b.confirmed, 3)
        eq(T.ConfirmText(b):find("3", 1, true) ~= nil, true)
        -- dieselbe Person zählt nur einmal; weitergereichte (ohne ":o") zählen nicht
        T.Sighted(ROUTE, { epoch = e1, seen = math.floor(now), source = "player", tags = { "1437.111" }, from = "Anna", own = true })
        T.Sighted(ROUTE, { epoch = e1, seen = math.floor(now), source = "player", tags = { "1437.111" }, from = "Dora" })
        eq(T.Board(ID, "a", now).confirmed, 3)
        -- Kennzeichen ":o" nur für selbst gemessene, ältere Einträge ohne werden gelesen
        local own = T._Encode(ROUTE, { epoch = e1, seen = math.floor(now), source = "you", tags = { "1437.111" } })
        local other = T._Encode(ROUTE, { epoch = e1, seen = math.floor(now), source = "public", tags = {} })
        eq(own:sub(-2), ":o"); eq(other:find(":o", 1, true), nil)
        local dec = T._Decode(own .. ";" .. other .. ";" .. ROUTE .. ":" .. math.floor(now) .. ":5000", now)
        eq(#dec, 3); eq(dec[1].anchor.own, true); eq(dec[2].anchor.own, false); eq(dec[3].anchor.own, false)
        eq(dec[1].anchor.tags[1], "1437.111")
        -- über die Gilde: der Absender zählt als Bestätiger
        T.Forget()
        W.Receive("Anna", msg("TRS", "Realm", T._Encode(ROUTE, { epoch = e1, seen = W.server, source = "you", tags = { "1437.111" } })))
        W.Receive("Bert", msg("TRS", "Realm", T._Encode(ROUTE, { epoch = e1 + 500, seen = W.server, source = "you", tags = { "1437.111" } })))
        eq(T.Board(ID, "a").confirmed, 2, "zwei Gildenmitglieder")
        setLayer(nil, nil)
        T.Forget()
    end)

    test("Schiffe: Layer-Start aus Kreaturen-GUIDs, geschätzt erst nach zwei passenden Eichungen", function()
        T.Forget()
        GuildPrideDB.transitStarts, GuildPrideDB.transitCalib = nil, nil
        local now = math.floor(T.Now())
        local function guid(zone, ago)
            local low = (now - ago) % 2 ^ 23
            return ("Creature-0-1-2-%s-1234-0000%06X"):format(zone, low)
        end
        eq(T.SpawnTime(guid("111", 100), now), now - 100, "Entstehungszeit aus der GUID")
        eq(T.SpawnTime("Player-1-0000ABCD", now), nil)
        -- früheste Kreatur je Layer = Start
        T.SawCreature(guid("111", 5000), "1437.111", now)
        T.SawCreature(guid("111", 9000), "1437.111", now)
        T.SawCreature(guid("111", 200), "1437.111", now)
        T.SawCreature(guid("222", 3000), "1437.222", now)
        T.SawCreature(guid("333", 7000), "1437.333", now)
        eq(GuildPrideDB.transitStarts.Realm["1437.111"].t, now - 9000)
        local route = T.Routes()[ROUTE]
        local OFF = 123456
        local function epochFor(start) return start * 1000 + OFF end
        T.Calibrate(ROUTE, epochFor(now - 9000), { "1437.111" }, now)
        eq(T._Offset(ROUTE), nil, "eine Eichung reicht nicht")
        setLayer(1437, "333")
        eq(T.Board(ID, "a", now).timed, false, "noch nicht geschätzt")
        T.Calibrate(ROUTE, epochFor(now - 3000) + 1500, { "1437.222" }, now)
        eq(math.abs(T._Offset(ROUTE) - (OFF + 750)) < 1, true, "zwei Layer mit gleichem Abstand")
        local b = T.Board(ID, "a", now)
        eq(b.timed, true); eq(b.estimated, true); eq(b.layer, true)
        eq(T.LayerText(b):find("geschätzt", 1, true) ~= nil, true)
        -- echte Messung auf meinem Layer hat Vorrang vor der Schätzung
        T.Sighted(ROUTE, { epoch = now * 1000 - 1000, seen = now, source = "player", tags = { "1437.333" } })
        eq(T.Board(ID, "a", now).estimated, nil)
        -- widersprüchliche Eichungen: keine Schätzung
        GuildPrideDB.transitCalib = { [ROUTE] = { { off = 1000, start = now - 9000 }, { off = 200000, start = now - 3000 } } }
        eq(T._Offset(ROUTE), nil)
        GuildPrideDB.transitStarts, GuildPrideDB.transitCalib = nil, nil
        setLayer(nil, nil)
        T.Forget()
        local _ = route
    end)

    test("Schiffe: Erinnerung 1 Minute vor der Abfahrt", function()
        T.Forget()
        local now = T.Now()
        -- liegt seit 10 s am Steg, legt in ~50 s ab
        T.Sighted(ROUTE, { epoch = now * 1000 - 54297 - 10000, seen = math.floor(now), source = "player" })
        local warned = {}
        local oldRN, oldRW = RaidNotice_AddMessage, RaidWarningFrame
        RaidNotice_AddMessage = function(_, text) warned[#warned + 1] = text end
        RaidWarningFrame = {}
        local d = { id = ID, side = "a", kind = "boat", to = "Theramore" }
        eq(T.ToggleReminder(d, now), true)
        T.CheckReminders(now)
        eq(#warned, 0, "legt gleich ab: an die nächste Abfahrt erinnern")
        T.CheckReminders(now + 200)
        eq(#warned, 0, "noch zu früh")
        T.CheckReminders(now + 329.313 + 1)
        eq(#warned, 1, "1 Min. vor der nächsten Abfahrt"); eq(warned[1]:find("Theramore", 1, true) ~= nil, true)
        T.CheckReminders(now + 329.313 + 2)
        eq(#warned, 1, "nur einmal")
        eq(T.ToggleReminder(d, now), true); eq(T.ToggleReminder(d, now), false, "zweiter Klick: aus")
        eq(next(T.reminders), nil)
        RaidNotice_AddMessage, RaidWarningFrame = oldRN, oldRW
        T.Forget()
    end)

    test("Teilen ohne Ausnahme: Kanal für Schiffe auch ohne Gruppensuche, Rares teilen immer", function()
        local oldF, oldH, oldC = ns.IS_FOREVER, ns.HAS_PUBLIC_LFG, ns.PUBLIC_VIA_CHAT
        ns.IS_FOREVER, ns.HAS_PUBLIC_LFG, ns.PUBLIC_VIA_CHAT = true, true, false
        GuildPrideDB.publicLFG = false
        eq(ns.PublicLFGOn(), false); eq(ns.PublicDataOn(), true); eq(ns.PublicChannelWanted(), true)
        ns.IS_FOREVER = false
        eq(ns.PublicChannelWanted(), false, "andere Spielversion: nur mit Gruppensuche")
        ns.IS_FOREVER, ns.HAS_PUBLIC_LFG, ns.PUBLIC_VIA_CHAT = oldF, oldH, oldC
        GuildPrideDB.publicLFG = nil
        if ns.Rares and ns.Rares.Opt and ns.Rares.DB and ns.Rares.DB() then
            ns.Rares.DB().opts.share = false
            eq(ns.Rares.Opt("share"), true, "Rares: Teilen ist Pflicht")
        end
    end)

end
