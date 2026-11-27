-- GuildPride: Senden und Kanäle – Warteschlange gegen die Drosselung, abgesicherter Kanal der
-- Gilde, offener Kanal der serverweiten Gruppensuche. Früher in GuildPrideEvents.lua, das diese
-- Datei direkt danach braucht (ns.EventsNet).
local ADDON, ns = ...
local L = ns.L
local PREFIX = "GuildPride"
local SEP = "\031"

-- Addon-Flüstern an Spieler, die inzwischen offline sind, erzeugt sonst
-- "Momentan ist kein Spieler mit dem Namen ... online." im Chat
local whisperedAt = {}
function ns.SendAddonMsg(prefix, msg, channel, target)
    if channel == "WHISPER" and target then
        whisperedAt[target] = GetTime()
        whisperedAt[(target:match("^[^-]+")) or target] = GetTime()
    end
    local res = C_ChatInfo.SendAddonMessage(prefix, msg, channel, target)
    if ns.NetSent then ns.NetSent(channel, res) end
    if ns.ChannelWatch then ns.ChannelWatch.Sent(channel, res) end
    return res
end
local AddSystemFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
if AddSystemFilter and ERR_CHAT_PLAYER_NOT_FOUND_S then
    local pattern = "^" .. ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
    AddSystemFilter("CHAT_MSG_SYSTEM", function(_, _, text)
        if issecretvalue and issecretvalue(text) then return false end
        local who = text and text:match(pattern)
        if not who then return false end
        local t = whisperedAt[who] or whisperedAt[(who:match("^[^-]+")) or who]
        return t ~= nil and GetTime() - t < 10
    end)
end

local function Me()
    return ns.Me()
end

local function CanManage()
    return CanEditMOTD and CanEditMOTD()
end

local function Now() return GetServerTime() end

---------------------------------------------------------------------
-- Senden (mit Warteschlange gegen Drosselung)
---------------------------------------------------------------------
-- Der Server drosselt Addon-Nachrichten pro Prefix. Gedrosselte Nachrichten
-- gingen früher verloren; jetzt kommen sie zurück in die Warteschlange.
local queue = {}
local publicQueue = {}   -- serverweite Gruppensuche (Ziel "@PUBLIC"), eigener Takt
local pauseUntil = 0
local RESULT = Enum and Enum.SendAddonMessageResult
local function Throttled(res)
    if not RESULT then return false end
    return (RESULT.AddonMessageThrottle ~= nil and res == RESULT.AddonMessageThrottle)
        or (RESULT.ChannelThrottle ~= nil and res == RESULT.ChannelThrottle)
end

---------------------------------------------------------------------
-- Ränge ohne Gildenchat-Recht
-- Wer im Gildenchat nicht schreiben darf, kann auch keine Addon-Nachrichten an
-- die Gilde schicken. Solche Nachrichten gehen deshalb als Flüstern ("RLY") an
-- ein GuildPride-Mitglied mit Schreibrecht, das sie unter dem ursprünglichen
-- Namen an die Gilde weitergibt ("FWD", siehe GuildPride.lua).
---------------------------------------------------------------------
local function RankFlags(rankIndex)
    if not (rankIndex and C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags) then return nil end
    return C_GuildInfo.GuildControlGetRankFlags(rankIndex + 1)
end

-- Nur ein ausdrückliches "Nein" zählt. Achtung: Die Rangrechte ANDERER Ränge
-- kann nur die Gildenleitung lesen – für normale Mitglieder kommt dort "aus"
-- zurück. Darauf darf das Senden deshalb nie beruhen.
function ns.CanSpeakGuild()
    if C_GuildInfo and C_GuildInfo.CanSpeakInGuildChat then return C_GuildInfo.CanSpeakInGuildChat() ~= false end
    return true
end

function ns.CanListenGuild()
    local _, _, rankIndex = GetGuildInfo("player")
    local flags = RankFlags(rankIndex)
    if not flags or flags[1] == nil then return true end
    return flags[1] and true or false
end

-- Wer leitet weiter? Bekannte GuildPride-Nutzer zuerst (bis zu 2), sonst bis
-- zu 3 zufällige Mitglieder online (Addon-Nachrichten sind für Spieler ohne
-- GuildPride unsichtbar). Wer selbst nicht schreiben darf, leitet nicht weiter.
local function Relays()
    local known, others = {}, {}
    local me = Me()
    for i = 1, GetNumGuildMembers() do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if name and online then
            local full = ns.FullName and ns.FullName(name) or name
            if full ~= me then
                if ns.AddonUsers and ns.AddonUsers[full] then known[#known + 1] = full else others[#others + 1] = full end
            end
        end
    end
    local list = #known > 0 and known or others
    local pick, max = {}, #known > 0 and 2 or 3
    while #list > 0 and #pick < max do pick[#pick + 1] = table.remove(list, math.random(#list)) end
    return pick
end

local function Failed(res)
    if type(res) ~= "number" then return res == false end
    local ok = RESULT and RESULT.Success or 0
    return res ~= ok
end

local relayId = 0
local function Relay(msg)
    relayId = relayId % 9999 + 1
    local id = math.random(10, 99) .. relayId
    local res
    for _, r in ipairs(Relays()) do
        res = ns.SendAddonMsg(PREFIX, "RLY:" .. id .. SEP .. msg, "WHISPER", r)
    end
    return res
end

-- Immer zuerst direkt an die Gilde. Nur wenn das scheitert oder der eigene
-- Rang ausdrücklich nicht schreiben darf, zusätzlich über andere weiterleiten.
local function SendToGuild(msg)
    local res = ns.SendAddonMsg(PREFIX, msg, "GUILD")
    if Throttled(res) then return res end
    if Failed(res) or not ns.CanSpeakGuild() then
        Relay(msg)
        return nil
    end
    return res
end

---------------------------------------------------------------------
-- Abgesicherter Kanal der Gilde
-- Rundsendungen gehen zusätzlich über einen eigenen Chat-Kanal, damit sie nicht
-- von Rangrechten im Gildenkanal abhängen; auch der Abgleich (Antworten auf
-- Anfragen) läuft darüber, sobald der Empfänger im Kanal ist.
-- Name und Passwort kommen aus einem geheimen Zufallsschlüssel, den die
-- Gildenleitung erzeugt. Er wird NIE über den Kanal selbst verschickt, nur über
-- den Gildenkanal (Server liefert nur an Mitglieder) oder per Flüstern an
-- Gildenmitglieder ("CKY", Empfang in GuildPride.lua). Wer ihn nicht hat, fragt
-- nach ("CKQ"). Verlässt jemand die Gilde, erzeugt die Gildenleitung einen neuen.
-- Nachrichten zählen zusätzlich nur von Gildenmitgliedern (GuildPride.lua).
-- Der Kanal wird nicht in Chatfenster eingetragen (Addon-Nachrichten sind dort
-- ohnehin unsichtbar) – Blizzards Chatcode wird nicht angefasst.
---------------------------------------------------------------------
local function Hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end

local function GuildKey()
    local guild = GetGuildInfo("player")
    if not guild then return end
    local realm = select(4, GetGuildInfo("player")) or GetNormalizedRealmName() or ""
    return guild, realm
end

-- Alter Kanal (bis 1.12.2): aus dem Gildennamen berechnet, also für jeden
-- mit dem Addon-Code ausrechenbar. Wird nur noch verlassen.
local function LegacyChannel()
    local guild, realm = GuildKey()
    if not guild then return end
    return ("GPd%x"):format(Hash(guild .. "@" .. realm))
end

local function KeyStore()
    local guild, realm = GuildKey()
    if not guild or not GuildPrideDB then return end
    GuildPrideDB.chanKeys = GuildPrideDB.chanKeys or {}
    local id = guild .. "@" .. realm
    GuildPrideDB.chanKeys[id] = GuildPrideDB.chanKeys[id] or {}
    return GuildPrideDB.chanKeys[id]
end

local function DataChannel()
    local s = KeyStore()
    local k = s and s.k
    if not k then return end
    return ("GPs%x%x"):format(Hash(k), Hash(k:reverse())), ("%x%x"):format(Hash("pw" .. k), Hash(k .. "pw"))
end

function ns.DataChannelId()
    local name = DataChannel()
    if not name then return end
    local id = GetChannelName(name)
    return id and id > 0 and id or nil, name
end
function ns.DataChannelName() return (DataChannel()) end

-- Wer wurde zuletzt im Kanal gehört? Dorthin gehen Antworten über den Kanal
local chanSeen = {}
function ns.ChannelSeen(who) chanSeen[who] = GetTime() end
local function InChannel(who) return chanSeen[who] and GetTime() - chanSeen[who] < 300 end
ns.HeardInChannel = InChannel

local joinReady, joinedName = false, nil
local function JoinDataChannel()
    if not joinReady then return end
    local legacy = LegacyChannel()
    if legacy and LeaveChannelByName and GetChannelName(legacy) > 0 then LeaveChannelByName(legacy) end
    local name, pw = DataChannel()
    if joinedName and joinedName ~= name and LeaveChannelByName then LeaveChannelByName(joinedName) end
    joinedName = name
    if not name or ns.DataChannelId() then return end
    if JoinTemporaryChannel then JoinTemporaryChannel(name, pw) end
end

---------------------------------------------------------------------
-- Serverweite Gruppensuche: offener Kanal je Spielversion ("GPLFGR",
-- "GPLFGC1" …). Darin kann jeder schreiben – angenommen werden dort nur
-- Gruppensuche-Einträge mit passender Kennung (GuildPrideHelp.lua).
---------------------------------------------------------------------
local function PublicChannel() return "GPLFG" .. (ns.CLIENT_TAG or "X") end
ns.PublicChannelName = PublicChannel
local function SendChat(text, kind, lang, target) return ns.SendChat(text, kind, lang, target, true) end
-- Für /gp server status: gesendet, letztes Sende-Ergebnis, empfangen
ns.publicStats = { sent = 0, received = 0, echo = 0 }

-- Offener Kanal: für die Gruppensuche (Schalter) und in WoW Forever immer für die
-- Schiffs-Zähler. Gruppensuche und Layer-Wechsel prüfen den Schalter selbst (PublicLFGOn).
function ns.PublicChannelId()
    if not ns.PublicChannelWanted() then return end
    local id = GetChannelName(PublicChannel())
    return id and id > 0 and id or nil
end

function ns.IsPublicChannel(localID, chanName)
    local id = ns.PublicChannelId()
    if not id then return false end
    if localID == id then return true end
    local name = PublicChannel():lower()
    return type(chanName) == "string" and (chanName:lower() == name or chanName:lower():match("^%d+%.%s*(.+)$") == name)
end

-- farewell: beim Verlassen noch direkt gesendet (eigenen Eintrag zurückziehen)
local publicWarned = false
function ns.UpdatePublicChannel(farewell)
    if not joinReady then return end
    local name = PublicChannel()
    local joined = GetChannelName(name) > 0
    local function SendFarewell()
        if not farewell or not joined then return end
        if ns.PUBLIC_VIA_CHAT then SendChat((farewell:gsub(SEP, "~")), "CHANNEL", nil, (GetChannelName(name)))
        else ns.SendAddonMsg(PREFIX, farewell, "CHANNEL", (GetChannelName(name))) end
    end
    if ns.PublicChannelWanted() and not joined then
        if JoinTemporaryChannel then JoinTemporaryChannel(name) end
        -- Kein Platz mehr (höchstens 10 eigene Kanäle)? Einmal Bescheid geben
        C_Timer.After(5, function()
            if ns.PublicChannelWanted() and GetChannelName(name) == 0 and not publicWarned then
                publicWarned = true
                ns.Print(L["Serverweite Gruppensuche: Kanal konnte nicht betreten werden (zu viele Chatkanäle?)."])
            end
        end)
    elseif not ns.PublicChannelWanted() and joined then
        wipe(publicQueue)
        SendFarewell()
        if LeaveChannelByName then LeaveChannelByName(name) end
    elseif joined and not ns.PublicLFGOn() then
        -- Gruppensuche aus, Kanal bleibt für die Schiffs-Zähler: nur Gruppensuche-Einträge
        -- aus der Warteschlange nehmen und den eigenen Eintrag zurückziehen
        for i = #publicQueue, 1, -1 do
            if publicQueue[i].kind:sub(1, 2) ~= "TP" then table.remove(publicQueue, i) end
        end
        SendFarewell()
    end
end

-- Classic: Rundsendungen gehen als normale Chatnachricht in den offenen Kanal.
-- Das erlaubt Blizzard nur direkt bei einem Klick – Aufrufer achten darauf.
-- Das Trennzeichen ist dort nicht erlaubt und wird zu "~".
function ns.SendPublicChat(kind, ...)
    local chan = ns.PublicChannelId()
    if not chan then return end
    local parts = { ... }
    for i = 1, select("#", ...) do parts[i] = (tostring(parts[i] == nil and "" or parts[i]):gsub("~", "-")) end
    local msg = kind .. ":" .. table.concat(parts, "~")
    if #msg > 255 then return end
    SendChat(msg, "CHANNEL", nil, chan)
    local st = ns.publicStats
    st.sent, st.lastRes, st.lastAt = st.sent + 1, "chat", GetTime()
end

-- Kanalzeilen nicht im Chatfenster zeigen; der Filter kommt erst dazu, wenn
-- der Chat-Weg wirklich genutzt wird (Retail bleibt unberührt)
local chatFiltered = false
local function FilterPublicChat()
    if chatFiltered then return end
    local AddFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
    if not AddFilter then return end
    chatFiltered = true
    AddFilter("CHAT_MSG_CHANNEL", function(_, _, _, _, _, chanName, _, _, _, chanIndex, chanBase)
        if not ns.PUBLIC_VIA_CHAT then return false end
        return ns.IsPublicChannel(chanIndex, chanBase) or ns.IsPublicChannel(nil, chanName)
    end)
end
if ns.PUBLIC_VIA_CHAT then FilterPublicChat() end

-- Classic: Einträge und Abfragen aus dem offenen Kanal an die Gruppensuche
local chatIn = CreateFrame("Frame")
chatIn:RegisterEvent("CHAT_MSG_CHANNEL")
chatIn:SetScript("OnEvent", function(_, _, text, sender, _, chanName, _, _, _, chanIndex, chanBase)
    if not ns.PUBLIC_VIA_CHAT or not ns.OnPublicMessage then return end
    if type(text) ~= "string" or type(sender) ~= "string" or sender == "" then return end
    if not (ns.IsPublicChannel(chanIndex, chanBase) or ns.IsPublicChannel(nil, chanName)) then return end
    ns.OnPublicMessage((text:gsub("~", SEP)), ns.Normalize(sender))
end)

local chanFrame = CreateFrame("Frame")
chanFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
chanFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
chanFrame:SetScript("OnEvent", function()
    -- spät beitreten, damit Allgemein/Handel ihre gewohnten Nummern behalten
    C_Timer.After(15, function() joinReady = true; JoinDataChannel(); ns.UpdatePublicChannel() end)
end)

-- Alle GuildPride-Kanäle verlassen und neu betreten (GuildPrideChannelWatch.lua): manchmal glaubt
-- der Client, noch drin zu sein, der Server aber nicht.
-- done() läuft, wenn die Kanäle wieder da sein sollten.
function ns.RejoinChannels(done)
    if not joinReady or not LeaveChannelByName then return false end
    local names = { (DataChannel()) or false, PublicChannel(), ns.AH and ns.AH.CHANNEL or false, ns.Rares and ns.Rares.CHANNEL or false }
    for i = 1, 4 do
        local n = names[i]
        if n and GetChannelName(n) > 0 then LeaveChannelByName(n) end
    end
    joinedName = nil
    C_Timer.After(4, function()
        JoinDataChannel()
        ns.UpdatePublicChannel()
        if ns.AH and ns.AH.UpdateChannel then ns.AH.UpdateChannel() end
        if ns.Rares and ns.Rares.Join then ns.Rares.Join() end
        if done then C_Timer.After(4, done) end
    end)
    return true
end

-- Schlüssel: Hex-Text + Version (Zeit). Neuere Version gewinnt, bei
-- Gleichstand der größere Text – so landen alle beim selben Schlüssel.
local function NewKey()
    local t = {}
    for i = 1, 24 do t[i] = ("%x"):format(math.random(0, 15)) end
    return table.concat(t)
end

local function Newer(k, v, s)
    if not s.k then return true end
    return v > (s.v or 0) or (v == (s.v or 0) and k > s.k)
end

local function SendKey(target)
    local s = KeyStore()
    if not (s and s.k) then return end
    local msg = "CKY:" .. s.k .. SEP .. s.v
    if target then
        ns.SendAddonMsg(PREFIX, msg, "WHISPER", target)
    elseif IsInGuild() then
        ns.SendAddonMsg(PREFIX, msg, "GUILD")
    end
end

-- Empfang (nur über Gilde oder Flüstern von Mitgliedern, siehe GuildPride.lua)
function ns.OnChannelKey(payload, sender)
    local k, v = strsplit(SEP, payload)
    v = ns.Stamp(v)
    if not k or not k:match("^%x+$") or #k < 16 or #k > 64 or v == 0 then return end
    local s = KeyStore()
    if not s or not Newer(k, v, s) then return end
    s.k, s.v = k, v
    JoinDataChannel()
end

-- Neuen Schlüssel erzeugen (nur Gildenleitung), höchstens einmal pro Minute;
-- kommt eine weitere Anfrage zu früh, wird sie nach Ablauf der Minute nachgeholt
local rotatedAt, rotatePending = -999, false
function ns.RotateChannelKey(force)
    if not CanManage() or not IsInGuild() then return false end
    local wait = 60 - (GetTime() - rotatedAt)
    if not force and wait > 0 then
        if not rotatePending then
            rotatePending = true
            C_Timer.After(wait, function() rotatePending = false; ns.RotateChannelKey() end)
        end
        return false
    end
    local s = KeyStore()
    if not s then return false end
    rotatedAt = GetTime()
    s.k, s.v = NewKey(), math.max(Now(), (s.v or 0) + 1)
    SendKey()
    JoinDataChannel()
    return true
end

local keyAskedAt = -999
local function AskKey()
    local s = KeyStore()
    if not s or GetTime() - keyAskedAt < 25 then return end
    keyAskedAt = GetTime()
    ns.Queue("CKQ", nil, s.v or 0)
end

-- Anfrage: wer einen neueren Schlüssel hat, flüstert ihn zu. Damit nicht die
-- halbe Gilde antwortet, antwortet jeder nur mit einer Wahrscheinlichkeit,
-- die im Schnitt etwa drei Antworten ergibt (wer leer ausgeht, fragt erneut).
ns.On("CKQ", function(payload, sender)
    if sender == Me() then return end
    local s = KeyStore()
    if not s then return end
    local theirs = ns.Stamp(payload)
    if s.k and theirs < (s.v or 0) then
        local n = 0
        for i = 1, GetNumGuildMembers() do
            local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
            if name and online and ns.AddonUsers[ns.FullName and ns.FullName(name) or name] then n = n + 1 end
        end
        if math.random() * math.max(n, 1) < 3 then
            C_Timer.After(0.5 + math.random() * 3, function() SendKey(sender) end)
        end
    elseif theirs > (s.v or 0) then
        AskKey()   -- der andere hat einen neueren: selbst nachfragen
    end
end)

-- Nach dem Login nachfragen; ohne Schlüssel weiter fragen. Ist nach einer Weile
-- immer noch keiner da, erzeugt die Gildenleitung einen. Wer den Gildenkanal
-- nicht lesen darf, verpasst neue Schlüssel und fragt deshalb alle 10 Min.
local keyFrame = CreateFrame("Frame")
keyFrame:RegisterEvent("PLAYER_LOGIN")
keyFrame:SetScript("OnEvent", function()
    C_Timer.After(5, AskKey)
    local tries = 0
    C_Timer.NewTicker(30, function()
        if not IsInGuild() then return end
        local s = KeyStore()
        if not s then return end
        tries = tries + 1
        if not s.k then
            -- Gildenleitung erst nach zwei Nachfragen (1 Min.), damit sie keinen
            -- vorhandenen Schlüssel überschreibt, nur weil zufällig keiner antwortete
            if CanManage() and tries >= 2 then ns.RotateChannelKey(true) elseif tries <= 10 then AskKey() end
        elseif tries % 20 == 0 and ns.CanListenGuild and not ns.CanListenGuild() then
            AskKey()
        end
    end)
end)

local origSlash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd = strtrim(arg or ""):lower()
    if cmd == "kanal" or cmd == "channel" then
        local s = KeyStore()
        if s and s.k then
            ns.Print((L["Abgesicherter Kanal aktiv (Schlüssel vom %s)."]):format(ns.FormatDay(s.v, true)))
        else
            ns.Print(L["Noch kein Kanal-Schlüssel – er kommt von der Gildenleitung."])
        end
    elseif cmd == "kanal neu" or cmd == "channel new" then
        if ns.RotateChannelKey(true) then
            ns.Print(L["Neuer Kanal-Schlüssel erzeugt und an die Gilde verteilt."])
        else
            ns.Print(L["Nur die Gildenleitung kann einen neuen Kanal-Schlüssel erzeugen."])
        end
    else
        origSlash(arg)
    end
end

C_Timer.NewTicker(0.3, function()
    if GetTime() < pauseUntil then return end
    -- Während der Chat-Sperre (Bosskampf, M+, PvP) nichts senden; die Warteschlange bleibt erhalten
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
    local item = table.remove(queue, 1)
    if not item then return end
    local res
    if item.target == "@OFFICER" then
        if IsInGuild() then res = ns.SendAddonMsg(PREFIX, item.msg, "OFFICER") end
    elseif item.target == "@CHANNEL" then
        -- Nur über den abgesicherten Kanal; ohne Kanal-Schlüssel über die Gilde
        local chan = ns.DataChannelId()
        if chan then
            res = ns.SendAddonMsg(PREFIX, item.msg, "CHANNEL", chan)
        elseif IsInGuild() then
            res = SendToGuild(item.msg)
        end
    elseif item.target then
        -- Abgleich: ist der Empfänger im abgesicherten Kanal, dort senden
        -- (alle im Kanal bleiben so auf demselben Stand), sonst flüstern
        local chan = ns.DataChannelId()
        if chan and InChannel(item.target) then
            res = ns.SendAddonMsg(PREFIX, item.msg, "CHANNEL", chan)
        else
            res = ns.SendAddonMsg(PREFIX, item.msg, "WHISPER", item.target)
        end
    elseif IsInGuild() then
        res = SendToGuild(item.msg)
        local chan = ns.DataChannelId()
        if chan and not Throttled(res) then ns.SendAddonMsg(PREFIX, item.msg, "CHANNEL", chan) end
    end
    if Throttled(res) then
        item.tries = (item.tries or 0) + 1
        if item.tries <= 10 then table.insert(queue, 1, item) end
        pauseUntil = GetTime() + 1.5
    end
end)

-- Serverweite Gruppensuche: höchstens eine Nachricht alle 2 s, nur über den
-- offenen Kanal (nie ersatzweise an die Gilde), Gildennachrichten haben Vorrang
C_Timer.NewTicker(2, function()
    if #queue > 0 or GetTime() < pauseUntil then return end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
    local item = table.remove(publicQueue, 1)
    if not item then return end
    local res
    if item.to then
        -- Antwort auf eine Abfrage: direkt an den Fragenden
        res = ns.SendAddonMsg(PREFIX, item.msg, "WHISPER", item.to)
    else
        local chan = ns.PublicChannelId()
        if not chan or ns.PUBLIC_VIA_CHAT then return end
        res = ns.SendAddonMsg(PREFIX, item.msg, "CHANNEL", chan)
    end
    local st = ns.publicStats
    st.sent, st.lastRes, st.lastAt = st.sent + 1, res, GetTime()
    if not item.to and RESULT and RESULT.InvalidChatType ~= nil and res == RESULT.InvalidChatType then
        -- Diese Spielversion lässt keine Addon-Nachrichten in eigene Kanäle zu:
        -- weiter wie in Classic (Chatnachricht beim Klicken, Antworten per Flüstern)
        ns.PUBLIC_VIA_CHAT = true
        FilterPublicChat()
        for i = #publicQueue, 1, -1 do if not publicQueue[i].to then table.remove(publicQueue, i) end end
        ns.Print(L["Serverweite Gruppensuche: Diese Spielversion sperrt Addon-Nachrichten in Chatkanälen. Dein Eintrag geht jetzt beim Eintragen raus, Antworten kommen per Flüstern."])
    elseif Throttled(res) then
        item.tries = (item.tries or 0) + 1
        if item.tries <= 5 then table.insert(publicQueue, 1, item) end
        pauseUntil = GetTime() + 1.5
    end
end)

-- Addon-Nachrichten dürfen höchstens 255 Byte lang sein; längere (z. B. Events
-- mit Beschreibung und Notiz) kamen früher nie an. Sie werden jetzt als
-- "MP:id·nr·anzahl·stück" verschickt und beim Empfänger wieder zusammengesetzt
-- (siehe GuildPride.lua). Die Grenze lässt Platz für die Weiterleitung (RLY/FWD).
local MAX_LEN, PART_LEN = 195, 175
local multiId = 0

-- Serverweit: nie mehrteilig (MP wird dort nicht angenommen); pro Art und
-- Empfänger zählt nur der neueste Stand, ältere wartende werden ersetzt
local function PublicPush(kind, msg, to)
    if #msg > 255 then return end
    for i, it in ipairs(publicQueue) do
        if it.kind == kind and it.to == to then publicQueue[i] = { msg = msg, kind = kind, to = to }; return end
    end
    table.insert(publicQueue, { msg = msg, kind = kind, to = to })
end

-- Antwort auf eine serverweite Abfrage: per Flüstern an den Fragenden
function ns.QueuePublicTo(to, kind, ...)
    local parts = { ... }
    for i = 1, select("#", ...) do parts[i] = tostring(parts[i] == nil and "" or parts[i]) end
    PublicPush(kind, kind .. ":" .. table.concat(parts, SEP), to)
end

-- Eilig (Layer-Wechsel): sofort senden statt im 2-s-Takt hinter anderen
-- Nachrichten zu warten. Gesperrt oder gedrosselt: vorne in die Warteschlange.
function ns.SendPublicNow(to, kind, ...)
    local parts = { ... }
    for i = 1, select("#", ...) do parts[i] = tostring(parts[i] == nil and "" or parts[i]) end
    local msg = kind .. ":" .. table.concat(parts, SEP)
    if #msg > 255 then return end
    local res, sent
    if not (C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()) then
        if to then
            res, sent = ns.SendAddonMsg(PREFIX, msg, "WHISPER", to), true
        else
            local chan = ns.PublicChannelId()
            if chan and not ns.PUBLIC_VIA_CHAT then res, sent = ns.SendAddonMsg(PREFIX, msg, "CHANNEL", chan), true end
        end
    end
    if sent and not Throttled(res) then
        local st = ns.publicStats
        st.sent, st.lastRes, st.lastAt = st.sent + 1, res, GetTime()
        return true
    end
    table.insert(publicQueue, 1, { msg = msg, kind = kind, to = to })
    return false
end

local function Queue(kind, target, ...)
    local parts = { ... }
    for i = 1, select("#", ...) do parts[i] = tostring(parts[i] == nil and "" or parts[i]) end
    local msg = kind .. ":" .. table.concat(parts, SEP)
    if target == "@PUBLIC" then
        PublicPush(kind, msg)
        return
    end
    if #msg <= MAX_LEN then
        table.insert(queue, { msg = msg, target = target })
        return
    end
    multiId = multiId % 999 + 1
    local id = math.random(100, 999) .. multiId
    local n = math.ceil(#msg / PART_LEN)
    for i = 1, n do
        table.insert(queue, { target = target,
            msg = ("MP:%s%s%d%s%d%s%s"):format(id, SEP, i, SEP, n, SEP, msg:sub((i - 1) * PART_LEN + 1, i * PART_LEN)) })
    end
end
ns.Queue = Queue
function ns.QueueLength() return #queue end
-- Nur der neueste Stand zählt (z. B. die Kartenposition): wartende ältere
-- Nachrichten derselben Art an dasselbe Ziel fliegen vorher raus
function ns.QueueLatest(kind, target, ...)
    local head = kind .. ":"
    for i = #queue, 1, -1 do
        local it = queue[i]
        if it.target == target and it.msg:sub(1, #head) == head then table.remove(queue, i) end
    end
    Queue(kind, target, ...)
end

local function SendEvent(e, target)
    -- rep: Wiederholung in Tagen (7 = jede Woche); ältere Versionen ignorieren das Feld
    -- kind/inst: Dungeon oder Raid (GuildPrideInstances.lua), ebenso nur bei neueren Versionen
    Queue("EVT", target, e.id, e.t, e.title, e.desc, e.creator, e.ver, e.note or "", e.rep or 0,
        e.kind or "", e.inst or "")
end
local function SendDelete(e, target) Queue("DEL", target, e.id, e.ver) end
local function SendSign(id, name, s, target) Queue("SGN", target, id, name, s.s, s.v, s.r or "") end

-- Ist der Spieler gerade online? (Gildenliste)
local function IsOnline(full)
    for i = 1, GetNumGuildMembers() do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if name and online and (ns.FullName and ns.FullName(name) or name) == full then return true end
    end
end

-- Zusätzlich direkt an den Ersteller flüstern: Was ein Rang an die Gilde schickt,
-- kommt nicht immer bei allen an (Rangrechte), ein Flüstern schon.
function ns.TellCreator(creator, send)
    if creator and creator ~= "" and creator ~= Me() and IsOnline(creator) then send(creator) end
end

-- Kommt jemand online, ruft fn(name) auf (z. B. eigene Anmeldungen nachliefern,
-- die der Ersteller verpasst hat, weil er offline war)
local onlineBefore, onlineHooks = nil, {}
function ns.OnMemberOnline(fn) onlineHooks[#onlineHooks + 1] = fn end
ns.OnRoster(function(list)
    local now, me = {}, Me()
    for _, m in ipairs(list) do
        if m.online then now[ns.FullName and ns.FullName(m.name) or m.name] = true end
    end
    if onlineBefore then
        for full in pairs(now) do
            if not onlineBefore[full] and full ~= me then
                -- kurz warten, bis der andere sein Addon geladen hat
                C_Timer.After(20 + math.random() * 10, function()
                    for _, fn in ipairs(onlineHooks) do
                        local ok, err = pcall(fn, full)
                        if not ok then geterrorhandler()(err) end
                    end
                end)
            end
        end
    end
    onlineBefore = now
end)

-- Dasselbe für Nachrichten ohne Ersteller (z. B. Gruppensuche): an die Gildenleitung
-- (Rang 0 und 1) flüstern, die online ist. Wer selbst Rang 0/1 hat, braucht das nicht.
function ns.TellLeaders(send)
    local _, _, myRank = GetGuildInfo("player")
    if not myRank or myRank <= 1 then return end
    local me, n = Me(), 0
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(i)
        local full = name and (ns.FullName and ns.FullName(name) or name)
        if full and online and rankIndex and rankIndex <= 1 and full ~= me and n < 3 then
            n = n + 1
            send(full)
        end
    end
end

ns.EventsNet = { SendEvent = SendEvent, SendDelete = SendDelete, SendSign = SendSign }
