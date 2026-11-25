-- Tests: Tester freischalten und Testfunktionen (Core/GuildPrideTester.lua)
local SEP = "\031"

return function(test, eq, W, ns)
    local T, sent, dev, popups
    local KEYS = { "testerId", "testFeatures", "devTesters", "devAsPlayer" }
    local function Load()
        W.Load("GuildPrideErrorShare.lua"); W.Load("GuildPrideTester.lua")
        T = ns.Tester
    end
    local function tt(name, fn)
        test(name, function()
            local old = { ns.IsMarked, ns.IsDev, ns.SendAddonMsg, ns.VERSION, ns.Print, StaticPopup_Show, ns.Players, ns.RosterList, InCombatLockdown }
            local saved = {}
            for _, k in ipairs(KEYS) do saved[k] = GuildPrideDB[k]; GuildPrideDB[k] = nil end
            sent, popups, dev = {}, {}, false
            ns.IsMarked = function(n) return n == "Chef" end
            ns.IsDev = function() return dev end
            ns.SendAddonMsg = function(_, msg, channel, target) sent[#sent + 1] = { msg = msg, channel = channel, to = target }; return 0 end
            ns.VERSION = "9.9.9"
            ns.Print = function() end
            ns.Players = { public = {} }
            ns.RosterList = function() return {} end
            InCombatLockdown = function() return false end
            StaticPopup_Show = function(n, _, _, data) popups[#popups + 1] = { n = n, data = data } end
            Load()
            local ok, err = pcall(fn)
            ns.IsMarked, ns.IsDev, ns.SendAddonMsg, ns.VERSION, ns.Print, StaticPopup_Show, ns.Players, ns.RosterList, InCombatLockdown = unpack(old, 1, 9)
            for _, k in ipairs(KEYS) do GuildPrideDB[k] = saved[k] end
            Load()
            if not ok then error(err, 0) end
        end)
    end
    local function Grant(gid, on, sender, channel, tag)
        W.Receive(sender or "Chef", "DVT:" .. table.concat({ tag or ns.CLIENT_TAG, on or "1", gid }, SEP), channel or "WHISPER")
    end
    local function Popup() return StaticPopupDialogs.GUILDPRIDE_TESTER end

    tt("Testfunktionen: aus, nur Tester, alle; Unbekanntes ist aus; Entwickler sieht sie, auf Wunsch wie ein Spieler", function()
        local list = T.LIST
        T.LIST = { { key = "a", name = "A", state = "off" }, { key = "b", name = "B", state = "test" }, { key = "c", name = "C", state = "all" } }
        eq(ns.Feature("a"), false); eq(ns.Feature("b"), false); eq(ns.Feature("c"), true); eq(ns.Feature("x"), false)
        GuildPrideDB.testFeatures = true; eq(ns.Feature("b"), false, "ohne Freischaltung nie")
        GuildPrideDB.testerId = "g1"; eq(ns.Feature("b"), true); eq(ns.Feature("a"), false); eq(ns.IsTester(), true)
        GuildPrideDB.testFeatures = false; eq(ns.Feature("b"), false)
        GuildPrideDB.testerId = nil
        dev = true; eq(ns.Feature("b"), true); eq(ns.Feature("a"), false)
        GuildPrideDB.devAsPlayer = true; eq(ns.Feature("b"), false)
        local db = GuildPrideDB
        GuildPrideDB = nil; dev = false
        eq(ns.Feature("b"), false, "vor dem Laden"); eq(ns.Feature("c"), true)
        GuildPrideDB = db
        T.LIST = list
    end)

    tt("Testfunktionen: Liste stimmt und jede Abfrage im Code steht darin", function()
        local seen = {}
        for _, f in ipairs(T.LIST) do
            eq(seen[f.key], nil); seen[f.key] = true
            eq(type(f.name) == "string" and (f.state == "off" or f.state == "test" or f.state == "all"), true, f.key)
        end
        for line in io.lines("GuildPrideForever.toc") do
            local path = line:gsub("\r", ""):gsub("\\", "/")
            if path:match("%.lua$") and not path:find("^#") then
                for code in io.lines(path) do
                    for key in code:gsub("%-%-.*", ""):gmatch("%.Feature%(\"([%w_]+)\"%)") do eq(seen[key], true, path .. ": " .. key) end
                end
            end
        end
    end)

    tt("Freischalten: nur vom Entwickler, nur geflüstert, nur für diese Spielversion", function()
        Grant("g1", "1", "Anna"); Grant("g1", "1", "Chef", "GUILD"); Grant("g1", "1", "Chef", "WHISPER", "X9")
        Grant("", "1"); Grant("g 1", "1"); Grant(("x"):rep(40), "1"); Grant("g1", "7")
        eq(#popups, 0); eq(GuildPrideDB.testerId, nil); eq(#sent, 0)
        dev = true; Grant("g1"); eq(#popups, 0, "der Entwickler selbst nicht"); dev = false
        Grant("g1"); eq(#popups, 1); eq(popups[1].n, "GUILDPRIDE_TESTER")
        eq(GuildPrideDB.testerId, nil, "erst fragen"); eq(#sent, 0)
    end)

    tt("Freischalten: Ja und Nein werden gemeldet, gefragt wird einmal je Einladung", function()
        Grant("g1"); Grant("g1"); eq(#popups, 1, "nicht doppelt")
        Popup().OnAccept(nil, popups[1].data)
        eq(GuildPrideDB.testerId, "g1"); eq(ns.IsTester(), true)
        eq(sent[1].msg, "DVR:" .. table.concat({ "g1", "1", "9.9.9" }, SEP)); eq(sent[1].to, "Chef"); eq(sent[1].channel, "WHISPER")
        sent = {}; Grant("g1"); eq(#popups, 1); eq(sent[1].msg:find("g1" .. SEP .. "1", 1, true) ~= nil, true, "antwortet ohne Frage")
        -- neue Einladung nach Absage
        Grant("g2"); eq(#popups, 2); sent = {}
        Popup().OnCancel(nil, popups[2].data, "timeout"); eq(#sent, 0, "weggeklickt ist kein Nein")
        Popup().OnCancel(nil, popups[2].data, "clicked")
        eq(GuildPrideDB.testFeatures, false); eq(ns.IsTester(), false); eq(sent[1].msg:find("g2" .. SEP .. "0", 1, true) ~= nil, true)
        sent = {}; Grant("g2"); eq(#popups, 2); eq(sent[1].msg:find("g2" .. SEP .. "0", 1, true) ~= nil, true)
    end)

    tt("Freischalten: im Kampf erst danach fragen; zurücknehmen nur mit passender Kennung", function()
        local fight = true
        InCombatLockdown = function() return fight end
        Grant("g1"); eq(#popups, 0)
        fight = false; W.Fire("PLAYER_REGEN_ENABLED"); eq(#popups, 1)
        Popup().OnAccept(nil, popups[1].data); sent = {}
        Grant("g9", "0"); eq(ns.IsTester(), true); eq(sent[1].msg:find("g9" .. SEP .. "x", 1, true) ~= nil, true, "kennt er nicht: weg")
        Grant("g1", "0", "Anna"); eq(ns.IsTester(), true)
        sent = {}; Grant("g1", "0"); eq(ns.IsTester(), false); eq(GuildPrideDB.testerId, nil); eq(GuildPrideDB.testFeatures, nil)
        eq(sent[1].msg:find("g1" .. SEP .. "x", 1, true) ~= nil, true)
    end)

    tt("Tester melden sich, wenn der Entwickler da ist – gebremst; andere nie; Aussteigen kommt an", function()
        local function Hello(who) W.Receive(who or "Chef", "DVA:" .. ns.CLIENT_TAG, "GUILD") end
        Hello(); eq(#sent, 0, "kein Tester")
        GuildPrideDB.testerId, GuildPrideDB.testFeatures = "g1", true
        Hello("Anna"); eq(#sent, 0)
        Hello(); eq(#sent, 1); Hello(); eq(#sent, 1, "gebremst")
        W.Advance(700); SlashCmdList.GUILDPRIDE("tester aus"); eq(ns.IsTester(), false); eq(GuildPrideDB.testerId, "g1", "kann wieder einsteigen")
        sent = {}; Hello(); eq(sent[1].msg:find("g1" .. SEP .. "0", 1, true) ~= nil, true)
        SlashCmdList.GUILDPRIDE("tester an"); eq(ns.IsTester(), true)
    end)

    tt("Entwickler: hinzufügen, einladen nur wer online ist, Antworten zählen nur mit bekannter Kennung", function()
        eq(T.Add("Anna"), nil, "nur der Entwickler")
        dev = true
        ns.Players.public[ns.Normalize("Bert")] = { t = GetTime() }
        eq(T.Add(""), nil); eq(T.Add("A|cff"), nil); eq(T.Add(ns.Me()), nil)
        local a, b = T.Add("Anna"), T.Add("bert")
        eq(a.name, ns.Normalize("Anna")); eq(b.name, ns.Normalize("Bert"), "Schreibweise wie online"); eq(a.gid ~= b.gid, true)
        eq(T.Add("Anna"), a, "nicht doppelt")
        eq(#sent, 1, "nur Bert ist da"); eq(sent[1].to, b.name)
        eq(sent[1].msg, "DVT:" .. table.concat({ ns.CLIENT_TAG, "1", b.gid }, SEP))
        sent = {}; T.Deliver(); eq(#sent, 0, "gebremst"); T.Deliver(true); eq(#sent, 2, "von Hand an alle Offenen")
        W.Receive("Bert", "DVR:" .. table.concat({ "falsch", "1", "2.45.0" }, SEP), "WHISPER"); eq(b.s, "wait")
        W.Receive("Bert", "DVR:" .. table.concat({ b.gid, "1", "2.45.0" }, SEP), "GUILD"); eq(b.s, "wait", "nur geflüstert")
        W.Receive("Bert", "DVR:" .. table.concat({ b.gid, "1", "2.45.0|x" }, SEP), "WHISPER"); eq(b.s, "yes"); eq(b.v, nil, "Unsinn als Version")
        W.Receive("Twink", "DVR:" .. table.concat({ b.gid, "1", "2.45.0" }, SEP), "WHISPER"); eq(b.v, "2.45.0"); eq(b.name, ns.Normalize("Bert"), "Twinknamen werden nicht gespeichert")
        W.Receive("Anna", "DVR:" .. table.concat({ a.gid, "0", "2.45.0" }, SEP), "WHISPER"); eq(a.s, "no")
        eq(#T.View(), 2)
        dev = false; W.Receive("Anna", "DVR:" .. table.concat({ a.gid, "1", "2.45.0" }, SEP), "WHISPER"); eq(a.s, "no", "nur beim Entwickler")
    end)

    tt("Entwickler: zurücknehmen wird zugestellt und verschwindet erst dann; erneut einladen fragt neu", function()
        dev = true
        local a = T.Add("Anna")
        local gid = a.gid
        T.Invite(a.name); eq(a.gid ~= gid, true, "neue Kennung"); eq(a.s, "wait")
        W.Receive("Anna", "DVR:" .. table.concat({ a.gid, "1", "2.45.0" }, SEP), "WHISPER"); eq(a.s, "yes")
        T.Revoke(a.name); eq(a.s, "revoke"); eq(#T.View(), 1)
        sent = {}; W.Receive("Anna", "DVR:" .. table.concat({ a.gid, "1", "2.45.0" }, SEP), "WHISPER")
        eq(a.s, "revoke"); eq(sent[1].msg:find(SEP .. "0" .. SEP .. a.gid, 1, true) ~= nil, true, "Tester meldet sich: Rücknahme geht raus")
        W.Receive("Anna", "DVR:" .. table.concat({ a.gid, "x", "" }, SEP), "WHISPER"); eq(#T.View(), 0)
        -- nie zugestellt: sofort weg
        local b = T.Add("Carl"); T.Revoke(b.name); eq(#T.View(), 0)
    end)

    tt("Entwickler: eine Liste, ein Haken je Name – an lädt ein, aus nimmt zurück, nichts springt", function()
        dev = true
        local oldCompare = ns.CompareVersion
        ns.CompareVersion = function(a, b)   -- reicht für x.yy.z
            a, b = tonumber((a:gsub("%.", ""))), tonumber((b:gsub("%.", "")))
            return a == b and 0 or a > b and 1 or -1
        end
        local players = { { name = "Zoe", ver = "2.45.0" }, { name = "Alt", ver = "2.43.1", guild = true }, { name = "Bert", ver = "2.46.1", guild = true },
            { name = ns.Me(), ver = "2.46.1" }, { name = "Ohne" } }
        ns.Players = { public = { Zoe = {}, Alt = {}, Bert = {}, Ohne = {} }, List = function() return players end }
        local function Order() local o = {}; for _, v in ipairs(T.View()) do o[#o + 1] = v.name .. (v.on and "+" or "") end return table.concat(o, " ") end
        eq(Order(), "Bert Zoe Alt Ohne", "passende Version zuerst, Gilde zuerst, man selbst nicht")
        T.Toggle("Zoe"); eq(Order(), "Bert Zoe+ Alt Ohne", "Haken an, Reihenfolge bleibt")
        local e = GuildPrideDB.devTesters.Zoe
        eq(e.s, "wait"); eq(sent[#sent].to, "Zoe")
        W.Receive("Zoe", "DVR:" .. table.concat({ e.gid, "1", "2.45.0" }, SEP), "WHISPER"); eq(Order(), "Bert Zoe+ Alt Ohne")
        T.Toggle("Zoe"); eq(e.s, "revoke"); eq(Order(), "Bert Zoe Alt Ohne", "Haken aus")
        T.Toggle("Zoe"); eq(e.s, "wait", "wieder an: neu eingeladen"); eq(Order(), "Bert Zoe+ Alt Ohne")
        W.Receive("Zoe", "DVR:" .. table.concat({ e.gid, "0", "2.45.0" }, SEP), "WHISPER"); eq(Order(), "Bert Zoe Alt Ohne", "abgelehnt: kein Haken")
        -- wer offline ist und eingeladen wurde, steht unten
        T.Add("Offline"); eq(Order(), "Bert Zoe Alt Ohne Offline+")
        ns.Players = nil; eq(Order(), "Offline+ Zoe", "ohne Spielerliste nur Eingeladene")
        dev = false; T.Toggle("Bert"); eq(GuildPrideDB.devTesters.Bert, nil, "nur der Entwickler")
        ns.CompareVersion = oldCompare
    end)

    tt("Entwickler: Vor- und Nachname (Forever) – Haken, Eingabe und Antwort gehen", function()
        dev = true
        local oldCompare = ns.CompareVersion
        ns.CompareVersion = function() return 0 end
        ns.Players = { public = { ["Berta Muster"] = {} }, List = function() return { { name = "Berta Muster", ver = "2.45.0" } } end }
        T.Toggle("Berta Muster")
        local e = GuildPrideDB.devTesters["Berta Muster"]
        eq(e ~= nil and e.s, "wait"); eq(T.View()[1].on, true); eq(#T.View(), 1)
        eq(sent[1].to, "Berta Muster"); eq(sent[1].msg:find("DVT:", 1, true), 1)
        eq(T.Add("  berta   muster "), e, "getippt, mit Leerzeichen und klein")
        W.Receive("Berta Muster", "DVR:" .. table.concat({ e.gid, "1", "2.45.0" }, SEP), "WHISPER"); eq(e.s, "yes")
        T.Toggle("Berta Muster"); eq(e.s, "revoke"); eq(T.View()[1].on, false)
        ns.CompareVersion = oldCompare
    end)

    tt("Fehlerbericht vermerkt Tester, ohne Namen; andere Berichte bleiben gleich", function()
        eq(ns.TesterMark(), "")
        GuildPrideDB.testerId, GuildPrideDB.testFeatures = "g1", true
        eq(ns.TesterMark(), " test=yes")
    end)
end
