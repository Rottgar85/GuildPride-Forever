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
        -- verfällt nach 6 Stunden
        eq(T.Board(ID, "a", now + 6 * 3600 + 10).timed, false)
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
        local a = GuildPrideDB.transit.Realm[ROUTE]
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
        eq(GuildPrideDB.transit.Realm[ROUTE].source, "player")
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
        -- teilen aus
        GuildPrideDB.transitShare = false
        T.Forget()
        W.Receive("Bert", msg("TRS", "Realm", ROUTE .. ":" .. W.server .. ":1000"))
        eq(T.Board(ID, "a").timed, false, "Teilen aus: nichts übernommen")
        GuildPrideDB.transitShare = nil
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
end
