-- Tests für die Buff-Food- und Erholungs-Erinnerung (aus tests/run.lua aufgerufen)
return function(test, eq, W, ns)
    W.Load("GuildPrideBuffs.lua")
    local B = ns.Buffs

    test("Buff-Food: englischer Tooltip, Ausdauer und Willenskraft", function()
        local s = B.ParseFood({ "Tender Wolf Steak", "Requires Level 40",
            "Use: Restores 1392 health over 27 sec. Must remain seated while eating. If you spend at least 10 seconds eating you will become well fed and gain 12 Stamina and Spirit for 15 min." })
        eq(s.sta, 12, "Ausdauer"); eq(s.spi, 12, "Willenskraft"); eq(s.hp5, nil, "Heilung davor zählt nicht")
    end)

    test("Buff-Food: deutscher Tooltip mit Zeit vor dem Wert", function()
        local s = B.ParseFood({ "Benutzen: Stellt im Verlauf von 27 Sek. 1392 Punkt(e) Gesundheit wieder her. Ihr müsst beim Essen sitzen bleiben. Wenn Ihr mindestens 10 Sek. mit Essen verbringt, werdet Ihr satt und erhaltet 15 Min. lang 20 Stärke." })
        eq(s.str, 20, "Stärke"); eq(s.hp5, nil, "Gesundheit vor „satt“ zählt nicht")
    end)

    test("Buff-Food: „Satt“ in Anführungszeichen", function()
        local s = B.ParseFood({ "Benutzen: Wenn Ihr mindestens 10 Sek. mit Essen verbringt, erhaltet Ihr den Effekt „Satt“ und 15 Min. lang 12 Ausdauer und Willenskraft." })
        eq(s and s.sta, 12, "Ausdauer"); eq(s and s.spi, 12, "Willenskraft")
        s = B.ParseFood({ "Benutzen: ... werdet Ihr 'Satt' und erhaltet 15 Min. lang 10 Beweglichkeit." })
        eq(s and s.agi, 10, "einfache Anführungszeichen")
    end)

    test("Buff-Food: Mana alle 5 Sek. und kein Buff-Food", function()
        local s = B.ParseFood({ "Use: ... you will become well fed and gain 8 Mana every 5 seconds for 10 min." })
        eq(s.mp5, 8, "Mana/5")
        eq(B.ParseFood({ "Use: Restores 874 health over 27 sec." }), nil, "normales Essen")
        eq(B.ParseFood({ "Ein Sattel aus Leder", "Benutzen: Sattelt das Pferd." }), nil, "„Sattel“ ist nicht satt")
        eq(B.ParseFood({ "Satt und zufrieden" }), nil, "nur die Benutzen-Zeile zählt")
    end)

    test("Buff-Food: Krieger nimmt Stärke, Magier Mana", function()
        local list = {
            { id = 1, score = B.Score({ sta = 12, spi = 12 }, "WARRIOR") },
            { id = 2, score = B.Score({ str = 20 }, "WARRIOR") },
            { id = 3, score = B.Score({ mp5 = 8 }, "WARRIOR") },
        }
        eq(B.Sort(list)[1].id, 2, "Krieger")
        list = {
            { id = 1, score = B.Score({ sta = 12, spi = 12 }, "MAGE") },
            { id = 2, score = B.Score({ str = 20 }, "MAGE") },
            { id = 3, score = B.Score({ mp5 = 8 }, "MAGE") },
        }
        eq(B.Sort(list)[1].id, 3, "Magier")
        eq(B.Sort(list)[3].id, 2, "Stärke für Magier zuletzt")
    end)

    test("Buff-Food: gleiche Punkte -> größerer Stapel zuerst", function()
        local list = { { id = 5, score = 10, count = 2 }, { id = 9, score = 10, count = 7 } }
        eq(B.Sort(list)[1].id, 9)
        eq(B.StatText({ sta = 12, spi = 12 }), "+12 Ausdauer, +12 Willenskraft")
    end)
end
