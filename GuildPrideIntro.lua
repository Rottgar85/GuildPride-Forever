-- GuildPride: kurze Einführung beim ersten Start (wieder öffnen mit /gp intro)
-- Die letzte Seite fragt nach der Discord-Anbindung (GuildPrideDiscord.lua).
local ADDON, ns = ...
local L = ns.L
local INTRO_VERSION = 1

local PAGES = {
    { title = L["Willkommen bei GuildPride!"],
      text = L["GuildPride ist der Treffpunkt deiner Gilde: Gildenfenster, Chat, Events, Gruppensuche, DKP und Discord-Anbindung an einem Ort.\n\nDiese kurze Tour zeigt dir in fünf Schritten das Wichtigste. Du kannst sie jederzeit mit /gp intro wieder öffnen."] },
    { title = L["Das Gildenfenster"],
      text = L["Drücke J (oder /gp), um das Gildenfenster zu öffnen.\n\n• Übersicht: wer online ist, nächstes Event, Neuigkeiten der Woche\n• Gilde & Chat: Gilden-, Offiziers- und Community-Chat mit Mitgliederliste\n• Gruppensuche: Hilfe für Quests und Dungeons finden\n• Umfragen, Meilensteine und Gildeninfo\n\nMit /gp blizzard kommst du zurück zum Blizzard-Fenster."] },
    { title = L["Events und Raids"],
      text = L["Im Reiter Events legen Offiziere Termine an, auf Wunsch jede Woche.\n\nAlle Mitglieder melden sich mit Zusagen, Vielleicht oder Absagen und ihrer Rolle an. 15 Minuten vor Beginn gibt es eine Erinnerung, und Offiziere können alle Zusagen mit einem Klick einladen."] },
    { title = L["DKP"],
      text = L["Mit /gp dkp öffnest du die Punkte-Rangliste.\n\nOffiziere vergeben dort mit einem Klick Punkte an den ganzen Raid (Anwesenheit, Bosskills), ziehen Loot ab und können eine Buchung zurücknehmen.\n\nFahre mit der Maus über einen Spieler: Im Tooltip steht sein DKP-Stand."] },
    { discord = true, title = L["Discord-Anbindung"],
      text = L["GuildPride kann Events, Anmeldungen, DKP und Meilensteine über Blizzards Discord-Verknüpfung an den Discord deiner Gilde schicken. Dort trägt der Bot GameBot alles ein.\n\nDafür muss die Gildenleitung die Gilde mit einem Discord-Kanal verknüpfen und GameBot einladen (gamerbot.duckdns.org). Beides kannst du später jederzeit in den GuildPride-Einstellungen ändern."] },
}

local win, page = nil, 1

local function Close()
    GuildPrideDB.introSeen = INTRO_VERSION
    -- Wer die Tour schließt, ohne zu wählen, hat die Anbindung aus
    if GuildPrideDB.discordBridge == nil then GuildPrideDB.discordBridge = false end
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
    win:SetSize(440, 360)
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

    win.step = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.step:SetPoint("BOTTOM", 0, 16)
    win.back = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.back:SetSize(100, 24); win.back:SetPoint("BOTTOMLEFT", 16, 10)
    win.back:SetText(L["Zurück"])
    win.back:SetScript("OnClick", function() Show(page - 1) end)
    win.next = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.next:SetSize(100, 24); win.next:SetPoint("BOTTOMRIGHT", -16, 10)
    win.next:SetScript("OnClick", function() if page < #PAGES then Show(page + 1) else Close() end end)

    if ns.SkinAll then pcall(ns.SkinAll, win) end
end

function ns.ShowIntro()
    if not win then Build() end
    win:Show()
    Show(1)
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    C_Timer.After(8, function()
        if GuildPrideDB and (GuildPrideDB.introSeen or 0) < INTRO_VERSION and not InCombatLockdown() then
            ns.ShowIntro()
        end
    end)
end)

local slash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local a = strtrim(arg or ""):lower()
    if a == "intro" or a == "tour" or a == "einführung" then return ns.ShowIntro() end
    return slash(arg)
end
