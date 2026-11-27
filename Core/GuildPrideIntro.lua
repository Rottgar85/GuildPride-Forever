-- GuildPride: kurze Einführung beim ersten Start (wieder öffnen mit /gp intro)
-- Die letzte Seite fragt nach der Discord-Anbindung (GuildPrideDiscord.lua).
local ADDON, ns = ...
local L = ns.L
local INTRO_VERSION = 7   -- 3: Einrichtung (welches Gildenfenster, Aussehen), 4: Messenger bis Fehler melden, 5: Werkzeuge,
                          -- 6: Buff-Food-Neuerungen, 7: Stufen-Frage (Light, Medium, Max) für alle
ns.INTRO_VERSION = INTRO_VERSION
-- Soll die Tour beim Einloggen kommen? Neue Spieler immer, alle anderen einmal für die Neuerungen
function ns.IntroDue(seen)
    return (seen or 0) < INTRO_VERSION
end

-- Seiten mit "since" sind Neuerungen: Wer die Tour schon kennt, sieht nur diese
local ALL_PAGES = {
    { title = L["Willkommen bei GuildPride!"],
      text = L["GuildPride ist der Treffpunkt deiner Gilde: Gildenfenster, Chat, Events, Gruppensuche, Raid-Werkzeuge, Handwerk, DKP und Discord-Anbindung an einem Ort.\n\nDiese kurze Tour zeigt dir das Wichtigste. Du kannst sie jederzeit mit /gp intro wieder öffnen."] },
    { setup = true, since = 3, title = L["Einrichtung: dein Gildenfenster"],
      text = L["GuildPride bringt ein eigenes Gildenfenster mit: Chat, Events, Gruppensuche, Berufe, DKP und mehr.\n\nWas soll die Taste J öffnen? Erreichbar bleiben beide: GuildPride über den Minimap-Knopf oder /gp, Blizzards Fenster über die Einstellungen.\n\nDu kannst das jederzeit wieder ändern: Einstellungen > „Einrichtung …“."] },
    { preset = true, since = 7, title = L["Wie möchtest du GuildPride nutzen?"],
      text = L["Such dir eine Stufe aus. Was nicht dazugehört, ist aus und verschwindet auch aus den Menüs.\n\n• Light: nur Gilde – Gildenfenster, Chat, Events, Raid-Werkzeuge, Messenger\n• Medium: dazu alles für unterwegs allein – Handwerk, Buffs, Leveln, Reisen, Zettel, Rares, Item-Vergleich\n• Max: alles, dazu Auktionshaus und Verkaufs-Berater\n\nÄndern jederzeit mit /gp stufe."] },
    { title = L["Das Gildenfenster"],
      text = L["Drücke J (oder /gp), um das Gildenfenster zu öffnen.\n\n• Übersicht: wer online ist, nächstes Event, Neuigkeiten der Woche\n• Gilde & Chat: Gilden-, Offiziers- und Community-Chat mit Mitgliederliste\n• Gruppensuche: Hilfe für Quests und Dungeons finden\n• Umfragen, Meilensteine und Gildeninfo\n\nMit /gp blizzard kommst du zurück zum Blizzard-Fenster."] },
    { title = L["Events und Raids"],
      text = L["Im Reiter Events legen Offiziere Termine an, auf Wunsch jede Woche.\n\nAlle Mitglieder melden sich mit Zusagen, Vielleicht oder Absagen und ihrer Rolle an. 15 Minuten vor Beginn gibt es eine Erinnerung, und Offiziere können alle Zusagen mit einem Klick einladen."] },
    { title = L["DKP"],
      text = L["Mit /gp dkp öffnest du die Punkte-Rangliste.\n\nOffiziere vergeben dort mit einem Klick Punkte an den ganzen Raid (Anwesenheit, Bosskills), ziehen Loot ab und können eine Buchung zurücknehmen.\n\nFahre mit der Maus über einen Spieler: Im Tooltip steht sein DKP-Stand."] },
    { discord = true, title = L["Discord-Anbindung"],
      text = L["GuildPride kann Events, Anmeldungen, DKP und Meilensteine über Blizzards Discord-Verknüpfung an den Discord deiner Gilde schicken. Dort trägt der Bot GameBot alles ein.\n\nDafür muss die Gildenleitung die Gilde mit einem Discord-Kanal verknüpfen und GameBot einladen (gamerbot.duckdns.org). Beides kannst du später jederzeit in den GuildPride-Einstellungen ändern."] },
    { since = 2, title = L["Neu: schlankeres Menü"],
      text = L["Das Gildenfenster hat ein schlankeres Menü:\n\n• Übersicht – oben umschalten zu Meilensteine\n• Planen – Events, Wünsche, Umfragen, offene Dungeons und Werkzeuge\n• Handwerk – Berufe der Gilde und deine Leveling-Guides\n• Gruppensuche, Gilde & Chat, Gildeninfo, Einstellungen wie gewohnt\n\nDie Einstellungen sind in Abschnitte geteilt und haben oben eine Suche. Lieber das alte Menü? Einstellungen > Allgemein > „Kompaktes Menü“ ausschalten."] },
    { since = 2, title = L["Neu: Twinks automatisch erkennen"],
      text = L["Alle Charaktere eines Spielers erscheinen jetzt als eine Zeile in der Mitgliederliste, Twinks klappst du mit „+3“ auf.\n\nDein BattleTag bleibt dabei privat: Er verlässt nie deinen PC, die Gilde sieht nur einen daraus berechneten Code.\n\nRechtsklick auf einen eigenen Charakter: „Als Main festlegen“."] },
    { since = 2, title = L["Neu: Sicherung und Protokoll"],
      text = L["Einstellungen > „Datensicherung …“ sichert alle GuildPride-Daten mit einem Klick (und einmal pro Woche automatisch).\n\nIm DKP-Fenster zeigt „Protokoll …“ jede Buchung mit Wer, Wann und Warum.\n\nFalls einmal etwas schiefgeht: /gp fehler zeigt einen Fehlerbericht zum Kopieren."] },
    { since = 4, title = L["Neu: Messenger und Notizzettel"],
      text = L["• Messenger: Nachrichten an Gildenmitglieder mit GuildPride, auch wenn sie offline sind. Flüstern landet auf Wunsch im selben Fenster.\n\n• Notizzettel: /gp zettel schreiben hängt einen Zettel genau dort auf, wo du stehst – blau für die Gilde, weiß für alle. Kommt jemand vorbei, geht er auf.\n\nAlles einzeln abschaltbar in den Einstellungen."] },
    { since = 4, title = L["Neu: Auktionshaus und Handwerk"],
      text = L["• Auktionshaus: Preise im Tooltip, Einkaufslisten, Preisalarm und Aufträge der Gilde. Das eigene Fenster öffnest du im Auktionshaus mit „GuildPride“.\n\n• Handwerk: Weg von 1 bis 300 für jeden Beruf, Tracker für Zutaten, Lehrer auf der Karte, Angeln mit einer Taste (/gp handwerk)."] },
    { since = 4, title = L["Neu: Reisen, Buffs und Fehler melden"],
      text = L["• Reisen: Abfahrten von Schiffen, Zeppelinen und der Tiefenbahn, Flugzeiten am Flugmeister.\n\n• Buffs: Erinnerung an Buff-Food, Schlafsack und Lagerfeuer – ein Klick benutzt es.\n\n• Fehler: Hat GuildPride einen Fehler, wirst du einmal gefragt, ob er automatisch an den Entwickler gehen darf. Ohne dein Ja wird nichts gesendet."] },
    { since = 5, title = L["Neu: Werkzeuge, Suche und Pakete"],
      text = L["• Werkzeuge (unter „Planen“): Raid-Bereitschaft, Quests der Gilde, Boss-Notizen, Materialliste, Loot-Verlauf, Paten, Quiz und mehr.\n\n• Suche über alles: die Lupe oben im Gildenfenster oder /gp suche.\n\n• Pakete: /gp paket gilde, raid oder alles schaltet nur an, was du brauchst.\n\n• Besser lesbar: größere Schrift und Farben für Farbenblinde unter Einstellungen > Allgemein."] },
    { since = 6, title = L["Neu: Buff-Food-Erinnerung"],
      text = L["• Vorwarnung: 2 Minuten bevor „Satt“ ausläuft, kommt das Fenster schon.\n\n• Kein Essen dabei? Es zeigt, was du kochen kannst und welche deiner Twinks Buff-Food haben.\n\n• Beim Bereitschaftscheck erinnert es, wenn „Satt“ fehlt oder bald ausläuft.\n\n• Auf Wunsch nur in Instanzen und Gruppen (Zahnrad am Buff-Fenster)."] },
    { consent = true, since = 5, title = L["Hilfst du mit, GuildPride zu verbessern?"],
      text = L["Beides ist freiwillig und lässt sich jederzeit ändern (Einstellungen › Teilen). Ohne Haken wird nichts gesendet.\n\n• Fehler: Fehlertext (kann selten einen Spielernamen enthalten), Stelle im Code, Versionen, Sprache, Umstände (Kampf, Instanzart, offene GuildPride-Fenster).\n\n• Nutzung: nur Zähler, welche Reiter, GuildPride-Fenster und /gp-Befehle du öffnest und welche Schalter du geändert hast. Höchstens einmal am Tag.\n\nNie Chat, Gold oder Notizen. Der Entwickler speichert statt deines Namens nur einen Zählcode."] },
}
local PAGES = ALL_PAGES

local win, page = nil, 1

local hadDiscord = false
-- Seite „Mithelfen“: nur zeigen, wenn noch etwas offen ist; nie dem Entwickler
local sawConsent = false
local function NeedsConsent()
    if ns.IsDev and ns.IsDev() then return false end
    return GuildPrideDB.errorShare == nil or GuildPrideDB.usageShare == nil
end
local function Close()
    GuildPrideDB.introSeen = INTRO_VERSION
    -- gesehen und kein Haken gesetzt heißt Nein (dann fragt nichts mehr nach)
    if sawConsent then
        if GuildPrideDB.errorShare == nil then GuildPrideDB.errorShare = false end
        if GuildPrideDB.usageShare == nil then GuildPrideDB.usageShare = false end
    end
    -- Wer die Tour schließt, ohne zu wählen, hat die Anbindung aus
    if hadDiscord and GuildPrideDB.discordBridge == nil then GuildPrideDB.discordBridge = false end
    win:Hide()
end

local function Show(i)
    page = i
    local p = PAGES[i]
    win.title:SetText(p.title)
    win.text:SetText(p.text)
    win.step:SetText(("%d / %d"):format(i, #PAGES))
    win.back:SetShown(i > 1)
    win.next:SetText(i < #PAGES and L["Weiter"] or L["Fertig"])
    win.discord:SetShown(p.discord == true)
    win.setup:SetShown(p.setup == true)
    win.preset:SetShown(p.preset == true)
    win.consent:SetShown(p.consent == true)
    if p.consent then
        sawConsent = true
        win.errCb:SetChecked(GuildPrideDB.errorShare == true); win.useCb2:SetChecked(GuildPrideDB.usageShare == true)
    end
    if p.preset then win.PresetRefresh() end
    if p.setup then win.SetupRefresh() end
    if p.discord then
        win.useCb:SetChecked(GuildPrideDB.discordBridge == true)
        win.linkCb:SetChecked(GuildPrideDB.discordLinked == true)
        win.linkCb:SetEnabled(GuildPrideDB.discordBridge == true)
    end
end

local function Check(parent, y, label, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 0, y)
    local t = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    t:SetWidth(360); t:SetJustifyH("LEFT")
    t:SetText(label)
    cb:SetScript("OnClick", onClick)
    return cb
end

local function Build()
    win = CreateFrame("Frame", "GuildPrideIntroFrame", UIParent, "BasicFrameTemplateWithInset")
    win:SetSize(440, 420)   -- Platz für die Seite „Mithelfen“ mit zwei Haken
    win:SetPoint("CENTER", 0, 60)
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true); win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    if win.CloseButton then win.CloseButton:SetScript("OnClick", Close) end

    local head = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    head:SetPoint("TOP", 0, -5); head:SetText("GuildPride")

    win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    win.title:SetPoint("TOPLEFT", 20, -38)
    win.text = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    win.text:SetPoint("TOPLEFT", 20, -66)
    win.text:SetWidth(400); win.text:SetJustifyH("LEFT"); win.text:SetJustifyV("TOP")
    win.text:SetSpacing(2)

    win.discord = CreateFrame("Frame", nil, win)
    win.discord:SetPoint("BOTTOMLEFT", 20, 46); win.discord:SetSize(400, 64)
    win.useCb = Check(win.discord, 0, L["Discord-Anbindung nutzen"], function(self)
        GuildPrideDB.discordBridge = self:GetChecked() and true or false
        win.linkCb:SetEnabled(GuildPrideDB.discordBridge)
    end)
    win.linkCb = Check(win.discord, -30, L["Mein Discord ist mit WoW verknüpft (Optionen > Soziales > Discord)"], function(self)
        GuildPrideDB.discordLinked = self:GetChecked() and true or false
    end)

    ---------------------------------------------------------------------
    -- Einrichtung: welches Gildenfenster und welches Aussehen
    ---------------------------------------------------------------------
    win.setup = CreateFrame("Frame", nil, win)
    win.setup:SetPoint("BOTTOMLEFT", 20, 42); win.setup:SetSize(400, 104)
    local function SetWindow(own)
        GuildPrideDB.replaceGuildFrame = own and true or false
        if ns.GuildWindowChoiceChanged then ns.GuildWindowChoiceChanged() end
        win.SetupRefresh()
    end
    win.ownCb = Check(win.setup, 0, L["GuildPride-Fenster öffnen (empfohlen)"], function() SetWindow(true) end)
    win.blizzCb = Check(win.setup, -26, L["Blizzards Gildenfenster behalten"], function() SetWindow(false) end)

    local lookLabel = win.setup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lookLabel:SetPoint("TOPLEFT", 4, -58)
    local lookBtns = {}
    for i, l in ipairs(ns.LayoutList or {}) do
        local b = CreateFrame("Button", nil, win.setup, "UIPanelButtonTemplate")
        b:SetSize(118, 24); b:SetPoint("TOPLEFT", 4 + (i - 1) * 124, -76)
        b:SetText(l.name); b.key = l.key
        b:SetScript("OnClick", function()
            if ns.ApplyLayout then ns.ApplyLayout(l.key) end
            win.SetupRefresh()
        end)
        lookBtns[i] = b
    end
    lookLabel:SetShown(#lookBtns > 0)

    function win.SetupRefresh()
        local own = GuildPrideDB.replaceGuildFrame ~= false
        win.ownCb:SetChecked(own)
        win.blizzCb:SetChecked(not own)
        local cur = GuildPrideDB.layout or "book"
        local curName = cur
        for _, l in ipairs(ns.LayoutList or {}) do if l.key == cur then curName = l.name end end
        lookLabel:SetText((L["Aussehen: %s"]):format(curName))
        for _, b in ipairs(lookBtns) do
            b:SetEnabled(b.key ~= cur)
            if b.gpBg then b.gpBg:SetTexture(ns.MEDIA .. (b.key == cur and "nav_active" or "nav")) end
        end
    end

    -- Mithelfen: zwei Haken, ab Werk aus
    win.consent = CreateFrame("Frame", nil, win)
    win.consent:SetPoint("BOTTOMLEFT", 20, 38); win.consent:SetSize(400, 56)
    win.errCb = Check(win.consent, 0, L["GuildPride-Fehler automatisch senden"], function(self) GuildPrideDB.errorShare = self:GetChecked() and true or false end)
    win.useCb2 = Check(win.consent, -26, L["Mitteilen, welche Funktionen ich benutze"], function(self)
        GuildPrideDB.usageShare = self:GetChecked() and true or false
        if ns.Usage then ns.Usage.Changed() end
    end)

    -- Pakete: welche Funktionen an sein sollen (GuildPrideSearch.lua)
    win.preset = CreateFrame("Frame", nil, win)
    win.preset:SetPoint("BOTTOMLEFT", 20, 46); win.preset:SetSize(400, 28)
    local presetBtns = {}
    for i, o in ipairs({ { "light", "Light" }, { "medium", "Medium" }, { "max", "Max" } }) do
        local b = CreateFrame("Button", nil, win.preset, "UIPanelButtonTemplate")
        b:SetSize(126, 24); b:SetPoint("LEFT", (i - 1) * 134, 0); b:SetText(o[2])
        b:SetScript("OnClick", function()
            if ns.ApplyPreset then ns.ApplyPreset(o[1]) end
            win.PresetRefresh()
        end)
        presetBtns[i] = { b = b, key = o[1] }
    end
    function win.PresetRefresh()
        local cur = ns.TierChosen and ns.TierChosen() and ns.Tier() or nil
        for _, p in ipairs(presetBtns) do p.b:SetEnabled(p.key ~= cur) end
    end

    win.step = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.step:SetPoint("BOTTOM", 0, 16)
    win.back = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.back:SetSize(100, 24); win.back:SetPoint("BOTTOMLEFT", 16, 10)
    win.back:SetText(L["Zurück"])
    win.back:SetScript("OnClick", function() Show(page - 1) end)
    win.next = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.next:SetSize(100, 24); win.next:SetPoint("BOTTOMRIGHT", -16, 10)
    win.next:SetScript("OnClick", function() if page < #PAGES then Show(page + 1) else Close() end end)

    if ns.SkinWindow then ns.Try(ns.SkinWindow, win) end
end

-- Seiten der Tour: alle, oder nur die Neuerungen seit Tour-Stand seen
function ns.IntroPages(onlyNew, seen)
    if seen >= INTRO_VERSION then seen = INTRO_VERSION - 1 end   -- /gp neu: letzte Neuerungen
    local out = {}
    for _, p in ipairs(ALL_PAGES) do
        if (not onlyNew or (p.since or 1) > seen) and (not p.consent or NeedsConsent()) then out[#out + 1] = p end
    end
    if #out == 0 then out = ALL_PAGES end
    return out
end

-- onlyNew: nur die Neuerungen seit der zuletzt gesehenen Tour
function ns.ShowIntro(onlyNew)
    if not win then Build() end
    PAGES = ns.IntroPages(onlyNew, GuildPrideDB and GuildPrideDB.introSeen or 0)
    hadDiscord, sawConsent = false, false
    for _, p in ipairs(PAGES) do if p.discord then hadDiscord = true end end
    win:Show()
    Show(1)
end

-- Nur die Stufen-Frage (/gp stufe, Einstellungen)
function ns.ShowTierChoice()
    if not win then Build() end
    PAGES, hadDiscord, sawConsent = {}, false, false
    for _, p in ipairs(ALL_PAGES) do if p.preset then PAGES[#PAGES + 1] = p end end
    win:Show()
    Show(1)
end

-- Nur die Einrichtung (Einstellungen > „Einrichtung …“, /gp einrichtung)
function ns.ShowSetup()
    if not win then Build() end
    PAGES, hadDiscord = {}, false
    for _, p in ipairs(ALL_PAGES) do if p.setup then PAGES[#PAGES + 1] = p end end
    if #PAGES == 0 then return ns.ShowIntro() end
    win:Show()
    Show(1)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    C_Timer.After(8, function()
        if GuildPrideDB and ns.IntroDue(GuildPrideDB.introSeen) and not InCombatLockdown() then
            -- Wer die Tour schon kannte: nur die Neuerungen zeigen
            ns.ShowIntro((GuildPrideDB.introSeen or 0) > 0)
        end
    end)
end)

local slash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local a = strtrim(arg or ""):lower()
    if a == "intro" or a == "tour" or a == "einführung" then return ns.ShowIntro() end
    if a == "einrichtung" or a == "setup" then return ns.ShowSetup() end
    if a == "neu" or a == "news" then return ns.ShowIntro(true) end
    return slash(arg)
end
