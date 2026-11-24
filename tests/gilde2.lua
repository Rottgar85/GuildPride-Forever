-- Tests: Raid-Bereitschaft, Quests der Gilde, Boss-Notizen, Jubiläen, Event-Auswertung,
-- Materialliste und Rückmeldung zu behobenen Fehlern
local SEP = "\031"

return function(test, eq, W, ns)
    W.Load("GuildPrideInstances.lua")
    W.Load("GuildPrideReady.lua")
    W.Load("GuildPrideGuildQuests.lua")
    W.Load("GuildPrideBossNotes.lua")
    W.Load("GuildPrideJubilee.lua")
    W.Load("GuildPrideEventStats.lua")
    W.Load("GuildPrideStock.lua")
    -- eigene Gildenliste: frühere Tests verändern sie
    local oldRoster = W.roster
    W.roster = { { "Tester", 3 }, { "Gm", 0 }, { "Offi", 1 }, { "Anna", 3 }, { "Bert", 3 }, { "Carl", 3 }, { "Ohne", 3 } }
    local oldGuildInfo = C_GuildInfo
    C_GuildInfo = { GuildRoster = function() end, GuildControlGetRankFlags = function(rankOrder) return { [9] = rankOrder <= 2 } end }
    W.Advance(61); W.Fire("GUILD_ROSTER_UPDATE")
    local function msg(kind, ...) return kind .. ":" .. table.concat({ ... }, SEP) end

    -- Gruppe nachbilden: { { Name, Leiter, Assistent }, … }
    local group = {}
    local function withGroup(list, fn)
        local old = { GetNumGroupMembers, IsInRaid, IsInGroup, UnitFullName, UnitIsGroupLeader, UnitIsGroupAssistant, UnitInParty, UnitInRaid }
        group = list
        local function at(unit) return group[tonumber(tostring(unit):match("%d+$"))] end
        GetNumGroupMembers = function() return #group end
        IsInRaid, IsInGroup = function() return true end, function() return true end
        UnitFullName = function(u) local m = at(u); if m then return m[1], "" end return W.me, "" end
        UnitIsGroupLeader = function(u) local m = at(u); return m and m[2] or false end
        UnitIsGroupAssistant = function(u) local m = at(u); return m and m[3] or false end
        local ok, err = pcall(fn)
        GetNumGroupMembers, IsInRaid, IsInGroup, UnitFullName, UnitIsGroupLeader, UnitIsGroupAssistant, UnitInParty, UnitInRaid = unpack(old, 1, 8)
        if not ok then error(err, 0) end
    end
    -- Taschen: { { itemID, Name, Anzahl }, … }
    local function withBags(bag, fn)
        local old = { C_Container, C_Item, NUM_BAG_SLOTS, GetInventoryItemDurability }
        NUM_BAG_SLOTS = 0
        C_Container = { GetContainerNumSlots = function() return #bag end,
            GetContainerItemInfo = function(_, i) return { itemID = bag[i][1], stackCount = bag[i][3] } end }
        C_Item = { GetItemInfo = function(id) for _, b in ipairs(bag) do if b[1] == id then return b[2] end end end }
        GetInventoryItemDurability = function(slot) if slot == 1 then return 0, 50 elseif slot == 2 then return 50, 50 end end
        local ok, err = pcall(fn)
        C_Container, C_Item, NUM_BAG_SLOTS, GetInventoryItemDurability = unpack(old, 1, 4)
        if not ok then error(err, 0) end
    end
    local function catch(fn)
        local sent, old = {}, ns.SendAddonMsg
        ns.SendAddonMsg = function(_, m, channel, to) sent[#sent + 1] = { msg = m, channel = channel, to = to }; return 0 end
        local ok, err = pcall(fn, sent)
        ns.SendAddonMsg = old
        if not ok then error(err, 0) end
    end

    -----------------------------------------------------------------
    -- Raid-Bereitschaft
    -----------------------------------------------------------------
    local R = ns.Ready
    test("Bereitschaft: Tränke, Elixiere und Essen am Namen erkennen (deutsch und englisch)", function()
        eq(R.KindOf("Großer Heiltrank"), "pot"); eq(R.KindOf("Major Mana Potion"), "pot")
        eq(R.KindOf("Elixier des Mungos"), "elix"); eq(R.KindOf("Flask of the Titans"), "elix"); eq(R.KindOf("Fläschchen der Titanen"), "elix")
        eq(R.KindOf("Kupferbarren"), nil); eq(R.KindOf("Rezept: Heiltrank"), nil, "Rezept"); eq(R.KindOf(nil), nil)
    end)

    test("Bereitschaft: eigener Status aus Taschen und Haltbarkeit", function()
        withBags({ { 1, "Großer Heiltrank", 5 }, { 2, "Major Mana Potion", 3 }, { 3, "Elixier des Mungos", 2 }, { 4, "Kupfer", 20 } }, function()
            local s = R.Status()
            eq(s.pots, 8); eq(s.elix, 2); eq(s.dur, 50); eq(s.broken, 1)
        end)
    end)

    test("Bereitschaft: Status kodieren und lesen, Unsinn wird begrenzt", function()
        local s = { dur = 87, broken = 0, food = true, pots = 12, elix = 3, foods = 20 }
        local d = R.Decode(R.Encode(s))
        for k, v in pairs(s) do eq(d[k], v, k) end
        eq(R.Decode(R.Encode({ dur = 5, broken = 1, food = nil, pots = 0, elix = 0, foods = 0 })).food, nil, "unbekannt bleibt unbekannt")
        eq(R.Decode("x"), nil)
        local bad = R.Decode(table.concat({ "999", "-5", "1", "999999", "a", "3" }, SEP))
        eq(bad.dur, 100); eq(bad.broken, 0); eq(bad.pots, 999); eq(bad.elix, 0)
    end)

    test("Bereitschaft: geantwortet wird nur Leiter oder Assistent der eigenen Gruppe, per Flüstern", function()
        catch(function(sent) withBags({}, function()
            withGroup({ { "Tester" }, { "Anna", true }, { "Bert", false, true }, { "Carl" } }, function()
                W.Receive("Carl", msg("RDQ", "1")); eq(#sent, 0, "weder Leiter noch Assistent")
                W.Receive("Ohne", msg("RDQ", "1")); eq(#sent, 0, "nicht in der Gruppe")
                W.Receive("Anna", msg("RDQ", "1")); eq(#sent, 1)
                eq(sent[1].channel, "WHISPER"); eq(sent[1].to, "Anna"); eq(sent[1].msg:sub(1, 4), "RDY:")
                W.Receive("Bert", msg("RDQ", "1")); eq(#sent, 2, "Assistent")
                GuildPrideDB.raidReady = false
                W.Receive("Anna", msg("RDQ", "1")); eq(#sent, 2, "abgeschaltet")
                GuildPrideDB.raidReady = nil
            end)
        end) end)
    end)

    test("Bereitschaft: Anfrage über Weiterleitung zählt nicht", function()
        catch(function(sent)
            withGroup({ { "Tester" }, { "Anna", true } }, function()
                W.Receive("Carl", msg("FWD", "Anna", "r1", msg("RDQ", "1"))); eq(#sent, 0)
            end)
        end)
    end)

    test("Bereitschaft: Liste zeigt Probleme zuerst, ohne Antwort und fremde Antworten getrennt", function()
        withGroup({ { "Tester", true }, { "Anna" }, { "Bert" }, { "Ohne" } }, function()
            withBags({}, R.Ask)
            W.Receive("Anna", msg("RDY", "95", "0", "1", "10", "2", "5"), "WHISPER")
            W.Receive("Bert", msg("RDY", "20", "1", "0", "0", "0", "0"), "WHISPER")
            W.Receive("Carl", msg("RDY", "95", "0", "1", "10", "2", "5"), "WHISPER")   -- nicht in der Gruppe
            local list = R.List()
            eq(#list, 4)
            local by, pos = {}, {}
            for i, e in ipairs(list) do by[e.name] = e; pos[e.name] = i end
            eq(by.Carl, nil); eq(by.Anna.problems, 0)
            eq(by.Bert.problems > 0, true); eq(by.Ohne.status, nil)
            eq(pos.Bert < pos.Anna, true, "Probleme zuerst")
            eq(pos.Ohne > pos.Anna, true, "ohne Antwort zuletzt")
        end)
    end)

    -----------------------------------------------------------------
    -- Quests der Gilde
    -----------------------------------------------------------------
    local Q = ns.GuildQuests
    local oldLog = ns.QuestLogList
    local function setLog(list) ns.QuestLogList = function() return list end end
    test("Gildenquests: wer hat dieselbe Quest, in der eigenen Zone zuerst", function()
        wipe(Q.data)
        setLog({ { id = 100, level = 20, name = "Wölfe" }, { id = 200, level = 22, name = "Banditen" }, { id = 300, level = 30, name = "Allein" } })
        local oldInfo, oldZone = GetGuildRosterInfo, GetRealZoneText
        GetRealZoneText = function() return "Westfall" end
        GetGuildRosterInfo = function(i)
            local m = W.roster[i]
            if not m then return nil end
            return m[1], "R", m[2], 20, "K", m[1] == "Bert" and "Westfall" or "Elwynn", "", "", m[1] ~= "Carl", 0, "WARRIOR"
        end
        W.Receive("Anna", msg("GQL", "100,200,999"))
        W.Receive("Bert", msg("GQL", "100"))
        W.Receive("Carl", msg("GQL", "100"))   -- offline
        local list = Q.List()
        GetGuildRosterInfo, GetRealZoneText = oldInfo, oldZone
        eq(#list, 2, "nur Quests mit anderen")
        eq(list[1].id, 100); eq(#list[1].who, 2, "Carl ist offline")
        eq(list[1].who[1].name, "Bert", "gleiche Zone zuerst"); eq(list[1].here, 1)
        eq(list[2].id, 200)
    end)

    test("Gildenquests: Liste wird geprüft und begrenzt, Abschalten leert", function()
        wipe(Q.data)
        local ids = {}
        for i = 1, 60 do ids[i] = tostring(1000 + i) end
        W.Receive("Anna", msg("GQL", table.concat(ids, ",")))
        local n = 0
        for _ in pairs(Q.data.Anna.set) do n = n + 1 end
        eq(n, 25)
        W.Receive("Anna", msg("GQL", "5,abc,-3,99999999,6"))
        eq(Q.data.Anna.set[5], true); eq(Q.data.Anna.set[6], true); eq(Q.data.Anna.set[99999999], nil)
        W.Receive("Anna", msg("GQL", "-"))
        eq(next(Q.data.Anna.set), nil)
        W.sent = {}
        GuildPrideDB.guildQuests = false
        Q.Share(true); eq(#W.sent, 0, "aus: nichts senden")
        GuildPrideDB.guildQuests = nil
        Q.Share(true); eq(#W.sent, 1); eq(W.sent[1].msg, msg("GQL", "100,200,300")); eq(W.sent[1].target, "@CHANNEL")
    end)
    test("Gildenquests: unverändert wird nicht erneut gesendet", function()
        W.sent = {}
        Q.Share(); eq(#W.sent, 0)
        setLog({ { id = 100, level = 20, name = "Wölfe" } })
        W.Advance(60); Q.Share(); eq(#W.sent, 1)
        ns.QuestLogList = oldLog
    end)

    -----------------------------------------------------------------
    -- Boss-Notizen
    -----------------------------------------------------------------
    local B = ns.BossNotes
    test("Boss-Notizen: nur Offiziere schreiben, fremde nur mit zwei gleichen Meldungen", function()
        W.canMotd = false
        eq(B.Save(nil, "r:ony", "Onyxia", "Phase 2: Feuer ausweichen"), false)
        W.canMotd = true
        W.sent = {}
        eq(B.Save(nil, "r:ony", "Onyxia", "Phase 2: |cffff0000Feuer|r ausweichen"), true)
        W.canMotd = false
        local list = B.For("r:ony")
        eq(#list, 1); eq(list[1].boss, "Onyxia"); eq(list[1].text:find("|", 1, true), nil, "ohne Farbcodes")
        eq(W.sent[1].kind, "BOS")
        -- fremde Nachricht: Offizier sofort, Mitglied erst mit Bestätigung
        local t = W.server
        W.Receive("Anna", msg("BOS", "Anna-5-1", t, "Anna", "0", "r:ony", "X", "Unfug")); eq(#B.For("r:ony"), 1, "Anna ist kein Offizier")
        W.Receive("Offi", msg("BOS", "Offi-6-1", t, "Offi", "0", "r:ony", "Wächter", "Kiten")); eq(#B.For("r:ony"), 2)
        local m = msg("BOS", "Offi-7-1", t, "Offi", "0", "dm", "VanCleef", "Adds")
        W.Receive("Anna", m); eq(#B.For("dm"), 0)
        W.Receive("Bert", m); eq(#B.For("dm"), 1)
        -- zwei Mitglieder zusammen können keine Notiz eines Nicht-Offiziers durchsetzen
        local fake = msg("BOS", "Anna-9-1", t, "Anna", "0", "dm", "X", "Unfug")
        W.Receive("Anna", fake); W.Receive("Bert", fake); eq(#B.For("dm"), 1, "Verfasser ist kein Offizier")
        W.Receive("Offi", msg("BOS", "Offi-8-1", t, "Offi", "0", "gibtsnicht", "X", "Y")); eq(B.Count(), 3, "unbekannte Instanz")
    end)
    test("Boss-Notizen: ändern und löschen, ältere Fassung gewinnt nicht", function()
        W.canMotd = true
        local e = B.For("dm")[1]
        eq(B.Save(e.id, "dm", "VanCleef", "neu"), true); eq(B.For("dm")[1].text, "neu")
        W.canMotd = false
        W.Receive("Offi", msg("BOS", e.id, 5, "Offi", "0", "dm", "VanCleef", "uralt")); eq(B.For("dm")[1].text, "neu")
        W.canMotd = true
        eq(B.Delete(e.id), true); eq(#B.For("dm"), 0)
        W.canMotd = false
    end)
    test("Boss-Notizen: passende Instanz am Zonennamen", function()
        local old = GetInstanceInfo
        GetInstanceInfo = function() return "Onyxia's Lair", "raid" end
        eq(B.Here(), "r:ony")
        GetInstanceInfo = function() return "Elwynn", "none" end
        eq(B.Here(), nil)
        GetInstanceInfo = old
    end)

    -----------------------------------------------------------------
    -- Jubiläen
    -----------------------------------------------------------------
    local J = ns.Jubilee
    test("Jubiläen: 30, 100 Tage, halbes Jahr und jedes Jahr; nur genaue Daten, keine Twinks, keine Ehemaligen", function()
        local DAY = 86400
        eq(J.Next(0, 29 * DAY, 7), 30); eq(J.Next(0, 31 * DAY, 7), nil); eq(J.Next(0, 99 * DAY, 7), 100)
        eq(J.Next(0, 182 * DAY - 10, 1), 182); eq(J.Next(0, 364 * DAY, 7), 365); eq(J.Next(0, 729 * DAY, 7), 730)
        local now = W.server
        local h = ns.GuildTable("history")
        local keep = {}
        for k, v in pairs(h) do keep[k] = v; h[k] = nil end
        h.Anna = { first = now - 98 * DAY, joins = {}, leaves = {}, ranks = {} }
        h.Bert = { first = now - 98 * DAY, approx = true, joins = {}, leaves = {}, ranks = {} }
        h.Fremd = { first = now - 98 * DAY, left = now, joins = {}, leaves = {}, ranks = {} }
        h.Carl = { first = now - 28 * DAY, joins = {}, leaves = {}, ranks = {} }
        local oldMain = ns.MainOf
        ns.MainOf = function(n) return n == "Carl" and "Gm" or n end
        local list = J.Upcoming(7)
        eq(#list, 1); eq(list[1].name, "Anna"); eq(list[1].days, 100)
        eq(J.Text():find("Anna", 1, true) ~= nil, true)
        ns.MainOf = oldMain
        for k in pairs(h) do h[k] = nil end
        eq(J.Text(), nil, "nichts: keine Zeile")
        for k, v in pairs(keep) do h[k] = v end
    end)

    -----------------------------------------------------------------
    -- Event-Auswertung
    -----------------------------------------------------------------
    test("Event-Auswertung: Quote, Serie, Wochentage und Monate", function()
        local function rec(day, yes, present)
            return { title = "Raid", t = os.time({ year = 2026, month = 11, day = day, hour = 20 }), yes = yes, present = present }
        end
        local s = ns.EventStats.Compute({
            a = rec(2, { "Anna", "Bert" }, { "Anna", "Bert" }),        -- Montag
            b = rec(9, { "Anna", "Bert" }, { "Anna" }),                -- Montag
            c = rec(11, { "Anna" }, { "Anna", "Carl" }),               -- Mittwoch
            d = "Unsinn",
        })
        eq(s.events, 3)
        eq(s.players[1].name, "Anna"); eq(s.players[1].came, 3); eq(s.players[1].yes, 3); eq(s.players[1].streak, 3)
        local by = {}
        for _, p in ipairs(s.players) do by[p.name] = p end
        eq(by.Bert.came, 1); eq(by.Bert.yes, 2); eq(by.Bert.streak, 0, "zuletzt gefehlt")
        eq(by.Carl.present, 1, "ohne Zusage da"); eq(by.Carl.yes, 0)
        eq(s.weekdays[2].n, 2); eq(s.weekdays[2].avg, 1.5); eq(s.weekdays[4].n, 1); eq(s.weekdays[4].avg, 2)
        eq(s.months[1].key, "2026-11"); eq(s.months[1].n, 3)
        eq(ns.EventStats.Compute({}).events, 0)
        eq(#ns.EventStats.Lines({}) > 0, true, "leer: Hinweis")
    end)

    -----------------------------------------------------------------
    -- Materialliste
    -----------------------------------------------------------------
    local M = ns.Stock
    test("Materialliste: Offiziere legen an, jeder sagt nur für sich zu", function()
        W.canMotd = false
        eq(M.Add(13444, 20), false)
        W.canMotd = true
        W.sent = {}
        eq(M.Add(13444, 20), true); eq(M.Add(0, 5), false); eq(M.Add(13444, 0), false)
        W.canMotd = false
        local g = M.List()[1]
        eq(g.item, 13444); eq(g.qty, 20); eq(g.sum, 0); eq(W.sent[1].kind, "MGO")
        W.sent = {}
        eq(M.Pledge(g.id, 5), true); eq(W.sent[1].kind, "MGC")
        W.Receive("Anna", msg("MGC", g.id, W.server, "7"))
        eq(M.List()[1].sum, 12); eq(M.List()[1].mine, 5)
        -- niemand sagt für andere zu: auch nicht weitergeleitet
        W.Receive("Carl", msg("FWD", "Bert", "z1", msg("MGC", g.id, W.server, "9"))); eq(M.List()[1].sum, 12)
        W.Receive("Anna", msg("MGC", g.id, W.server - 100, "99")); eq(M.List()[1].sum, 12, "ältere Zusage")
        W.Advance(5); W.Receive("Anna", msg("MGC", g.id, W.server, "0")); eq(M.List()[1].sum, 5, "zurückgezogen")
        W.Receive("Anna", msg("MGC", "gibtsnicht", W.server, "5")); eq(#M.List(), 1)
    end)
    test("Materialliste: Offizier löscht, Mitglied nicht; Abgleich schickt Ziele und eigene Zusage", function()
        local id = M.List()[1].id
        eq(M.Remove(id), false)
        W.sent = {}
        W.Receive("Bert", msg("MGQ", "1"))
        local kinds = {}
        for _, m in ipairs(W.sent) do kinds[m.kind] = (kinds[m.kind] or 0) + 1 end
        eq(kinds.MGO, 1); eq(kinds.MGC, 1)
        W.canMotd = true
        eq(M.Remove(id), true); eq(#M.List(), 0)
        W.canMotd = false
        W.Receive("Anna", msg("MGO", "Anna-1-1", W.server, "Anna", "0", "13444", "5")); eq(#M.List(), 0, "Anna ist kein Offizier")
        local fake = msg("MGO", "Anna-2-1", W.server, "Anna", "0", "13444", "5")
        W.Receive("Anna", fake); W.Receive("Bert", fake); eq(#M.List(), 0, "auch nicht zu zweit")
        W.Receive("Offi", msg("MGO", "Offi-1-1", W.server, "Offi", "0", "13444", "5")); eq(#M.List(), 1)
    end)

    test("Abgleich: gleicher Stand bleibt still, nach einer Offiziers-Antwort oder zwei anderen auch", function()
        W.sent = {}
        W.Receive("Bert", msg("MGQ", ns.SyncHash(ns.GuildTable("stock"))))
        for _, m in ipairs(W.sent) do eq(m.kind ~= "MGO", true, "gleicher Stand") end
        local old, waiting = C_Timer.After, {}
        local function Ask(heard)
            waiting = {}
            C_Timer.After = function(_, fn) waiting[#waiting + 1] = fn end
            W.Receive("Bert", msg("MGQ", "anders"))
            C_Timer.After = old
            W.Advance(1)
            for _, who in ipairs(heard) do ns.SyncHeard("MGO", who) end
            W.sent = {}
            for _, fn in ipairs(waiting) do fn() end
            local n = 0
            for _, m in ipairs(W.sent) do if m.kind == "MGO" then n = n + 1 end end
            return n
        end
        eq(Ask({}) > 0, true); eq(Ask({ "Anna" }) > 0, true, "eine Antwort reicht nicht")
        eq(Ask({ "Anna", "Carl" }), 0); eq(Ask({ "Offi" }), 0)
    end)

    -----------------------------------------------------------------
    -- Rückmeldung zu behobenen Fehlern
    -----------------------------------------------------------------
    test("Fehler-Rückmeldung: Betroffene erfahren es einmal, nur vom Entwickler", function()
        local old = { ns.IsMarked, ns.IsDev, ns.SendAddonMsg, ns.VERSION, ns.Print, GuildPrideDB.errors, GuildPrideDB.dev }
        local sent, said, dev = {}, {}, false
        ns.IsMarked = function(n) return n == "Chef" end
        ns.IsDev = function() return dev end
        ns.SendAddonMsg = function(_, m, channel, to) sent[#sent + 1] = { msg = m, to = to }; return 0 end
        ns.VERSION = "9.9.9"
        ns.Print = function(t) said[#said + 1] = t end
        GuildPrideDB.errorShare, GuildPrideDB.dev = true, nil
        local e = { msg = "Core/X.lua:1: kaputt\nzweite Zeile", stack = "", n = 1, v = "9.9.9" }
        GuildPrideDB.errors = { e }
        W.Load("GuildPrideErrorShare.lua")
        local ok, err = pcall(function()
            local S = ns.ErrorShare
            W.Receive("Chef", "DVA:" .. ns.CLIENT_TAG, "GUILD")
            local pieces = sent
            dev, sent = true, {}
            for _, m in ipairs(pieces) do W.Receive("Anna", m.msg, "WHISPER") end
            local g = S.List()[1]
            S.Fixed(g.key); eq(#S.List(), 0, "aus der Liste")
            W.sent = {}
            S.Hello()
            local dvf
            for _, m in ipairs(W.sent) do if m.kind == "DVF" then dvf = m end end
            eq(dvf ~= nil, true, "beim Melden dabei")
            dev, said = false, {}
            W.Receive("Fremder", dvf.msg, "GUILD"); eq(#said, 0, "fremder Absender")
            W.Receive("Chef", dvf.msg, "GUILD"); eq(#said, 1); eq(e.fixed, true)
            W.Receive("Chef", dvf.msg, "GUILD"); eq(#said, 1, "nur einmal")
        end)
        ns.IsMarked, ns.IsDev, ns.SendAddonMsg, ns.VERSION, ns.Print, GuildPrideDB.errors, GuildPrideDB.dev = unpack(old, 1, 7)
        GuildPrideDB.errorShare = nil
        if not ok then error(err, 0) end
    end)

    test("Weitere Sprachen: Schlüssel gibt es wirklich, Platzhalter sind gleich, Rest fällt auf Englisch zurück", function()
        local L2, oldLocale = {}, GetLocale
        GetLocale = function() return "frFR" end
        local ok, err = pcall(function()
            assert(loadfile("Core/GuildPrideLocale.lua"))("GuildPrideForever", L2)
            assert(loadfile("Core/GuildPrideLocaleMore.lua"))("GuildPrideForever", L2)
        end)
        GetLocale = oldLocale
        eq(ok, true, tostring(err))
        local function holders(s) local out = {}; for p in s:gsub("%%%%", ""):gmatch("%%[%d%.]*[a-z]") do out[#out + 1] = p end; return table.concat(out, " ") end
        for lang, t in pairs(L2.MORE_LOCALES) do
            for de, text in pairs(t) do
                eq(L2.HasEnglish(de), true, lang .. ": kein Text im Addon: " .. de:sub(1, 60))
                eq(holders(text), holders(de), lang .. ": " .. de:sub(1, 60))
            end
        end
        eq(L2.L["Einstellungen"], "Réglages", "Französisch")
        eq(L2.L["Gildenfenster öffnen"], "Open guild window", "fehlt: Englisch")
        eq(L2.L["gibt es nicht"], "gibt es nicht")
    end)

    W.roster, C_GuildInfo = oldRoster, oldGuildInfo
    W.Advance(60); W.Fire("GUILD_ROSTER_UPDATE")
end
