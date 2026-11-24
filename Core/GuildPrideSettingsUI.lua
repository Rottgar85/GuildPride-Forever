-- GuildPride: Seite „Einstellungen“ im Gildenfenster und dieselben Schalter in Blizzards Optionen
-- (früher Teil von GuildPrideUI.lua; ausgelagert wegen Luas Grenze von 200 lokalen Variablen)
local ADDON, ns = ...
local L = ns.L

local MEDIA = ns.MEDIA
local AddTab, Section, MenuEntry, MenuTabs, TabHidden = ns.AddTab, ns.Section, ns.MenuEntry, ns.MenuTabs, ns.TabHidden
local frame = ns.GuildFrame

---------------------------------------------------------------------
-- 4) Einstellungen
---------------------------------------------------------------------
local settingsPage = AddTab(L["Einstellungen"], 90)
-- Die Seite ist länger als das Fenster: Inhalt in einem Scrollbereich
local settingsScroll = ns.NewScroll(settingsPage)
settingsScroll:SetPoint("TOPLEFT", 0, -30)
settingsScroll:SetPoint("BOTTOMRIGHT", -26, 0)
local settings = CreateFrame("Frame", nil, settingsScroll)
settings:SetSize(640, 1)
settingsScroll:SetScrollChild(settings)

-- Style-Auswahl ganz oben: ein Knopf je Style, der aktive ist hervorgehoben
local styleLabel = settings:CreateFontString(nil, "OVERLAY", "GPFont_TextBold")
styleLabel:SetPoint("TOPLEFT", 4, -4)
styleLabel:SetText(L["Style"])
styleLabel:Hide()   -- seit 2.14 nur noch ein Style
local styleButtons = {}
for i, t in ipairs(ns.THEMES) do
    local b = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
    b:SetSize(98, 24)
    b:SetPoint("TOPLEFT", 4 + (i - 1) * 104, -22)
    b:SetText(t.name)
    b:SetScript("OnClick", function() ns.ApplyTheme(t.key) end)
    -- Farbtupfer des Styles
    local dot = b:CreateTexture(nil, "OVERLAY")
    dot:SetSize(8, 8); dot:SetPoint("LEFT", 8, 0)
    b.dot, b.theme = dot, t
    b.key = t.key
    b:Hide()
    styleButtons[i] = b
end
local function MarkStyle()
    local current = ns.Theme().key
    for _, b in ipairs(styleButtons) do
        if b.gpBg then b.gpBg:SetTexture(MEDIA .. (b.key == current and "nav_active" or "nav")) end
        local c = b.theme.ember   -- "Eigene" ändert die Farbe
        b.dot:SetColorTexture(c[1], c[2], c[3], 1)
    end
end
ns.OnThemeChanged(MarkStyle)

-- Eigener Style: Farbe über Blizzards Farbwähler
local colorBtn = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
colorBtn:SetSize(170, 22); colorBtn:SetPoint("TOPLEFT", 4, -50)
colorBtn:SetText(L["Eigene Farbe wählen …"])
colorBtn:SetScript("OnClick", function() ns.PickCustomColor() end)
colorBtn:Hide()

local OPT_Y = -4   -- Style- und Layout-Auswahl gibt es seit 2.14 nicht mehr
local options = {
    { header = L["Allgemein"] },
    { key = "replaceGuildFrame", label = L["Dieses Fenster statt Blizzard-Gildenfenster (J)"],
      changed = function() if ns.GuildWindowChoiceChanged then ns.GuildWindowChoiceChanged() end end },
    { key = "showItemID",    label = L["Item-ID im Item-Tooltip zeigen"] },
    { key = "easyRead",      label = L["Besser lesbar: größere Schrift und hellere graue Texte"],
      changed = function() if ns.ApplyReadable then ns.ApplyReadable() end end },
    { key = "colorSafe",     label = L["Farben für Farbenblinde in Listenfenstern (Blau und Orange statt Grün und Rot)"] },
    { key = "crestGuild",    label = L["Oben das Gildenwappen statt des Fraktionslogos zeigen"],
      changed = function() if ns.UpdateCrestChoice then ns.UpdateCrestChoice() end end },
    { key = "compactMenu",   label = L["Kompaktes Menü (Übersicht + Meilensteine, Events + Gruppensuche + Umfragen zusammen)"],
      changed = function() if ns.MenuChanged then ns.MenuChanged() end end },
    { key = "minimap",       label = L["Minimap-Knopf anzeigen"],
      changed = function() if ns.UpdateMinimap then ns.UpdateMinimap() end end },
    { key = "guildTab",      label = L["Knopf am Blizzard-Gildenfenster anzeigen"],
      changed = function() if ns.UpdateGuildTab then ns.UpdateGuildTab() end end },
    { header = L["Hinweise"] },
    { key = "popup",         label = L["Meilenstein-Popups anzeigen"] },
    { key = "sound",         label = L["Sounds abspielen"] },
    { key = "memberAlerts",  label = L["Warnung bei Beitritt / Austritt"] },
    { key = "helpAlerts",    label = L["Hinweis, wenn jemand Gruppe / Quest-Hilfe sucht"] },
    { key = "albumShot",     label = L["Gildenalbum: beim ersten Sieg über einen Boss einen Screenshot machen"] },
    { key = "wishTooltip",   label = L["Im Item-Tooltip zeigen, wer in der Gilde das Item sucht"] },
    { key = "wishDropHint",  label = L["Bei einem Drop zeigen, wer in der Gruppe ihn sich wünscht"] },
    { header = L["Teilen"] },
    { key = "shareMilestones", label = L["Eigene Erfolge, Bosse, M+ und Reittiere mit der Gilde teilen"] },
    { key = "raidReady",     label = L["Raid-Bereitschaft: Leitern und Assistenten deiner Gruppe Haltbarkeit, Buff-Food und Tränke melden"] },
    { key = "cooldownShare", label = L["Abklingzeiten: eigene wichtige Zauber mit der Gilde teilen (nur in einer Gruppe)"] },
    { key = "guildQuests",   label = L["Quests der Gilde: eigene Quests (nur die Nummern) mit der Gilde teilen"],
      changed = function() if ns.GuildQuests then ns.GuildQuests.Changed() end end },
    { key = "errorShare",    label = L["GuildPride-Fehler automatisch an den Entwickler senden (Fehlertext, Versionen, Sprache, Umstände)"] },
    { key = "mapShow",       label = L["Gildenmitglieder mit GuildPride auf der Weltkarte zeigen"],
      changed = function() if ns.MapShowChanged then ns.MapShowChanged() end end },
    { key = "mapShare",      label = L["Eigene Position auf der Weltkarte mit der Gilde teilen"],
      changed = function() if ns.MapShareChanged then ns.MapShareChanged() end end },
    { key = "publicLFG",     label = L["Serverweite Gruppensuche (Schiffe, Rares und Auktionshaus teilen immer)"], public = true,
      changed = function() if ns.PublicLFGChanged then ns.PublicLFGChanged() end end },
    { key = "publicAlerts",  label = L["Hinweis auch bei Einträgen vom Server"], public = true },
    { header = L["Auktionshaus"] },
    { key = "ahTab",         label = L["GuildPride-Auktionshaus nutzen (aus = nur Blizzards Auktionshaus)"],
      changed = function() if ns.AH and ns.AH.SetModernUI then ns.AH.SetModernUI(GuildPrideDB.ahTab) end end },
    { key = "ahTooltip",     label = L["Auktionshauspreis im Item-Tooltip zeigen"] },
    { key = "ahTooltipWithAuctionator", label = L["Tooltip-Preis auch zeigen, wenn Auctionator geladen ist"] },
    { key = "ahTipSenders",  label = L["Tooltip: wie viele Spieler den Preis gemeldet haben"] },
    { key = "ahTipTrend",    label = L["Tooltip: Preistrend der Woche"] },
    { key = "ahTipHistory",  label = L["Tooltip: Preisverlauf (bis 30 Tage)"] },
    { key = "ahTipVendor",   label = L["Tooltip: Händlerpreis"] },
    { key = "ahTipCraft",    label = L["Tooltip: Herstellkosten und Gewinn"] },
    { key = "ahSellHint",    label = L["Verkaufs-Hinweis: Münze in den Taschen, wenn ein Preis gerade hoch ist"] },
    { key = "ahMailSummary", label = L["Briefkasten: Auktionsbriefe zusammenfassen"] },
    { header = L["Handwerk"] },
    { key = "craftCard",     label = L["Rezeptkarte am Berufsfenster (Skill-Up, Zutaten, Gewinn, Guide)"],
      changed = function() if ns.CraftCard then ns.CraftCard.SetShown(GuildPrideDB.craftCard) end end },
    { key = "craftHints",    label = L["Hinweise: Guide-Schritt geschafft, Rang-Limit, was du am Lehrer lernen solltest"] },
    { key = "craftTooltip",  label = L["Item-Tooltip: Bestand deiner Charaktere und was dein Guide noch braucht"] },
    { key = "craftBank",     label = L["Bank und Briefkasten: Knöpfe „Mats holen“, „Mats einlagern“, „Mats für Twink“"] },
    { key = "craftNPCMap",   label = L["Lehrer und Händler des gewählten Berufs auf der Weltkarte"],
      changed = function() if ns.RefreshMapPins then ns.RefreshMapPins(true) end end },
    { key = "craftTips",     label = L["Tooltips: Baupläne, Beute-Berater; Alt-Klick auf Links trackt"] },
    { key = "craftTrade",    label = L["Hinweis, wenn im Handelschannel jemand sucht, was du herstellen kannst"] },
    { key = "craftNodes",    label = L["Eigene Sammelpunkte (Bergbau, Kräuter) auf der Weltkarte"],
      changed = function() if ns.RefreshMapPins then ns.RefreshMapPins(true) end end },
    { key = "craftFish",     label = L["Angel-Leiste, wenn du eine Angel trägst"],
      changed = function() if ns.CraftFish then ns.CraftFish.Update() end end },
    { key = "craftSell",     label = L["Verkaufs-Berater im Tooltip: Händler, Auktionshaus oder behalten"] },
    { header = L["Reisen"] },
    { key = "transitUI",     label = L["Abfahrten an Anlegern und Bahnsteigen zeigen (wann Schiff, Zeppelin oder Bahn kommt)"],
      changed = function() if ns.Transit and ns.Transit.SetWindow then ns.Transit.SetWindow(GuildPrideDB.transitUI) end end },
    { key = "flightTimes",   label = L["Flugzeit am Flugmeister im Tooltip zeigen (lernt echte Zeiten beim Fliegen)"] },
    { key = "flightUI",      label = L["Flug-Zähler im Flug zeigen (Restzeit bis zur Landung)"],
      changed = function() if ns.Flight and ns.Flight.SetWindow then ns.Flight.SetWindow(GuildPrideDB.flightUI) end end },
    { key = "mapNotes",      label = L["Notizzettel auf der Karte (Gilde blau, alle anderen weiß; gehen auf ~5 m auf)"],
      changed = function() if ns.Zettel then ns.Zettel.Changed() end end },
    { key = "mapNotesPublic", label = L["… auch Zettel für alle (weiß) zeigen, nicht nur die der Gilde"],
      changed = function() if ns.Zettel then ns.Zettel.Changed() end end },
    { key = "mapNotesMinimap", label = L["… Zettel in der Nähe auf der Minimap zeigen"],
      changed = function() if ns.Zettel then ns.Zettel.Changed() end end },
    { header = L["Buffs & Erholung"] },
    { key = "buffFood",      label = L["Buff-Food-Fenster, wenn „Satt“ ausläuft (bestes Essen für deine Klasse)"],
      changed = function() if ns.Buffs then ns.Buffs.Check() end end },
    { key = "restReminder",  label = L["Schlafsack-/Lagerfeuer-Fenster, wenn „Gut erholt“ oder „Lagervorteile“ fehlt (beim Leveln)"],
      changed = function() if ns.Buffs then ns.Buffs.Check() end end },
    { header = L["Namensplaketten"] },
    { key = "plateColors",   label = L["Eigene Farben auf den Namensplaketten (nur für dich)"],
      changed = function() if ns.Plates then ns.Plates.RefreshAll() end end },
    { header = L["Gilde"] },
    { key = "bossNotes",     label = L["Boss-Notizen beim Betreten einer Instanz zeigen"] },
    { key = "welcome",       label = L["Neue Mitglieder automatisch im Gildenchat begrüßen"] },
    { key = "welcomePack",   label = L["Willkommensfenster, wenn du einer Gilde beitrittst"] },
    { key = "whisperWindow", label = L["Messenger-Fenster geht auf, wenn dich jemand anflüstert"] },
    { key = "whisperCombat", label = L["… auch im Kampf (sonst erst danach)"] },
    { key = "whisperOutgoing", label = L["Selbst flüstern (/w, R, Namensmenü) im Messenger-Fenster"] },
    { key = "whisperKnownOnly", label = L["… nur bei Gilde, Freunden und Gruppe"] },
    { key = "discordBridge", label = L["Discord-Anbindung nutzen (Events, Anmeldungen, DKP an Discord)"] },
    { key = "discordLinked", label = L["Mein Discord ist mit WoW verknüpft (Optionen > Soziales)"] },
    { key = "discordViaGuild", label = L["Discord-Zeilen immer in den Gildenchat (sonst eigener Discord-Kanal der Gilde)"] },
    { key = "discordShowRaw", label = L["Discord-Zeilen im Chat anzeigen"] },
    { header = L["Twinks"] },
    { key = "ausweisAuto",   label = L["Meine Charaktere automatisch verknüpfen (BattleTag bleibt privat)"] },
    { key = "groupAlts",     label = L["Twinks in der Mitgliederliste unter dem Main zusammenfassen"],
      changed = function() if ns.RefreshUI then ns.RefreshUI() end end },
}
-- Serverweite Gruppensuche: in Classic-Clients nicht möglich, Schalter weglassen
for i = #options, 1, -1 do
    if (options[i].public and not ns.HAS_PUBLIC_LFG) or (options[i].forever and not ns.IS_FOREVER) then table.remove(options, i) end
end
ns.SettingOptions = options   -- für Suche und Pakete (GuildPrideSearch.lua)
local function SetOption(opt, on)
    GuildPrideDB[opt.key] = on and true or false
    if opt.changed then opt.changed() end
end
local checks = {}
for i, opt in ipairs(options) do
  if opt.header then
    -- Abschnitts-Überschrift statt Haken
    local h = settings:CreateFontString(nil, "OVERLAY", "GPFont_TextBold")
    h:SetPoint("TOPLEFT", 4, OPT_Y - (i - 1) * 30 - 8)
    h:SetText(opt.header)
    opt.fs, opt.y = h, OPT_Y - (i - 1) * 30
  else
    local cb = CreateFrame("CheckButton", nil, settings, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 0, OPT_Y - (i - 1) * 30)
    local label = settings:CreateFontString(nil, "OVERLAY", "GPFont_Text")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetText(opt.label)
    cb:SetScript("OnClick", function(self) SetOption(opt, self:GetChecked()) end)
    checks[opt.key] = cb
    opt.fs, opt.cb, opt.y = label, cb, OPT_Y - (i - 1) * 30
    -- Knopf zum Testen der Discord-Anbindung direkt neben dem Schalter
    if opt.key == "plateColors" then
        local pb = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
        pb:SetSize(110, 20)
        pb:SetPoint("LEFT", label, "RIGHT", 10, 0)
        pb:SetText(L["Farben …"])
        pb:SetScript("OnClick", function() if ns.Plates then ns.Plates.Toggle() end end)
    end
    if opt.key == "discordBridge" then
        local test = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
        test:SetSize(130, 20)
        test:SetPoint("LEFT", label, "RIGHT", 10, 0)
        test:SetText(L["Discord testen"])
        test:SetScript("OnClick", function() if ns.Discord and ns.Discord.Test then ns.Discord.Test() end end)
    end
  end
end

do
-- Suche oben: passende Einstellungen hervorheben, andere abblenden,
-- zur ersten passenden springen (Inhalt wird unten nach "options" gefüllt)
local settingsSearch = CreateFrame("EditBox", nil, settingsPage, "InputBoxTemplate")
settingsSearch:SetSize(220, 22); settingsSearch:SetPoint("TOPLEFT", 10, -2)
settingsSearch:SetAutoFocus(false)
local settingsSearchHint = settingsSearch:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
settingsSearchHint:SetPoint("LEFT", 4, 0)
settingsSearchHint:SetText(L["Einstellung suchen …"])
settingsSearch:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
settingsSearch:SetScript("OnEnterPressed", settingsSearch.ClearFocus)

settingsSearch:SetScript("OnTextChanged", function(self)
    local q = strtrim(self:GetText() or ""):lower()
    settingsSearchHint:SetShown(q == "")
    local first
    for _, opt in ipairs(options) do
        if opt.fs then
            local text = (opt.label or opt.header or ""):lower()
            local hit = q ~= "" and text:find(q, 1, true) ~= nil
            local a = (q == "" or hit) and 1 or 0.3
            opt.fs:SetAlpha(a)
            if opt.cb then opt.cb:SetAlpha(a) end
            if hit and not opt.header then
                opt.fs:SetTextColor(1, 0.82, 0.2)
                if not first then first = opt end
            elseif not opt.header then
                opt.fs:SetTextColor(0.92, 0.90, 0.88)
            end
        end
    end
    if first then
        local range = settingsScroll:GetVerticalScrollRange() or 0
        settingsScroll:SetVerticalScroll(math.min(range, math.max(0, -first.y - 40)))
    end
end)
end

local blizzBtn = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
blizzBtn:SetSize(220, 26)
blizzBtn:SetPoint("TOPLEFT", 4, OPT_Y - (#options * 30) - 8)
blizzBtn:SetText(L["Blizzard-Gildenfenster öffnen"])
blizzBtn:SetScript("OnClick", function() ns.OpenBlizzardGuild() end)

do
local backupBtn = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
backupBtn:SetSize(180, 26)
backupBtn:SetPoint("LEFT", blizzBtn, "RIGHT", 10, 0)
backupBtn:SetText(L["Datensicherung …"])
backupBtn:SetScript("OnClick", function() if ns.ToggleBackupWindow then ns.ToggleBackupWindow() end end)

-- Einrichtung erneut öffnen: welches Gildenfenster, welches Aussehen
local setupBtn = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
setupBtn:SetSize(150, 26)
setupBtn:SetPoint("LEFT", backupBtn, "RIGHT", 10, 0)
setupBtn:SetText(L["Einrichtung …"])
setupBtn:SetScript("OnClick", function() if ns.ShowSetup then ns.ShowSetup() end end)
end

-- Begrüßungstext (GuildPrideMembers.lua), {name} = neues Mitglied
local welcomeY = OPT_Y - (#options * 30) - 46
local welcomeLabel = settings:CreateFontString(nil, "OVERLAY", "GPFont_TextBold")
welcomeLabel:SetPoint("TOPLEFT", 4, welcomeY)
welcomeLabel:SetText(L["Begrüßungstext ({name} = neues Mitglied, {discord} und {community} = Links der Gilde)"])
-- Fehler melden: fertiger Bericht zum Kopieren (GuildPrideErrors.lua)
do
    local bugBtn = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
    bugBtn:SetSize(150, 24)
    bugBtn:SetPoint("TOPRIGHT", settings, "TOPRIGHT", -8, welcomeY + 4)
    bugBtn:SetText(L["Fehler melden …"])
    bugBtn:SetScript("OnClick", function() if ns.BugReport then ns.BugReport() end end)
    bugBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["Fehler melden"])
        GameTooltip:AddLine(L["Erstellt einen Bericht mit Version und gespeicherten Fehlern zum Kopieren und Einsenden."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    bugBtn:SetScript("OnLeave", GameTooltip_Hide)
end
local welcomeBox = CreateFrame("EditBox", nil, settings, "InputBoxTemplate")
welcomeBox:SetSize(470, 22); welcomeBox:SetPoint("TOPLEFT", 10, welcomeY - 18)
welcomeBox:SetAutoFocus(false); welcomeBox:SetMaxLetters(200)
welcomeBox:SetScript("OnTextChanged", function(self, user)
    if user then GuildPrideDB.welcomeText = self:GetText() end
end)
welcomeBox:SetScript("OnEnterPressed", welcomeBox.ClearFocus)
welcomeBox:SetScript("OnEscapePressed", welcomeBox.ClearFocus)

-- Regler mit - / +: Fenstergröße, Deckkraft, Chat-Schrift
local function ApplyLook()
    frame:SetScale(GuildPrideDB.scale or 1)
    frame:SetAlpha(GuildPrideDB.alpha or 1)
end
local steppers = {}
local function Stepper(label, y, key, step, min, max, fmt, apply)
    local l = settings:CreateFontString(nil, "OVERLAY", "GPFont_Text")
    l:SetPoint("TOPLEFT", 8, y); l:SetWidth(170); l:SetText(label)
    local minus = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
    minus:SetSize(26, 22); minus:SetPoint("LEFT", l, "RIGHT", 4, 0); minus:SetText("-")
    local value = settings:CreateFontString(nil, "OVERLAY", "GPFont_TextBold")
    value:SetPoint("LEFT", minus, "RIGHT", 6, 0); value:SetWidth(60)
    local plus = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
    plus:SetSize(26, 22); plus:SetPoint("LEFT", value, "RIGHT", 6, 0); plus:SetText("+")
    local s = { value = value }
    function s.Show() value:SetText(fmt(GuildPrideDB[key])) end
    local function Change(d)
        local v = (GuildPrideDB[key] or min) + d
        v = math.max(min, math.min(max, math.floor(v / step + 0.5) * step))
        GuildPrideDB[key] = v
        apply(v)
        s.Show()
    end
    minus:SetScript("OnClick", function() Change(-step) end)
    plus:SetScript("OnClick", function() Change(step) end)
    steppers[#steppers + 1] = s
end
local lookY = welcomeY - 56
local function Pct(v) return ("%d %%"):format(math.floor((v or 1) * 100 + 0.5)) end
Stepper(L["Fenstergröße"], lookY, "scale", 0.05, 0.6, 2, Pct, ApplyLook)
Stepper(L["Deckkraft"], lookY - 28, "alpha", 0.05, 0.5, 1, Pct, ApplyLook)
Stepper(L["Chat-Schrift"], lookY - 56, "chatFont", 1, 10, 18, function(v) return ("%d pt"):format(v or 12) end,
    function(v) if ns.SetChatFont then ns.SetChatFont(v) end end)
Stepper(L["Event-Erinnerung"], lookY - 84, "remindMin", 5, 0, 60,
    function(v) return (v or 15) == 0 and L["aus"] or (L["%d Min."]):format(v or 15) end, function() end)

-- Ecke unten rechts: ziehen vergrößert/verkleinert das ganze Fenster
-- (alles wächst mit, auch die Schrift). Die linke obere Ecke bleibt stehen.
do   -- eigener Block (Grenze von 200 lokalen Variablen)
local SCALE_MIN, SCALE_MAX = 0.6, 2
local grip = CreateFrame("Button", nil, frame)
grip:SetSize(18, 18)
grip:SetPoint("BOTTOMRIGHT", -3, 3)
grip:SetFrameLevel(frame:GetFrameLevel() + 50)
grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L["Ziehen: Fenster größer oder kleiner"])
    GameTooltip:AddLine(L["Rechtsklick: zurück auf 100 %"], 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
grip:SetScript("OnLeave", GameTooltip_Hide)
local function KeepTopLeft(left, top, scale)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / scale, top / scale)
end
local function ShowSteppers() for _, st in ipairs(steppers) do st.Show() end end
grip:RegisterForClicks("RightButtonUp")
grip:SetScript("OnClick", function()
    local sc = frame:GetScale()
    local left, top = frame:GetLeft() * sc, frame:GetTop() * sc
    GuildPrideDB.scale = 1
    frame:SetScale(1)
    KeepTopLeft(left, top, 1)
    ShowSteppers()
end)
grip:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    local sc = frame:GetScale()
    -- Lage in UIParent-Einheiten (unabhängig von der eigenen Skalierung)
    local left, top = frame:GetLeft() * sc, frame:GetTop() * sc
    local uiScale = UIParent:GetEffectiveScale()
    self:SetScript("OnUpdate", function()
        local cx, cy = GetCursorPosition()
        cx, cy = cx / uiScale, cy / uiScale
        local new = math.max((cx - left) / frame:GetWidth(), (top - cy) / frame:GetHeight())
        new = math.max(SCALE_MIN, math.min(SCALE_MAX, new))
        if math.abs(new - frame:GetScale()) > 0.005 then
            frame:SetScale(new)
            KeepTopLeft(left, top, new)
        end
    end)
end)
grip:SetScript("OnMouseUp", function(self)
    self:SetScript("OnUpdate", nil)
    GuildPrideDB.scale = math.floor(frame:GetScale() * 100 + 0.5) / 100
    ShowSteppers()
end)
end

local lookFrame = CreateFrame("Frame")
lookFrame:RegisterEvent("PLAYER_LOGIN")
lookFrame:SetScript("OnEvent", ApplyLook)

-- Werbetext, Bewerbungen und Notiz-Vorlagen: Reiter "Verwaltung" (GuildPrideAdmin.lua)
local baseY = lookY - 124

-- Menü anpassen: Reiter zeigen/ausblenden, umbenennen, verschieben, Startreiter.
-- Die Zeilen entstehen erst beim ersten Öffnen, weil andere Dateien ihre
-- Reiter nach dieser Datei anlegen.
local MENU_ROWS = 10
local menuY = baseY
Section(settings, L["Menü anpassen"], nil, menuY)
local menuHint = settings:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
menuHint:SetPoint("TOPLEFT", 4, menuY - 26)
menuHint:SetWidth(620); menuHint:SetJustifyH("LEFT")
menuHint:SetText(L["Haken = sichtbar, Name ändern, Pfeile = Reihenfolge, Start = beim Öffnen gezeigt. „Einstellungen“ bleibt immer da."])
menuHint:SetTextColor(0.75, 0.72, 0.68)
local menuRows = {}

local function RenumberMenu(list)
    for i, tab in ipairs(list) do MenuEntry(tab, true).order = i * 10 end
end

local RefreshMenuRows
local function MoveTab(index, dir)
    local list = MenuTabs()
    local other = index + dir
    if not list[index] or not list[other] then return end
    list[index], list[other] = list[other], list[index]
    RenumberMenu(list)
    ns.MenuChanged()
    RefreshMenuRows()
end

local function ArrowButton(parent, up)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(24, 24)
    local base = "Interface\\ChatFrame\\UI-ChatIcon-Scroll" .. (up and "Up" or "Down")
    b:SetNormalTexture(base .. "-Up")
    b:SetPushedTexture(base .. "-Down")
    b:SetDisabledTexture(base .. "-Disabled")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    return b
end

local function BuildMenuRow(i)
    local y = menuY - 48 - (i - 1) * 30
    local row = {}
    row.show = CreateFrame("CheckButton", nil, settings, "UICheckButtonTemplate")
    row.show:SetSize(26, 26); row.show:SetPoint("TOPLEFT", 4, y)
    row.show:SetScript("OnClick", function(self)
        local tab = row.tab
        if not tab then return end
        MenuEntry(tab, true).hide = not self:GetChecked() or nil
        ns.MenuChanged()
        RefreshMenuRows()
    end)
    row.name = CreateFrame("EditBox", nil, settings, "InputBoxTemplate")
    row.name:SetSize(200, 22); row.name:SetPoint("TOPLEFT", 42, y - 2)
    row.name:SetAutoFocus(false); row.name:SetMaxLetters(24)
    row.name:SetScript("OnTextChanged", function(self, user)
        local tab = row.tab
        if not user or not tab then return end
        local text = strtrim(((self:GetText() or ""):gsub("|", "")))
        MenuEntry(tab, true).name = (text ~= "" and text ~= (tab.shownDefault or tab.defaultLabel)) and text or nil
        ns.MenuChanged()
    end)
    row.name:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    row.name:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    row.name:SetScript("OnEditFocusLost", function(self)
        if row.tab then self:SetText(row.tab.label) end
    end)
    row.orig = settings:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    row.orig:SetPoint("LEFT", row.name, "RIGHT", 10, 0)
    row.orig:SetWidth(150); row.orig:SetJustifyH("LEFT")
    row.orig:SetTextColor(0.6, 0.58, 0.55)
    row.up = ArrowButton(settings, true)
    row.up:SetPoint("LEFT", row.name, "RIGHT", 168, 0)
    row.up:SetScript("OnClick", function() MoveTab(row.index, -1) end)
    row.down = ArrowButton(settings, false)
    row.down:SetPoint("LEFT", row.up, "RIGHT", 2, 0)
    row.down:SetScript("OnClick", function() MoveTab(row.index, 1) end)
    row.start = CreateFrame("CheckButton", nil, settings, "UIRadioButtonTemplate")
    row.start:SetPoint("LEFT", row.down, "RIGHT", 16, 0)
    row.start:SetScript("OnClick", function()
        -- Nochmal klicken: kein fester Start mehr (zuletzt offener Reiter)
        if row.tab then
            GuildPrideDB.startTab = GuildPrideDB.startTab ~= row.tab.key and row.tab.key or nil
        end
        RefreshMenuRows()
    end)
    row.startText = settings:CreateFontString(nil, "OVERLAY", "GPFont_Text")
    row.startText:SetPoint("LEFT", row.start, "RIGHT", 4, 0)
    row.startText:SetText(L["Start"])
    row.widgets = { row.show, row.name, row.orig, row.up, row.down, row.start, row.startText }
    menuRows[i] = row
    return row
end

local menuReset = CreateFrame("Button", nil, settings, "UIPanelButtonTemplate")
menuReset:SetSize(200, 24)
menuReset:SetText(L["Menü zurücksetzen"])
menuReset:SetScript("OnClick", function()
    GuildPrideDB.menu = nil
    GuildPrideDB.startTab = nil
    ns.MenuChanged()
    RefreshMenuRows()
end)

function RefreshMenuRows()
    local list = MenuTabs()
    local startKey = GuildPrideDB.startTab
    for i = 1, math.min(#list, MENU_ROWS) do
        local row = menuRows[i] or BuildMenuRow(i)
        local tab = list[i]
        row.tab, row.index = tab, i
        for _, w in ipairs(row.widgets) do w:Show() end
        row.show:SetChecked(not TabHidden(tab))
        if not row.name:HasFocus() then row.name:SetText(tab.label) end
        local def = tab.shownDefault or tab.defaultLabel
        row.orig:SetText(tab.label ~= def and ("(" .. def .. ")") or "")
        row.up:SetEnabled(i > 1)
        row.down:SetEnabled(i < #list)
        row.start:SetChecked(startKey == tab.key)
    end
    for i = #list + 1, #menuRows do
        menuRows[i].tab = nil
        for _, w in ipairs(menuRows[i].widgets) do w:Hide() end
    end
    menuReset:ClearAllPoints()
    menuReset:SetPoint("TOPLEFT", 10, menuY - 56 - math.min(#list, MENU_ROWS) * 30)
end

settings:SetHeight(-(menuY - 56 - MENU_ROWS * 30 - 60))

function settingsPage:Refresh()
    RefreshMenuRows()
    MarkStyle()
    for key, cb in pairs(checks) do cb:SetChecked(GuildPrideDB[key]) end
    for _, s in ipairs(steppers) do s.Show() end
    if not welcomeBox:HasFocus() then
        local w = GuildPrideDB.welcomeText
        welcomeBox:SetText((w and w ~= "") and w or (ns.WELCOME_DEFAULT or ""))
    end
end
ns.SettingsPage = settingsPage
ns.UIParts.settings = settings   -- für die Layouts (GuildPrideLayout.lua)

-- Dieselben Schalter im WoW-Menü (Optionen -> AddOns -> GuildPride)
-- Ältere Classic-Clients ohne neues Settings-Menü: alte Interface-Optionen
if (Settings and Settings.RegisterCanvasLayoutCategory) or InterfaceOptions_AddCategory then
    local panel = CreateFrame("Frame")
    panel.name = "GuildPride"
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("GuildPride")
    -- Die Schalter passen nicht in Blizzards Fenster: Inhalt scrollt unter dem Titel
    -- (panel.body; als Feld statt lokaler Variable wegen der 200-Lokale-Grenze dieser Datei)
    panel.scroll = ns.NewScroll(panel)
    panel.scroll:SetPoint("TOPLEFT", 0, -40)
    panel.scroll:SetPoint("BOTTOMRIGHT", -28, 8)
    panel.body = CreateFrame("Frame", nil, panel.scroll)
    panel.body:SetSize(600, #options * 32 + 60)
    panel.scroll:SetScrollChild(panel.body)
    panel.scroll:SetScript("OnSizeChanged", function(self, w) if w and w > 0 then panel.body:SetWidth(w) end end)
    local panelChecks = {}
    for i, opt in ipairs(options) do
      if opt.header then
        local h = panel.body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h:SetPoint("TOPLEFT", 20, -4 - (i - 1) * 32 - 8)
        h:SetText(opt.header)
      else
        local cb = CreateFrame("CheckButton", nil, panel.body, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 16, -4 - (i - 1) * 32)
        local label = panel.body:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        label:SetText(opt.label)
        cb:SetScript("OnClick", function(self) SetOption(opt, self:GetChecked()) end)
        panelChecks[opt.key] = cb
      end
    end
    local open = CreateFrame("Button", nil, panel.body, "UIPanelButtonTemplate")
    open:SetSize(220, 26)
    open:SetPoint("TOPLEFT", 20, -4 - #options * 32 - 12)
    open:SetText(L["Gildenfenster öffnen"])
    open:SetScript("OnClick", function()
        if SettingsPanel then HideUIPanel(SettingsPanel) end
        if InterfaceOptionsFrame then HideUIPanel(InterfaceOptionsFrame) end
        if not frame:IsShown() then ns.ToggleUI() end
    end)
    panel:SetScript("OnShow", function()
        if not GuildPrideDB then return end
        for key, cb in pairs(panelChecks) do cb:SetChecked(GuildPrideDB[key]) end
    end)
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "GuildPride")
        Settings.RegisterAddOnCategory(category)
        ns.SettingsCategory = category
    else
        InterfaceOptions_AddCategory(panel)
        ns.SettingsPanel = panel
    end
end
