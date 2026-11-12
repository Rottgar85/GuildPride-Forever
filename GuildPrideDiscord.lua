-- GuildPride: Discord-Brücke
-- Nutzt Blizzards Gildenchat-Discord-Verknüpfung, um Events und Anmeldungen als
-- lesbare "[GP] ..."-Zeilen an Discord zu melden. Dort wertet sie GameBot aus.
-- Addons dürfen nichts ins Netz schicken: der einzige Weg ist der Gildenchat
-- (bzw. Blizzards eigener Discord-Stream der Gilde, falls getrennt).
--
-- Regeln (Tests vom 12.11.2026):
--  * Nur Spieler mit verknüpftem Discord werden nach Discord gespiegelt.
--    Unverknüpfte erzeugen dort nur einen Platzhalter, deshalb senden sie nie
--    selbst, sondern bitten ein verknüpftes Mitglied mit GuildPride (DRL).
--  * Gesendet wird nur aus einer Spieleraktion heraus (Klick/Tastendruck),
--    nie im Kampf. Bis dahin wartet die Zeile in einer Warteschlange.
local ADDON, ns = ...
local L = ns.L
local PREFIX = "GuildPride"
local TAG = "[GP]"

local Discord = {}
ns.Discord = Discord

local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function Clean(s, max) return (tostring(s or ""):gsub("[%c|]", "")):sub(1, max or 200) end

-- Einstellungen: an/aus und "verknüpft" stehen als normale Schalter in den
-- GuildPride-Einstellungen (GuildPrideDB.discordBridge / .discordLinked).
-- Alles andere (Weg, Rohzeilen, Hinweis) liegt in GuildPrideDB.discord.
local function Opt()
    GuildPrideDB.discord = GuildPrideDB.discord or {}
    local o = GuildPrideDB.discord
    -- Testversionen hatten "enabled"/"linked" hier: einmal übernehmen
    if o.linked ~= nil and GuildPrideDB.discordLinked == nil then
        GuildPrideDB.discordLinked = o.linked
        if o.linked then GuildPrideDB.discordBridge = true end
    end
    o.linked, o.enabled = nil, nil
    return o
end

local function Enabled() return GuildPrideDB and GuildPrideDB.discordBridge == true end
Discord.Enabled = Enabled

---------------------------------------------------------------------
-- Erkennen
---------------------------------------------------------------------
function ns.IsBridgeLine(text)
    return type(text) == "string" and not Secret(text) and text:sub(1, #TAG + 1) == TAG .. " "
end

-- Ist mein Discord verknüpft? Blizzards C_Discord ist für Addons gesperrt
-- (ein Aufruf löst "Aktion blockiert" aus), daher zählt nur die Einstellung
-- /gp discord verknuepft.
function Discord.IsLinked()
    Opt()
    return GuildPrideDB.discordLinked == true
end

-- Kurze, für alle gleiche Event-Nummer aus der langen Event-ID
function Discord.ShortId(id)
    local h = 5381
    for i = 1, #id do h = (h * 33 + id:byte(i)) % 2147483647 end
    local chars, out = "0123456789abcdefghijklmnopqrstuvwxyz", ""
    for _ = 1, 5 do
        local r = h % 36
        out = chars:sub(r + 1, r + 1) .. out
        h = math.floor(h / 36)
    end
    return out
end

---------------------------------------------------------------------
-- Gesehene Zeilen (gegen doppeltes Senden)
---------------------------------------------------------------------
local seen = {}
local function Seen(text)
    local t = seen[text]
    return t and GetTime() - t < 30
end
local function MarkSeen(text)
    local now = GetTime()
    for k, t in pairs(seen) do if now - t > 30 then seen[k] = nil end end
    seen[text] = now
end

---------------------------------------------------------------------
-- Senden
---------------------------------------------------------------------
local queue = {}

local function DiscordStream()
    if not (C_Club and C_Club.GetGuildClubId and C_Club.GetStreams) then return end
    if not (C_GuildInfo and C_GuildInfo.IsDiscordStreamSeparate) then return end
    local ok, separate = pcall(C_GuildInfo.IsDiscordStreamSeparate)
    if not ok or separate ~= true then return end
    local clubId = C_Club.GetGuildClubId()
    if not clubId then return end
    local want = Enum.ClubStreamType and Enum.ClubStreamType.Discord
    if not want then return end
    for _, st in ipairs(C_Club.GetStreams(clubId) or {}) do
        if not Secret(st.streamType) and st.streamType == want then return clubId, st.streamId end
    end
end

-- Rückgabe: "stream", "guild" oder nil (fehlgeschlagen)
local function SendNow(text)
    local o = Opt()
    if o.via == "stream" then
        local clubId, streamId = DiscordStream()
        if clubId and C_Club.SendMessage and pcall(C_Club.SendMessage, clubId, streamId, text) then
            return "stream"
        end
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if pcall(send, text, "GUILD") then return "guild" end
end

-- Aus einer Spieleraktion heraus aufrufen (Klick, Tastendruck)
function Discord.Flush()
    if #queue == 0 or InCombatLockdown() then return end
    if not IsInGuild() then wipe(queue); return end
    -- Bis zu drei Zeilen pro Aktion (lange DKP-Buchungen sind mehrteilig)
    for _ = 1, 3 do
        local item = table.remove(queue, 1)
        if not item then break end
        -- Hat es inzwischen schon jemand anderes gesendet?
        if not Seen(item) then
            MarkSeen(item)
            SendNow(item)
        end
    end
end

local function Enqueue(text)
    text = text:sub(1, 255)
    for _, q in ipairs(queue) do if q == text then return end end
    table.insert(queue, text)
end

-- Eine Zeile nach Discord bringen: selbst (verknüpft) oder über ein Mitglied
function Discord.Post(text, now)
    local o = Opt()
    if not Enabled() or not IsInGuild() then return end
    text = TAG .. " " .. Clean(text, 250)
    if Discord.IsLinked() then
        Enqueue(text)
        if now then Discord.Flush() end
    else
        ns.SendAddonMsg(PREFIX, "DRL:" .. text, "GUILD")
        if not o.hinted then
            o.hinted = true
            ns.Print(L["Tipp: Verknüpfe Discord (Optionen > Soziales), damit deine Anmeldungen direkt in Discord ankommen. Bis dahin gibt ein Gildenmitglied sie weiter. Schon verknüpft? /gp discord verknuepft"])
        end
    end
end

-- Bitte eines unverknüpften Mitglieds: kurz zufällig warten, dann übernehmen,
-- falls es noch niemand getan hat (gesendet wird mit der nächsten Aktion)
ns.On("DRL", function(payload, sender)
    if not Enabled() or not Discord.IsLinked() or sender == ns.Me() then return end
    if not ns.IsGuildMember(sender) or not ns.IsBridgeLine(payload) then return end
    local text = payload:sub(1, 255)
    C_Timer.After(math.random() * 4, function()
        if not Seen(text) then Enqueue(text) end
    end)
end)

-- Jeder Tastendruck außerhalb des Kampfes darf eine wartende Zeile senden.
-- Die Taste selbst wird normal weitergereicht.
local keys = CreateFrame("Frame", nil, UIParent)
keys:SetPropagateKeyboardInput(true)
keys:SetScript("OnKeyDown", function()
    if #queue > 0 then Discord.Flush() end
end)
keys:EnableKeyboard(true)

---------------------------------------------------------------------
-- Zeilen im Chat ausblenden und als gesehen merken
---------------------------------------------------------------------
local AddFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
local function Filter(_, _, text)
    if not ns.IsBridgeLine(text) then return false end
    MarkSeen(text)
    for i = #queue, 1, -1 do if queue[i] == text then table.remove(queue, i) end end
    return not (GuildPrideDB and Opt().showRaw)
end
if AddFilter then
    for _, ev in ipairs({ "CHAT_MSG_GUILD", "CHAT_MSG_GUILD_DISCORD", "CHAT_MSG_COMMUNITIES_CHANNEL" }) do
        pcall(AddFilter, ev, Filter)
    end
end

function ns.HideBridgeLine(text)
    return ns.IsBridgeLine(text) and not (GuildPrideDB and Opt().showRaw)
end

---------------------------------------------------------------------
-- Inhalte: Events und Anmeldungen
---------------------------------------------------------------------
-- Feste Wörter, die GameBot erkennt (Deutsch oder Englisch je nach Spielsprache)
local DE = ns.IS_GERMAN
Discord.DE = DE
local ROLE_TEXT = DE and { TANK = "Tank", HEALER = "Heiler", DAMAGER = "DD" } or { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }
local STATUS_TEXT = DE and { yes = "Zusage", maybe = "Vielleicht", no = "Absage" } or { yes = "Attending", maybe = "Maybe", no = "Declined" }

local function Name(full) return Ambiguate(full or "", "guild") end

local function When(t) return date("%d.%m. %H:%M", t) end

function Discord.EventCreated(e)
    if not e or not e.title then return end
    local line = ((DE and "Neues Event" or "New event") .. " #%s: %s – %s (t=%d%s)"):format(Discord.ShortId(e.id), Clean(e.title, 40),
        When(e.t), e.t, (e.rep and e.rep > 0) and (DE and ", wöchentlich" or ", weekly") or "")
    if e.desc and e.desc ~= "" then line = line .. " – " .. Clean(e.desc, 80) end
    Discord.Post(line, true)
end

function Discord.EventDeleted(e)
    if not e or not e.title then return end
    Discord.Post(((DE and "Event abgesagt" or "Event cancelled") .. " #%s: %s"):format(Discord.ShortId(e.id), Clean(e.title, 40)), true)
end

function Discord.SignedUp(e, s)
    if not e or not e.title or not s then return end
    local parts = {}
    if s.r and ROLE_TEXT[s.r] and s.s ~= "no" then parts[#parts + 1] = ROLE_TEXT[s.r] end
    local _, class = UnitClass("player")
    if class then parts[#parts + 1] = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class end
    local extra = #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or ""
    Discord.Post(("%s: %s #%s %s%s"):format(Name(ns.Me()), STATUS_TEXT[s.s] or s.s, Discord.ShortId(e.id),
        Clean(e.title, 40), extra), true)
end

---------------------------------------------------------------------
-- Befehle: /gp discord [an|aus|verknuepft|test|roh|gilde|auto]
---------------------------------------------------------------------
local slash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd, rest = strtrim(arg or ""):lower():match("^(%S+)%s*(.*)$")
    if cmd ~= "discord" then return slash(arg) end
    local o = Opt()
    if rest == "an" or rest == "on" then GuildPrideDB.discordBridge = true
    elseif rest == "aus" or rest == "off" then GuildPrideDB.discordBridge = false
    elseif rest == "verknuepft" or rest == "verknüpft" or rest == "linked" then GuildPrideDB.discordLinked = not Discord.IsLinked()
    elseif rest == "roh" or rest == "raw" then o.showRaw = not o.showRaw
    elseif rest == "gilde" or rest == "guild" then o.via = "guild"
    elseif rest == "stream" then o.via = "stream"
    elseif rest == "auto" then o.via = nil
    elseif rest == "test" then
        Discord.Post(("%s: Test %s"):format(Name(ns.Me()), ns.VERSION or ""), true)
        ns.Print(Discord.IsLinked() and L["Discord-Test gesendet."] or L["Discord-Test an ein verknüpftes Mitglied gegeben."])
        return
    end
    local stream = DiscordStream() and L["eigener Discord-Kanal"] or L["Gildenchat"]
    ns.Print(("Discord: %s · %s: %s · %s: %s · %s · %s: %d"):format(
        Enabled() and L["an"] or L["aus"],
        L["verknüpft"], Discord.IsLinked() and L["ja"] or L["nein"],
        L["Weg"], o.via == "stream" and stream or L["Gildenchat"],
        o.showRaw and L["Zeilen sichtbar"] or L["Zeilen ausgeblendet"],
        L["wartend"], #queue))
end
