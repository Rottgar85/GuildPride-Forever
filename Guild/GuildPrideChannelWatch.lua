-- GuildPride: Kanal-Wache – tote Chat-Kanäle erkennen und neu betreten
-- Eigene Kanal-Nachrichten schickt der Server auch an den Absender zurück. Gehen mehrere raus (Ergebnis
-- „ok“) und kommt gar nichts an, nicht einmal die eigenen, ist der Client nur noch scheinbar im Kanal
-- (gesehen am 25.11.2026: 36 gesendet, 0 zurück; Gilde und Flüstern gingen). Dann verlässt GuildPride
-- seine Kanäle und tritt neu bei (ns.RejoinChannels).
local ADDON, ns = ...

local C = {}
ns.ChannelWatch = C
local MIN_SENT, MIN_WAIT = 3, 30        -- so viele Nachrichten und Sekunden ohne jede Antwort
local PAUSE, MAX_TRIES = 300, 3         -- zwischen zwei Versuchen; danach ist das Problem ein anderes
local sent, since, tries, last = 0, nil, 0, -PAUSE
C.stats = { repairs = 0, heard = 0 }

-- Aus ns.SendAddonMsg: nur Kanal-Nachrichten, die der Client angenommen hat
function C.Sent(channel, res)
    if channel ~= "CHANNEL" or not (res == 0 or res == true) then return end
    sent = sent + 1
    since = since or GetTime()
end

function C.Heard()
    sent, since, tries = 0, nil, 0
    C.stats.heard = C.stats.heard + 1
end

function C.Check()
    if sent < MIN_SENT or not since or GetTime() - since < MIN_WAIT then return false end
    if tries >= MAX_TRIES or GetTime() - last < PAUSE or not ns.RejoinChannels then return false end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return false end
    last, tries, sent, since = GetTime(), tries + 1, 0, nil
    C.stats.repairs = C.stats.repairs + 1
    ns.RejoinChannels(function()
        -- wieder drin: Gilde und Server neu fragen
        if ns.Players and ns.Players.Ask then ns.Players.Ask(true) end
    end)
    return true
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:SetScript("OnEvent", function(_, _, prefix, _, channel)
    -- Geschützte Werte zuerst prüfen: schon ein Vergleich damit wirft einen Fehler
    if issecretvalue and (issecretvalue(prefix) or issecretvalue(channel)) then return end
    if channel == "CHANNEL" and type(prefix) == "string" and (prefix == "GuildPride" or prefix == "GPAH" or prefix == "GPRare") then C.Heard() end
end)
C_Timer.NewTicker(15, function() C.Check() end)
