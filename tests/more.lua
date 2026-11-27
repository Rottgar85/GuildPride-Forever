-- Tests für 2.39: Verkaufshelfer, Gildenbank, Offene Dungeons, Willkommen, Export/Import,
-- Ankunftszeiten, sparsamer Preistausch (aus tests/run.lua aufgerufen)
return function(test, eq, W, ns)
    local SEP = "\031"
    local function has(list, kind)
        for _, s in ipairs(list) do if s.kind == kind then return s end end
    end

    -----------------------------------------------------------------
    -- Verkaufshelfer
    -----------------------------------------------------------------
    W.Load("GuildPrideAHSell.lua")
    local AH = ns.AH

    test("Verkaufs-Hinweis: erst ab 3 Tagen Verlauf und 25 % über dem Schnitt", function()
        local now = math.floor(W.server)
        local link = "|Hitem:41001:0:0:0:0:0:0:0|h"
        for d = 1, 3 do AH.RecordOwn("41001", 100, 1, now - (5 - d) * 86400) end
        eq(AH.SellHint(link), false, "Preis wie im Schnitt")
        AH.RecordOwn("41001", 200, 1, now)   -- heute 200c, Schnitt (100+100+100+200)/4 = 125
        eq(AH.SellHint(link), true)
        eq(AH.TooltipSell(link):find("60 %", 1, true) ~= nil, true, "60 % über dem Schnitt")
        GuildPrideDB.ahSellHint = false
        eq(AH.SellHint(link), false, "abschaltbar")
        GuildPrideDB.ahSellHint = true
        eq(AH.SellHint("|Hitem:41002:0:0:0:0:0:0:0|h"), false, "ohne Verlauf kein Hinweis")
        W.itemInfo[41001] = { quality = 1, bindType = 1, classID = 7, sellPrice = 5 }
        eq(AH.SellHint(link), false, "seelengebunden: nie")
        W.itemInfo[41001] = nil
    end)

    test("Auktions-Tipps: was gerade über dem Schnitt liegt, aus Taschen und Bank, der größte Gewinn zuerst", function()
        local now = math.floor(W.server)
        for _, e in ipairs({ { "41011", 200 }, { "41012", 1000 }, { "41013", 101 } }) do
            for d = 1, 3 do AH.RecordOwn(e[1], 100, 1, now - (5 - d) * 86400) end
            AH.RecordOwn(e[1], e[2], 1, now)
            W.itemInfo[tonumber(e[1])] = { quality = 1, bindType = 0, classID = 7, sellPrice = 5 }
        end
        W.itemInfo[41014] = { quality = 1, bindType = 0, classID = 7, sellPrice = 5 }   -- ohne Preis
        local oldBags, oldCraft = AH.BagItems, ns.Craft
        AH.BagItems = function() return { { key = "41011", link = "|Hitem:41011:0:0:0:0:0:0:0|h", itemID = 41011, count = 20 },
            { key = "41013", link = "|Hitem:41013:0:0:0:0:0:0:0|h", itemID = 41013, count = 5 },
            { key = "41014", link = "|Hitem:41014:0:0:0:0:0:0:0|h", itemID = 41014, count = 5 } } end
        ns.Craft = { MyEntry = function() return { items = { [41012] = 3, [41011] = 25, [41013] = 1 } } end,
            Count = function(id) if id == 41011 then return 20, 5 elseif id == 41012 then return 0, 3 end return 1, 0 end }
        GuildPrideDB.ahSellHint = false   -- die Liste hängt nicht am Hinweis in den Taschen
        local ok, err = pcall(function()
            local l = AH.SellTips()
            eq(#l, 2)
            eq(l[1].itemID, 41012); eq(l[1].bags, 0); eq(l[1].bank, 3); eq(l[1].price, 1000); eq(l[1].pct > 25, true)
            eq(l[2].itemID, 41011); eq(l[2].bags, 20); eq(l[2].bank, 5); eq(l[2].pct, 60); eq(l[2].gain > 0, true)
            ns.Craft = nil
            eq(#AH.SellTips(), 1, "ohne Handwerk nur die Taschen")
        end)
        AH.BagItems, ns.Craft, GuildPrideDB.ahSellHint = oldBags, oldCraft, true
        for id = 41011, 41014 do W.itemInfo[id] = nil end
        if not ok then error(err, 0) end
    end)

    test("Briefkasten: Verkäufe, Gold und abgelaufene Auktionen gezählt", function()
        AUCTION_EXPIRED_MAIL_SUBJECT = "Auktion abgelaufen: %s"
        AUCTION_REMOVED_MAIL_SUBJECT = "Auktion abgebrochen: %s"
        AUCTION_OUTBID_MAIL_SUBJECT = "Überboten: %s"
        local mails = {
            { "Auktion erfolgreich: Leinen", 500, "seller" },
            { "Auktion erfolgreich: Kupfer", 250, "seller" },
            { "Auktion abgelaufen: Wolle", 0 },
            { "Überboten: Eisen", 100 },
            { "Hallo", 0 },
        }
        GetInboxNumItems = function() return #mails end
        GetInboxHeaderInfo = function(i) local m = mails[i]; return nil, nil, "x", m[1], m[2] end
        GetInboxInvoiceInfo = function(i) return mails[i][3] end
        local s = AH.MailSummary()
        eq(s.sold, 2); eq(s.money, 750); eq(s.expired, 1); eq(s.outbid, 1); eq(s.won, 0)
        local text = AH.MailSummaryText(s)
        eq(text:find("2 verkauft", 1, true) ~= nil, true); eq(text:find("1 abgelaufen", 1, true) ~= nil, true)
        eq(AH.MailSummaryText({ sold = 0, money = 0, expired = 0, cancelled = 0, won = 0, outbid = 0 }), nil, "nichts: keine Zeile")
        GetInboxNumItems, GetInboxHeaderInfo, GetInboxInvoiceInfo = nil, nil, nil
    end)

    -----------------------------------------------------------------
    -- Sparsamer Preistausch
    -----------------------------------------------------------------
    local function Capture(fn)
        local out, oldSend = {}, AH.SendRaw
        AH.SendRaw = function(m) out[#out + 1] = m end
        local ok, err = pcall(fn)
        AH.SendRaw = oldSend
        assert(ok, err)
        return out
    end

    test("Preistausch: Antwort schickt nur Tage, die dem Frager fehlen", function()
        local today = math.floor(W.server / 86400)
        for d = 1, 4 do AH.RecordOwn("41010", 100 + d, 1, (today - 4 + d) * 86400 + 60) end
        eq(#AH.HistorySince("41010", today - 1), 1, "nur heute")
        eq(#AH.HistorySince("41010"), 4)
        AH.OnMessage("Q:" .. AH.Side() .. ":41010", "Fremder")
        AH.OnMessage("K:" .. AH.Side() .. ":41010:" .. (today - 1), "Fremder")
        local sent = Capture(function() AH._tick(math.huge) end)
        local hist
        for _, m in ipairs(sent) do if m:sub(1, 2) == "H:" then hist = m end end
        eq(hist ~= nil, true, "Verlauf geschickt")
        local _, _, list = AH.DecodeH(hist)
        eq(#list, 1, "nur der fehlende Tag")
    end)

    test("Preistausch: kein zweiter Verlauf, wenn ihn schon jemand geschickt hat", function()
        local today = math.floor(W.server / 86400)
        AH.OnMessage("Q:" .. AH.Side() .. ":41010", "Fremder2")
        AH.OnMessage(AH.EncodeH(AH.Side(), "41010", { { d = today - 2, p = 103 }, { d = today - 1, p = 104 } }), "Dritter")
        local sent = Capture(function() AH._tick(math.huge) end)
        for _, m in ipairs(sent) do eq(m:sub(1, 2) ~= "H:", true, "kein doppelter Verlauf") end
    end)

    -----------------------------------------------------------------
    -- Gildenbank
    -----------------------------------------------------------------
    test("Gildenbank: Protokoll lesen, filtern, Wochensumme", function()
        local tx = {
            { "deposit", "Anna", "[Leinen]", 20, 1, 1, 0, 0, 1, 2 },
            { "withdraw", "Bert", "[Kupfer]", 5, 1, 1, 0, 0, 0, 3 },
            { "withdraw", "Bert", "[Eisen]", 2, 1, 1, 0, 0, 9, 0 },   -- vor 9 Tagen: nicht in der Woche
        }
        QueryGuildBankLog = function() end
        GetGuildBankTransaction = function(_, i) return unpack(tx[i]) end
        GetNumGuildBankTransactions = function() return #tx end
        GetNumGuildBankTabs = function() return 1 end
        GetNumGuildBankMoneyTransactions = function() return 1 end
        GetGuildBankMoneyTransaction = function() return "deposit", "Anna", 5000, 0, 0, 0, 1 end
        W.Load("GuildPrideBank.lua")
        local Bank = ns.Bank
        eq(Bank.Available(), true)
        Bank.ReadTab(1, W.server); Bank.ReadMoney(W.server)
        local all = Bank.Entries()
        eq(#all, 4)
        eq(all[1].who, "Anna", "neueste zuerst (Gold vor 1 Std.)")
        eq(#Bank.Entries("ber"), 2, "Filter ohne Groß/klein")
        local week = Bank.WeekTotals(W.server)
        eq(#week, 2)
        eq(week[1].who, "Bert"); eq(week[1].withdraw, 5, "alter Eintrag zählt nicht")
        eq(week[2].deposit, 20); eq(week[2].gold, 5000)
        eq(Bank.LineText(all[3], W.server):find("Leinen", 1, true) ~= nil, true)
        eq(Bank.Ago(0, 0, 1, 2), 26 * 3600)
        for _, k in ipairs({ "QueryGuildBankLog", "GetGuildBankTransaction", "GetNumGuildBankTransactions",
                             "GetNumGuildBankTabs", "GetNumGuildBankMoneyTransactions", "GetGuildBankMoneyTransaction" }) do
            rawset(_G, k, nil)
        end
    end)

    -----------------------------------------------------------------
    -- Offene Dungeons und Gruppen-Vorschläge
    -----------------------------------------------------------------
    test("Offene Dungeons: eintragen, senden, empfangen, Übersicht", function()
        W.Load("GuildPrideNeeds.lua")
        local N = ns.Needs
        eq(N.Find("dm").key, "dm"); eq(N.Find("r:ony").key, "ony"); eq(N.Find("quatsch"), nil)
        eq(N.Encode({ dm = true, ["r:ony"] = true, x = true }), "dm,r:ony", "unbekannte fallen raus")
        eq(#N.Decode("dm,quatsch,sfk"), 2)
        W.sent = {}
        eq(N.Set("dm", true), true)
        local s = has(W.sent, "DND")
        eq(s ~= nil, true, "Liste verschickt")
        eq(s.msg:find("dm", 1, true) ~= nil, true)
        W.Receive("Anna", "DND:" .. (W.server + 50) .. SEP .. "dm,sfk")
        W.Receive("Fremdling", "DND:" .. (W.server + 50) .. SEP .. "dm")   -- kein Mitglied
        eq(#N.Who("dm"), 2, "ich und Anna, kein Fremder")
        eq(N.Overview()[1].key, "dm", "Dungeon mit den meisten online zuerst")
        W.Receive("Anna", "DND:" .. (W.server - 1000) .. SEP .. "")   -- ältere Liste ersetzt keine neuere
        eq(#N.Who("sfk"), 1)
        N.Set("dm", false)
        eq(N.IsMine("dm"), false)
    end)

    test("Gruppen-Vorschläge: Stufe passt, Heiler für fehlenden Heiler, wer braucht zuerst", function()
        local N = ns.Needs
        local oldRoster, oldInfo = W.roster, GetGuildRosterInfo
        local classes = { Anna = "PRIEST", Bert = "WARRIOR", Carl = "MAGE", Dora = "PRIEST" }
        W.roster = { { W.me, 3, 18 }, { "Anna", 3, 17 }, { "Bert", 3, 19 }, { "Carl", 3, 60 }, { "Dora", 3, 18 } }
        GetGuildRosterInfo = function(i)
            local m = W.roster[i]
            if not m then return nil end
            return m[1], "Rang", m[2], m[3], "", "Zone", "", "", true, 0, classes[m[1]] or "WARRIOR"
        end
        W.Fire("GUILD_ROSTER_UPDATE")
        local oldParty, oldRaid = UnitInParty, UnitInRaid
        UnitInParty = function() return false end; UnitInRaid = function() return false end
        N.Store(ns.Normalize("Dora"), W.server + 500, { "dm" })
        local list = N.Suggest({ name = "Die Todesminen", min = 16, max = 21 }, "H", 5)
        eq(#list, 2, "Carl zu hoch, Bert kein Heiler")
        -- Anna (aus dem Test davor) und Dora brauchen die Todesminen beide
        eq(list[1].needs and list[2].needs, true, "wer den Dungeon braucht, steht vorn")
        eq(list[2].role, "H")
        N.Store(ns.Normalize("Dora"), W.server + 600, {})
        list = N.Suggest({ name = "Die Todesminen", min = 16, max = 21 }, "H", 5)
        eq(list[2].name, ns.Normalize("Dora")); eq(list[2].needs, false)
        eq(N.SuggestText(list):find("Dora", 1, true) ~= nil, true)
        eq(#N.Suggest(nil, "", 10), 4, "ohne Dungeon: alle Online-Mitglieder außer mir")
        W.roster, GetGuildRosterInfo = oldRoster, oldInfo
        UnitInParty, UnitInRaid = oldParty, oldRaid
        W.Fire("GUILD_ROSTER_UPDATE")
    end)

    -----------------------------------------------------------------
    -- Willkommens-Paket
    -----------------------------------------------------------------
    test("Willkommen: Text des Fensters", function()
        W.Load("GuildPrideWelcomePack.lua")
        local Wp = ns.WelcomePack
        eq(Wp.Body():find("Testgilde", 1, true) ~= nil, true)
        eq(Wp.Clean("a|cffff0000b"):find("|", 1, true), nil, "keine Farbcodes")
        eq(Wp.AskResultText(nil, 0, "keine"), "In dieser Gilde ist kein Offizier bekannt.")
        eq(Wp.AskResultText(2, 0):find("Gerade ist kein Offizier online", 1, true) ~= nil, true)
        eq(Wp.AskResultText(3, 1):find("1 gerade online", 1, true) ~= nil, true)
    end)

    -----------------------------------------------------------------
    -- Einstellungen exportieren und importieren
    -----------------------------------------------------------------
    test("Export/Import: Einstellungen hin und zurück, nur bekannte Schlüssel", function()
        W.Load("GuildPrideSettingsIO.lua")
        local IO = ns.SettingsIO
        local src = { sound = false, chatFont = 14, welcomeText = "Hallo {name}; viel Spaß=", secret = "x", ahTab = "kaputt" }
        local text = IO.Export(src)
        eq(text:sub(1, 4), "GP1;")
        eq(text:find("secret", 1, true), nil, "unbekannte Schlüssel fehlen")
        eq(text:find("ahTab", 1, true), nil, "falscher Typ fehlt")
        local dst = {}
        eq(IO.Import(text, dst), 3)
        eq(dst.sound, false); eq(dst.chatFont, 14); eq(dst.welcomeText, "Hallo {name}; viel Spaß=")
        eq(IO.Import("irgendwas", dst), nil)
        eq(IO.Import("GP1;sound=sJa;chatFont=nabc;minimap=b1", dst), 1, "falsche Typen übersprungen")
    end)

    -----------------------------------------------------------------
    -- Messenger
    -----------------------------------------------------------------
    test("Messenger: direkt zustellen, Quittung macht „zugestellt“", function()
        W.roster = { { "Tester", 3 }, { "Gm", 0 }, { "Offi", 1 }, { "Anna", 3 }, { "Bert", 3 }, { "Carl", 3 }, { "Ohne", 3 } }
        W.Fire("GUILD_ROSTER_UPDATE")
        W.Load("GuildPrideMessenger.lua")
        W.Load("GuildPrideMessengerUI.lua")
        local M = ns.Messenger
        local gm = ns.Normalize("Gm")
        W.sent = {}
        local id = M.Send("gm", "Hallo Chef")
        eq(type(id), "string", "verschickt")
        local direct
        for _, x in ipairs(W.sent) do if x.kind == "NMS" then direct = x end end
        eq(direct and direct.target, gm, "direkt an den Online-Charakter")
        eq(M.DB().outbox[id] ~= nil, true, "wartet auf Quittung")
        -- falsche Quittung (nicht vom Empfänger) zählt nicht
        W.Receive("Offi", "NMA:" .. id)
        eq(M.DB().outbox[id] ~= nil, true, "Quittung von Fremden zählt nicht")
        W.Receive("Gm", "NMA:" .. id)
        eq(M.DB().outbox[id], nil)
        local c = M.Conv(ns.MainOf(gm))
        eq(c[#c].state, "delivered")
        eq(M.LineText(c[#c]):find("Hallo Chef", 1, true) ~= nil, true)
        eq(select(2, M.Send("gm", "   ")), "leer")
        eq(select(2, M.Send("Niemand", "x")), "unbekannt")
        eq(select(2, M.Send(ns.Me(), "x")), "selbst")
    end)

    test("Messenger: Absender loggt später ein – offene Nachrichten gehen an den online Empfänger", function()
        local M = ns.Messenger
        local gm = ns.Normalize("Gm")
        local main = ns.MainOf(gm)
        M.DB().outbox.offen1 = { to = main, text = "noch offen", t = W.server }
        W.sent = {}
        M.ResendOpen()
        local again = has(W.sent, "NMS")
        eq(again and again.target, gm, "offene Nachricht geht an den Online-Charakter")
        -- quittiert: nichts mehr nachschicken
        M.DB().outbox.offen1 = nil
        W.sent = {}
        M.ResendOpen()
        eq(has(W.sent, "NMS"), nil, "nach der Quittung ruhig")
        -- Grenze: nie mehr als RESEND_MAX auf einmal
        for i = 1, 30 do M.DB().outbox["viel" .. i] = { to = main, text = "x" .. i, t = W.server } end
        W.sent = {}
        M.ResendOpen()
        local n = 0
        for _, x in ipairs(W.sent) do if x.kind == "NMS" then n = n + 1 end end
        eq(n, 20, "höchstens 20 auf einmal")
        for i = 1, 30 do M.DB().outbox["viel" .. i] = nil end
    end)

    test("Messenger: Empfang, ungelesen, Doppelte, nicht für mich", function()
        local M = ns.Messenger
        local me = ns.MainOf(ns.Me())
        W.sent = {}
        W.Receive("Offi", "NMS:abcd1" .. SEP .. me .. SEP .. W.server .. SEP .. "Raid um 20 Uhr")
        local from = ns.MainOf(ns.Normalize("Offi"))
        eq(#M.Conv(from), 1)
        eq(M.UnreadTotal() >= 1, true, "ungelesen gezählt")
        eq(has(W.sent, "NMA") ~= nil, true, "quittiert")
        W.Receive("Offi", "NMS:abcd1" .. SEP .. me .. SEP .. W.server .. SEP .. "Raid um 20 Uhr")
        eq(#M.Conv(from), 1, "doppelt nur einmal")
        W.Receive("Offi", "NMS:abcd2" .. SEP .. "Jemand anders" .. SEP .. W.server .. SEP .. "nicht für mich")
        eq(#M.Conv(from), 1, "fremde Nachricht nicht angenommen")
        W.Receive("Fremdling", "NMS:abcd3" .. SEP .. me .. SEP .. W.server .. SEP .. "Spam")
        eq(M.Conv(ns.Normalize("Fremdling"))[1], nil, "nur von Gildenmitgliedern")
        M.MarkRead(from)
        eq(M.DB().unread[from], nil)
        eq(M.Clean("a|cffff0000b" .. SEP .. "c"):find("|", 1, true), nil, "keine Farbcodes")
    end)

    test("Messenger: offline – aufheben, beim Einloggen weiterreichen, Quittung löscht die Kopie", function()
        local M = ns.Messenger
        local offi = ns.Normalize("Offi")
        local to = ns.MainOf(offi)
        -- Gm schickt mir eine Nachricht für Offi (der offline ist) zum Aufheben
        W.Receive("Gm", "NMR:relay1" .. SEP .. to .. SEP .. W.server .. SEP .. "Bitte melden")
        eq(M.DB().relay.relay1 ~= nil, true, "aufgehoben")
        eq(M.DB().relay.relay1.author, ns.Normalize("Gm"), "Absender ist, wer es geschickt hat")
        -- Offi loggt ein und fragt nach
        W.sent = {}
        W.Receive("Offi", "NMQ:1")
        local fwd = has(W.sent, "NMF")
        eq(fwd and fwd.target, offi, "an Offi weitergereicht")
        eq(fwd.msg:find("Bitte melden", 1, true) ~= nil, true)
        W.Receive("Offi", "NMA:relay1")
        eq(M.DB().relay.relay1, nil, "Kopie gelöscht")
        -- Grenzen: höchstens 20 je Absender
        for i = 1, 25 do M.Keep("lim" .. i .. "xx", ns.Normalize("Gm"), to, W.server, "x" .. i) end
        local n = 0
        for _, r in pairs(M.DB().relay) do if r.author == ns.Normalize("Gm") then n = n + 1 end end
        eq(n, 20)
        M.Prune(W.server + 15 * 86400)
        eq(next(M.DB().relay), nil, "nach 14 Tagen weg")
    end)

    test("Messenger: weitergereichte Nachricht und Befehle", function()
        local M = ns.Messenger
        local me = ns.MainOf(ns.Me())
        W.Receive("Offi", "NMF:fwd12" .. SEP .. ns.Normalize("Gm") .. SEP .. me .. SEP .. (W.server - 3600) .. SEP .. "Von gestern")
        local c = M.Conv(ns.MainOf(ns.Normalize("Gm")))
        local last
        for _, e in ipairs(c) do if e.id == "fwd12" then last = e end end
        eq(c[#c].text, "Hallo Chef", "nach Zeit einsortiert: die alte Nachricht steht davor")
        eq(last.text, "Von gestern"); eq(last.via, ns.Normalize("Offi"))
        eq(M.LineText(last):find("später zugestellt", 1, true) ~= nil, true)
        local name, text = M.ParseArgs('"Reon Strobek" Hallo du')
        eq(name, "Reon Strobek"); eq(text, "Hallo du")
        eq(M.Resolve("gm"), ns.MainOf(ns.Normalize("Gm")))
        eq(M.Resolve("niemand"), nil)
        eq(#M.Conversations() >= 2, true)
    end)

    test("Flüstern: eigene Unterhaltung, Fenster geht auf, im Kampf erst danach", function()
        W.Load("GuildPrideWhisper.lua")
        W.Load("GuildPrideMessengerUI.lua")
        local Wh, M = ns.Whisper, ns.Messenger
        local opened = {}
        local oldShow = M.ShowIncoming
        M.ShowIncoming = function(key) opened[#opened + 1] = key end
        W.Fire("CHAT_MSG_WHISPER", "Hi, Gruppe für DM?", "Zufall-Realm")
        local key = Wh.Key("Zufall-Realm")
        eq(#Wh.Conv(key), 1)
        eq(Wh.DB().target[key], "Zufall-Realm", "zum Antworten der Name wie vom Spiel")
        eq(opened[1], "W:" .. key, "Fenster geht auf")
        eq(Wh.UnreadTotal() >= 1, true)
        eq(M.AllUnread() >= Wh.UnreadTotal(), true)
        -- eigene Antwort (aus dem normalen Chat oder dem Fenster) kommt in dieselbe Unterhaltung
        W.Fire("CHAT_MSG_WHISPER_INFORM", "Ja, komm", "Zufall-Realm")
        eq(#Wh.Conv(key), 2); eq(Wh.Conv(key)[2].out, true)
        eq(M.LineText(Wh.Conv(key)[2], nil, key):find("Ja, komm", 1, true) ~= nil, true)
        -- im Kampf: erst nach dem Kampf
        local oldCombat = InCombatLockdown
        InCombatLockdown = function() return true end
        GuildPrideDB.whisperCombat = true   -- Standard: auch im Kampf sofort
        W.Fire("CHAT_MSG_WHISPER", "Kampf!", "Sofort-Realm")
        eq(opened[2], "W:" .. Wh.Key("Sofort-Realm"), "im Kampf sofort")
        table.remove(opened, 2)
        GuildPrideDB.whisperCombat = false
        W.Fire("CHAT_MSG_WHISPER", "noch da?", "Kampf-Realm")
        eq(#opened, 1, "abgeschaltet: im Kampf nicht sofort")
        InCombatLockdown = oldCombat
        W.Fire("PLAYER_REGEN_ENABLED")
        eq(opened[2], "W:" .. Wh.Key("Kampf-Realm"), "nach dem Kampf")
        GuildPrideDB.whisperCombat = true
        -- abschaltbar und „nur Bekannte“
        GuildPrideDB.whisperWindow = false
        W.Fire("CHAT_MSG_WHISPER", "x", "Aus-Realm")
        eq(#opened, 2, "abgeschaltet: kein Fenster")
        eq(#Wh.Conv(Wh.Key("Aus-Realm")), 1, "aber gespeichert")
        GuildPrideDB.whisperWindow, GuildPrideDB.whisperKnownOnly = true, true
        local oldParty, oldRaid = UnitInParty, UnitInRaid
        UnitInParty = function() return false end; UnitInRaid = function() return nil end
        W.Fire("CHAT_MSG_WHISPER", "Gold billig", "Spam-Realm")
        eq(#opened, 2, "Fremder: kein Fenster")
        W.Fire("CHAT_MSG_WHISPER", "Hallo", "Gm")
        eq(#opened, 3, "Gildenmitglied: Fenster")
        UnitInParty, UnitInRaid = oldParty, oldRaid
        GuildPrideDB.whisperKnownOnly = false
        -- ganz aus: GuildPride fasst Flüstern nicht an (nur Blizzards Chat)
        GuildPrideDB.whisperEnabled = false
        local gone = #opened
        W.Fire("CHAT_MSG_WHISPER", "ganz aus", "Weg-Realm")
        eq(#opened, gone, "ganz aus: kein Fenster")
        eq(#Wh.Conv(Wh.Key("Weg-Realm")), 0, "ganz aus: nicht gespeichert")
        eq(#Wh.Conversations(), 0, "ganz aus: keine Flüster im Fenster")
        eq(Wh.StartOutgoing("Fremd-Realm"), false, "ganz aus: eigenes /w bleibt im Chat")
        GuildPrideDB.whisperEnabled = true
        -- antworten: normales Flüstern an den gespeicherten Namen
        local sent, refuse
        local oldSend = C_ChatInfo.SendChatMessage
        C_ChatInfo.SendChatMessage = function(text, kind, _, to)
            if refuse then error("Chat message limits exceeded", 0) end
            sent = { text, kind, to }
        end
        W.Load("GuildPrideWhisper.lua")   -- holt die neue Sendefunktion
        eq(ns.Whisper.Send(key, "  bis gleich "), true)
        eq(sent[1], "bis gleich"); eq(sent[2], "WHISPER"); eq(sent[3], "Zufall-Realm")
        eq(ns.Whisper.Send(key, "   "), false, "leer: nichts")
        -- zu lang fürs Spiel (255 Byte): der Rest bleibt fürs nächste Enter stehen, nichts geht verloren
        local long = ("Größe "):rep(60)
        local okLong, rest = ns.Whisper.Send(key, long)
        eq(okLong, true); eq(type(rest), "string")
        eq(#sent[1] <= 255, true, #sent[1]); eq(sent[1]:match("Größe$") ~= nil, true, "an einem Wort getrennt")
        eq(sent[1] .. " " .. rest, strtrim(long))
        eq(select(2, ns.Whisper.Send(key, "kurz")), nil)
        -- nie mitten in einem Zeichen oder Link trennen
        local _, r2 = ns.Whisper.Send(key, ("ä"):rep(200)); eq(#sent[1] % 2, 0); eq(sent[1] .. r2, ("ä"):rep(200))
        local link = "|cffffffff|Hitem:2589::::::::|h[Leinenstoff]|h|r"
        local _, r3 = ns.Whisper.Send(key, ("x"):rep(230) .. " " .. link); eq(sent[1], ("x"):rep(230)); eq(r3, link)
        -- lehnt das Spiel ab (Grenze erreicht), gibt es keinen Lua-Fehler und der Text bleibt
        refuse = true
        eq(ns.Whisper.Send(key, "noch einer"), false)
        refuse = nil
        C_ChatInfo.SendChatMessage = oldSend
        ns.Whisper.Delete(key)
        eq(#ns.Whisper.Conv(key), 0)
        M.ShowIncoming = oldShow
    end)

    test("Namensplaketten: geschützte Einheiten und Namen (Instanzen) werfen keinen Fehler", function()
        local old = { UnitIsPlayer, UnitFullName, issecretvalue, ns.Plates }
        local SECRET = setmetatable({}, { __eq = function() error("Vergleich mit geschütztem Wert", 0) end })
        issecretvalue = function(v) return rawequal(v, SECRET) end
        UnitIsPlayer = function(u) if rawequal(u, SECRET) then error("Secret values are only allowed during untainted execution", 0) end return true end
        UnitFullName = function() return SECRET, SECRET end
        W.Load("GuildPrideNameplates.lua")
        local ok, err = pcall(function()
            eq(ns.Plates.UnitKey(SECRET), nil); eq(ns.Plates.UnitKey("nameplate1"), nil)
            UnitFullName = function() return "Anna", "" end
            eq(ns.Plates.UnitKey("nameplate1"), ns.Normalize("Anna"))
        end)
        UnitIsPlayer, UnitFullName, issecretvalue, ns.Plates = unpack(old, 1, 4)
        if not ok then error(err, 0) end
    end)

    test("Nachrichten kürzen: gemeinsame Regel für Gildenchat, Begrüßung und Flüstern", function()
        local head, rest = ns.CutMessage(("ü"):rep(200))
        eq(#head <= 255, true); eq(head .. rest, ("ü"):rep(200))
        head, rest = ns.CutMessage("kurz"); eq(head, "kurz"); eq(rest, nil)
    end)

    test("Spieler-Notiz im Tooltip: geschützte Einheiten (Instanzen) werfen keinen Fehler", function()
        local old = { TooltipDataProcessor, Enum, GameTooltip, UnitIsPlayer, UnitName, issecretvalue }
        local SECRET, post, lines = "geheim", nil, {}
        TooltipDataProcessor = { AddTooltipPostCall = function(_, f) post = f end }
        Enum = { TooltipDataType = { Unit = 2 } }
        local unit
        GameTooltip = { GetUnit = function() return "x", unit end, AddLine = function(_, t) lines[#lines + 1] = t end }
        issecretvalue = function(v) return v == SECRET end
        UnitIsPlayer = function(u) if u == SECRET then error("Secret values are only allowed during untainted execution", 0) end return true end
        UnitName = function(u) return u == "geheimername" and SECRET or "Notizmann" end
        W.Load("GuildPrideNotes.lua")
        ns.SetPlayerNote("Notizmann", "guter Tank")
        local ok, err = pcall(function()
            unit = SECRET; post(GameTooltip); eq(#lines, 0)
            unit = "geheimername"; post(GameTooltip); eq(#lines, 0)
            unit = "mouseover"; post(GameTooltip); eq(#lines, 1)
        end)
        ns.SetPlayerNote("Notizmann", "")
        TooltipDataProcessor, Enum, GameTooltip, UnitIsPlayer, UnitName, issecretvalue = unpack(old, 1, 6)
        if not ok then error(err, 0) end
    end)

    test("Flüstern: selbst flüstern öffnet den Messenger, ohne Blizzards Chat anzufassen", function()
        local Wh, M = ns.Whisper, ns.Messenger
        local opened = {}
        local oldOpen = M.OpenWhisper
        M.OpenWhisper = function(raw) opened[#opened + 1] = raw end
        local touched = false
        local box = {
            GetAttribute = function(_, k) return ({ chatType = "WHISPER", tellTarget = "Ziel-Realm" })[k] end,
            SetText = function() touched = true end, Hide = function() touched = true end,
        }
        Wh._FromEditBox(box)
        eq(opened[1], "Ziel-Realm", "Unterhaltung geöffnet")
        eq(touched, false, "Blizzards Eingabe unverändert")
        Wh._FromEditBox(box)
        eq(#opened, 1, "nicht doppelt kurz hintereinander")
        Wh._FromEditBox({ GetAttribute = function(_, k) return k == "chatType" and "SAY" or nil end })
        eq(#opened, 1, "nur beim Flüstern")
        GuildPrideDB.whisperOutgoing = false
        eq(Wh.StartOutgoing("Anders-Realm"), false, "abschaltbar")
        GuildPrideDB.whisperOutgoing = true
        eq(Wh.StartOutgoing(""), false)
        M.OpenWhisper = oldOpen
    end)

    test("Links der Gilde: nur echte Einladungslinks, nur Offiziere, an alle verteilt", function()
        W.Load("GuildPrideGuildLinks.lua")
        local GL = ns.GuildLinks
        eq(GL.Clean("discord", "discord.gg/abc123"), "https://discord.gg/abc123", "https ergänzt")
        eq(GL.Clean("discord", "https://discord.com/invite/Ab-1"), "https://discord.com/invite/Ab-1")
        eq(GL.Clean("discord", "https://boese.example/discord.gg/x"), nil, "fremde Seite")
        eq(GL.Clean("discord", "https://discord.gg/a b"), nil, "Leerzeichen")
        eq(GL.Clean("community", "https://www.worldofwarcraft.com/invite/vpG0eJPCqEX?region=EU&faction=Horde") ~= nil, true)
        eq(GL.Clean("community", "https://example.com/invite/x"), nil)
        eq(GL.Clean("discord", ""), "", "leer = löschen")
        local oldOff = ns.IsOfficer
        ns.IsOfficer = function() return false end
        eq(select(2, GL.Set("discord.gg/abc", "")), "recht", "nur Offiziere")
        ns.IsOfficer = function() return true end
        W.sent = {}
        eq(select(2, GL.Set("kein link", "")), "discord")
        eq(GL.Set("discord.gg/gilde1", ""), true)
        eq(GL.Get("discord"), "https://discord.gg/gilde1")
        eq(GL.Get("community"), nil)
        eq(has(W.sent, "GLK") ~= nil, true, "an die Gilde geschickt")
        ns.IsOfficer = oldOff
        eq(GL.Fill("Willkommen {name}! Discord: {discord} {community}"), "Willkommen {name}! Discord: https://discord.gg/gilde1")
        local v = W.server + 1000
        local oldName = ns.IsOfficerName
        ns.IsOfficerName = function(n) return n == ns.Normalize("Offi") end
        W.Receive("Anna", "GLK:" .. v .. SEP .. "Anna" .. SEP .. "https://discord.gg/falsch" .. SEP .. "")
        eq(GL.Get("discord"), "https://discord.gg/gilde1", "ein Mitglied allein ändert nichts")
        W.Receive("Offi", "GLK:" .. (v + 1) .. SEP .. "Offi" .. SEP .. "https://discord.gg/neu" .. SEP .. "https://www.worldofwarcraft.com/invite/abc")
        eq(GL.Get("discord"), "https://discord.gg/neu", "vom Offizier sofort")
        eq(GL.Get("community"), "https://www.worldofwarcraft.com/invite/abc")
        W.Receive("Offi", "GLK:" .. (v + 2) .. SEP .. "Offi" .. SEP .. "https://boese.example" .. SEP .. "")
        eq(GL.Get("discord"), "https://discord.gg/neu", "ungültiger Link wird verworfen")
        ns.IsOfficerName = oldName
        W.sent = {}
        W.Receive("Bert", "GLQ:1")
        local a = has(W.sent, "GLK")
        eq(a and a.target, ns.Normalize("Bert"), "wer die Links hat, antwortet")
    end)

    test("Gildenliste: je Änderung einmal gelesen, alle bekommen dieselbe Liste, Salven gebremst", function()
        local oldRoster, oldInfo, oldAfter, oldSecret = W.roster, GetGuildRosterInfo, C_Timer.After, issecretvalue
        local reads, seen, later = 0, 0, {}
        W.roster = { { "Tester", 3 }, { "Gm", 0 }, { "Anna", 2, 33, false }, { "Geheim", 3 } }
        GetGuildRosterInfo = function(i) reads = reads + 1; return oldInfo(i) end
        issecretvalue = function(v) return v == "Geheim" end
        local last
        ns.OnRoster(function(list)
            seen = seen + 1
            last = {}
            for _, m in ipairs(list) do last[m.full] = { m.name, m.rankIndex, m.level, m.online } end
        end)
        W.Advance(100)
        reads = 0
        W.Fire("GUILD_ROSTER_UPDATE")
        eq(seen, 1); eq(ns.IsGuildMember("Anna"), true)
        local a = last[ns.Normalize("Anna")]
        eq(a[1], "Anna"); eq(a[2], 2); eq(a[3], 33); eq(a[4], false)
        eq(last[ns.Normalize("Geheim")], nil, "geschützte Namen bleiben draußen")
        -- Salve: erst nach der Pause noch einmal, und dann nur einmal
        C_Timer.After = function(_, fn) later[#later + 1] = fn end
        reads = 0
        for _ = 1, 10 do W.Fire("GUILD_ROSTER_UPDATE") end
        eq(seen, 1); eq(#later, 1); eq(reads, 0, "während der Pause nichts gelesen")
        table.remove(W.roster, 3)
        later[1](); eq(seen, 2); eq(last[ns.Normalize("Anna")], nil)
        eq(reads, #W.roster, "einmal je Mitglied")
        GetGuildRosterInfo, W.roster, C_Timer.After, issecretvalue = oldInfo, oldRoster, oldAfter, oldSecret
        W.Advance(10); W.Fire("GUILD_ROSTER_UPDATE")
    end)

    test("Fragen an die Offiziere: über den Messenger, beantwortet für alle", function()
        W.Load("GuildPrideQuestions.lua")
        local Q, M = ns.Questions, ns.Messenger
        W.roster = { { "Tester", 3 }, { "Gm", 0 }, { "Offi", 1, 60, false }, { "Anna", 3 } }
        W.Fire("GUILD_ROSTER_UPDATE")
        local oldRank = ns.IsOfficerRank
        ns.IsOfficerRank = function(r) return r <= 1 end
        local offs = Q.Officers()
        eq(#offs, 2, "Gildenleitung und Offizier")
        W.sent = {}
        local sent, online = Q.Ask("Wann ist Raid?")
        eq(sent, 2); eq(online, 1, "Offi ist offline")
        local direct, stored
        for _, x in ipairs(W.sent) do
            if x.kind == "NMS" then direct = x end
            if x.kind == "NMR" then stored = x end
        end
        eq(direct and direct.target, ns.Normalize("Gm"), "an den Online-Offizier direkt")
        eq(direct.msg:match("Wann ist Raid%?" .. SEP .. "(q%w+)$") ~= nil, true, "mit Frage-Kennung")
        eq(stored ~= nil, true, "für den Offline-Offizier aufgehoben")
        eq(select(2, Q.Ask("Noch eine")), "wait", "gebremst")
        -- Offizier-Seite: Frage kommt an, steht in der Liste
        local oldOff = ns.IsOfficer
        ns.IsOfficer = function() return true end
        local me = ns.MainOf(ns.Me())
        W.Receive("Anna", "NMS:fq001" .. SEP .. me .. SEP .. W.server .. SEP .. "Wie komme ich in den Raid?" .. SEP .. "qabc1")
        eq(Q.OpenCount(), 1)
        local e = Q.List()[1]
        eq(e.text, "Wie komme ich in den Raid?"); eq(e.answeredBy, nil)
        local conv = M.Conv(ns.MainOf(ns.Normalize("Anna")))
        eq(M.LineText(conv[#conv]):find("[Frage]", 1, true) ~= nil, true, "im Verlauf markiert")
        -- antworten im Messenger: beantwortet, die anderen Offiziere erfahren es
        W.sent = {}
        eq(type(M.Send("Anna", "Melde dich bei Gm")), "string")
        eq(Q.OpenCount(), 0)
        eq(Q.List()[1].answeredBy, ns.Me())
        eq(has(W.sent, "FQA") ~= nil, true, "an die Gilde gemeldet")
        ns.IsOfficer = oldOff
        -- Meldung „beantwortet“ nur von Offizieren
        local oldName = ns.IsOfficerName
        ns.IsOfficerName = function(n) return n == ns.Normalize("Gm") end
        ns.IsOfficer = function() return true end
        W.Receive("Anna", "NMS:fq002" .. SEP .. me .. SEP .. W.server .. SEP .. "Noch eine Frage" .. SEP .. "qabc2")
        W.Receive("Anna", "FQA:qabc2" .. SEP .. "Anna")
        eq(Q.OpenCount(), 1, "Mitglied kann nichts als beantwortet melden")
        W.Receive("Gm", "FQA:qabc2" .. SEP .. "Gm")
        eq(Q.OpenCount(), 0, "Offizier schon")
        ns.IsOfficer, ns.IsOfficerName = oldOff, oldName
        -- Nicht-Offiziere speichern keine Fragen
        ns.IsOfficer = function() return false end
        W.Receive("Anna", "NMS:fq003" .. SEP .. me .. SEP .. W.server .. SEP .. "x" .. SEP .. "qabc3")
        eq(#Q.List(), 2)
        ns.IsOfficer = oldOff
        Q.Prune(W.server + 31 * 86400)
        eq(#Q.List(), 0, "nach 30 Tagen weg")
        ns.IsOfficerRank = oldRank
    end)

    -----------------------------------------------------------------
    -- Ankunftszeit
    -----------------------------------------------------------------
    test("Abfahrten: Ankunft am Ziel = Abfahrt + Fahrzeit", function()
        local T = ns.Transit
        eq(T.ArrivalText(nil), "")
        eq(T.ArrivalText({ timed = true }), "", "ohne Fahrzeit keine Angabe")
        eq(T.ArrivalText({ timed = true, arriveThereIn = 600 }, 0), "Ankunft ~" .. os.date("%H:%M", 600))
    end)
end
