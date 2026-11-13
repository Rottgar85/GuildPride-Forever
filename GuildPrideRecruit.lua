-- GuildPride: Bewerbungen – auch für Spieler OHNE GuildPride
--
-- Ablauf:
-- 1. Offiziere legen einen Steckbrief fest (wen ihr sucht, Raidzeiten,
--    Sprache, kurze Beschreibung) und schalten Bewerbungen an. Der Steckbrief
--    geht an alle Mitglieder mit GuildPride (RCP, nur von Offizieren angenommen).
-- 2. Der Werbetext (Knopf „In den Chat legen“) bekommt automatisch den Hinweis
--    „Flüstere !bewerben“. Gepostet wird er wie bisher von Hand (Blizzard
--    erlaubt Kanal-Nachrichten nur per Klick, außerdem wäre Auto-Werbung Spam).
-- 3. Wer einem Mitglied mit GuildPride „!bewerben“ flüstert, wird per Flüstern
--    durch vier feste Fragen geführt. „!info“ schickt den Steckbrief.
--    Das funktioniert ganz ohne Addon beim Bewerber.
-- 4. Die fertige Bewerbung geht per Addon-Flüstern an alle Offiziere online (APP).
--    Ist gerade keiner online, hält das Mitglied sie fest und liefert sie nach,
--    sobald ein Offizier online kommt; der Offizier bestätigt (APK).
-- 5. Offiziere sehen alle Bewerbungen im Fenster „Bewerbungen“ und nehmen an
--    (zeigt den /ginvite-Befehl) oder lehnen ab (freundliche Flüsternachricht).
--
-- Schutz: Den Absender eines Flüsterns prüft der Server. Pro Bewerber höchstens
-- eine Bewerbung am Tag, höchstens drei Gespräche gleichzeitig, Antworten auf
-- 200 Zeichen gekürzt und von Codes befreit, Gildenmitglieder werden ignoriert.
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP or "\031"

local QUESTIONS = {
    L["Frage 1/4: Welche Klasse und welches Level hast du?"],
    L["Frage 2/4: Welche Rolle spielst du (Tank, Heiler, DD)?"],
    L["Frage 3/4: Wann spielst du meistens (Tage und Uhrzeit)?"],
    L["Frage 4/4: Erzähl kurz etwas über dich – warum möchtest du zu uns?"],
}
local LABELS = { L["Klasse/Level"], L["Rolle"], L["Spielzeiten"], L["Über sich"] }
local KEYWORDS = { ["!bewerben"] = "apply", ["!apply"] = "apply", ["!info"] = "info" }
local TIMEOUT = 600          -- Sekunden bis ein Gespräch verfällt
local MAX_TALKS = 3
local MAX_ANSWER = 200
local DAY = 86400

local function Now() return GetServerTime() end
local function Clean(s, n) return (tostring(s or ""):gsub("[%c|]", "")):sub(1, n or MAX_ANSWER) end
local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function CanManage() return CanEditMOTD and CanEditMOTD() end
local function Profile() local p = ns.GuildTable("recruit"); return p end
local function Apps() return ns.GuildTable("apps") end          -- nur bei Offizieren gefüllt
local function Outbox() return ns.GuildTable("appOutbox") end   -- noch nicht bestätigte

local SendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
local function Locked() return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() end
local function Whisper(to, text)
    if Locked() then return end
    pcall(SendChat, Clean(text, 250), "WHISPER", nil, to)
end

---------------------------------------------------------------------
-- Steckbrief (Offiziere) und Abgleich in der Gilde
---------------------------------------------------------------------
local FIELDS = { "seek", "times", "lang", "about" }

function ns.RecruitOpen() return Profile().open == true end

function ns.SetRecruitProfile(values, open)
    if not CanManage() then return end
    local p = Profile()
    for _, k in ipairs(FIELDS) do p[k] = Clean(values[k], 120) end
    p.open, p.ver = open and true or false, Now()
    ns.Queue("RCP", nil, p.ver, p.open and 1 or 0, p.seek, p.times, p.lang, p.about)
end

ns.On("RCP", function(payload, sender)
    if not ns.IsOfficerName(sender) then return end
    local a = { strsplit(SEP, payload) }
    local ver = ns.Stamp(a[1])
    local p = Profile()
    if ver <= (p.ver or 0) then return end
    p.ver, p.open = ver, a[2] == "1"
    for i, k in ipairs(FIELDS) do p[k] = Clean(a[i + 2], 120) end
end)

-- Neue Mitglieder fragen den Steckbrief beim Einloggen ab
ns.On("RCPQ", function(_, sender)
    if not CanManage() or not ns.IsGuildMember(sender) then return end
    local p = Profile()
    if not p.ver then return end
    C_Timer.After(1 + math.random() * 4, function()
        ns.Queue("RCP", sender, p.ver, p.open and 1 or 0, p.seek or "", p.times or "", p.lang or "", p.about or "")
    end)
end)

-- Hinweis für den Werbetext
function ns.RecruitSuffix()
    if not ns.RecruitOpen() then return "" end
    return " " .. L["– Bewerben: flüstere mir „!bewerben“, Infos: „!info“"]
end

---------------------------------------------------------------------
-- Gespräch per Flüstern (Bewerber braucht kein Addon)
---------------------------------------------------------------------
local talks = {}       -- [Name] = { step, answers, t }
local lastApply = {}   -- [Name] = Zeit (pro Sitzung; dazu Apps/Outbox)

local function Count(t) local n = 0; for _ in pairs(t) do n = n + 1 end return n end

local function SendInfo(to)
    local p = Profile()
    local guild = GetGuildInfo("player") or ""
    Whisper(to, (L["%s – wir suchen: %s"]):format(guild, p.seek ~= "" and p.seek or "–"))
    if (p.times or "") ~= "" then Whisper(to, L["Spielzeiten: "] .. p.times) end
    if (p.lang or "") ~= "" then Whisper(to, L["Sprache: "] .. p.lang) end
    if (p.about or "") ~= "" then Whisper(to, p.about) end
    Whisper(to, L["Bewerben: flüstere mir „!bewerben“."])
end

local function Finish(name, talk)
    talks[name] = nil
    lastApply[name] = Now()
    local id = ("%s-%d"):format(name, Now())
    local app = { id = id, name = name, t = Now(), a = talk.answers, via = ns.Me() }
    Outbox()[id] = app
    ns.SendApp(app)
    Whisper(name, L["Danke! Deine Bewerbung ist bei der Gildenleitung. Du bekommst eine Antwort per Flüstern."])
end

local function OnWhisper(text, sender)
    if Secret(text) or Secret(sender) or type(text) ~= "string" or type(sender) ~= "string" then return end
    sender = ns.Normalize(sender)
    if sender == ns.Me() or ns.IsGuildMember(sender) then return end
    local word = KEYWORDS[strtrim(text):lower()]
    local talk = talks[sender]
    if talk and Now() - talk.t > TIMEOUT then talks[sender], talk = nil, nil end

    if word == "info" then
        if ns.RecruitOpen() then SendInfo(sender) end
        return
    end
    if word == "apply" then
        if not ns.RecruitOpen() then
            Whisper(sender, L["Wir nehmen gerade keine Bewerbungen an. Danke für dein Interesse!"])
            return
        end
        if lastApply[sender] and Now() - lastApply[sender] < DAY then
            Whisper(sender, L["Du hast dich heute schon beworben. Die Gildenleitung meldet sich."])
            return
        end
        if Count(talks) >= MAX_TALKS and not talk then
            Whisper(sender, L["Gerade sind viele Bewerbungen offen – bitte in ein paar Minuten nochmal."])
            return
        end
        talks[sender] = { step = 1, answers = {}, t = Now() }
        Whisper(sender, L["Schön, dass du dich bewerben möchtest! Bitte beantworte vier kurze Fragen. „!abbrechen“ beendet."])
        Whisper(sender, QUESTIONS[1])
        return
    end
    if not talk then return end
    if strtrim(text):lower() == "!abbrechen" or strtrim(text):lower() == "!cancel" then
        talks[sender] = nil
        Whisper(sender, L["Bewerbung abgebrochen."])
        return
    end
    talk.answers[talk.step] = Clean(text)
    talk.step, talk.t = talk.step + 1, Now()
    if talk.step > #QUESTIONS then Finish(sender, talk) else Whisper(sender, QUESTIONS[talk.step]) end
end

---------------------------------------------------------------------
-- Weitergabe an die Offiziere (Offizierskanal) mit Bestätigung
---------------------------------------------------------------------
-- Direkt an jeden Offizier, der gerade online ist (in den Offizierskanal dürfen
-- normale Mitglieder nicht schreiben). Niemand online: bleibt im Ausgang.
local function OnlineOfficers()
    local list = {}
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if online and type(name) == "string" and not Secret(name) and ns.IsOfficerRank(rankIndex) then
            name = ns.Normalize(name)
            if name ~= ns.Me() then list[#list + 1] = name end
        end
    end
    return list
end

function ns.SendApp(app)
    local parts = { app.id, app.name, app.t, app.via }
    for i = 1, #QUESTIONS do parts[#parts + 1] = app.a[i] or "" end
    -- Bin ich selbst Offizier: direkt bei mir eintragen
    if CanManage() and ns.ReceiveApp then ns.ReceiveApp(table.concat(parts, SEP), ns.Me(), true) end
    for _, officer in ipairs(OnlineOfficers()) do ns.Queue("APP", officer, unpack(parts)) end
end

local newApps = 0
function ns.ReceiveApp(payload, sender, local_)
    if not CanManage() or not (local_ or ns.IsGuildMember(sender)) then return end
    local a = { strsplit(SEP, payload) }
    local id, name = Clean(a[1], 80), Clean(a[2], 60)
    if id == "" or name == "" or ns.IsGuildMember(name) then return end
    local apps = Apps()
    if not apps[id] then
        -- höchstens 200 offene Bewerbungen speichern
        local n = 0
        for _ in pairs(apps) do n = n + 1 end
        if n >= 200 then return end
        local answers = {}
        for i = 1, #QUESTIONS do answers[i] = Clean(a[4 + i]) end
        apps[id] = { id = id, name = name, t = ns.Stamp(a[3]), via = Clean(a[4], 60), a = answers, status = "new" }
        newApps = newApps + 1
        ns.Print((L["Neue Bewerbung von |cffffd100%s|r – /gp bewerbungen"]):format(Ambiguate(name, "none")))
        if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.READY_CHECK) end
        if ns.RefreshApps then ns.RefreshApps() end
        if ns.AdminPage and ns.AdminPage.Refresh then ns.AdminPage:Refresh() end
    end
    if local_ then Outbox()[id] = nil else ns.Queue("APK", sender, id) end   -- Bestätigung
end
ns.On("APP", function(payload, sender) ns.ReceiveApp(payload, sender) end)

ns.On("APK", function(payload, sender)
    if not ns.IsOfficerName(sender) then return end
    Outbox()[Clean(payload, 80)] = nil
end)

-- Offizier kommt online: noch offene Bewerbungen nachliefern; alte verwerfen
local function FlushOutbox()
    local box = Outbox()
    for id, app in pairs(box) do
        if Now() - (app.t or 0) > 14 * DAY then box[id] = nil else ns.SendApp(app) end
    end
end
if ns.OnMemberOnline then
    ns.OnMemberOnline(function(who) if ns.IsOfficerName(who) then C_Timer.After(5, FlushOutbox) end end)
end

---------------------------------------------------------------------
-- Fenster „Bewerbungen“ (Offiziere): Steckbrief oben, Bewerbungen darunter
---------------------------------------------------------------------
local win
local function Edit(parent, w, x, y, label)
    local l = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l:SetPoint("TOPLEFT", x, y); l:SetText(label)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(w, 20); e:SetPoint("TOPLEFT", x + 4, y - 14)
    e:SetAutoFocus(false); e:SetMaxLetters(120)
    e:SetScript("OnEnterPressed", e.ClearFocus); e:SetScript("OnEscapePressed", e.ClearFocus)
    return e
end

local function Decide(app, accept)
    app.status = accept and "accepted" or "declined"
    if accept then
        local cmd = "/ginvite " .. Ambiguate(app.name, "none")
        ns.Print((L["Angenommen. Einladen: |cffffd100%s|r (selbst eintippen – Forever sperrt Einladungen durch Addons)"]):format(cmd))
        Whisper(app.name, L["Deine Bewerbung wurde angenommen! Eine Gildeneinladung kommt gleich."])
    else
        Whisper(app.name, L["Danke für deine Bewerbung! Leider passt es gerade nicht. Viel Erfolg weiterhin!"])
    end
    ns.RefreshApps()
end

local function Build()
    win = CreateFrame("Frame", "GuildPrideAppsFrame", UIParent, "BasicFrameTemplateWithInset")
    win:SetSize(620, 500); win:SetPoint("CENTER"); win:SetFrameStrata("DIALOG")
    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
    tinsert(UISpecialFrames, "GuildPrideAppsFrame")
    local title = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5); title:SetText(L["Bewerbungen"])

    win.seek = Edit(win, 280, 14, -30, L["Wir suchen (Klassen, Rollen)"])
    win.times = Edit(win, 280, 310, -30, L["Raid- und Spielzeiten"])
    win.lang = Edit(win, 120, 14, -68, L["Sprache"])
    win.about = Edit(win, 440, 150, -68, L["Kurz über die Gilde"])
    win.open = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    win.open:SetPoint("TOPLEFT", 12, -104)
    local ol = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ol:SetPoint("LEFT", win.open, "RIGHT", 2, 0); ol:SetText(L["Bewerbungen annehmen"])
    local save = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    save:SetSize(160, 22); save:SetPoint("TOPRIGHT", -16, -106); save:SetText(L["Steckbrief speichern"])
    save:SetScript("OnClick", function()
        ns.SetRecruitProfile({ seek = win.seek:GetText(), times = win.times:GetText(),
            lang = win.lang:GetText(), about = win.about:GetText() }, win.open:GetChecked())
        ns.Print(L["Steckbrief gespeichert und an die Gilde verteilt."])
    end)
    local hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 16, -134); hint:SetWidth(590); hint:SetJustifyH("LEFT")
    hint:SetText(L["Bewerber flüstern einem Mitglied mit GuildPride „!bewerben“ (kein Addon nötig). Der Werbetext bekommt den Hinweis automatisch."])

    local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -156); scroll:SetPoint("BOTTOMRIGHT", -32, 12)
    win.content = CreateFrame("Frame", nil, scroll)
    win.content:SetSize(560, 10)
    scroll:SetScrollChild(win.content)
    win.rows = {}
    if ns.SkinWindow then pcall(ns.SkinWindow, win) end
end

local function Row(i)
    local r = win.rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, win.content)
    r:SetSize(560, 96)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * 100)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(1, 1, 1, 0.04)
    r.head = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.head:SetPoint("TOPLEFT", 6, -4)
    r.body = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.body:SetPoint("TOPLEFT", 6, -22); r.body:SetWidth(390); r.body:SetJustifyH("LEFT"); r.body:SetJustifyV("TOP")
    r.body:SetHeight(70)
    r.yes = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.yes:SetSize(140, 22); r.yes:SetPoint("TOPRIGHT", -6, -6); r.yes:SetText(L["Annehmen"])
    r.no = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.no:SetSize(140, 22); r.no:SetPoint("TOPRIGHT", -6, -32); r.no:SetText(L["Ablehnen"])
    r.del = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.del:SetSize(140, 22); r.del:SetPoint("TOPRIGHT", -6, -58); r.del:SetText(L["Löschen"])
    win.rows[i] = r
    return r
end

local STATUS_TEXT = { new = "|cffffd100" .. L["neu"] .. "|r", accepted = "|cff40ff40" .. L["angenommen"] .. "|r",
                      declined = "|cffff6060" .. L["abgelehnt"] .. "|r" }

function ns.RefreshApps()
    if not (win and win:IsShown()) then return end
    local list = {}
    for _, app in pairs(Apps()) do list[#list + 1] = app end
    table.sort(list, function(a, b) return (a.t or 0) > (b.t or 0) end)
    for i, app in ipairs(list) do
        local r = Row(i)
        r.head:SetText(("%s  |cff999999%s · %s|r  %s"):format(Ambiguate(app.name, "none"),
            date("%d.%m. %H:%M", app.t or 0), (L["über %s"]):format(Ambiguate(app.via or "?", "guild")),
            STATUS_TEXT[app.status] or ""))
        local lines = {}
        for q = 1, #LABELS do lines[#lines + 1] = ("|cffaaaaaa%s:|r %s"):format(LABELS[q], app.a and app.a[q] or "") end
        r.body:SetText(table.concat(lines, "\n"))
        r.yes:SetShown(app.status ~= "accepted"); r.no:SetShown(app.status == "new")
        r.yes:SetScript("OnClick", function() Decide(app, true) end)
        r.no:SetScript("OnClick", function() Decide(app, false) end)
        r.del:SetScript("OnClick", function() Apps()[app.id] = nil; ns.RefreshApps() end)
        r:Show()
    end
    for i = #list + 1, #win.rows do win.rows[i]:Hide() end
    win.content:SetHeight(math.max(10, #list * 100))
end

function ns.ToggleApps()
    if not CanManage() then ns.Print(L["Bewerbungen sehen nur Offiziere."]) return end
    if not win then Build() end
    if win:IsShown() then win:Hide() return end
    local p = Profile()
    win.seek:SetText(p.seek or ""); win.times:SetText(p.times or "")
    win.lang:SetText(p.lang or ""); win.about:SetText(p.about or "")
    win.open:SetChecked(p.open == true)
    win:Show()
    newApps = 0
    ns.RefreshApps()
end

---------------------------------------------------------------------
-- Events
---------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_WHISPER")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
local started = false
f:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if not GuildPrideDB or not IsInGuild() then return end
    if event == "CHAT_MSG_WHISPER" then
        local ok, err = pcall(OnWhisper, a1, a2)
        if not ok then geterrorhandler()(err) end
    elseif not started and (a1 or a2) then
        started = true
        C_Timer.After(40, function()
            if IsInGuild() and ns.Queue then ns.Queue("RCPQ", nil, "1") end
            if next(Outbox()) then FlushOutbox() end
        end)
    end
end)

-- Ausgeblendet: die Schlüsselwörter und unsere Antworten bleiben im Chat sichtbar,
-- damit man nachvollziehen kann, was geschickt wurde.
