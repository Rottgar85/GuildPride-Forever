-- Tests: Nutzerzahl für den Entwickler (Core/GuildPrideCount.lua), immer an, anonym
return function(test, eq, W, ns)
    local sent, dev
    local function counttest(name, fn)
        test(name, function()
            local old = { ns.IsMarked, ns.IsDev, ns.SendAddonMsg, ns.VERSION, GuildPrideDB.installId, GuildPrideDB.countDay,
                GuildPrideDB.devCount, GuildPrideDB.preset, GuildPrideDB.usageShare }
            ns.IsMarked = function(n) return n == "Chef" end
            ns.IsDev = function() return dev end
            ns.SendAddonMsg = function(_, m, channel, to) sent[#sent + 1] = { msg = m, channel = channel, to = to }; return 0 end
            ns.VERSION, dev, sent = "9.9.9", false, {}
            GuildPrideDB.installId, GuildPrideDB.countDay, GuildPrideDB.devCount, GuildPrideDB.preset = nil, nil, nil, nil
            GuildPrideDB.usageShare = false
            W.Load("GuildPrideErrorShare.lua"); W.Load("GuildPrideCount.lua")
            local ok, err = pcall(fn, ns.UserCount)
            ns.IsMarked, ns.IsDev, ns.SendAddonMsg, ns.VERSION, GuildPrideDB.installId, GuildPrideDB.countDay,
                GuildPrideDB.devCount, GuildPrideDB.preset, GuildPrideDB.usageShare = unpack(old, 1, 9)
            if not ok then error(err, 0) end
        end)
    end
    local function Hello(from) W.Receive(from or "Chef", "DVA:" .. ns.CLIENT_TAG, "GUILD") end
    local function Deliver(from)
        local pieces = sent
        dev, sent = true, {}
        for _, m in ipairs(pieces) do W.Receive(from, m.msg, "WHISPER") end
        dev = false
    end

    counttest("Nutzerzahl: meldet sich ohne Zustimmung, einmal am Tag, nur an den Entwickler", function(C)
        GuildPrideDB.preset = "medium"
        Hello()
        eq(#sent, 1, "immer an, auch ohne Nutzungs-Haken")
        eq(sent[1].channel, "WHISPER"); eq(sent[1].to, "Chef")
        eq(sent[1].msg:sub(1, 4), "DVC:")
        eq(sent[1].msg:find("Anna", 1, true), nil, "kein Name")
        eq(sent[1].msg:find("medium", 1, true) ~= nil, true); eq(sent[1].msg:find("9.9.9", 1, true) ~= nil, true)
        sent = {}
        Hello(); eq(#sent, 0, "am selben Tag nicht noch einmal")
        W.Advance(86400); Hello(); eq(#sent, 1, "am nächsten Tag wieder")
        sent = {}
        Hello("Fremder"); W.Advance(86400); Hello("Fremder"); eq(#sent, 0, "nur an den echten Entwickler")
    end)

    counttest("Nutzerzahl: Kennung ist zufällig und bleibt", function(C)
        local id = C.Id()
        eq(type(id), "string"); eq(#id, 12); eq(id:match("^%x+$") ~= nil, true)
        eq(C.Id(), id)
    end)

    counttest("Nutzerzahl: Entwickler zählt Kennungen, Stufen und Versionen", function(C)
        GuildPrideDB.preset = "light"
        Hello(); Deliver("Anna-Realm")
        GuildPrideDB.installId, GuildPrideDB.countDay, GuildPrideDB.preset = nil, nil, nil
        Hello(); Deliver("Bert-Realm")
        local db = GuildPrideDB.devCount
        local n = 0
        for id in pairs(db) do
            n = n + 1
            eq(id:match("^%x+$") ~= nil, true, "nur die Kennung, kein Name")
        end
        eq(n, 2)
        local s = C.Summary()
        eq(s.today, 2); eq(s.week, 2); eq(s.total, 2)
        eq(s.tiers.light, 1); eq(s.tiers.none, 1)
        eq(s.versions["9.9.9"], 2)
        -- derselbe Spieler am nächsten Tag zählt nicht doppelt
        W.Advance(86400)
        GuildPrideDB.countDay = nil
        GuildPrideDB.installId = next(db)
        Hello(); Deliver("Anna-Realm")
        n = 0
        for _ in pairs(db) do n = n + 1 end
        eq(n, 2)
        eq(C.Summary().today, 1)
        local text = table.concat(C.Lines(), "\n")
        eq(text:find("Anna", 1, true), nil)
    end)

    counttest("Nutzerzahl: kaputte Meldungen werden verworfen", function(C)
        dev = true
        eq(C.Collect("zz|<>" .. ns.SEP .. "9.9.9" .. ns.SEP .. "max", "X"), false)
        eq(C.Collect("abcdefabcdef" .. ns.SEP .. "kaputt" .. ns.SEP .. "max", "X"), false)
        eq(C.Collect("abcdefabcdef" .. ns.SEP .. "9.9.9" .. ns.SEP .. "riesig", "X"), false)
        eq(C.Collect("abcdefabcdef" .. ns.SEP .. "9.9.9" .. ns.SEP .. "max", "X"), true)
        dev = false
        eq(C.Collect("abcdefabcdef" .. ns.SEP .. "9.9.9" .. ns.SEP .. "max", "X"), false, "nur beim Entwickler")
    end)
end
