-- Tests für den Layer-Wechsel: Wechsel wird geprüft (aus tests/run.lua aufgerufen)
return function(test, eq, W, ns)
    -- Timer von Hand laufen lassen
    local timers, oldTimer = {}, C_Timer
    C_Timer = {
        After = function(sec, fn) timers[#timers + 1] = { at = W.now + sec, fn = fn } end,
        NewTimer = function() return W.magic end,
        NewTicker = function() return { Cancel = function() end } end,
    }
    local function Run(sec)
        W.Advance(sec)
        local due = {}
        for i = #timers, 1, -1 do
            if timers[i].at <= W.now then due[#due + 1] = table.remove(timers, i) end
        end
        for i = #due, 1, -1 do due[i].fn() end
    end
    local oldGroup, inGroup, left = IsInGroup, true, 0
    IsInGroup = function() return inGroup end
    C_PartyInfo = { LeaveParty = function() left = left + 1; inGroup = false end }
    local oldIn, oldPrint, oldNow = IsInInstance, ns.Print, ns.SendPublicNow
    IsInInstance = function() return false end
    local printed, sent = {}, {}
    ns.Print = function(t) printed[#printed + 1] = t end
    ns.SendPublicNow = function(to, kind) sent[#sent + 1] = { to = to, kind = kind } end
    W.Load("GuildPrideLayer.lua")
    local Layer = ns.Layer
    local function Last() return printed[#printed] or "" end
    local function Start(from, target)
        inGroup, left = true, 0
        wipe(printed); wipe(sent); wipe(timers)
        Layer._State({ map = 1429, from = from, target = target, helper = "Helfer", offers = {},
                       asked = true, joinedAt = W.now }, false)
    end

    test("Layer: eine einzelne fremde Kreatur reicht nicht sofort", function()
        Start("100", "200")
        Layer.OnSeen("200", "g1", 1429)
        eq(Layer._State() ~= nil, true, "noch nicht bestätigt")
        eq(left, 0, "Gruppe bleibt")
        -- zweite Kreatur auf dem neuen Layer: bestätigt
        Layer.OnSeen("200", "g2", 1429)
        local r, c = Layer._State()
        eq(r, nil); eq(c.to, "200")
        eq(Last():find("bestätigt", 1, true) ~= nil, true)
        Run(0.5); eq(left, 1, "Gruppe verlassen")
        eq(#sent, 0, "Dank erst nach der Nachprüfung")
        Run(10)
        eq(select(2, Layer._State()), nil)
        eq(sent[1].kind, "LYT"); eq(sent[1].to, "Helfer")
        eq(Last():find("jetzt auf Layer 200", 1, true) ~= nil, true)
    end)

    test("Layer: dieselbe Kreatur über 1,5 s bestätigt auch", function()
        Start("100", "200")
        Layer.OnSeen("200", "g1", 1429)
        W.Advance(1)
        Layer.OnSeen("200", "g1", 1429)
        eq(Layer._State() ~= nil, true, "nach 1 s noch nicht")
        W.Advance(0.6)
        Layer.OnSeen("200", "g1", 1429)
        eq(Layer._State(), nil, "nach 1,6 s bestätigt")
        Layer._State(false, false)
    end)

    test("Layer: alter Layer wieder gesehen setzt die Bestätigung zurück", function()
        Start("100", "200")
        Layer.OnSeen("200", "g1", 1429)
        Layer.OnSeen("100", "g2", 1429)
        Layer.OnSeen("200", "g3", 1429)
        eq(Layer._State() ~= nil, true, "nur eine neue Kreatur seit dem Zurücksetzen")
        Layer.OnSeen("200", "g4", 1429)
        eq(Layer._State(), nil, "zwei Kreaturen auf dem neuen Layer")
        Layer._State(false, false)
    end)

    test("Layer: andere Karte und unbekannter alter Layer", function()
        Start("100", "200")
        Layer.OnSeen("200", "g1", 1430); Layer.OnSeen("200", "g2", 1430)
        eq(Layer._State() ~= nil, true, "andere Zone zählt nicht")
        Start(nil, "200")
        Layer.OnSeen("300", "g1", 1429); Layer.OnSeen("300", "g2", 1429)
        eq(Layer._State() ~= nil, true, "ohne alten Layer zählt nur der des Helfers")
        Layer.OnSeen("200", "g3", 1429); Layer.OnSeen("200", "g4", 1429)
        eq(Layer._State(), nil)
        Layer._State(false, false)
    end)

    test("Layer: Wechsel hält nicht – kein Dank, kein Zähler", function()
        Start("100", "200")
        local before = Layer.Stats().switched
        Layer.OnSeen("200", "g1", 1429); Layer.OnSeen("200", "g2", 1429)
        Run(0.5)
        eq(left, 1)
        -- nach dem Austritt wieder auf dem alten Layer
        Layer.OnSeen("100", "g5", 1429); Layer.OnSeen("100", "g6", 1429)
        eq(select(2, Layer._State()), nil)
        eq(Last():find("nicht gehalten", 1, true) ~= nil, true)
        Run(10)
        eq(#sent, 0, "kein Dank")
        eq(Layer.Stats().switched, before)
    end)

    test("Layer: Gruppe vor der Bestätigung verlassen", function()
        Start("100", "200")
        inGroup = false
        Layer.OnGroup()
        eq(Layer._State(), nil)
        eq(Last():find("bevor der neue Layer bestätigt", 1, true) ~= nil, true)
    end)

    C_Timer, IsInGroup, IsInInstance, ns.Print, ns.SendPublicNow = oldTimer, oldGroup, oldIn, oldPrint, oldNow
    C_PartyInfo = nil
end
