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

    test("Buff-Food: nur der Buff „Satt“ zählt, nicht andere Buffs mit Essens-Symbol", function()
        local oldAuras, oldSpell = C_UnitAuras, C_Spell
        local auras = {}
        C_Spell = { GetSpellName = function(id) return id == 19705 and "Satt" or nil end }
        C_UnitAuras = { GetAuraDataByIndex = function(_, i) return auras[i] end }
        auras = { { name = "Essen", icon = 136000, spellId = 433 },
                  { name = "Mondfrucht-Leckerei", icon = 136000, spellId = 12345 } }
        eq((B.ReadAuras()), false, "Essen/andere Buffs mit gleichem Symbol sind nicht satt")
        auras = { { name = "Satt", icon = 136000, spellId = 19705 } }
        eq((B.ReadAuras()), true, "Satt")
        auras = { { name = "Well Fed", icon = 136000, spellId = 19706 } }
        eq((B.ReadAuras()), true, "englischer Client")
        C_UnitAuras, C_Spell = oldAuras, oldSpell
    end)

    test("Buff-Food: Rezepte sind kein Essen (nur hergestelltes Essen zählt)", function()
        -- Rezept-Tooltip enthält unten den Tooltip des fertigen Essens
        eq(B.ParseFood({ "Rezept: Gebratener Raptorschenkel", "Benötigt Kochkunst (165)",
            "Benutzen: Lehrt Euch, wie man einen Gebratenen Raptorschenkel kocht.", "",
            "Gebratener Raptorschenkel",
            "Benutzen: Wenn Ihr mindestens 10 Sek. mit Essen verbringt, erhaltet Ihr den Effekt „Satt“ und 15 Min. lang 12 Ausdauer und Willenskraft." }),
            nil, "deutsches Rezept")
        eq(B.ParseFood({ "Recipe: Cooked Glossy Mightfish", "Use: Teaches you how to cook Cooked Glossy Mightfish.",
            "Cooked Glossy Mightfish", "Use: ... you will become well fed and gain 10 Stamina for 10 min." }),
            nil, "englisches Rezept")
        eq(B.IsRecipe(9), true); eq(B.IsRecipe(0), false); eq(B.IsRecipe(nil), false)
    end)

    test("Buff-Food: Vorwarnung kurz bevor „Satt“ ausläuft, Restzeit aus dem Buff", function()
        eq(B.NeedFood(false, nil), true, "nicht satt")
        eq(B.NeedFood(true, nil), false, "satt ohne Restzeit")
        eq(B.NeedFood(true, 600), false, "noch 10 Min.")
        eq(B.NeedFood(true, 90), true, "nur noch 90 Sek.")
        eq(B.NeedFood(true, 240, 300), true, "Bereitschaftscheck: weniger als 5 Min.")
        eq(B.NeedFood(nil, nil), false, "unbekannt (Kampf)")
        local oldAuras, oldSpell = C_UnitAuras, C_Spell
        C_Spell = { GetSpellName = function(id) return id == 19705 and "Satt" or nil end }
        local t = GetTime()
        C_UnitAuras = { GetAuraDataByIndex = function(_, i)
            return i == 1 and { name = "Satt", icon = 136000, spellId = 19705, expirationTime = t + 100 } or nil end }
        local fed, _, _, left = B.ReadAuras()
        eq(fed, true); eq(math.floor(left + 0.5), 100, "Restzeit in Sek.")
        C_UnitAuras, C_Spell = oldAuras, oldSpell
    end)

    test("Buff-Food: Schalter „nur in Instanzen und Gruppen“", function()
        local oldInst, oldGroup = IsInInstance, IsInGroup
        local inst, typ, grp = false, "none", false
        IsInInstance = function() return inst, typ end
        IsInGroup = function() return grp end
        GuildPrideDB.buffFoodGroupOnly = nil
        eq(B.FoodHere(), true, "ohne Schalter überall")
        GuildPrideDB.buffFoodGroupOnly = true
        eq(B.FoodHere(), false, "allein in der Welt")
        grp = true; eq(B.FoodHere(), true, "in der Gruppe")
        grp = false; inst, typ = true, "raid"; eq(B.FoodHere(), true, "im Schlachtzug")
        GuildPrideDB.buffFoodGroupOnly = nil
        IsInInstance, IsInGroup = oldInst, oldGroup
    end)

    -- Gemeinsame Ersatz-Daten: Gegenstände und Tooltips nach ID
    local TIPS = {
        [100] = { "Raptorschenkel", "Benutzen: ... erhaltet Ihr den Effekt „Satt“ und 15 Min. lang 12 Ausdauer und Willenskraft." },
        [101] = { "Würziges Brot", "Benutzen: ... erhaltet Ihr den Effekt „Satt“ und 15 Min. lang 6 Ausdauer und Willenskraft." },
        [200] = { "Brot", "Benutzen: Stellt 243 Gesundheit wieder her." },
        [300] = { "Kupfererz" },
    }
    local function WithItems(fn)
        local oldItem, oldTip = C_Item, C_TooltipInfo
        C_Item = { GetItemInfoInstant = function(id) if TIPS[id] then return id, "", "", "", 1, id == 300 and 7 or 0, 0 end end }
        C_TooltipInfo = { GetItemByID = function(id)
            local lines = {}
            for _, l in ipairs(TIPS[id] or {}) do lines[#lines + 1] = { leftText = l } end
            return { lines = lines }
        end }
        local ok, err = pcall(fn)
        C_Item, C_TooltipInfo = oldItem, oldTip
        if not ok then error(err, 0) end
    end

    test("Buff-Food: Werte eines Gegenstands nach ID (nur Verbrauchsgüter mit „Satt“)", function()
        WithItems(function()
            eq(B.FoodStatsByID(100).sta, 12)
            eq(B.FoodStatsByID(200), nil, "normales Brot")
            eq(B.FoodStatsByID(300), nil, "kein Verbrauchsgut")
        end)
    end)

    test("Buff-Food: kein Essen dabei – bestes kochbares Satt-Essen und Bestand der Twinks", function()
        local oldCraft = ns.Craft
        ns.Craft = {
            Me = function() return "Ich" end,
            MyEntry = function() return { known = { [185] = { [1] = true, [2] = true, [3] = true } } } end,
            CanCraft = function(r) return ({ [1] = 2, [2] = 5, [3] = 0 })[r] end,
            OutputItem = function(r) return ({ [1] = 100, [2] = 101, [3] = 100 })[r] end,
            Chars = function() return {
                Ich = { items = { [101] = 3 } },
                Twink = { items = { [100] = 12, [200] = 40, [300] = 5 } },
                Zweit = { items = { [101] = 4 } },
            } end,
        }
        WithItems(function()
            local c = B.BestCookable("WARRIOR")
            eq(c.id, 100, "Raptorschenkel ist besser als Brot"); eq(c.n, 2, "2-mal kochbar"); eq(c.recipe, 1)
            local alts = B.AltFood("WARRIOR")
            eq(#alts, 2, "nur Twinks mit Buff-Food, nicht ich")
            eq(alts[1].name, "Twink"); eq(alts[1].id, 100); eq(alts[1].n, 12)
            eq(alts[2].name, "Zweit"); eq(alts[2].id, 101)
        end)
        ns.Craft = nil
        eq(B.BestCookable("WARRIOR"), nil, "ohne Handwerks-Modul")
        eq(#B.AltFood("WARRIOR"), 0)
        ns.Craft = oldCraft
    end)

    test("Buff-Food: Bereitschaftscheck erinnert, wenn „Satt“ fehlt oder bald ausläuft", function()
        local oldAuras, oldSpell = C_UnitAuras, C_Spell
        C_Spell = { GetSpellName = function(id) return id == 19705 and "Satt" or nil end }
        local auras = {}
        C_UnitAuras = { GetAuraDataByIndex = function(_, i) return auras[i] end }
        GuildPrideDB.buffFood, GuildPrideDB.buffFoodReady = true, true
        eq(B.ReadyCheckNeedsFood(), true, "nicht satt")
        auras = { { name = "Satt", icon = 1, spellId = 19705, expirationTime = GetTime() + 900 } }
        eq(B.ReadyCheckNeedsFood(), false, "noch 15 Min. satt")
        auras = { { name = "Satt", icon = 1, spellId = 19705, expirationTime = GetTime() + 200 } }
        eq(B.ReadyCheckNeedsFood(), true, "unter 5 Min.")
        GuildPrideDB.buffFoodReady = false
        eq(B.ReadyCheckNeedsFood(), false, "Schalter aus")
        GuildPrideDB.buffFood, GuildPrideDB.buffFoodReady = nil, nil
        C_UnitAuras, C_Spell = oldAuras, oldSpell
    end)

    test("Buff-Fenster: von Hand geöffnet (/gp buff) bleibt offen, bis X – auch wenn die Erinnerung aus ist", function()
        local oldAuras, oldSpell, oldCont = C_UnitAuras, C_Spell, C_Container
        C_Spell = { GetSpellName = function() return nil end }
        C_UnitAuras = { GetAuraDataByIndex = function() return nil end }
        C_Container = { GetContainerNumSlots = function() return 0 end }
        GuildPrideDB.buffFood, GuildPrideDB.restReminder = false, false
        -- einfache Fenster-Attrappen: sichtbar/unsichtbar und Ebene, der Rest tut nichts
        local oldCF = CreateFrame
        CreateFrame = function()
            local f = {}
            function f:Show() self.shown = true end
            function f:Hide() self.shown = false end
            function f:SetShown(v) self.shown = v and true or false end
            function f:IsShown() return self.shown and true or false end
            function f:GetFrameLevel() return 1 end
            return setmetatable(f, { __index = function() return UIParent end })
        end
        local oldDead, oldTaxi = UnitIsDeadOrGhost, UnitOnTaxi
        UnitIsDeadOrGhost, UnitOnTaxi = function() return false end, function() return false end
        local oldSlots = NUM_BAG_SLOTS
        NUM_BAG_SLOTS = 4
        local ok, err = pcall(B.Open, "food")
        CreateFrame = oldCF
        if not ok then error(err, 0) end
        eq(B.Window():IsShown(), true, "offen")
        B.Check()
        eq(B.Window():IsShown(), true, "Prüfung schließt das Fenster nicht")
        B.Close()
        eq(B.Window():IsShown(), false, "X schließt es")
        B.Check()
        eq(B.Window():IsShown(), false, "bleibt zu (Erinnerung aus)")
        GuildPrideDB.buffFood, GuildPrideDB.restReminder = nil, nil
        NUM_BAG_SLOTS = oldSlots
        C_UnitAuras, C_Spell, C_Container = oldAuras, oldSpell, oldCont
        UnitIsDeadOrGhost, UnitOnTaxi = oldDead, oldTaxi
    end)
end
