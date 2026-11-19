-- Tests für die Flugzeit am Flugmeister (aus tests/run.lua aufgerufen)
return function(test, eq, W, ns)
    W.Load("GuildPrideFlightData.lua")
    W.Load("GuildPrideFlight.lua")
    W.Load("GuildPrideFlightUI.lua")
    local F = ns.Flight

    -- Flugkarte in Sturmwind: 1 = hier, 2 = Dunkelhain, 3 = Seenhain (über Dunkelhain)
    local SLOTS = { { id = 2, name = "Stormwind, Elwynn", kind = "CURRENT" },
                    { id = 12, name = "Darkshire, Duskwood", kind = "REACHABLE" },
                    { id = 5, name = "Lakeshire, Redridge", kind = "REACHABLE" },
                    { id = 45, name = "Nethergarde Keep, Blasted Lands", kind = "DISTANT" } }
    local ROUTES = { [2] = { { 1, 2 } }, [3] = { { 1, 2 }, { 2, 3 } }, [4] = { { 1, 4 } } }
    local withIDs = true
    local function Map()
        GetTaxiMapID = function() return 1415 end
        C_TaxiMap = { GetAllTaxiNodes = function()
            if not withIDs then return {} end
            local out = {}
            for i, s in ipairs(SLOTS) do out[i] = { slotIndex = i, nodeID = s.id } end
            return out
        end }
        NumTaxiNodes = function() return #SLOTS end
        TaxiNodeName = function(i) return SLOTS[i] and SLOTS[i].name end
        TaxiNodeGetType = function(i) return SLOTS[i] and SLOTS[i].kind end
        GetNumRoutes = function(i) return ROUTES[i] and #ROUTES[i] or 0 end
        TaxiGetNodeSlot = function(i, hop, source)
            local h = ROUTES[i][hop]
            return source and h[1] or h[2]
        end
    end
    local onTaxi, pos = false, nil
    UnitOnTaxi = function() return onTaxi end
    UnitPosition = function() if pos then return pos[1], pos[2], 0, pos[3] end end
    local function Tip()
        local t = { lines = {} }
        function t:AddLine(text, r, g, b) self.lines[#self.lines + 1] = { text = text, r = r, g = g, b = b } end
        function t:Show() self.shown = true end
        return t
    end
    local function near(a, b) return math.abs(a - b) < 0.01 end

    test("Flug: Flugpunkte und Direktflüge aus Polestar sind da", function()
        eq(F.Yards(2, 4), 2319)
        eq(F.Yards(4, 2), 2565, "eine Richtung je Eintrag")
        eq(F.Node(2)[4], "Stormwind, Elwynn")
        eq(F.Node(5)[1], 0, "Seenhain liegt in den Östlichen Königreichen")
        eq(F.Yards(2, 999), nil)
    end)

    test("Flug: Schätzung wie Polestar (Yards / 30 + 2 s je Teilflug)", function()
        GuildPrideDB.flightLog = nil
        eq(near(F.Estimate({ 2, 5 }), 3368 / 30 + 2), true)
        eq(near(F.Estimate({ 2, 12, 5 }), 3469 / 30 + 2 + 1787 / 30 + 2), true)
        eq(F.Estimate({ 2, 999 }), nil, "unbekannter Teilflug")
        eq(F.Estimate({ 2 }), nil)
        local secs, measured = F.Time({ 2, 12, 5 })
        eq(measured, false)
        eq(F.Text(secs, measured), "Flugzeit: ca. 2:59")
        eq(F.Countdown(59.6), "1:00")
    end)

    test("Flug: Strecke zu einem Ziel aus der Flugkarte", function()
        Map()
        withIDs = true
        eq(table.concat(F.Chain(3), "-"), "2-12-5")
        eq(table.concat(F.Chain(2), "-"), "2-12")
        -- Client ohne Flugpunkt-IDs: über den englischen Namen
        withIDs = false
        eq(table.concat(F.Chain(3), "-"), "2-12-5")
        withIDs = true
        eq(F.Chain(1), nil, "zum eigenen Flugpunkt gibt es keine Strecke")
    end)

    test("Flug: Tooltip am Ziel, nicht an unerreichbaren", function()
        Map()
        GuildPrideDB.flightLog, GuildPrideDB.flightTimes = nil, nil
        F.OnMapOpened()
        local t = Tip()
        eq(F.AddTooltip(3, t), true)
        eq(t.lines[1].text, "Flugzeit: ca. 2:59"); eq(t.shown, true)
        eq(F.AddTooltip(1, Tip()), false, "hier")
        eq(F.AddTooltip(4, Tip()), false, "nicht erreichbar")
        GuildPrideDB.flightTimes = false
        eq(F.AddTooltip(3, Tip()), false, "Einstellung aus")
        GuildPrideDB.flightTimes = true
    end)

    test("Flug: gemessene Zeit ersetzt die Schätzung", function()
        Map()
        GuildPrideDB.flightLog = nil
        F.OnMapOpened()
        F.OnTakeTaxiNode(3)
        eq(F.Pending() ~= nil, true)
        eq(F.Tick(W.now), nil, "noch am Boden")
        onTaxi = true
        W.Advance(1); eq(F.Tick(W.now), nil, "Abflug")
        W.Advance(170); eq(F.Tick(W.now), nil, "fliegt noch")
        onTaxi, pos = false, { -9420, -2230, 0 }
        W.Advance(0.25)
        eq(F.Tick(W.now), 170)
        eq(F.Pending(), nil)
        eq(GuildPrideDB.flightLog["2-12-5"], 170)
        local t = Tip()
        F.AddTooltip(3, t)
        eq(t.lines[1].text, "Flugzeit: 2:50")
        eq(t.lines[1].g < 1 and t.lines[1].r == 1, true, "gold = gemessen")
        -- Rückflug: dieselbe gemessene Zeit
        local secs, measured = F.Time({ 5, 12, 2 })
        eq(secs, 170); eq(measured, true, "Rückflug gilt als gemessen")
    end)

    test("Flug: Landung mit vertauschten Achsen zählt", function()
        GuildPrideDB.flightLog = nil
        F.Begin({ 2, 12, 5 }, W.now, "Lakeshire")
        onTaxi = true; F.Tick(W.now)
        W.Advance(120)
        onTaxi, pos = false, { -2230, -9420, 0 }   -- x und y vertauscht
        eq(F.Tick(W.now), 120)
        eq(GuildPrideDB.flightLog["2-12-5"], 120)
        -- woanders gelandet: nicht gespeichert
        F.Begin({ 2, 12, 5 }, W.now, "Lakeshire")
        onTaxi = true; F.Tick(W.now)
        W.Advance(60)
        onTaxi, pos = false, { -8840, 489, 0 }
        eq(F.Tick(W.now), nil)
        eq(GuildPrideDB.flightLog["2-12-5"], 120, "alte Messung bleibt")
        pos = nil
    end)

    test("Flug: abgebrochene Flüge zählen nicht", function()
        GuildPrideDB.flightLog = nil
        -- woanders gelandet (z. B. ausgeloggt und versetzt)
        F.Begin({ 2, 12, 5 }, W.now)
        onTaxi = true; F.Tick(W.now)
        W.Advance(60)
        onTaxi, pos = false, { -8840, 489, 0 }
        eq(F.Tick(W.now), nil)
        eq((GuildPrideDB.flightLog or {})["2-12-5"], nil)
        -- nie abgeflogen
        F.Begin({ 2, 5 }, W.now)
        W.Advance(16); F.Tick(W.now)
        eq(F.Pending(), nil)
        eq(F.Record({ 2, 5 }, 2), false, "zu kurz")
        eq(F.Record({ 2, 5 }, 99999), false, "zu lang")
        pos = nil
    end)

    test("Flug: einzeln gemessene Teilflüge fließen in die Schätzung ein", function()
        GuildPrideDB.flightLog = { ["2-12"] = 100 }
        local secs, measured = F.Time({ 2, 12, 5 })
        eq(measured, false)
        eq(near(secs, 100 + 1787 / 30 + 2), true)
        GuildPrideDB.flightLog = nil
    end)
    test("Flug-Zähler: Fenster im Flug mit Restzeit und Balken", function()
        Map()
        GuildPrideDB.flightLog, GuildPrideDB.flightUI, GuildPrideDB.flightNow = nil, nil, nil
        onTaxi, pos = false, nil
        F.OnMapOpened()
        F.OnTakeTaxiNode(3)
        eq(F.Pending().name, "Lakeshire", "Name aus der Flugkarte, ohne Zone")
        F.UpdateWindow()
        eq(F._Window() == nil or not F._Window():IsShown(), true, "noch am Boden: kein Fenster")
        onTaxi = true
        F.Tick(W.now); F.onTick()
        local win = F._Window()
        eq(win:IsShown(), true)
        local total = 3469 / 30 + 2 + 1787 / 30 + 2
        W.Advance(60)
        local st = F.Status(W.now)
        eq(st.to, "Lakeshire"); eq(st.measured, false)
        eq(near(st.left, total - 60), true)
        eq(near(st.fill, 60 / total), true)
        local clock, label, color = F.Clock(st)
        eq(clock, "ca. " .. F.Countdown(total - 60)); eq(label, "bis zur Landung"); eq(color[1] < 1, true, "grau")
        eq(F.StatusText(st):find("geschätzt", 1, true) ~= nil, true)
        F.UpdateWindow(W.now)
        eq(near(win.row.fill, 60 / total), true)
        -- über der Zeit: „gleich da“
        W.Advance(200)
        eq((F.Clock(F.Status(W.now))), "gleich da")
        -- X blendet aus, bis der Flug endet
        win.close.scripts.OnClick()
        F.UpdateWindow(W.now); eq(win:IsShown(), false)
        -- Landung in Seenhain: Fenster weg
        onTaxi, pos = false, { -9420, -2230, 0 }
        F.Tick(W.now); F.onTick()
        eq(win:IsShown(), false)
        eq(GuildPrideDB.flightNow, nil, "Flug vorbei: nichts mehr gespeichert")
        pos = nil
    end)

    test("Flug-Zähler: gemessene Strecke in Gold, Einstellung aus", function()
        GuildPrideDB.flightLog = { ["2-12-5"] = 170 }
        F.Begin({ 2, 12, 5 }, W.now)
        eq(F.Pending().name, "Lakeshire", "ohne Flugkarte: englischer Name aus den Daten")
        onTaxi = true; F.Tick(W.now)
        W.Advance(20)
        local st = F.Status(W.now)
        eq(st.measured, true)
        local clock, _, color = F.Clock(st)
        eq(clock, "2:30"); eq(color[1] == 1 and color[2] < 1, true, "gold")
        eq(F.StatusText(st):find("gemessen", 1, true) ~= nil, true)
        F.SetWindow(false)
        eq(F._Window():IsShown(), false)
        F.SetWindow(true)
        eq(F._Window():IsShown(), true)
        F.Cancel(); onTaxi = false; F.UpdateWindow()
        eq(F._Window():IsShown(), false)
        GuildPrideDB.flightLog = nil
    end)

    test("Flug-Zähler: läuft nach /reload weiter", function()
        GuildPrideDB.flightLog = nil
        F.Begin({ 2, 5 }, W.now, "Lakeshire")
        onTaxi = true; F.Tick(W.now)
        W.Advance(30); F.Tick(W.now)
        local saved = GuildPrideDB.flightNow
        eq(type(saved), "table"); eq(saved.name, "Lakeshire")
        -- /reload: der Flug im Speicher ist weg, GuildPrideDB bleibt
        F.Cancel(); GuildPrideDB.flightNow = saved
        W.Advance(10)
        eq(F.Restore(W.now), true)
        local st = F.Status(W.now)
        eq(st.to, "Lakeshire")
        eq(near(st.elapsed, 40), true, "zählt ab dem echten Abflug")
        -- am Boden: nichts wiederherstellen
        F.Cancel(); GuildPrideDB.flightNow = saved; onTaxi = false
        eq(F.Restore(W.now), false)
        GuildPrideDB.flightNow = nil
    end)
end
