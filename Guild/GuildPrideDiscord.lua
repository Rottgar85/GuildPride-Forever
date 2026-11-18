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
    -- "Weg" und "Rohzeilen" sind seit 2.20 normale Schalter in den Einstellungen
    if o.via ~= nil then
        if GuildPrideDB.discordViaGuild == nil then GuildPrideDB.discordViaGuild = (o.via == "guild") end
        o.via = nil
    end
    if o.showRaw ~= nil then
        if GuildPrideDB.discordShowRaw == nil then GuildPrideDB.discordShowRaw = o.showRaw end
        o.showRaw = nil
    end
    return o
end
local function ViaGuild() return GuildPrideDB and GuildPrideDB.discordViaGuild == true end
local function ShowRaw() return GuildPrideDB and GuildPrideDB.discordShowRaw == true end

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
local notBefore = {}   -- Zeile -> frühester Sendezeitpunkt (GetTime)
local hinted = false

-- Anmeldungen kurz zurückhalten: wer schnell umentscheidet (Zusage, dann
-- Vielleicht …), erzeugt nur eine Zeile statt mehrerer
local SIGN_HOLD = 10

-- Zeilen, die nur von Offizieren angenommen werden (GameBot prüft das)
local OFFICER_LINES = { "DKP ", "Raid: ", "Ankündigung: ", "Announcement: ", "Umfrage #", "Poll #", "Meilenstein: ", "Milestone: " }
local function OfficerLine(text)
    local body = text:sub(1, #TAG + 1) == TAG .. " " and text:sub(#TAG + 2) or text
    for _, p in ipairs(OFFICER_LINES) do if body:sub(1, #p) == p then return true end end
    return false
end
Discord.OfficerLine = OfficerLine

-- Kommt eine über den Discord-Kanal gesendete Zeile nicht zurück, nimmt
-- Blizzard sie offenbar still nicht an: dann in dieser Sitzung Gildenchat
local ECHO_WAIT = 10
local echoed, awaiting, missed = {}, {}, {}
local streamOk, streamBroken = false, false
local officerHinted = false
local Enqueue
local SIGN_WORDS = { Zusage = true, Vielleicht = true, Absage = true, Attending = true, Maybe = true, Declined = true }
local function SignKey(text)
    local name, word, id = text:match("^%[GP%] ([^:]+): (%S+) #(%w+)")
    if name and SIGN_WORDS[word] then return name .. "#" .. id end
end

-- Hat die Gildenleitung "Discord-Chat getrennt" eingeschaltet? Dann kommt
-- aus dem Gildenchat nichts mehr in Discord an.
local function Separated()
    if not (C_GuildInfo and C_GuildInfo.IsDiscordStreamSeparate) then return false end
    local ok, separate = pcall(C_GuildInfo.IsDiscordStreamSeparate)
    return ok and separate == true
end

local function DiscordStream()
    if not (C_Club and C_Club.GetGuildClubId and C_Club.GetStreams) then return end
    if not Separated() then return end
    local clubId = C_Club.GetGuildClubId()
    if not clubId then return end
    local want = Enum.ClubStreamType and Enum.ClubStreamType.Discord
    if not want then return end
    for _, st in ipairs(C_Club.GetStreams(clubId) or {}) do
        if not Secret(st.streamType) and st.streamType == want then return clubId, st.streamId end
    end
end

-- Zuletzt selbst gesendete Zeile: Meldet Blizzard gleich danach etwas zu
-- Discord, ist das eigene Konto nicht verknüpft
local lastSent, lastSentAt = nil, 0

-- Eigene Addon-Version für GameBots Versions-Übersicht: höchstens einmal pro
-- Woche (oder nach einem Update), nur über den eigenen Discord-Kanal der
-- Gilde, damit /g davon nichts abbekommt
local VERSION_EVERY = 7 * 86400
local function MaybeSendVersion(clubId, streamId)
    local v = ns.VERSION
    if type(v) ~= "string" or not v:match("^%d+%.%d+") then return end
    local o = Opt()
    if o.verSent == v and time() - (o.verAt or 0) < VERSION_EVERY then return end
    if pcall(C_Club.SendMessage, clubId, streamId, TAG .. " V " .. v) then
        o.verSent, o.verAt = v, time()
    end
end

-- Rückgabe: "stream", "guild" oder nil (fehlgeschlagen)
-- Standard: in Blizzards eigenen Discord-Kanal der Gilde, sobald die Gilde
-- ihn vom Gildenchat getrennt hat. Dann sieht /g die Zeilen gar nicht.
-- Nur mit /gp discord gilde immer in den Gildenchat.
local lastRoute, lastErr
local separatedWarned = false
local function SendNow(text)
    lastSent, lastSentAt = text, GetTime()
    if not ViaGuild() then
        local clubId, streamId = DiscordStream()
        local ok, err = false, "kein Discord-Kanal gefunden"
        if clubId and C_Club.SendMessage then ok, err = pcall(C_Club.SendMessage, clubId, streamId, text) end
        if not ok then lastErr = tostring(err) end
        if ok then
            if not streamOk then
                awaiting[text] = GetTime()
                C_Timer.After(ECHO_WAIT, function() Discord.CheckEcho(text) end)
            end
            MaybeSendVersion(clubId, streamId)
            lastRoute = "stream"
            return "stream"
        end
        -- Getrennter Discord-Chat: Der Gildenchat erreicht Discord nicht mehr,
        -- dorthin auszuweichen wäre nur Spam
        if Separated() then
            lastRoute = "none"
            if not separatedWarned then
                separatedWarned = true
                ns.Print(L["Discord-Zeile konnte nicht gesendet werden: Der Discord-Chat ist vom Gildenchat getrennt, aber GuildPride erreicht den Discord-Kanal nicht. Details: /gp discord info"])
            end
            return
        end
    end
    -- "Immer Gildenchat" bei getrenntem Discord-Chat: kommt nie in Discord an
    if ViaGuild() and Separated() and not separatedWarned then
        separatedWarned = true
        ns.Print(L["Achtung: Der Discord-Chat ist vom Gildenchat getrennt, aber „Discord-Zeilen immer in den Gildenchat“ ist an. So kommt nichts in Discord an. Abschalten: Einstellungen › Gilde oder /gp discord auto"])
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    lastRoute = "guild"
    if pcall(send, text, "GUILD") then
        -- Offizieren einmal pro Sitzung sagen, wie der Gildenchat frei bleibt
        if not hinted and not ViaGuild() and ns.IsOfficerName and ns.IsOfficerName(ns.Me()) then
            hinted = true
            ns.Print(L["Discord-Zeilen landen im Gildenchat. Damit /g frei bleibt: Gildenleitung schaltet unter Gildeneinstellungen → Discord-Einstellungen „Discord-Chat getrennt“ ein."])
        end
        return "guild"
    end
end

function Discord.CheckEcho(text)
    if not awaiting[text] then return end
    awaiting[text] = nil
    if echoed[text] then echoed[text] = nil; streamOk = true; wipe(missed); return end
    if streamOk then return end
    missed[#missed + 1] = text
    -- Erst nach zwei fehlenden Echos melden (eins kann Zufall sein). Nicht auf
    -- den Gildenchat ausweichen: Bei getrenntem Discord-Chat erreicht der
    -- Discord ohnehin nicht, das wäre nur Spam in /g.
    if #missed < 2 or streamBroken then return end
    streamBroken = true
    ns.Print(L["Deine Discord-Zeilen kommen im Spiel nicht zurück. Prüfe in Discord, ob sie ankommen. Details: /gp discord info"])
    wipe(missed)
end

local function NoteEcho(text)
    if type(text) ~= "string" or Secret(text) then return end
    if awaiting[text] then echoed[text] = true; streamOk = true end
end
local echoFrame = CreateFrame("Frame")
for _, ev in ipairs({ "CHAT_MSG_COMMUNITIES_CHANNEL", "CHAT_MSG_GUILD_DISCORD", "CHAT_MSG_GUILD" }) do
    pcall(echoFrame.RegisterEvent, echoFrame, ev)
end
echoFrame:SetScript("OnEvent", function(_, _, text) NoteEcho(text) end)

-- "Nicht verknüpft" erkennen: Blizzard antwortet auf eine Zeile von einem
-- unverknüpften Konto sofort mit einer Meldung, in der "Discord" vorkommt
local LINK_WINDOW = 3
function Discord.OnSystemText(text)
    if type(text) ~= "string" or Secret(text) then return end
    if not lastSent or GetTime() - lastSentAt > LINK_WINDOW or not Discord.IsLinked() then return end
    if not text:lower():find("discord", 1, true) then return end
    GuildPrideDB.discordLinked = false
    local line = lastSent
    lastSent = nil
    ns.Print(L["Blizzard meldet: Dein Discord ist nicht verknüpft. GuildPride gibt deine Discord-Zeilen ab jetzt über ein verknüpftes Mitglied weiter. Später verknüpft? /gp discord verknuepft"])
    -- Die eben gesendete Zeile über ein Mitglied nachholen
    ns.SendAddonMsg(PREFIX, "DRL:" .. line, "GUILD")
end
local sysFrame = CreateFrame("Frame")
for _, ev in ipairs({ "CHAT_MSG_SYSTEM", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE" }) do pcall(sysFrame.RegisterEvent, sysFrame, ev) end
sysFrame:SetScript("OnEvent", function(_, event, a, b)
    Discord.OnSystemText(event == "CHAT_MSG_SYSTEM" and a or b)
end)

-- Wartende Zeilen überleben das Ausloggen (höchstens 6 Std. alt)
local KEEP = 6 * 3600
local saveFrame = CreateFrame("Frame")
saveFrame:RegisterEvent("PLAYER_LOGOUT")
saveFrame:RegisterEvent("PLAYER_LOGIN")
saveFrame:SetScript("OnEvent", function(_, event)
    if not GuildPrideDB then return end
    local o = Opt()
    if event == "PLAYER_LOGOUT" then
        local now, keep = time(), {}
        for _, p in ipairs(o.pending or {}) do if now - (p.t or 0) < KEEP then keep[#keep + 1] = p end end
        for _, text in ipairs(queue) do keep[#keep + 1] = { t = now, text = text } end
        o.pending = #keep > 0 and keep or nil
    else
        local list = o.pending
        o.pending = nil
        if not list then return end
        local now = time()
        for _, p in ipairs(list) do
            if type(p) == "table" and type(p.text) == "string" and now - (p.t or 0) < KEEP and ns.IsBridgeLine(p.text) then
                Enqueue(p.text)
            end
        end
    end
end)
Discord.Pending = function() return queue end

-- Aus einer Spieleraktion heraus aufrufen (Klick, Tastendruck)
function Discord.Flush()
    if #queue == 0 or InCombatLockdown() then return end
    if not IsInGuild() then wipe(queue); wipe(notBefore); return end
    -- Bis zu drei Zeilen pro Aktion (lange DKP-Buchungen sind mehrteilig);
    -- zurückgehaltene Anmeldungen bleiben liegen, bis ihre Zeit um ist
    local now, sent, i = GetTime(), 0, 1
    while i <= #queue and sent < 3 do
        local item = queue[i]
        if (notBefore[item] or 0) > now then
            i = i + 1
        else
            table.remove(queue, i)
            notBefore[item] = nil
            -- Hat es inzwischen schon jemand anderes gesendet?
            if not Seen(item) then
                MarkSeen(item)
                SendNow(item)
                sent = sent + 1
            end
        end
    end
end

function Enqueue(text)
    text = text:sub(1, 255)
    for _, q in ipairs(queue) do if q == text then return end end
    -- Neue Anmeldung desselben Spielers zum selben Event ersetzt die wartende
    local key = SignKey(text)
    if key then
        for i = #queue, 1, -1 do
            if SignKey(queue[i]) == key then notBefore[queue[i]] = nil; table.remove(queue, i) end
        end
        notBefore[text] = GetTime() + SIGN_HOLD
    end
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
        -- Offiziers-Zeilen nimmt GameBot nur von einem Offizier an. Ein
        -- verknüpfter Offizier kann sie weitergeben – sicherer ist, selbst
        -- zu verknüpfen
        if OfficerLine(text) and not officerHinted then
            officerHinted = true
            ns.Print(L["Dein Discord ist nicht verknüpft: DKP, Ankündigungen und Umfragen kommen nur in Discord an, wenn gerade ein verknüpfter Offizier online ist. Verknüpfe Discord (Optionen > Soziales) und gib /gp discord verknuepft ein."])
        end
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
    -- Offiziers-Zeilen nur von Offizieren und nur durch Offiziere weitergeben:
    -- sonst könnte jeder über uns Buchungen fälschen, und GameBot würde
    -- Zeilen eines Nicht-Offiziers ohnehin ablehnen (unnötige Zeile im Chat)
    if OfficerLine(payload) and not (ns.IsOfficerName(sender) and ns.IsOfficerName(ns.Me())) then return end
    local text = payload:sub(1, 255)
    C_Timer.After(math.random() * 4, function()
        if not Seen(text) then Enqueue(text) end
    end)
end)

-- Jeder Tastendruck außerhalb des Kampfes darf eine wartende Zeile senden.
-- Die Taste selbst wird normal weitergereicht.
-- Tastatur nur abhören, solange Zeilen warten und kein Kampf ist (sonst blockiert
-- das Spiel im Kampf); die Prüfung läuft jede Sekunde und bei Kampfbeginn/-ende
ns.KeyAction(function() return #queue > 0 end, function() Discord.Flush() end)

---------------------------------------------------------------------
-- Zeilen im Chat ausblenden und als gesehen merken
---------------------------------------------------------------------
local AddFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
local signSeen = {}   -- Anmelde-Zeilen, die schon in Discord sind (10 Min.), gegen doppeltes Weiterleiten
local function Filter(_, _, text)
    if not ns.IsBridgeLine(text) then return false end
    NoteEcho(text)
    MarkSeen(text)
    if SignKey(text) then signSeen[text] = GetTime() end
    for i = #queue, 1, -1 do if queue[i] == text then notBefore[text] = nil; table.remove(queue, i) end end
    return not ShowRaw()
end
if AddFilter then
    for _, ev in ipairs({ "CHAT_MSG_GUILD", "CHAT_MSG_GUILD_DISCORD", "CHAT_MSG_COMMUNITIES_CHANNEL" }) do
        pcall(AddFilter, ev, Filter)
    end
end

function ns.HideBridgeLine(text)
    return ns.IsBridgeLine(text) and not ShowRaw()
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

-- Dungeon/Raid für den Bot: "[raid=ony]" vorn in der Beschreibung – er wählt danach
-- Vorlage und Gruppengröße. Ältere Bot-Versionen zeigen es nur als Text an.
function Discord.InstTag(e)
    local x = ns.Instances and ns.Instances.Find(e.kind, e.inst)
    return x and ("[%s=%s]"):format(x.kind, x.key) or ""
end

local function Tail(e)
    local parts = {}
    local tag = Discord.InstTag(e)
    if tag ~= "" then parts[#parts + 1] = tag end
    if e.desc and e.desc ~= "" then parts[#parts + 1] = Clean(e.desc, 80) end
    return #parts > 0 and (" – " .. table.concat(parts, " ")) or ""
end

function Discord.EventCreated(e)
    if not e or not e.title then return end
    local line = ((DE and "Neues Event" or "New event") .. " #%s: %s – %s (t=%d%s)"):format(Discord.ShortId(e.id), Clean(e.title, 40),
        When(e.t), e.t, (e.rep and e.rep > 0) and (DE and ", wöchentlich" or ", weekly") or "") .. Tail(e)
    Discord.Post(line, true)
end

function Discord.EventDeleted(e)
    if not e or not e.title then return end
    Discord.Post(((DE and "Event abgesagt" or "Event cancelled") .. " #%s: %s"):format(Discord.ShortId(e.id), Clean(e.title, 40)), true)
end

function Discord.SignedUp(e, s)
    if not e or not e.title or not s then return end
    local _, class = UnitClass("player")
    Discord.Post(Discord.SignLine(e, ns.Me(), s, class), true)
end

-- Anmeldung eines anderen zu MEINEM Event weitergeben: Bei vielen ist die
-- Discord-Anbindung aus (Standard), dann käme ihre Anmeldung nie in Discord an.
-- Der Ersteller wartet 30–40 s; hat der Anmelder die Zeile inzwischen selbst
-- gesendet (sie tauchte im Kanal auf), entfällt die Weitergabe. GameBot nimmt
-- weitergegebene Anmeldungen an, eine doppelte ändert dort nichts.
local RELAY_HOLD, SIGN_MEMORY = 30, 600
local function ClassOf(name)
    if not GetNumGuildMembers then return nil end
    local want = ns.Normalize and ns.Normalize(name) or name
    for i = 1, GetNumGuildMembers() do
        local n, _, _, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
        if n and (ns.Normalize and ns.Normalize(n) or n) == want then return classFile end
    end
end

function Discord.SignLine(e, name, s, class)
    local parts = {}
    if s.r and ROLE_TEXT[s.r] and s.s ~= "no" then parts[#parts + 1] = ROLE_TEXT[s.r] end
    if class then parts[#parts + 1] = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class end
    local extra = #parts > 0 and (" (" .. table.concat(parts, ", ") .. ")") or ""
    return ("%s: %s #%s %s%s"):format(Name(name), STATUS_TEXT[s.s] or s.s, Discord.ShortId(e.id), Clean(e.title, 40), extra)
end

function Discord.RelaySign(e, name, s)
    if not Enabled() or not e or not e.title or not s or not name or name == ns.Me() then return end
    local line = Discord.SignLine(e, name, s, ClassOf(name))
    local text = TAG .. " " .. Clean(line, 250)
    C_Timer.After(RELAY_HOLD + math.random() * 10, function()
        local t = signSeen[text]
        if t and GetTime() - t < SIGN_MEMORY then return end
        -- inzwischen anders entschieden? Dann nur den neuesten Stand weitergeben
        local cur = e.signups and e.signups[name]
        if cur and cur.s ~= s.s then return end
        Discord.Post(line)
    end)
end
Discord._SignSeen = signSeen   -- für Tests

function Discord.EventChanged(e)
    if not e or not e.title then return end
    local line = ((DE and "Event geändert" or "Event changed") .. " #%s: %s – %s (t=%d%s)"):format(Discord.ShortId(e.id), Clean(e.title, 40),
        When(e.t), e.t, (e.rep and e.rep > 0) and (DE and ", wöchentlich" or ", weekly") or "") .. Tail(e)
    Discord.Post(line, true)
end

-- Fehlersuche: zeigt jeden Schritt der Kanalwahl
function Discord.Info()
    local function say(k, v) ns.Print(("|cffffd100%s:|r %s"):format(k, tostring(v))) end
    say("Version", ns.VERSION)
    say("Anbindung an / verknüpft", tostring(Enabled()) .. " / " .. tostring(Discord.IsLinked()))
    say("Immer Gildenchat (Einstellung)", ViaGuild())
    say("C_GuildInfo.IsDiscordStreamSeparate", C_GuildInfo and C_GuildInfo.IsDiscordStreamSeparate and "vorhanden" or "FEHLT")
    if C_GuildInfo and C_GuildInfo.IsDiscordStreamSeparate then
        local ok, v = pcall(C_GuildInfo.IsDiscordStreamSeparate)
        say("  getrennt", ok and tostring(v) or ("Fehler: " .. tostring(v)))
    end
    say("Enum.ClubStreamType.Discord", Enum and Enum.ClubStreamType and Enum.ClubStreamType.Discord)
    local clubId = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    say("Gilden-Club", clubId)
    if clubId and C_Club.GetStreams then
        for _, st in ipairs(C_Club.GetStreams(clubId) or {}) do
            say("  Kanal", ("%s · Typ %s · %s"):format(tostring(st.streamId), Secret(st.streamType) and "geheim" or tostring(st.streamType), Secret(st.name) and "?" or tostring(st.name)))
        end
    end
    say("C_Club.SendMessage", C_Club and C_Club.SendMessage and "vorhanden" or "FEHLT")
    say("Gefundener Discord-Kanal", DiscordStream() and "ja" or "nein")
    say("Echo fehlte (Zeilen kamen nicht zurück)", streamBroken)
    say("Letzter Weg / letzter Fehler", tostring(lastRoute) .. " / " .. tostring(lastErr))
end

function Discord.Test()
    if not Enabled() then ns.Print(L["Die Discord-Anbindung ist aus (Einstellungen > Gilde)."]); return end
    Discord.Post(("%s: Test %s"):format(Name(ns.Me()), ns.VERSION or ""), true)
    ns.Print(Discord.IsLinked() and L["Discord-Test gesendet."] or L["Discord-Test an ein verknüpftes Mitglied gegeben."])
end

---------------------------------------------------------------------
-- Befehle: /gp discord [an|aus|verknuepft|test|roh|gilde|auto]
---------------------------------------------------------------------
local slash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd, rest = strtrim(arg or ""):lower():match("^(%S+)%s*(.*)$")
    if cmd ~= "discord" then return slash(arg) end
    Opt()
    if rest == "an" or rest == "on" then GuildPrideDB.discordBridge = true
    elseif rest == "aus" or rest == "off" then GuildPrideDB.discordBridge = false
    elseif rest == "verknuepft" or rest == "verknüpft" or rest == "linked" then GuildPrideDB.discordLinked = not Discord.IsLinked()
    elseif rest == "roh" or rest == "raw" then GuildPrideDB.discordShowRaw = not ShowRaw()
    elseif rest == "gilde" or rest == "guild" then GuildPrideDB.discordViaGuild = true
    elseif rest == "stream" or rest == "auto" then GuildPrideDB.discordViaGuild = false
    elseif rest == "test" then
        Discord.Test()
        return
    elseif rest == "info" then
        Discord.Info()
        return
    end
    local stream = DiscordStream() and L["eigener Discord-Kanal"] or L["Gildenchat"]
    ns.Print(("Discord: %s · %s: %s · %s: %s · %s · %s: %d"):format(
        Enabled() and L["an"] or L["aus"],
        L["verknüpft"], Discord.IsLinked() and L["ja"] or L["nein"],
        L["Weg"], ViaGuild() and L["Gildenchat"] or stream,
        ShowRaw() and L["Zeilen sichtbar"] or L["Zeilen ausgeblendet"],
        L["wartend"], #queue))
end
