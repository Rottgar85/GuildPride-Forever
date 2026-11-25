-- Tests: tote Chat-Kanäle erkennen und neu betreten (Guild/GuildPrideChannelWatch.lua)
return function(test, eq, W, ns)
    local function watchtest(name, fn)
        test(name, function()
            local old = { ns.RejoinChannels, ns.Players, ns.Queue, InCombatLockdown, C_ChatInfo.InChatMessagingLockdown }
            local rejoined, asked = 0, 0
            ns.RejoinChannels = function(done) rejoined = rejoined + 1; if done then done() end return true end
            ns.Players = { Ask = function(force) if force then asked = asked + 1 end end }
            C_ChatInfo.InChatMessagingLockdown = function() return false end
            W.Load("GuildPrideChannelWatch.lua")
            local C = ns.ChannelWatch
            local ok, err = pcall(fn, C, function() return rejoined, asked end)
            ns.RejoinChannels, ns.Players, ns.Queue, InCombatLockdown, C_ChatInfo.InChatMessagingLockdown = unpack(old, 1, 5)
            if not ok then error(err, 0) end
        end)
    end
    local function Heard(prefix, sender) W.Fire("CHAT_MSG_ADDON", prefix or "GuildPride", "LYS:x", "CHANNEL", sender or "Anna") end

    watchtest("Kanal-Wache: gesendet, aber nichts kommt zurück – neu betreten und wieder fragen", function(C, n)
        for _ = 1, 3 do C.Sent("CHANNEL", 0) end
        C.Check(); eq((n()), 0, "nicht sofort")
        W.Advance(31); C.Check()
        local r, a = n()
        eq(r, 1); eq(a, 1, "danach nach Spielern fragen")
    end)

    watchtest("Kanal-Wache: kommt etwas zurück (auch Eigenes), ist alles in Ordnung", function(C, n)
        for _ = 1, 5 do C.Sent("CHANNEL", 0) end
        Heard("GuildPride", ns.Me())
        W.Advance(60); C.Check(); eq((n()), 0)
        -- andere GuildPride-Kanäle zählen auch
        for _ = 1, 5 do C.Sent("CHANNEL", 0) end
        Heard("GPAH"); W.Advance(60); C.Check(); eq((n()), 0)
        -- fremde Addons nicht
        for _ = 1, 5 do C.Sent("CHANNEL", 0) end
        Heard("AndereAddon"); W.Advance(60); C.Check(); eq((n()), 1)
    end)

    watchtest("Kanal-Wache: Gilde, Flüstern und gedrosselte Nachrichten zählen nicht", function(C, n)
        for _ = 1, 5 do C.Sent("GUILD", 0); C.Sent("WHISPER", 0); C.Sent("CHANNEL", 3) end
        W.Advance(60); C.Check(); eq((n()), 0)
    end)

    watchtest("Kanal-Wache: höchstens drei Versuche je Sitzung, mit Pause, nie während der Chat-Sperre", function(C, n)
        C_ChatInfo.InChatMessagingLockdown = function() return true end
        for _ = 1, 3 do C.Sent("CHANNEL", 0) end
        W.Advance(60); C.Check(); eq((n()), 0, "gesperrt")
        C_ChatInfo.InChatMessagingLockdown = function() return false end
        C.Check(); eq((n()), 1)
        for _ = 1, 3 do C.Sent("CHANNEL", 0) end
        W.Advance(40); C.Check(); eq((n()), 1, "Pause")
        for i = 2, 6 do
            W.Advance(400); for _ = 1, 3 do C.Sent("CHANNEL", 0) end
            W.Advance(40); C.Check()
            eq((n()), math.min(i, 3), "Versuch " .. i)
        end
        -- lebt der Kanal wieder, zählt ein späterer Ausfall neu
        Heard(); for _ = 1, 3 do C.Sent("CHANNEL", 0) end
        W.Advance(400); C.Check(); eq((n()), 4)
    end)
end
