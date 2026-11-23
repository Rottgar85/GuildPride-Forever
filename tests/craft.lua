-- Tests für das Handwerk (Guides, Tracker, Rezeptkarte, Fenster-Inhalte) – aus tests/run.lua
return function(test, eq, W, ns)
    W.Load("GuildPrideCraftGuides.lua")
    W.Load("GuildPrideCraftCore.lua")
    W.Load("GuildPrideCraftTracker.lua")
    W.Load("GuildPrideCraftCard.lua")
    W.Load("GuildPrideCraftWindow.lua")
    local G, Craft, Track, Card, Win = ns.CraftGuides, ns.Craft, ns.CraftTrack, ns.CraftCard, ns.CraftWindow

    -- Spiel-Funktionen für die Tests: feste Bestände, Namen
    local stock = {}
    local oldCount = GetItemCount
    GetItemCount = function(id) return stock[id] or 0 end
    local oldCItem = C_Item
    C_Item = nil
    local oldSpell = C_Spell
    C_Spell = { GetSpellName = function(id) return "Rezept" .. id end }

    test("Handwerk: jeder Guide ist lückenlos 1–300 und sortiert", function()
        for _, line in ipairs(G.ORDER) do
            local steps = G.Steps(line)
            eq(#steps > 0, true, G.Name(line) .. " hat Schritte")
            eq(steps[#steps].to, 300, G.Name(line) .. " endet bei 300")
            for i = 2, #steps do
                eq(steps[i].from >= steps[i - 1].from, true, G.Name(line) .. " sortiert")
                eq(steps[i].from <= steps[i - 1].to, true, G.Name(line) .. " ohne Lücke bei " .. steps[i].from)
            end
        end
    end)

    test("Handwerk: aktueller Schritt und Rest", function()
        local steps = G.Steps(164)
        local i = G.CurrentIndex(steps, 0); eq(steps[i].spell, 2660)
        i = G.CurrentIndex(steps, 30); eq(steps[i].spell, 3320, "bei 30 schon der nächste")
        eq(G.CurrentIndex(steps, 300), nil, "fertig")
        local s = steps[G.CurrentIndex(steps, 15)]
        eq(G.Remaining(s, 15), 17, "Hälfte geschafft")
        eq(G.Remaining(s, 0), 32)
    end)

    test("Handwerk: Ränge", function()
        local r, n = G.Rank(75); eq(r.max, 75); eq(n.max, 150); eq(n.learnAt, 50)
        r, n = G.Rank(300); eq(r.max, 300); eq(n, nil)
    end)

    test("Handwerk: Tracker zählt Zutaten × Herstellungen", function()
        GuildPrideDB.craftReagents = { [2660] = { made = 1, r = { { 2835, 1 } } }, [3320] = { made = 1, r = { { 2836, 2 } } } }
        Track.Clear()
        Track.AddRecipe(2660, 10)
        Track.AddRecipe(3320, 3)
        Track.AddItem(2770, 20)
        local need = Track.Needs()
        eq(need[2835], 10); eq(need[2836], 6); eq(need[2770], 20)
        stock[2835] = 4; stock[2836] = 6
        local miss = Track.Missing()
        eq(miss[2835], 6); eq(miss[2836], nil, "genug da"); eq(miss[2770], 20)
        local lines = Track.Lines()
        eq(lines[1].head, true)
        Track.SetRecipe(2660, 0)
        eq(Track.Needs()[2835], nil, "Rezept entfernt")
        Track.Clear()
        eq(Track.IsEmpty(), true)
    end)

    test("Handwerk: Rezeptkarte zeigt Zutaten mit Bestand und Guide", function()
        GuildPrideDB.craftReagents = { [2660] = { made = 1, r = { { 2835, 1 } } } }
        GuildPrideDB.craftChars = { [Craft.Me()] = { profs = { [164] = { skill = 10, max = 75 } }, known = {}, items = {} },
                                    ["Twink"] = { profs = {}, known = { [164] = { [2660] = true } }, items = { [2835] = 7 } } }
        stock[2835] = 3
        local lines = Card.Lines(2660, 5, 164)
        local all = table.concat(lines, "\n")
        eq(all:find("Rezept2660", 1, true) ~= nil, true, "Name")
        eq(all:find("Guide:", 1, true) ~= nil, true, "Guide-Schritt")
        eq(all:find("3/5", 1, true) ~= nil, true, "Bestand/Bedarf")
        eq(all:find("Twinks 7", 1, true) ~= nil, true, "Twink-Bestand")
        eq(all:find("Twinks: Twink", 1, true) ~= nil, true, "Twink kennt das Rezept")
    end)

    test("Handwerk: Fenster – Berufsliste, Guide-Zeilen, Kopf", function()
        local list = Win.ProfList()
        eq(list[1].line, 164, "eigener Beruf zuerst"); eq(list[1].mine, true)
        eq(#list, #G.ORDER)
        local lines, cur = Win.GuideLines(164)
        eq(cur, 1); eq(lines[1].current, true)
        local head = Win.Header(164)
        eq(head:find("10 / 75", 1, true) ~= nil, true)
        local _, note = Win.Header(185)
        eq(note ~= nil, true, "Kochen hat einen Rang-Hinweis")
        local alts = Win.AltLines()
        eq(#alts, 2)
    end)

    W.Load("GuildPrideCraftExtras.lua")
    local X = ns.CraftExtras

    test("Handwerk: Schritt abhaken springt weiter, Spiel-Abgleich markiert", function()
        local me = Craft.Me()
        GuildPrideDB.craftChars[me].profs[164].skill = 10
        local s = Craft.CurrentStep(164); eq(s.spell, 2660)
        Craft.ToggleSkip(164, s)
        eq(Craft.CurrentStep(164).spell, 3320, "übersprungen")
        local lines = Win.GuideLines(164)
        eq(lines[1].done, true); eq(lines[2].current, true)
        Craft.ToggleSkip(164, s)
        eq(Craft.CurrentStep(164).spell, 2660, "wieder da")
        GuildPrideDB.craftAll = { [164] = { [2660] = true } }
        eq(Craft.InGame(164, 2660), true); eq(Craft.InGame(164, 3320), false); eq(Craft.InGame(171, 1), nil)
        eq(Win.GuideLines(164)[2].text:find("nicht in deinem Spiel", 1, true) ~= nil, true)
        GuildPrideDB.craftAll = nil
    end)

    test("Handwerk: Route bis zum Rangende – Rezepte und fehlende Zutaten", function()
        GuildPrideDB.craftReagents = { [2660] = { made = 1, r = { { 2835, 1 } } }, [3320] = { made = 1, r = { { 2836, 2 } } } }
        stock[2835] = 0; stock[2836] = 0
        local recipes, items, unknown = Craft.RouteNeeds(164, 75, 10)
        eq(recipes[2660], G.Remaining(G.Steps(164)[1], 10))
        eq(recipes[3320], 42)
        eq(unknown, 0, "alle Zutaten bekannt (Guide-Daten)")
        eq(recipes[2661], 10, "Kupferkettengürtel")
        local byId = {}
        for _, it in ipairs(items) do byId[it.id] = it end
        eq(byId[2836].need, 84)
        eq(byId[2835].have, 7, "Twink zählt mit")
        Track.Clear()
        local n, target = Win.TrackRoute(164)
        eq(target, 75); eq(n >= 2, true)
        eq(Track.DB().recipes[3320], 42)
        Track.Clear()
    end)

    test("Handwerk: Rezeptfarbe aus verschiedenen Feldern", function()
        eq(Craft.DifficultyOf({ relativeDifficulty = 0 }), "orange")
        eq(Craft.DifficultyOf({ relativeDifficulty = 1 }), "yellow")
        eq(Craft.DifficultyOf({ difficulty = "optimal" }), "orange")
        eq(Craft.DifficultyOf({ skillType = "Trivial" }), "gray")
        eq(Craft.DifficultyOf({ difficulty = "easy" }), "green")
        eq(Craft.DifficultyOf({}), nil)
    end)

    test("Handwerk: jedes Guide-Rezept hat Zutaten", function()
        for line, steps in pairs(G.STEPS) do
            for _, s in ipairs(steps) do
                eq(G.REAGENTS[s[3]] ~= nil, true, G.Name(line) .. " Rezept " .. s[3])
            end
        end
    end)

    test("Handwerk: Anleitung – Menge, Zutaten, Bestand, Fehlendes", function()
        GuildPrideDB.craftReagents = {}
        stock[2835] = 10
        local lines, cur, total = Win.InstructionLines(164)
        eq(lines[1].current, true)
        eq(lines[1].text:find("23× ", 1, true) ~= nil, true, "noch 23 bei Stufe 10: " .. lines[1].text)
        eq(lines[2].item, 2835)
        eq(lines[2].text:find("23×", 1, true) ~= nil, true, "23 Steine")
        eq(lines[2].text:find("hast 17, fehlt 6", 1, true) ~= nil, true, "du 10 + Twink 7")
        eq(total > 300, true, "Herstellungen bis 300")
        -- Kasten „Als Nächstes“: nur der aktuelle Schritt mit seinen Zutaten
        local now = Win.NowLines(164)
        eq(now[1].current, true, "beginnt mit dem Schritt")
        eq(now[2].item, 2835, "dann die Zutat")
        for _, l in ipairs(now) do eq(l.step, now[1].step, "kein anderer Schritt") end
    end)

    test("Handwerk: dünne Scrollleiste nur, wenn die Liste länger ist als Platz", function()
        local oldCF = CreateFrame
        local function Obj()
            local o = { shown = true }
            return setmetatable(o, { __index = function(_, k)
                if k == "SetShown" then return function(self, v) self.shown = v and true or false end end
                if k == "Hide" then return function(self) self.shown = false end end
                if k == "SetMinMaxValues" then return function(self, a, b) self.min, self.max = a, b end end
                if k == "SetValue" then return function(self, v) self.value = v end end
                if k == "GetHeight" then return function() return 190 end end
                if k == "SetScript" then return function(self, n, f) self[n] = f end end
                if k == "CreateTexture" then return function() return Obj() end end
                return function() end
            end })
        end
        CreateFrame = function() return Obj() end
        local got
        local s = Craft.ThinScroll({}, function(v) got = v end)
        CreateFrame = oldCF
        eq(s.shown, false, "erst unsichtbar")
        s:Update(0, 8, 10)
        eq(s.shown, false, "passt alles hinein")
        s:Update(5, 30, 10)
        eq(s.shown, true); eq(s.max, 20); eq(s.value, 5)
        s.OnValueChanged(s, 7.4)
        eq(got, 7, "Ziehen blättert")
        got = nil
        s.updating = true; s.OnValueChanged(s, 3); s.updating = false
        eq(got, nil, "eigenes Setzen löst nichts aus")
    end)

    test("Handwerk: Rezept zeigt, was es herstellt, und hat ein Bild", function()
        GuildPrideDB.craftReagents[99123] = { made = 2, out = 2862, r = { { 2835, 1 } } }
        local out, made = Craft.OutputItem(99123)
        eq(out, 2862); eq(made, 2)
        eq(Craft.RecipeIcon(99123), Craft.ItemIcon(2862), "Bild des hergestellten Items")
        eq(Win.RowIcon({ item = 2835 }), Craft.ItemIcon(2835))
        eq(Win.RowIcon({ recipe = 99123 }), Craft.ItemIcon(2862))
        eq(Win.RowIcon({ text = "x" }), nil, "Textzeile ohne Bild")
        eq(Win.Icon("abc"):find("|Tabc:16:16", 1, true) ~= nil, true)
        GuildPrideDB.craftReagents[99123] = nil
    end)

    test("Handwerk: Fenster baut sich und wechselt alle vier Reiter ohne Fehler", function()
        local ok, err = pcall(function()
            Win.Show(164, "prof")
            for _, m in ipairs({ "codex", "profit", "guild", "prof" }) do Win.SetMode(m) end
            Win.Show(185)   -- Beruf, den du nicht hast
        end)
        eq(ok, true, tostring(err))
    end)

    test("Handwerk: Hinweise bei Schritt geschafft und Rang-Limit", function()
        local notes = X.ProgressNotes(164, 29, 30, 75)
        eq(#notes, 1)
        eq(notes[1]:find("Rezept3320", 1, true) ~= nil, true, "nennt den nächsten Schritt")
        notes = X.ProgressNotes(164, 69, 71, 75)
        local limit = false
        for _, t in ipairs(notes) do if t:find("Limit", 1, true) then limit = true end end
        eq(limit, true, "fast am Limit")
        eq(#X.ProgressNotes(164, 30, 30, 75), 0, "nichts passiert")
    end)

    test("Handwerk: Gewinnliste und Item-Tooltip", function()
        local oldAH = ns.AH
        ns.AH = { Key = function(id) return id end,
                  PriceFor = function(id) return ({ [2835] = 10, [2862] = 100 })[id] end,
                  Money = function(c) return c .. "c" end }
        GuildPrideDB.craftReagents = { [2660] = { made = 1, out = 2862, r = { { 2835, 1 } } } }
        GuildPrideDB.craftChars[Craft.Me()].known = { [164] = { [2660] = true } }
        local list = X.ProfitList()
        eq(#list, 1); eq(list[1].v.profit, 85, "100 × 0,95 − 10")
        eq(#Win.ProfitLines(), 1)
        Craft.Changed()
        local tip = X.TooltipLines(2835)
        local all = ""
        for _, l in ipairs(tip) do all = all .. l[1] .. l[2] end
        eq(all:find("Twink 7", 1, true) ~= nil, true, "Bestand des Twinks")
        eq(all:find("Guide braucht noch", 1, true) ~= nil, true, "Guide-Bedarf")
        ns.AH = oldAH
    end)

    W.Load("GuildPrideCraftMats.lua")
    W.Load("GuildPrideCraftBank.lua")
    W.Load("GuildPrideCraftMini.lua")
    W.Load("GuildPrideCraftAsk.lua")
    local Mats, Bank, Mini, Ask = ns.CraftMats, ns.CraftBank, ns.CraftMini, ns.CraftAsk

    test("Handwerk: Herkunft der Materialien", function()
        eq(Mats.Origin(2835) ~= nil, true, "Grober Stein")
        eq(Mats.Origin(2447):find("1+", 1, true) ~= nil, true, "Kraut mit Stufe")
        eq(Mats.Origin(999999), nil)
    end)

    test("Handwerk: Kosten bis Rangende, Schrittkosten, herstellbar", function()
        local oldAH = ns.AH
        ns.AH = { Key = function(id) return id end, PriceFor = function(id) return ({ [2835] = 5 })[id] end }
        GuildPrideDB.craftReagents = {}
        stock[2835] = 0; stock[2836] = 0
        local cost, unknown = Craft.RouteCost(164, 30, 10)
        local _, items = Craft.RouteNeeds(164, 30, 10)
        local miss = 0
        for _, it in ipairs(items) do if it.id == 2835 then miss = it.missing end end
        eq(cost, miss * 5, "fehlende Steine × Preis")
        eq(unknown, 0)
        eq(Craft.StepCost(2660, 10), 50)
        stock[2835] = 7
        eq(Craft.CanCraft(2660), 7); eq(Craft.CanCraft(3320), 3)
        ns.AH = oldAH
    end)

    test("Handwerk: Bank holt, was fehlt; Twink-Post rechnet den Bedarf des Twinks", function()
        GuildPrideDB.craftTrack = nil
        local wanted = Bank.Wanted()
        eq(wanted[2835] ~= nil, true, "Guide braucht Steine")
        local altNeed = Bank.AltNeeds("Twink")
        eq(next(altNeed), nil, "Twink hat keinen Beruf")
        GuildPrideDB.craftChars["Twink"].profs = { [164] = { skill = 1, max = 75 } }
        altNeed = Bank.AltNeeds("Twink")
        eq(altNeed[2835] ~= nil and altNeed[2835] > 0, true, "Twink braucht Steine (abzüglich seiner 7)")
        local targets = Bank.AltTargets()
        eq(#targets, 1); eq(targets[1].items[2835], math.min(altNeed[2835], 7), "nur was du dabei hast")
        GuildPrideDB.craftChars["Twink"].profs = {}
    end)

    test("Handwerk: Statistik und Kompaktansicht", function()
        GuildPrideDB.craftLog = nil
        Mini.Record(164, 10, 13)
        eq(Mini.TodayGain(164), 3)
        eq(Mini.PerHour(164) ~= nil, true)
        local lines = Mini.Lines()
        eq(lines[1].text:find("+3", 1, true) ~= nil, true, "Heute +3")
        eq(lines[2].text:find("kannst", 1, true) ~= nil or lines[2].text:find("Zutaten fehlen", 1, true) ~= nil, true)
    end)

    test("Handwerk: Abklingzeiten aller Charaktere", function()
        local now = GetServerTime()
        GuildPrideDB.craftChars["Twink"].cd = { mooncloth = now - 5, transmute = now + 7200 }
        local list = Mini.CooldownList()
        eq(#list, 2); eq(list[1].ready, true); eq(list[2].ready, false)
        eq(Mini.Left(30 * 60), "30 Min.")
        GuildPrideDB.craftChars["Twink"].cd = nil
    end)

    test("Handwerk: Gilde fragen – Antwort mit eigenem Charakter, gemerkt beim Fragenden", function()
        GuildPrideDB.craftChars[Craft.Me()].known = { [164] = { [2660] = true } }
        local hits = Ask.MyMatches("ezept26")
        eq(#hits >= 1, true, "Rezept2660 passt")
        W.sent = {}
        W.Receive("Anna", "CWQ:Rezept26")
        local reply
        for _, s in ipairs(W.sent) do if s.kind == "CWA" then reply = s end end
        eq(reply ~= nil, true, "geantwortet"); eq(reply.target, "Anna")
        GuildPrideDB.craftAsk = nil
        W.Receive("Bert", "CWA:Rezept26\031Bertie\0312660")
        local found = Ask.Find("rezept26")
        eq(#found, 1); eq(found[1].who, "Bert"); eq(found[1].char, "Bertie")
        local guild = Win.GuildLines("rezept26")
        eq(guild[1].text:find("Bert", 1, true) ~= nil, true, "Antwort steht im Gilde-Bereich")
    end)

    W.Load("GuildPrideCraftVendor.lua")
    test("Handwerk: Händler verkauft, was im Tracker fehlt – passende Menge, Bündel, Gold", function()
        local V = ns.CraftVendor
        local saved = { GetMerchantNumItems, GetMerchantItemID, GetMerchantItemInfo, GetMerchantItemMaxStack, BuyMerchantItem, GetMoney, C_MerchantFrame, UnitName, GetZoneText }
        -- Händler: [1] Grober Faden 2320 einzeln 10c, [2] Leere Phiole 3371 im 5er-Bündel für 20c
        local goods = { { 2320, 10, 1 }, { 3371, 20, 5 } }
        local bought = {}
        C_MerchantFrame = nil
        GetMerchantNumItems = function() return #goods end
        GetMerchantItemID = function(i) return goods[i][1] end
        GetMerchantItemInfo = function(i) return "x", 1, goods[i][2], goods[i][3], -1 end
        GetMerchantItemMaxStack = function() return 20 end
        BuyMerchantItem = function(i, n) bought[#bought + 1] = { i, n } end
        local money = 1000
        GetMoney = function() return money end
        UnitName = function(u) return u == "npc" and "Händlerin" or W.me end
        GetZoneText = function() return "Sturmwind" end
        stock[2320] = 0; stock[3371] = 1
        Track.Clear()
        Track.AddItem(2320, 25)   -- 25 Faden fehlen
        Track.AddItem(3371, 8)    -- 7 Phiolen fehlen → zwei 5er-Bündel
        V.open = true
        local list, total = V.Buyable()
        eq(#list, 2)
        local by = {}
        for _, b in ipairs(list) do by[b.id] = b end
        eq(by[2320].buy, 25); eq(by[3371].buy, 10, "aufgerundet auf ganze Bündel")
        eq(total, 25 * 10 + 10 * 4)
        local n = V.BuyAll()
        eq(n, 2)
        local count = { [1] = 0, [2] = 0 }
        for _, b in ipairs(bought) do count[b[1]] = count[b[1]] + (b[1] == 2 and 1 or b[2]) end
        eq(count[1], 25, "25 Faden in Stapeln"); eq(count[2], 2, "zwei Bündel")
        money = 10; bought = {}
        eq(V.BuyAll(), 0, "zu wenig Gold"); eq(#bought, 0)
        V.Remember()
        eq(V.Where(2320):find("Händlerin", 1, true) ~= nil, true, "Händler gemerkt")
        V.open = false
        Track.Clear()
        GetMerchantNumItems, GetMerchantItemID, GetMerchantItemInfo, GetMerchantItemMaxStack, BuyMerchantItem, GetMoney, C_MerchantFrame, UnitName, GetZoneText = unpack(saved)
    end)

    W.Load("GuildPrideCraftNPCs.lua")
    W.Load("GuildPrideCraftTips.lua")
    W.Load("GuildPrideCraftGather.lua")
    W.Load("GuildPrideCraftFish.lua")
    local NPC, Tips, Gather, Fish = ns.CraftNPC, ns.CraftTips, ns.CraftGather, ns.CraftFish

    test("Handwerk: Lehrer auf der Karte nach Fraktion, bester Lehrer, Guide-Händler", function()
        local a = NPC.ForLine(164, "A")
        local h = NPC.ForLine(164, "H")
        local hasBrikkA, hasSaruA = false, false
        for _, n in ipairs(a) do
            if n.name == "Brikk Keencraft" then hasBrikkA = true end
            if n.name == "Saru Steelfury" then hasSaruA = true end
        end
        eq(hasBrikkA, true, "neutraler Lehrer für Allianz"); eq(hasSaruA, false, "Horde-Lehrer nicht für Allianz")
        eq(#h > 0, true)
        eq(NPC.TitleRank("Artisan Blacksmith"), 3); eq(NPC.TitleRank("Journeyman Tailor"), 1)
        eq(NPC.GuideVendors(164)["Magnus Frostwake"], true)
        eq(NPC.GuideVendors(165)["Leonard Porter"], true, "Name ohne (A)")
        for _, line in ipairs(G.ORDER) do eq(#(NPC.TRAINERS[line] or {}) > 0, true, G.Name(line) .. " hat Lehrer") end
    end)

    test("Handwerk: Bauplan-Status je Charakter, Rezeptname aus Itemname", function()
        eq(Tips.RecipeNameOf("Pläne: Ebenholzklinge"), "Ebenholzklinge")
        GuildPrideDB.craftChars[Craft.Me()].profs[164] = { skill = 250, max = 300 }
        GuildPrideDB.craftChars["Twink"].profs = { [164] = { skill = 100, max = 150 } }
        GuildPrideDB.craftChars["Twink"].known = { [164] = { [10013] = true } }
        local st = Tips.PatternStatus(164, 10013, 257)
        local by = {}
        for _, s in ipairs(st) do by[s.name] = s.state end
        eq(by["Twink"], "known"); eq(by[Craft.Me()], "skill", "250 < 257")
        st = Tips.PatternStatus(164, 10013, 200)
        for _, s in ipairs(st) do by[s.name] = s.state end
        eq(by[Craft.Me()], "can")
        GuildPrideDB.craftChars["Twink"].profs = {}
        GuildPrideDB.craftChars[Craft.Me()].profs[164] = { skill = 10, max = 75 }
    end)

    test("Handwerk: Handels-Chat erkennt Anfragen und was du herstellen kannst", function()
        eq(Tips.IsRequest("LF Schmied für [Ebenholzklinge]"), true)
        eq(Tips.IsRequest("WTS Kupfererz"), false)
        GuildPrideDB.craftReagents = { [2660] = { made = 1, out = 2862, r = { { 2835, 1 } } } }
        GuildPrideDB.craftChars[Craft.Me()].known = { [164] = { [2660] = true } }
        local id, who = Tips.CanMake("suche |Hitem:2862::::|h[Wetzstein]|h")
        eq(id, 2862); eq(who[1], Craft.Me())
        eq(Tips.RecipeForItem(2862), 2660)
    end)

    test("Handwerk: Alt-Klick auf Rezept-Link trackt", function()
        Track.Clear()
        eq(Tips.TrackLink("enchant:2660"), true)
        eq(Track.DB().recipes[2660], 1)
        eq(Tips.TrackLink("item:2862"), true, "Item → Rezept")
        eq(Track.DB().recipes[2660], 2)
        Track.Clear()
    end)

    test("Handwerk: Sammelpunkte – Farbe, doppelte, grau → nächste Stufe", function()
        eq(Gather.Color(65, 50), "red"); eq(Gather.Color(65, 70), "orange"); eq(Gather.Color(65, 100), "yellow")
        eq(Gather.Color(65, 150), "green"); eq(Gather.Color(65, 170), "gray")
        GuildPrideDB.craftNodes = {}
        eq(Gather.Record(1429, 0.5, 0.5, 2770), true)
        eq(Gather.Record(1429, 0.501, 0.502, 2770), false, "gleiches Vorkommen")
        eq(Gather.Record(1429, 0.6, 0.5, 2770), true)
        eq(Gather.Record(1429, 0.6, 0.5, 99999), false, "kein Sammel-Item")
        eq(Gather.GrayHint(2770, 110) ~= nil, true, "Kupfer grau ab 101")
        eq(Gather.GrayHint(2770, 50), nil)
        eq(Gather.NextTier(186, 110), 2775, "Silber (75) ist die höchste nicht-graue Stufe")
    end)

    test("Handwerk: Angeln – bester Köder, Fang zählen", function()
        stock[6530] = 2; stock[6529] = 5
        eq(Fish.BestLure(), 6530, "Nachtkriecher vor Glänzendem Tand")
        Fish.session = {}
        GuildPrideDB.craftFish = nil
        Fish.Record(6291, 3)
        local _, n = Fish.SessionValue()
        eq(n, 3)
        eq(Fish.Stats().total[6291], 3)
        stock[6530] = 0; stock[6529] = 0
    end)

    test("Handwerk: Angel-Taste – Tasten und Maustasten richtig benannt", function()
        eq(Fish.KeyName("F"), "F")
        eq(Fish.KeyName("F", true, true, true), "ALT-CTRL-SHIFT-F", "Blizzard-Reihenfolge")
        eq(Fish.KeyName("Button4"), "BUTTON4")
        eq(Fish.KeyName("MiddleButton", true), "SHIFT-BUTTON3")
        eq(Fish.KeyName("LeftButton"), nil, "linke Maustaste tabu")
        eq(Fish.KeyName("RightButton"), nil)
        eq(Fish.KeyName("LSHIFT", true), nil, "nur Umschalt wartet weiter")
        eq(Fish.KeyName("ESCAPE"), false, "Esc bricht ab")
        eq(Fish.IsFishing(7620), true)
        eq(Fish.IsFishing(18248), true, "höherer Rang")
        GuildPrideDB.craftFishKey = "F"
        eq(Fish.Key(), "F")
        GuildPrideDB.craftFishKey = nil
        eq(Fish.Key(), nil)
    end)

    W.Load("GuildPrideCraftSell.lua")
    local Sell = ns.CraftSell
    test("Handwerk: Verkaufs-Berater – Händler, AH, nachsehen oder behalten", function()
        local oldAH = ns.AH
        ns.AH = { Key = function(id) return id end,
            PriceFor = function(id) return ({ [90002] = 5000, [90003] = 110, [90004] = 5000, [90007] = 900 })[id] end }
        W.itemInfo[90001] = { quality = 0, bindType = 0, classID = 15, sellPrice = 30 }   -- grau
        W.itemInfo[90002] = { quality = 1, bindType = 0, classID = 7, sellPrice = 100 }   -- AH viel besser
        W.itemInfo[90003] = { quality = 1, bindType = 0, classID = 7, sellPrice = 100 }   -- AH kaum besser
        W.itemInfo[90004] = { quality = 3, bindType = 1, classID = 4, sellPrice = 800 }   -- seelengebunden
        W.itemInfo[90005] = { quality = 2, bindType = 2, classID = 2, sellPrice = 400 }   -- grün, kein AH-Preis
        W.itemInfo[90006] = { quality = 1, bindType = 1, classID = 12, sellPrice = 0 }    -- Quest
        W.itemInfo[90007] = { quality = 1, bindType = 0, classID = 7, sellPrice = 10 }    -- Tracker braucht 3
        eq(Sell.Advice(90001, 4).verdict, "vendor", "grau zum Händler")
        eq(Sell.Advice(90001, 4).vendor, 120)
        local a = Sell.Advice(90002, 2)
        eq(a.verdict, "ah"); eq(a.ah, 9500, "5 % Gebühr abgezogen")
        eq(Sell.Advice(90003, 1).verdict, "vendor", "AH lohnt nicht")
        eq(Sell.Advice(90004, 1).verdict, "vendor", "gebunden geht nicht ins AH")
        eq(Sell.Advice(90005, 1).verdict, "check")
        eq(Sell.Advice(90005, 1, true).verdict, "vendor", "in der Tasche gebunden")
        eq(Sell.Advice(90006, 1).verdict, "keep", "Quest behalten")
        Track.Clear()
        Track.AddItem(90007, 3)
        eq(Sell.Advice(90007, 2).verdict, "keep", "Tracker braucht alles")
        local b = Sell.Advice(90007, 10)
        eq(b.keep, 3); eq(b.sell, 7); eq(b.verdict, "ah", "Überschuss ins AH")
        eq(b.ah, math.floor(900 * 0.95 * 7 + 0.5))
        eq(Sell.TooltipText(90006):find("Behalten", 1, true) ~= nil, true)
        Track.Clear()
        for id = 90001, 90007 do W.itemInfo[id] = nil end
        ns.AH = oldAH
    end)

    test("Handwerk: Lexikon zeigt alle Rezepte, wer sie kann, Filter fehlende", function()
        GuildPrideDB.craftAll = { [164] = { [2660] = true, [99001] = true } }
        GuildPrideDB.craftChars[Craft.Me()].known = { [164] = { [2660] = true } }
        local all = Win.CodexLines(164, "", false)
        eq(#all >= #G.STEPS[164] - 5, true, "Guide-Rezepte dabei")
        local miss = Win.CodexLines(164, "", true)
        for _, l in ipairs(miss) do eq(l.recipe ~= 2660, true, "gelerntes fehlt nicht") end
        local hit = Win.CodexLines(164, "rezept99001", false)
        eq(#hit, 1)
        GuildPrideDB.craftAll = nil
    end)

    test("Handwerk: günstigster Weg – selbst herstellen schlägt kaufen", function()
        local oldAH = ns.AH
        ns.AH = { Key = function(id) return id end, PriceFor = function(id) return ({ [2840] = 100, [2770] = 20 })[id] end }
        GuildPrideDB.craftVendor = nil
        GuildPrideDB.craftReagents = { [2657] = { made = 1, out = 2840, r = { { 2770, 1 } } } }   -- Kupfer schmelzen
        GuildPrideDB.craftChars[Craft.Me()].known = { [186] = { [2657] = true } }
        local p, how, via = Craft.CheapestPrice(2840)
        eq(p, 20); eq(how, "craft"); eq(via, 2657)
        GuildPrideDB.craftChars[Craft.Me()].known = {}
        p, how = Craft.CheapestPrice(2840)
        eq(p, 100); eq(how, "ah", "kann keiner schmelzen")
        GuildPrideDB.craftVendor = { [2840] = { p = 50 } }
        p, how = Craft.CheapestPrice(2840)
        eq(p, 50); eq(how, "vendor")
        GuildPrideDB.craftVendor = nil
        ns.AH = oldAH
    end)

    GetItemCount, C_Item, C_Spell = oldCount, oldCItem, oldSpell
    GuildPrideDB.craftChars, GuildPrideDB.craftReagents, GuildPrideDB.craftTrack = nil, nil, nil
end
