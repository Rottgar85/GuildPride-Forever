-- GuildPride Rares: serverweites Teilen über einen offenen Addon-Kanal
--   S:npc:name:map:x:y:hp:layer:zeit   Sichtung (x, y: 0 … 1000)
--   K:npc:map:layer:zeit               getötet
-- In den offenen Kanal kann jeder schreiben: alles wird geprüft und gebremst.
local ADDON, GP = ...
-- Rare-Scanner läuft in einem eigenen Unter-Namensraum, damit sich nichts mit GuildPride beißt
GP.Rares = GP.Rares or {}
local ns = GP.Rares

local PREFIX   = "GPRare"
local CHANNEL  = "GPRaresF"     -- eigener Kanal für WoW Forever
local SEND_GAP = 1.5            -- s zwischen eigenen Nachrichten
local queue, lastSend = {}, 0
ns.stats = { sent = 0, received = 0, dropped = 0 }

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
end

local function ChannelId()
    local id = GetChannelName(CHANNEL)
    return id and id > 0 and id or nil
end
ns.ChannelId = ChannelId

local function Join()
    if ChannelId() or not JoinTemporaryChannel then return end
    JoinTemporaryChannel(CHANNEL)
    C_Timer.After(5, function()
        if not ChannelId() then
            ns.Print("Kanal konnte nicht betreten werden (höchstens 10 Chatkanäle). Teilen ist aus, bis wieder Platz ist.")
        end
    end)
end

-- Spät beitreten, damit Allgemein/Handel ihre gewohnten Nummern behalten
ns.Listen("PLAYER_ENTERING_WORLD", function()
    C_Timer.After(20, Join)
end)

-- Kanalzeilen nie im Chatfenster zeigen (Addon-Nachrichten tauchen dort
-- ohnehin nicht auf – nur zur Sicherheit, falls jemand Text hineinschreibt)
local AddFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
if AddFilter then
    AddFilter("CHAT_MSG_CHANNEL", function(_, _, _, _, _, _, _, _, _, _, chanBase)
        return type(chanBase) == "string" and not ns.Secret(chanBase) and chanBase:lower() == CHANNEL:lower()
    end)
end

function ns.Send(...)
    if not ns.Opt("share") or not ns.Enabled() then return end
    local parts = { ... }
    for i = 1, select("#", ...) do parts[i] = tostring(parts[i] == nil and "" or parts[i]) end
    local msg = table.concat(parts, ":")
    if #msg > 250 then return end
    -- gleiche Art für denselben Gegner: nur der neueste Stand zählt
    local key = parts[1] .. ":" .. parts[2]
    for i = #queue, 1, -1 do if queue[i].key == key then table.remove(queue, i) end end
    queue[#queue + 1] = { key = key, msg = msg }
end

local warned = false
C_Timer.NewTicker(0.5, function()
    if #queue == 0 or GetTime() - lastSend < SEND_GAP then return end
    local id = ChannelId()
    if not id then return end
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
    local item = table.remove(queue, 1)
    lastSend = GetTime()
    local res = C_ChatInfo.SendAddonMessage(PREFIX, item.msg, "CHANNEL", id)
    ns.stats.sent = ns.stats.sent + 1
    ns.stats.lastRes = res
    if Enum and Enum.SendAddonMessageResult and res == Enum.SendAddonMessageResult.InvalidChatType and not warned then
        warned = true
        ns.Print("Diese Spielversion sperrt Addon-Nachrichten in Chatkanälen – Teilen geht so nicht.")
    end
end)

---------------------------------------------------------------------
-- Empfang mit Schutz gegen Spam und Unsinn
---------------------------------------------------------------------
local perSender = {}     -- [Name] = { n, since, blockedUntil }
local function Allowed(sender)
    local now = GetTime()
    local s = perSender[sender]
    if not s then s = { n = 0, since = now }; perSender[sender] = s end
    if s.blockedUntil and now < s.blockedUntil then return false end
    if now - s.since > 60 then s.n, s.since = 0, now end
    s.n = s.n + 1
    if s.n > 10 then s.blockedUntil = now + 300; return false end   -- mehr als 10/min: 5 min Pause
    return true
end

local function Num(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= v or v < lo or v > hi then return nil end
    return math.floor(v)
end

local function ValidMap(map)
    return map and C_Map.GetMapInfo and C_Map.GetMapInfo(map) ~= nil
end

-- Zeitangabe nur in einem vernünftigen Rahmen (keine Meldungen aus der Zukunft)
local function Stamp(v)
    local t, now = tonumber(v), GetServerTime()
    if not t or t > now + 60 or t < now - 600 then return now end
    return t
end

ns.Listen("CHAT_MSG_ADDON", function(prefix, msg, channel, sender)
    if ns.Secret(prefix) or prefix ~= PREFIX or not ns.Enabled() then return end
    if ns.Secret(msg) or ns.Secret(sender) or ns.Secret(channel) then return end
    if channel ~= "CHANNEL" or type(msg) ~= "string" or type(sender) ~= "string" then return end
    if sender == UnitName("player") or Ambiguate(sender, "none") == UnitName("player") then return end
    if #msg > 250 or not Allowed(sender) then ns.stats.dropped = ns.stats.dropped + 1; return end
    ns.stats.received = ns.stats.received + 1
    local kind, a, b, c, d, e, f, g, h, i = strsplit(":", msg)
    local who = Ambiguate(sender, "none")
    if kind == "S" then
        local npc, name, map = Num(a, 1, 9999999), ns.Clean(b, 40), Num(c, 1, 99999)
        local x, y, hp = Num(d, 0, 1000), Num(e, 0, 1000), Num(f, 0, 100)
        if not (npc and name ~= "" and map and x and y and ValidMap(map)) then
            ns.stats.dropped = ns.stats.dropped + 1; return
        end
        -- Gleicher Name wie bei früheren Meldungen dieser NPC-ID? Sonst verwerfen
        local old = ns.DB().seen[npc]
        if old and old.name and old.name ~= name then ns.stats.dropped = ns.stats.dropped + 1; return end
        local isNew = ns.AddSighting(npc, name, map, x / 1000, y / 1000, hp, ns.Clean(g, 12), who, Stamp(h), i == "1")
        if ns.OnRemoteSighting then ns.OnRemoteSighting(npc, isNew) end
    elseif kind == "K" then
        local npc = Num(a, 1, 9999999)
        local e2 = npc and ns.DB().seen[npc]
        -- Tod nur annehmen, wenn wir den Gegner kennen (verhindert erfundene IDs)
        if not e2 then ns.stats.dropped = ns.stats.dropped + 1; return end
        ns.AddKill(npc, Stamp(d))
    end
end)

-- Für /gpr status
function ns.CommStatus()
    return ("Kanal: %s · gesendet %d · empfangen %d · verworfen %d"):format(
        ChannelId() and ("ja (" .. ChannelId() .. ")") or "nein", ns.stats.sent, ns.stats.received, ns.stats.dropped)
end
