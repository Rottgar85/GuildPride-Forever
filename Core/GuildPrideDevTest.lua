-- GuildPride: Testliste des Entwicklers (Entwicklerfenster › „Testliste“) – nur für ihn, ohne Übersetzung
-- Links: offen → geht → geht nicht → offen. Rechts: Notiz. Was geht, bleibt abgehakt; steht bei
-- einem Punkt eine neuere Fassung (v), zählt ein älterer Haken nicht mehr.
-- Gespeichert: GuildPrideDB.devTests = { [id] = { s = "ok"/"bad", v = Version, t = Zeit, note = Text } }
local ADDON, ns = ...

local T = {}
ns.DevTest = T

-- { Kennung, Bereich, was zu tun ist und was passieren soll, geändert in }
T.ITEMS = {
    { "start", "Grundlagen", "Einloggen und /reload: kein roter Fehler", "2.43.1" },
    { "chat", "Grundlagen", "Gilde, Flüstern, Gruppe schreiben: kommt an, auch im Kampf", "2.38.0" },
    { "keys", "Grundlagen", "Tastatur: laufen, Zauber, Enter gehen immer, auch bei offenen Fenstern", "2.38.0" },
    { "suche", "Grundlagen", "/gp suche und Lupe oben: findet Mitglied, Einstellung, Befehl; Klick öffnet", "2.43.0" },
    { "hilfe", "Grundlagen", "/gp hilfe: Liste, ein Klick führt den Befehl aus", "2.43.0" },
    { "einst", "Grundlagen", "Einstellungen: kurz; „… weitere“ klappt den Abschnitt auf, „Alle zeigen“ alles, Sprungleiste und Suche stimmen", "2.43.1" },
    { "paket", "Grundlagen", "/gp paket raid und /gp paket all: Schalter ändern sich, Spiel läuft weiter", "2.42.0" },
    { "neuling", "Grundlagen", "Ganz neue Installation: Einführung, danach kein Buff-Food- und kein Schlafsack-Fenster", "2.43.1" },
    { "farben", "Grundlagen", "Farben für Farbenblinde an: Listen in den Reitern gut lesbar", "2.43.0" },
    { "bereit", "Raid", "Bereitschaftscheck starten: Fenster geht auf, Probleme stehen oben", "2.43.0" },
    { "boss", "Raid", "/gp boss: Notiz mit mehreren Zeilen, geht beim Betreten der Instanz auf", "2.43.0" },
    { "loot", "Raid", "Seltenes in der Gruppe looten: steht in /gp loot, auch beim zweiten Offizier", "2.43.0" },
    { "cd", "Raid", "/gp abklingzeiten: Wiedergeburt eines Mitglieds läuft herunter", "2.43.0" },
    { "event", "Raid", "Event läuft: 10 Minuten danach steht die Anwesenheit, Nachzügler kommen dazu", "2.43.0" },
    { "quests", "Gilde", "/gp quests: Mitglied mit gleicher Quest erscheint, Klick lädt ein", "2.42.0" },
    { "material", "Gilde", "/gp material: Ziel über den Namen anlegen, Zusage eintragen, zweiter Spieler sieht es", "2.43.0" },
    { "paten", "Gilde", "/gp paten: Pate werden; neues Mitglied online meldet sich beim Paten", "2.43.0" },
    { "quiz", "Gilde", "/gp quiz: Frage stellen, schnellste richtige Antwort zählt, Rangliste stimmt", "2.43.0" },
    { "jagd", "Gilde", "/gp jagd: Station anlegen, zweiter Spieler findet sie", "2.43.0" },
    { "album", "Gilde", "Bosskill in der Gruppe: steht in /gp album", "2.42.0" },
    { "kacheln", "Gilde", "Planen › Werkzeuge: Kacheln, Rechtsklick blendet aus und wieder ein", "2.43.0" },
    { "block", "Gilde", "/gp block Testname Grund: rotes X, Einladen wird abgelehnt, /gp unblock entfernt", "2.36.0" },
    { "frage", "Gilde", "Twink: /gp willkommen › Frage senden; Offizier sieht sie und antwortet", "2.40.0" },
    { "links", "Gilde", "Verwaltung › Links der Gilde speichern; Knöpfe in /gp willkommen zeigen sie", "2.40.0" },
    { "msg", "Nachrichten", "/gp nachrichten: senden, zugestellt, an Offline-Spieler später zugestellt", "2.39.0" },
    { "flustern", "Nachrichten", "Angeflüstert werden: Fenster geht auf, Antwort kommt als normales Flüstern an", "2.40.0" },
    { "handwerk", "Handwerk", "Reiter Handwerk: Klick auf Beruf eines Mitglieds; geht es nicht auf, klappen seine Rezepte auf", "2.43.1" },
    { "luecken", "Handwerk", "/gp luecken: Symbole wählen den Beruf, Liste füllt sich in wenigen Sekunden, Tooltip stimmt", "2.43.1" },
    { "berufslink", "Handwerk", "Berufs-Link vom eigenen Heimatserver: Blizzards Fenster geht auf", "2.43.1" },
    { "berater", "Auktionshaus", "Item-Tooltip: BEHALTEN, HÄNDLER oder AUKTIONSHAUS, darunter Preise und Unterschied", "2.43.1" },
    { "tipblock", "Auktionshaus", "Item-Tooltip: ein Block GuildPride, Umschalt zeigt mehr Zeilen, Preis vom Server kommt nach", "2.43.1" },
    { "marken", "Auktionshaus", "Farbmarken in den Taschen einschalten: Farbe passt zur Empfehlung im Tooltip", "2.43.1" },
    { "kanal", "Nachrichten", "/gp spieler: andere Spieler erscheinen, auch nach langem Spielen ohne Ausloggen", "2.43.1" },
    { "tracker", "Handwerk", "/gp tracker: Rezept tracken, herstellen, Zähler geht herunter", "2.41.0" },
    { "angeln", "Handwerk", "Angeln mit einer Taste: auswerfen, einholen, Fang wird gezählt", "2.41.0" },
    { "ahpreis", "Auktionshaus", "Tooltip: Preis, Melder, Verlauf wie vor dem Update (neue Speicherform)", "2.43.1" },
    { "ahscan", "Auktionshaus", "Auktionshaus öffnen, suchen, verkaufen; nach /reload sind die Preise noch da", "2.43.1" },
    { "ahliste", "Auktionshaus", "Einkaufsliste: kaufen zieht die Menge ab", "2.38.0" },
    { "post", "Auktionshaus", "Briefkasten öffnen: Zeile mit verkauft und abgelaufen", "2.39.0" },
    { "gruppe", "Unterwegs", "Gruppensuche: anmelden, Browser durchsuchen, Filter", "2.43.1" },
    { "karte", "Unterwegs", "Karte und Minimap: Gildenmitglieder und Zettel in der Nähe", "2.41.0" },
    { "schiff", "Unterwegs", "Anleger und Tiefenbahn: Zeiten und Erinnerung", "2.39.0" },
    { "rares", "Unterwegs", "/gp rares: Rare gesehen, Meldung kommt beim zweiten Spieler an", "2.41.0" },
    { "fehler", "Entwickler", "Mit Haupt einloggen: Fehler und Nutzung von Spielern kommen an", "2.43.0" },
}

local function DB()
    if type(GuildPrideDB) ~= "table" then return {} end
    if type(GuildPrideDB.devTests) ~= "table" then GuildPrideDB.devTests = {} end
    return GuildPrideDB.devTests
end

-- "2.43.1" → vergleichbare Zahl
local function Value(v)
    local a, b, c = tostring(v or ""):match("^(%d+)%.(%d+)%.(%d+)")
    return a and (a * 1000000 + b * 1000 + c) or 0
end

-- Stand eines Punkts: "ok", "bad" oder nil; ein Haken zählt nur für die Fassung, ab der der Punkt gilt
function T.State(item)
    local e = DB()[item[1]]
    if type(e) ~= "table" then return nil end
    if e.s == "ok" and Value(e.v) < Value(item[4]) then return nil, e end
    return e.s, e
end

function T.Click(id)
    for _, item in ipairs(T.ITEMS) do
        if item[1] == id then
            local s, e = T.State(item)
            local to
            if s == nil then to = "ok" elseif s == "ok" then to = "bad" end
            local note = e and e.note
            DB()[id] = (to or note) and { s = to, v = Value(item[4]) > Value(ns.VERSION) and item[4] or ns.VERSION,
                t = GetServerTime(), note = note } or nil   -- getestet wird oft schon die kommende Fassung
            return to
        end
    end
end

function T.Note(id, text)
    text = strtrim(text or ""):sub(1, 200)
    local e = DB()[id] or { v = ns.VERSION, t = GetServerTime() }
    e.note = text ~= "" and text or nil
    DB()[id] = (e.s or e.note) and e or nil
end

-- offen, geht, geht nicht
function T.Counts()
    local open, ok, bad = 0, 0, 0
    for _, item in ipairs(T.ITEMS) do
        local s = T.State(item)
        if s == "ok" then ok = ok + 1 elseif s == "bad" then bad = bad + 1 else open = open + 1 end
    end
    return open, ok, bad
end

-- Zeilen { text, id }: was nicht geht zuerst, dann offen, dann erledigt
local PARTS = { { "bad", "|cffff6060Geht nicht|r" }, { nil, "|cffffd100Offen|r" }, { "ok", "|cff40ff40Geht|r" } }
function T.Lines(hideDone)
    local out = {}
    for i = 1, #PARTS do
        local want, title = PARTS[i][1], PARTS[i][2]
        if want ~= "ok" or not hideDone then
            local head = false
            for _, item in ipairs(T.ITEMS) do
                local s, e = T.State(item)
                if s == want then
                    if not head then out[#out + 1] = { text = title }; head = true end
                    out[#out + 1] = { id = item[1], text = ("   |cff999999%s|r  %s%s"):format(item[2], item[3], e and e.note and ("  |cff8cc8ff(" .. e.note .. ")|r") or "") }
                end
            end
        end
    end
    return out
end

-- Bericht zum Kopieren: was nicht geht und alle Notizen
function T.Text()
    local open, ok, bad = T.Counts()
    local out = { ("GuildPride %s: %d gehen, %d gehen nicht, %d offen"):format(tostring(ns.VERSION), ok, bad, open) }
    for _, item in ipairs(T.ITEMS) do
        local s, e = T.State(item)
        if s == "bad" or (e and e.note) then
            out[#out + 1] = ("[%s] %s: %s%s"):format(s == "bad" and "geht nicht" or (s == "ok" and "geht" or "offen"), item[2], item[3], e.note and (" – " .. e.note) or "")
        end
    end
    return table.concat(out, "\n")
end

---------------------------------------------------------------------
-- Messung des Addon-Versands (nur beim Entwickler, nur lokal): GuildPrideDB.netState beim Ausloggen
---------------------------------------------------------------------
local net = { sent = {}, got = {}, own = {}, kinds = {} }
T.net = net
function ns.NetSent(channel, res)
    local k = tostring(channel) .. ":" .. tostring(res)
    net.sent[k] = (net.sent[k] or 0) + 1
end
function T.NetState()
    local function Try(f, ...) if not f then return nil end local ok, v = pcall(f, ...) if ok then return v end return "Fehler: " .. tostring(v) end
    local s = { t = GetServerTime(), up = math.floor(GetTime() - (net.start or GetTime())), sent = net.sent, got = net.got, own = net.own, kinds = net.kinds,
        publicId = Try(ns.PublicChannelId) or 0, dataId = Try(ns.DataChannelId) or 0, queue = Try(ns.QueueLength) or 0,
        lockdown = tostring(Try(C_ChatInfo.InChatMessagingLockdown)), lfg = tostring(Try(ns.PublicLFGOn)), viaChat = tostring(ns.PUBLIC_VIA_CHAT),
        prefix = tostring(Try(C_ChatInfo.IsAddonMessagePrefixRegistered, "GuildPride")), guild = tostring(IsInGuild()), me = tostring(ns.Me()) }
    local v, p = 0, 0
    for _ in pairs(ns.Versions or {}) do v = v + 1 end
    for _ in pairs(ns.Players and ns.Players.public or {}) do p = p + 1 end
    s.versions, s.players = v, p
    s.watch = ns.ChannelWatch and ns.ChannelWatch.stats
    local list = { pcall(GetChannelList) }
    s.channels = {}
    for i = 2, #list do s.channels[#s.channels + 1] = tostring(list[i]) end
    local online = 0
    for i = 1, GetNumGuildMembers() or 0 do if select(9, GetGuildRosterInfo(i)) then online = online + 1 end end
    s.online = online
    return s
end
local nev = CreateFrame("Frame")
ns.RegisterEvents(nev, "PLAYER_LOGIN", "CHAT_MSG_ADDON", "PLAYER_LOGOUT")
nev:SetScript("OnEvent", function(_, event, prefix, msg, channel, sender)
    if event == "PLAYER_LOGIN" then net.start = GetTime() return end
    if event == "PLAYER_LOGOUT" then
        if ns.IsDev and ns.IsDev() and type(GuildPrideDB) == "table" then GuildPrideDB.netState = T.NetState() end
        return
    end
    if issecretvalue and (issecretvalue(prefix) or issecretvalue(channel) or issecretvalue(sender) or issecretvalue(msg)) then
        net.got.secret = (net.got.secret or 0) + 1
        return
    end
    if type(prefix) ~= "string" or not (prefix:find("^Guild") or prefix:find("^GP")) or type(sender) ~= "string" then return end
    local to = ns.Normalize(sender) == ns.Me() and net.own or net.got
    local k = prefix .. ":" .. tostring(channel)
    to[k] = (to[k] or 0) + 1
    if to == net.got and type(msg) == "string" then
        local kind = msg:match("^(%u%w+):") or "?"
        net.kinds[kind] = (net.kinds[kind] or 0) + 1
    end
end)

---------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------
StaticPopupDialogs["GUILDPRIDE_DEV_NOTE"] = {
    text = "Notiz zum Testpunkt (leer = löschen):",
    button1 = OKAY or "OK", button2 = CANCEL,
    hasEditBox = true, editBoxWidth = 300, maxLetters = 200,
    OnShow = function(self, data)
        local eb = self.editBox or self.EditBox
        local e = DB()[data]
        eb:SetText(e and e.note or ""); eb:SetFocus()
    end,
    OnAccept = function(self, data) T.Note(data, (self.editBox or self.EditBox):GetText()); T.Refresh() end,
    EditBoxOnEnterPressed = function(eb)
        local p = eb:GetParent()
        T.Note(p.data, eb:GetText()); p:Hide(); T.Refresh()
    end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local win
local hideDone = true
function T.Refresh()
    if not win or not win:IsShown() then return end
    win.list = T.Lines(hideDone)
    local lines = {}
    for i, l in ipairs(win.list) do lines[i] = l.text end
    local open, ok, bad = T.Counts()
    win.title:SetText(("Testliste: %d offen · %d gehen · %d gehen nicht"):format(open, ok, bad))
    win.toggle:SetText(hideDone and "Erledigte zeigen" or "Erledigte ausblenden")
    win:SetLines(lines)
end

function T.Open()
    if not (ns.IsDev and ns.IsDev()) then return end
    if not win then
        win = ns.ListWindow({ name = "GuildPrideDevTest", title = "Testliste", rows = 20, width = 760,
            sub = "Links: offen › geht › geht nicht. Rechts: Notiz. Mausrad blättert." })
        for i, row in ipairs(win.rows) do
            row:EnableMouse(true)
            row:SetScript("OnMouseUp", function(_, button)
                local l = win.list and win.list[i + win.offset]
                if not (l and l.id) then return end
                if button == "RightButton" then StaticPopup_Show("GUILDPRIDE_DEV_NOTE", nil, nil, l.id)
                else T.Click(l.id); T.Refresh() end
            end)
        end
        local function Button(label, x, fn)
            local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
            if ns.SkinButton then ns.SkinButton(b) end
            b:SetSize(160, 22); b:SetPoint("TOPLEFT", x, win.bottomY); b:SetText(label)
            b:SetScript("OnClick", fn)
            return b
        end
        Button("Bericht kopieren", 14, function() if ns.ShowCopy then ns.ShowCopy("GuildPride-Testliste", T.Text()) end end)
        win.toggle = Button("Erledigte zeigen", 184, function() hideDone = not hideDone; win.offset = 0; T.Refresh() end)
        win:SetScript("OnShow", function() win.offset = 0; T.Refresh() end)
    end
    win:SetShown(not win:IsShown())
end
