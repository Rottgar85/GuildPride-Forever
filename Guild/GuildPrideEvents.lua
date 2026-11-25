-- GuildPride: Event-Planer mit Anmeldung (synchronisiert über Addon-Nachrichten)
local ADDON, ns = ...
local L = ns.L
local PREFIX = "GuildPride"
local SEP = "\031"
local ROLES = {
    TANK   = { short = "T", label = "Tank",   color = "|cff6fa8ff" },
    HEALER = { short = "H", label = L["Heiler"], color = "|cff40ff40" },
    DAMAGER= { short = "D", label = L["DD"],     color = "|cffff6060" },
}

local STATUS = {
    yes   = { label = L["Zugesagt"],   color = "|cff40ff40" },
    maybe = { label = L["Vielleicht"], color = "|cffffd100" },
    no    = { label = L["Abgesagt"],   color = "|cffff4040" },
}

---------------------------------------------------------------------
-- Daten
---------------------------------------------------------------------
local function DB()
    return ns.GuildTable("events")   -- je Gilde getrennt
end

local Queue, SendEvent, SendDelete, SendSign = ns.Queue, ns.EventsNet.SendEvent, ns.EventsNet.SendDelete, ns.EventsNet.SendSign

local function Me()
    return ns.Me()
end

local function CanManage()
    -- Offiziere (wer die Gildennachricht ändern darf) dürfen Events anlegen/löschen
    return CanEditMOTD and CanEditMOTD()
end

local function Now() return GetServerTime() end

local function Clean(s, max)
    s = (tostring(s or ""):gsub("[%c|]", ""))
    return s:sub(1, max)
end

---------------------------------------------------------------------
-- Daten anwenden (neuere Version gewinnt)
---------------------------------------------------------------------
local STORE_MAX = 300   -- Obergrenze für gespeicherte Events (gegen Speicherfluten)

local function StoreCount()
    local n = 0
    for _ in pairs(DB()) do n = n + 1 end
    return n
end

-- Voll? Dann zuerst Einträge wegräumen, die seit 30 Tagen vorbei bzw. unverändert sind
local function GetOrStub(id)
    local e = DB()[id]
    if not e then
        if StoreCount() >= STORE_MAX then
            local old = Now() - 30 * 86400
            for k, x in pairs(DB()) do
                if (x.t or 0) < old and (x.ver or 0) < old then DB()[k] = nil end
            end
            if StoreCount() >= STORE_MAX then return nil end
        end
        e = { id = id, ver = 0, signups = {} }
        DB()[id] = e
    end
    e.signups = e.signups or {}
    return e
end

-- kind/inst: nil = unverändert lassen (Nachricht einer älteren Version), "" = keine Instanz
local function ApplyEvent(id, t, title, desc, creator, ver, note, fromOther, rep, kind, inst)
    local e = GetOrStub(id)
    if not e or ver <= e.ver then return end
    local isNew = not e.title
    -- Wiederholtes Event: hier schon um ganze Wochen weitergerückt? Dann nicht
    -- zurücksetzen. Eine echte Zeitänderung (Bearbeiten) wird übernommen.
    local rolled = rep and rep > 0 and e.rep == rep and e.t and e.t > t and (e.t - t) % (rep * 86400) == 0
    if not rolled then e.t = t end
    e.title, e.desc, e.creator, e.ver, e.deleted = title, desc, creator, ver, nil
    e.note = note or ""
    e.rep = (rep and rep > 0) and rep or nil
    if kind ~= nil then
        local x = ns.Instances and ns.Instances.Find(kind, inst)
        e.kind, e.inst = x and x.kind or nil, x and x.key or nil
    end
    if isNew and fromOther then
        ns.Print((L["Neues Gildenevent: |cffffd100%s|r am %s"]):format(title, ns.FormatDate(t, "short")))
        -- Noch nicht gesehen: Hinweisfenster und Markierung am Reiter
        if e.t > Now() then
            e.unseen = true
            if ns.NoteNewEvent then ns.NoteNewEvent(e) end
        end
    end
end

local function ApplyDelete(id, ver)
    local e = GetOrStub(id)
    if not e or ver < e.ver then return end
    e.deleted, e.ver = true, ver
end

local function ApplySign(id, name, status, ver, role)
    if not STATUS[status] then return end
    if not ROLES[role or ""] then role = nil end
    local e = GetOrStub(id)
    if not e then return end
    local cur = e.signups[name]
    if not cur or ver > cur.v then
        e.signups[name] = { s = status, v = ver, r = role }
        return e
    end
end

---------------------------------------------------------------------
-- Empfangen
---------------------------------------------------------------------
-- Unsere bekannten Events (inkl. Anmeldungen) an jemanden schicken
local function SendAllEvents(target)
    local cutoff = Now() - 86400
    for _, e in pairs(DB()) do
        if e.deleted then
            if (e.ver or 0) > cutoff - 6 * 86400 then SendDelete(e, target) end
        elseif e.title and e.t > cutoff then
            SendEvent(e, target)
            for name, s in pairs(e.signups) do SendSign(e.id, name, s, target) end
        end
    end
end

-- Ersteller kommt online: eigene Anmeldungen zu seinen Events direkt nachliefern
ns.OnMemberOnline(function(who)
    local me, cutoff = Me(), Now() - 86400
    for _, e in pairs(DB()) do
        local s = e.signups[me]
        if s and e.creator == who and not e.deleted and e.title and e.t > cutoff then
            SendSign(e.id, me, s, who)
        end
    end
end)

local function OnEventMessage(kind, payload, sender)
    if sender == Me() then return end
    local a = { strsplit(SEP, payload) }
    -- Fremde Werte prüfen: IDs und Namen ohne Codes und begrenzt lang,
    -- Versionen nicht in der Zukunft (sonst ließe sich ein Event sperren)
    local id = Clean(a[1], 80)
    if id == "" and (kind == "EVT" or kind == "DEL" or kind == "SGN") then return end
    -- Wer darf? Ein Event gehört dem, dessen Name vorne in der ID steht.
    -- Direkt vom Urheber oder von Offizieren: sofort. Abgleich über andere
    -- Mitglieder: erst, wenn zwei verschiedene genau dasselbe melden.
    if kind == "EVT" or kind == "DEL" or kind == "SGN" then
        local author = kind == "SGN" and Clean(a[2], 60) or id:match("^(.+)%-%d+%-%d+$")
        if not author then return end
        if kind == "EVT" and Clean(a[5], 60) ~= author then return end   -- Ersteller passt nicht zur ID
        if not (ns.IsDirect(sender, author) or ns.IsOfficerName(sender))
           and not ns.Confirmed(kind .. "\030" .. payload, sender) then return end
    end
    if kind == "EVT" then
        local rep = tonumber(a[8]) or 0
        ApplyEvent(id, ns.Num(a[2], 0, 2 ^ 31) or 0, Clean(a[3], 40), Clean(a[4], 120), Clean(a[5], 60),
            ns.Stamp(a[6]), Clean(a[7], 100), true, (rep == 7) and 7 or 0, a[9] and Clean(a[9], 10), a[10] and Clean(a[10], 20))
    elseif kind == "DEL" then
        ApplyDelete(id, ns.Stamp(a[2]))
    elseif kind == "SGN" then
        local name = Clean(a[2], 60)
        if name == "" or not ns.IsGuildMember(name) then return end
        local e = ApplySign(id, name, a[3], ns.Stamp(a[4]), a[5])
        -- Neue Anmeldung direkt vom Spieler zu meinem Event: an Discord weitergeben
        -- (seine eigene Discord-Anbindung ist oft aus)
        if e and e.creator == Me() and ns.IsDirect(sender, name) and ns.Discord and ns.Discord.RelaySign then
            ns.Discord.RelaySign(e, name, e.signups[name])
        end
    elseif kind == "REQ" or kind == "EVQ" then
        -- Jemand hat sich eingeloggt bzw. den Reiter Events geöffnet:
        -- kurz zufällig warten, damit nicht alle gleichzeitig antworten
        C_Timer.After(math.random() * 3, function() SendAllEvents(sender) end)
        return
    end
    if ns.RefreshUI then ns.RefreshUI() end
end
for _, k in ipairs({ "EVT", "DEL", "SGN", "REQ", "EVQ" }) do
    ns.On(k, function(payload, sender) OnEventMessage(k, payload, sender) end)
end

---------------------------------------------------------------------
-- Aktionen
---------------------------------------------------------------------
local function CreateEvent(title, t, desc, rep, kind, inst)
    local e = GetOrStub(Me() .. "-" .. Now() .. "-" .. math.random(1000, 9999))
    if not e then return end
    ApplyEvent(e.id, t, Clean(title, 40), Clean(desc, 120), Me(), Now(), nil, nil, rep, kind or "", inst or "")
    SendEvent(e)
    if ns.Discord then ns.Discord.EventCreated(e) end
    ns.RefreshUI()
end

-- Wöchentliche Events: 3 Std. nach Beginn auf die nächste Woche rücken.
-- Jeder rechnet gleich; Anmeldungen von vor dem letzten Termin verfallen.
function ns.RollEvents()
    if not GuildPrideDB then return end
    local now = Now()
    for _, e in pairs(DB()) do
        if e.rep and e.rep > 0 and e.title and not e.deleted and e.t then
            local moved = false
            while e.t + 3 * 3600 < now do
                e.t = e.t + e.rep * 86400
                moved = true
            end
            if moved then
                e.reminded = nil
                local cutoff = e.t - e.rep * 86400 + 3 * 3600
                for name, s in pairs(e.signups) do
                    if (s.v or 0) < cutoff then e.signups[name] = nil end
                end
            end
        end
    end
end

-- Titel, Zeit, Beschreibung oder Wiederholung ändern (Ersteller oder Offizier)
local function EditEvent(e, title, t, desc, rep, kind, inst)
    ApplyEvent(e.id, t, Clean(title, 40), Clean(desc, 120), e.creator, math.max(Now(), e.ver + 1), e.note, nil, rep,
        kind or "", inst or "")
    e.t = t
    e.reminded = nil
    SendEvent(e)
    if ns.Discord and ns.Discord.EventChanged then ns.Discord.EventChanged(e) end
    ns.RefreshUI()
end

local function DeleteEvent(e)
    ApplyDelete(e.id, Now())
    SendDelete(e)
    if ns.Discord then ns.Discord.EventDeleted(e) end
    ns.RefreshUI()
end

local function MyRole()
    if GuildPrideDB.role then return GuildPrideDB.role end
    local spec = GetSpecialization and GetSpecialization()
    local r = spec and GetSpecializationRole and GetSpecializationRole(spec)
    return ROLES[r or ""] and r or "DAMAGER"
end

local function SetNote(e, note)
    ApplyEvent(e.id, e.t, e.title, e.desc, e.creator, Now(), Clean(note, 100), nil, e.rep)
    SendEvent(e)
    ns.RefreshUI()
end

local function SignUp(e, status)
    ApplySign(e.id, Me(), status, Now(), status ~= "no" and MyRole() or nil)
    SendSign(e.id, Me(), e.signups[Me()])
    ns.TellCreator(e.creator, function(who) SendSign(e.id, Me(), e.signups[Me()], who) end)
    if ns.Discord then ns.Discord.SignedUp(e, e.signups[Me()]) end
    ns.RefreshUI()
end

-- Datum: "24.12.", "24.12", "24.12.26", "24.12.2026" (auch mit / oder -)
-- Rückgabe: Tag, Monat, Jahr (Jahr nil, wenn nicht angegeben)
local function ParseDay(str)
    local d, m, y = str:match("^(%d%d?)[%./%-](%d%d?)[%./%-]?(%d*)$")
    d, m = tonumber(d), tonumber(m)
    if not d or m < 1 or m > 12 or d < 1 or d > 31 then return nil end
    y = tonumber(y)
    if y and y < 100 then y = y + 2000 end
    return d, m, y
end

-- Uhrzeit: "20", "20:00", "20.00", "2000", "8:30", "20 Uhr"
local function ParseClock(str)
    str = str:lower():gsub("%s*uhr$", "")
    local H, M = str:match("^(%d%d?)[:%.](%d%d)$")
    if not H then H, M = str:match("^(%d%d)(%d%d)$") end
    if not H then H, M = str:match("^(%d%d?)$"), "0" end
    H, M = tonumber(H), tonumber(M)
    if not H or H > 23 or M > 59 then return nil end
    return H, M
end

-- Datum + Uhrzeit -> Zeitstempel; ohne Jahr gilt der nächste passende Termin
local function ParseDate(dayStr, clockStr)
    local d, m, y = ParseDay(dayStr)
    if not d then return nil, "date" end
    local H, M = ParseClock(clockStr)
    if not H then return nil, "time" end
    local function Make(year)
        local t = time({ year = year, month = m, day = d, hour = H, min = M })
        local check = date("*t", t)
        if check.day ~= d or check.month ~= m then return nil end   -- z. B. 31.02.
        return t
    end
    local t = Make(y or tonumber(date("%Y")))
    if not t then return nil, "date" end
    if not y and t < time() then t = Make(tonumber(date("%Y")) + 1) or t end
    return t
end

local function UpcomingEvents()
    ns.RollEvents()
    local list, cutoff = {}, Now() - 3 * 3600 -- 3 h nach Beginn noch sichtbar
    for _, e in pairs(DB()) do
        if e.title and not e.deleted and e.t > cutoff then list[#list + 1] = e end
    end
    table.sort(list, function(a, b) return a.t < b.t end)
    return list
end

local function CountSignups(e)
    local c = { yes = 0, maybe = 0, no = 0 }
    for _, s in pairs(e.signups) do c[s.s] = (c[s.s] or 0) + 1 end
    return c
end

---------------------------------------------------------------------
-- UI: Reiter "Events"
---------------------------------------------------------------------
local page = ns.AddTab("Events", 30)

-- Beim Öffnen die Events der anderen abfragen (höchstens alle 2 Minuten)
local lastAsk = 0
page:HookScript("OnShow", function()
    if GetTime() - lastAsk < 120 then return end
    lastAsk = GetTime()
    Queue("EVQ", nil, "1")
end)

-- Neue Events, die man noch nicht gesehen hat: Markierung am Reiter + Hinweisfenster
do   -- eigener Block: Lua erlaubt nur 200 lokale Variablen je Datei-Ebene
local fresh, timer = {}, nil

local function UnseenCount()
    local n, now = 0, Now()
    for _, e in pairs(DB()) do
        if e.unseen and (e.deleted or not e.title or e.t <= now) then e.unseen = nil end
        if e.unseen then n = n + 1 end
    end
    return n
end

function ns.UpdateEventBadge()
    if not GuildPrideDB then return end
    local n = UnseenCount()
    ns.SetTabBadge(page, n > 0 and ("(" .. L["Neu"] .. ")") or nil)
end

StaticPopupDialogs["GUILDPRIDE_NEW_EVENT"] = {
    text = "%s",
    button1 = L["Ansehen"], button2 = L["Später"],
    OnAccept = function() ns.OpenTab(page) end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
}

local function ShowFresh()
    timer = nil
    if InCombatLockdown() then return end   -- nach dem Kampf (PLAYER_REGEN_ENABLED)
    local list = {}
    for _, e in ipairs(fresh) do
        if e.unseen and not e.deleted then list[#list + 1] = e end
    end
    wipe(fresh)
    if #list == 0 or page:IsVisible() then return end
    table.sort(list, function(a, b) return a.t < b.t end)
    local lines = {}
    for i = 1, math.min(#list, 3) do
        lines[#lines + 1] = ("|cffffd100%s|r – %s"):format(list[i].title, ns.FormatDate(list[i].t, "short"))
    end
    if #list > 3 then lines[#lines + 1] = (L["… und %d weitere"]):format(#list - 3) end
    local head = #list == 1 and L["Neues Gildenevent"] or (L["%d neue Gildenevents"]):format(#list)
    if GuildPrideDB.sound then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
    if GuildPrideDB.popup then
        StaticPopup_Show("GUILDPRIDE_NEW_EVENT", head .. "\n\n" .. table.concat(lines, "\n"))
    end
end

-- Mehrere Events kommen beim Login kurz hintereinander: gesammelt melden
function ns.NoteNewEvent(e)
    fresh[#fresh + 1] = e
    ns.UpdateEventBadge()
    if not timer then timer = C_Timer.NewTimer(4, ShowFresh) end
end

local after = CreateFrame("Frame")
after:RegisterEvent("PLAYER_REGEN_ENABLED")
after:RegisterEvent("PLAYER_LOGIN")
after:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        -- Vom letzten Mal noch ungesehen? Markierung gleich zeigen
        C_Timer.After(2, ns.UpdateEventBadge)
    elseif #fresh > 0 and not timer then
        timer = C_Timer.NewTimer(2, ShowFresh)
    end
end)

-- Reiter geöffnet: alles gesehen
page:HookScript("OnShow", function()
    local any = false
    for _, e in pairs(DB()) do
        if e.unseen then e.unseen = nil; any = true end
    end
    wipe(fresh)
    StaticPopup_Hide("GUILDPRIDE_NEW_EVENT")
    if any then ns.UpdateEventBadge() end
end)
end
local selected
local ROWS = 6
local rows = {}

for i = 1, ROWS do
    local b = CreateFrame("Button", nil, page)
    b:SetSize(650, 24)
    b:SetPoint("TOPLEFT", 0, -(i - 1) * 25)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.when = b:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    b.when:SetPoint("LEFT", 6, 0)
    b.title = b:CreateFontString(nil, "OVERLAY", "GPFont_Normal")
    b.title:SetPoint("LEFT", 110, 0)
    b.info = b:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    b.info:SetPoint("RIGHT", -6, 0)
    -- Spalte Dungeon/Raid mit Gruppengröße
    b.kind = b:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    b.kind:SetPoint("RIGHT", -100, 0); b.kind:SetWidth(110); b.kind:SetJustifyH("LEFT")
    b:SetScript("OnClick", function(self) selected = self.event and self.event.id; page:Refresh() end)
    rows[i] = b
end

local empty = page:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
empty:SetPoint("TOP", 0, -60)
empty:SetText(L["Keine anstehenden Events."])

-- Detailbereich
local detail = CreateFrame("Frame", nil, page, "BackdropTemplate")
detail:SetPoint("TOPLEFT", 0, -ROWS * 25 - 8)
detail:SetPoint("BOTTOMRIGHT", 0, 34)
detail:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
ns.DarkPanel(detail, 0.20, 0.16, 0.13, 0.40)

local dTitle = detail:CreateFontString(nil, "OVERLAY", "GPFont_Large")
dTitle:SetPoint("TOPLEFT", 8, -8)
local dWhen = detail:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
dWhen:SetPoint("TOPLEFT", dTitle, "BOTTOMLEFT", 0, -4)
local dDesc = detail:CreateFontString(nil, "OVERLAY", "GPFont_Text")
dDesc:SetPoint("TOPLEFT", dWhen, "BOTTOMLEFT", 0, -6)
dDesc:SetWidth(620); dDesc:SetJustifyH("LEFT")
local dPeople = detail:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
dPeople:SetPoint("TOPLEFT", dDesc, "BOTTOMLEFT", 0, -8)
dPeople:SetWidth(620); dPeople:SetJustifyH("LEFT"); dPeople:SetSpacing(3)

local function Btn(text, w, anchor, x, onClick)
    local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    b:SetSize(w, 24); b:SetText(text)
    b:SetPoint("BOTTOMLEFT", anchor or page, anchor and "BOTTOMRIGHT" or "BOTTOMLEFT", x or 0, 0)
    b:SetScript("OnClick", onClick)
    return b
end

local function Sel() return selected and DB()[selected] end
local bYes   = Btn(L["Zusagen"], 90, nil, 0, function() if Sel() then SignUp(Sel(), "yes") end end)
local bMaybe = Btn(L["Vielleicht"], 90, bYes, 4, function() if Sel() then SignUp(Sel(), "maybe") end end)
local bNo    = Btn(L["Absagen"], 90, bMaybe, 4, function() if Sel() then SignUp(Sel(), "no") end end)
local bDel   = Btn(L["Löschen"], 80, bNo, 20, function()
    if Sel() then StaticPopup_Show("GUILDPRIDE_DELETE_EVENT", Sel().title, nil, Sel()) end
end)
local bNew   = Btn(L["Neues Event"], 110, bDel, 8, function() ns.ShowCreateDialog() end)
local bAttend = Btn(L["Anwesenheit"], 110, bNew, 8, function() end)   -- Klick siehe unten

-- Rollenwahl (oben rechts im Detailbereich)
local roleBtns = {}
local roleLabel = detail:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
for i, key in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
    local b = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    b:SetSize(58, 20)
    b:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -8 - (3 - i) * 62, -8)
    b:SetText(ROLES[key].label)
    b:SetScript("OnClick", function()
        GuildPrideDB.role = key
        local e = Sel()
        local mine = e and e.signups[Me()]
        if mine and mine.s ~= "no" then SignUp(e, mine.s) else page:Refresh() end
    end)
    roleBtns[key] = b
end
roleLabel:SetPoint("RIGHT", roleBtns.TANK, "LEFT", -6, 0)
roleLabel:SetText(L["Meine Rolle:"])

-- Offiziers-Notiz bearbeiten
local bNote = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
bNote:SetSize(140, 22)
bNote:SetPoint("BOTTOMRIGHT", -8, 8)
bNote:SetText(L["Notiz bearbeiten"])
bNote:SetScript("OnClick", function()
    if Sel() then StaticPopup_Show("GUILDPRIDE_EVENT_NOTE", nil, nil, Sel()) end
end)

-- Event bearbeiten (oben rechts neben „Aufstellung …“)
local bEdit = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
bEdit:SetSize(100, 22)
bEdit:SetText(L["Bearbeiten"])
bEdit:SetScript("OnClick", function() if Sel() and ns.ShowEditDialog then ns.ShowEditDialog(Sel()) end end)

-- Alle Zugesagten einladen: erst bis zu 4 in die Gruppe, dann zum Schlachtzug
-- umwandeln und den Rest einladen (Umwandeln geht erst mit bestehender Gruppe)
local InviteToGroup = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
local ConvertToRaidFn = (C_PartyInfo and C_PartyInfo.ConvertToRaid) or ConvertToRaid

local function InviteAttendees(e)
    local names = {}
    for name, s in pairs(e.signups) do
        if s.s == "yes" and name ~= Me() and not UnitInParty(Ambiguate(name, "none")) then
            names[#names + 1] = name
        end
    end
    if #names == 0 then ns.Print(L["Keine weiteren Zusagen zum Einladen."]); return end
    table.sort(names)
    local first = IsInRaid() and #names or math.min(#names, 4)
    for i = 1, first do InviteToGroup(names[i]) end
    ns.Print((L["%d Spieler eingeladen."]):format(first))
    if first < #names then
        C_Timer.After(2, function()
            if not IsInRaid() and ConvertToRaidFn then ConvertToRaidFn() end
            C_Timer.After(1.5, function()
                for i = first + 1, #names do InviteToGroup(names[i]) end
                ns.Print((L["%d Spieler eingeladen."]):format(#names - first))
            end)
        end)
    end
end

local bInvite = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
bInvite:SetSize(170, 22)
bInvite:SetPoint("RIGHT", bNote, "LEFT", -6, 0)
bInvite:SetText(L["Alle Zugesagten einladen"])
bInvite:SetScript("OnClick", function() if Sel() then InviteAttendees(Sel()) end end)

-- Raid-Aufstellung (GuildPrideRoster.lua): Offiziere teilen ein, alle sehen sie
local bRoster = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
bRoster:SetSize(130, 22)
-- oben rechts unter "Meine Rolle" (unten ist die Knopfreihe schon voll)
bRoster:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -8, -34)
bRoster:SetText(L["Aufstellung …"])
bRoster:SetScript("OnClick", function() if Sel() and ns.ShowRoster then ns.ShowRoster(Sel()) end end)
bEdit:SetPoint("RIGHT", bRoster, "LEFT", -6, 0)

---------------------------------------------------------------------
-- Anwesenheit: wer zugesagt hat und wer wirklich in der Gruppe war.
-- Nur lokal gespeichert, je Gilde: ["id:t"] = { title, t, yes, present }
---------------------------------------------------------------------
local function Attendance() return ns.GuildTable("attendance") end

local function GroupNames()
    local out = {}
    local realm = GetNormalizedRealmName() or ""
    local n = GetNumGroupMembers()
    for i = 1, n do
        local unit = IsInRaid() and ("raid" .. i) or (i == n and "player" or ("party" .. i))
        -- Forever: Der zweite Wert von UnitFullName ist der Nachname
        local name, r = (ns.IS_FOREVER and UnitFullName or UnitName)(unit)
        if name and not (issecretvalue and issecretvalue(name)) then
            out[ns.Normalize(name .. "-" .. ((r and r ~= "") and r or realm))] = true
        end
    end
    out[Me()] = true
    return out
end

local function RecordAttendance(e, quiet)
    if not IsInGroup() then
        if not quiet then ns.Print(L["Du bist in keiner Gruppe – Anwesenheit kann nicht erfasst werden."]) end
        return
    end
    local rec = { title = e.title, t = e.t, yes = {}, present = {}, at = Now() }
    for name, s in pairs(e.signups) do
        if s.s == "yes" then rec.yes[#rec.yes + 1] = name end
    end
    for name in pairs(GroupNames()) do rec.present[#rec.present + 1] = name end
    Attendance()[e.id .. ":" .. e.t] = rec
    if not quiet then ns.Print((L["Anwesenheit für |cffffd100%s|r erfasst (%d da)."]):format(e.title, #rec.present)) end
end

-- Übersicht: je Spieler Zusagen, davon da, Quote
local function AttendanceText()
    local stats, events = {}, 0
    for _, rec in pairs(Attendance()) do
        events = events + 1
        local here = {}
        for _, n in ipairs(rec.present) do here[n] = true end
        for _, n in ipairs(rec.yes) do
            local s = stats[n] or { yes = 0, came = 0 }
            s.yes = s.yes + 1
            if here[n] then s.came = s.came + 1 end
            stats[n] = s
        end
    end
    if events == 0 then return L["|cff888888Noch nichts erfasst. Das passiert 10 Min. nach Beginn automatisch (Ersteller oder Offizier in der Gruppe).|r"] end
    local list = {}
    for n, s in pairs(stats) do list[#list + 1] = { n = n, s = s } end
    table.sort(list, function(a, b)
        local qa, qb = a.s.came / a.s.yes, b.s.came / b.s.yes
        if qa ~= qb then return qa > qb end
        return a.n < b.n
    end)
    local parts = {}
    for _, x in ipairs(list) do
        local q = math.floor(x.s.came / x.s.yes * 100 + 0.5)
        local col = q >= 75 and "|cff40ff40" or (q >= 50 and "|cffffd100" or "|cffff6060")
        parts[#parts + 1] = ("%s %s%d/%d (%d %%)|r"):format(Ambiguate(x.n, "guild"), col, x.s.came, x.s.yes, q)
    end
    return (L["Erfasste Events: %d · da / zugesagt (Quote)"]):format(events) .. "\n" .. table.concat(parts, "  ·  ")
end

local attendView = false
local bRecord = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
bRecord:SetSize(160, 22)
bRecord:SetPoint("RIGHT", bInvite, "LEFT", -6, 0)
bRecord:SetText(L["Anwesenheit erfassen"])
bRecord:SetScript("OnClick", function() if Sel() then RecordAttendance(Sel()) end end)

-- Aufstellung: bis 5 Spieler 1/1/3, sonst Schlachtzug mit 2 Tanks und
-- einem Heiler je 5 Spieler
-- Dungeon/Raid eines Events (nil bei normalen Events)
local function InstOf(e) return e and ns.Instances and ns.Instances.Find(e.kind, e.inst) end
local KIND_COLOR = { dungeon = "|cff66ccff", raid = "|cffff8040" }
local function KindCell(e)
    local x = InstOf(e)
    if not x then return "|cff888888" .. L["Event"] .. "|r" end
    return ("%s%s|r |cff999999· %d|r"):format(KIND_COLOR[x.kind], ns.Instances.KindLabel(x.kind), x.size)
end

local function Lineup(roleCount, total, size)
    local need
    if size then need = ns.Instances.Need(size); total = size
    elseif total <= 5 then need = { TANK = 1, HEALER = 1, DAMAGER = 3 }
    else
        local heal = math.ceil(total / 5)
        need = { TANK = 2, HEALER = heal, DAMAGER = math.max(total - 2 - heal, 0) }
    end
    local parts = {}
    for _, key in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
        local have, want = roleCount[key], need[key]
        local col = have >= want and "|cff40ff40" or "|cffff6060"
        parts[#parts + 1] = ("%s%s %s%d/%d|r"):format(ROLES[key].color, ROLES[key].label, col, have, want)
    end
    return (L["Aufstellung (%s): %s"]):format(total <= 5 and L["Gruppe"] or L["Schlachtzug"], table.concat(parts, " · "))
end

StaticPopupDialogs["GUILDPRIDE_EVENT_NOTE"] = {
    text = L["Offiziers-Notiz (z. B. Treffpunkt, benötigte Rollen):"],
    button1 = SAVE or L["Speichern"], button2 = CANCEL,
    hasEditBox = true, maxLetters = 100, editBoxWidth = 320,
    OnShow = function(self, e)
        local eb = self.editBox or self.EditBox
        eb:SetText(e.note or ""); eb:SetFocus()
    end,
    OnAccept = function(self, e)
        local eb = self.editBox or self.EditBox
        SetNote(e, strtrim(eb:GetText()))
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        SetNote(p.data, strtrim(self:GetText())); p:Hide()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

StaticPopupDialogs["GUILDPRIDE_DELETE_EVENT"] = {
    text = L["Event \"%s\" wirklich löschen?"],
    button1 = YES, button2 = NO,
    OnAccept = function(_, e) DeleteEvent(e); selected = nil end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

bAttend:SetScript("OnClick", function() attendView = not attendView; page:Refresh() end)

function page:Refresh()
    local list = UpcomingEvents()
    empty:SetShown(#list == 0)
    for i, b in ipairs(rows) do
        local e = list[i]
        b.event = e
        b:SetShown(e ~= nil)
        if e then
            local c = CountSignups(e)
            local mine = e.signups[Me()]
            b.when:SetText(ns.FormatDate(e.t, "short"))
            b.title:SetText(e.title .. (e.rep and ("  |cff999999(" .. L["jede Woche"] .. ")|r") or ""))
            b.kind:SetText(KindCell(e))
            b.info:SetText(("%s%d|r / %s%d|r%s"):format(STATUS.yes.color, c.yes, STATUS.maybe.color, c.maybe,
                mine and ("  " .. STATUS[mine.s].color .. "●|r") or ""))
            b.bg:SetColorTexture(1, 0.82, 0, e.id == selected and 0.18 or (i % 2 == 0 and 0.04 or 0))
        end
    end

    local e = Sel()
    if e and (e.deleted or not e.title) then e, selected = nil, nil end
    if not CanManage() then attendView = false end
    detail:SetShown(e ~= nil or attendView)
    bYes:SetEnabled(e ~= nil); bMaybe:SetEnabled(e ~= nil); bNo:SetEnabled(e ~= nil)
    bDel:SetShown(CanManage() and e ~= nil)
    bNew:SetShown(CanManage())
    bAttend:SetShown(CanManage())
    if attendView then bAttend:LockHighlight() else bAttend:UnlockHighlight() end

    -- Anwesenheits-Übersicht im Detailbereich
    local eventOnly = not attendView
    for _, b in pairs(roleBtns) do b:SetShown(eventOnly) end
    roleLabel:SetShown(eventOnly)
    bRecord:SetShown(eventOnly and CanManage())
    if attendView then
        dTitle:SetText(L["Anwesenheit"])
        dWhen:SetText(L["Nur auf diesem Rechner gespeichert."])
        dDesc:SetText("")
        dPeople:SetText(AttendanceText())
        bNote:Hide(); bInvite:Hide(); bEdit:Hide()
        return
    end
    if not e then return end

    dTitle:SetText(e.title)
    dWhen:SetText((L["%s · erstellt von %s"]):format(ns.FormatDate(e.t, "long"), Ambiguate(e.creator or "?", "guild"))
        .. (e.rep and (" · " .. L["jede Woche"]) or ""))
    local descText = e.desc ~= "" and e.desc or L["|cff888888Keine Beschreibung.|r"]
    if e.note and e.note ~= "" then
        descText = descText .. L["\n|cffff7d0aOffiziers-Notiz:|r "] .. e.note
    end
    local inst = InstOf(e)
    if inst then
        descText = ("%s%s: %s|r · %s · %s\n"):format(KIND_COLOR[inst.kind], ns.Instances.KindLabel(inst.kind), inst.name,
            (L["%d Spieler"]):format(inst.size), (L["Stufe %s"]):format(inst.level)) .. descText
    end
    dDesc:SetText(descText)
    bNote:SetShown(CanManage())
    bInvite:SetShown(CanManage())
    bEdit:SetShown(CanManage() or e.creator == Me())
    bRoster:SetShown(e ~= nil and not attendView and (CanManage() or (e.layout ~= nil and next(e.layout) ~= nil)))

    local myRole = MyRole()
    for key, b in pairs(roleBtns) do
        if key == myRole then b:LockHighlight() else b:UnlockHighlight() end
    end

    local groups = { yes = {}, maybe = {}, no = {} }
    local roleCount = { TANK = 0, HEALER = 0, DAMAGER = 0 }
    for name, s in pairs(e.signups) do
        local label = Ambiguate(name, "guild")
        if s.r and ROLES[s.r] and s.s ~= "no" then
            label = ("%s %s(%s)|r"):format(label, ROLES[s.r].color, ROLES[s.r].short)
            if s.s == "yes" then roleCount[s.r] = roleCount[s.r] + 1 end
        end
        table.insert(groups[s.s], label)
    end
    local lines = {
        (L["Zusagen nach Rolle: %sTanks %d|r · %sHeiler %d|r · %sDD %d|r"]):format(
            ROLES.TANK.color, roleCount.TANK, ROLES.HEALER.color, roleCount.HEALER,
            ROLES.DAMAGER.color, roleCount.DAMAGER),
    }
    if #groups.yes > 0 or inst then lines[#lines + 1] = Lineup(roleCount, #groups.yes, inst and inst.size) end
    for _, key in ipairs({ "yes", "maybe", "no" }) do
        table.sort(groups[key])
        lines[#lines + 1] = ("%s%s (%d):|r %s"):format(STATUS[key].color, STATUS[key].label, #groups[key],
            #groups[key] > 0 and table.concat(groups[key], ", ") or "–")
    end
    dPeople:SetText(table.concat(lines, "\n"))
end

-- für GuildPrideEventDialog.lua
ns.EventsX = { CanManage = CanManage, Clean = Clean, CreateEvent = CreateEvent, EditEvent = EditEvent,
    InstOf = InstOf, Me = Me, ParseDate = ParseDate }

---------------------------------------------------------------------
-- Sync beim Login + Erinnerung 15 Min. vorher
---------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    -- nach dem Kanalbeitritt (15 s), damit die Antworten über den Kanal kommen
    C_Timer.After(20, function() Queue("REQ", nil, "1") end)
    -- Noch einmal nach 2 Min.: Bis dahin sind meist mehr Mitglieder online, und
    -- weitergereichte Events brauchen zwei Melder, bevor sie angenommen werden
    C_Timer.After(120, function() Queue("REQ", nil, "1") end)
end)

C_Timer.NewTicker(30, function()
    if not GuildPrideDB then return end
    local now = Now()
    ns.RollEvents()
    for _, e in pairs(DB()) do
        -- 10 Min. nach Beginn Anwesenheit erfassen (Ersteller bzw. Offizier in der Gruppe)
        if e.title and not e.deleted and now >= e.t + 600 and now < e.t + 3 * 3600 and IsInGroup()
           and (e.creator == Me() or CanManage()) and not Attendance()[e.id .. ":" .. e.t] then
            RecordAttendance(e, true)
        end
        -- Nachzügler: bis zwei Stunden nach Beginn alle 10 Minuten ergänzen
        local rec = e.title and not e.deleted and Attendance()[e.id .. ":" .. e.t]
        if rec and now < e.t + 2 * 3600 and IsInGroup() and (e.creator == Me() or CanManage()) and now - (rec.at or 0) >= 600 then
            local known = {}
            for _, n in ipairs(rec.present) do known[n] = true end
            for n in pairs(GroupNames()) do if not known[n] then rec.present[#rec.present + 1] = n end end
            rec.at = now
        end
        -- Ersteller ohne Gruppe: einmal sagen, dass nichts erfasst wird
        if e.title and not e.deleted and not rec and e.creator == Me() and not IsInGroup()
           and now >= e.t + 900 and now < e.t + 3600 and e.attHint ~= e.t then
            e.attHint = e.t
            ns.Print((L["Anwesenheit für „%s“ wird erst erfasst, wenn du oder ein Offizier in der Gruppe ist."]):format(e.title))
        end
        local mine = e.signups and e.signups[Me()]
        local lead = (tonumber(GuildPrideDB.remindMin) or 15) * 60   -- 0 = keine Erinnerung
        if e.title and not e.deleted and mine and mine.s ~= "no" and not e.reminded
           and lead > 0 and e.t - now <= lead and e.t - now > 0 then
            e.reminded = true
            RaidNotice_AddMessage(RaidWarningFrame,
                (L["%s %s beginnt in %d Min.!"]):format(ns.IconString(20), e.title, math.ceil((e.t - now) / 60)),
                ChatTypeInfo["GUILD"])
            if GuildPrideDB.sound then PlaySound(SOUNDKIT.RAID_WARNING) end
        end
    end
end)
