-- GuildPride: Testfunktionen und Tester
--
-- Neue Funktionen fragen vorher:   if ns.Feature("schluessel") then … end
-- Liste T.LIST: state "off" (niemand), "test" (nur freigeschaltete Tester) oder "all" (alle).
--
-- Freischalten: Der Entwickler trägt einen Spieler ein (/gp dev › Tester). Ist der online, bekommt er
-- eine Frage; erst mit seinem Ja wird er Tester. Der Server bürgt für den Absender: angenommen wird
-- nur Geflüstertes von Charakteren, die ns.IsMarked kennt.
--   DVT  Spielversion · 1/0 · Kennung    einladen / zurücknehmen (Entwickler → Spieler)
--   DVR  Kennung · 1/0/x · Version       ja / nein / nicht (mehr) freigeschaltet (Spieler → Entwickler)
-- Wer eingeladen ist, meldet sich mit DVR auch, wenn der Entwickler da ist (DVA, höchstens alle 9 Minuten);
-- so kommt eine Rücknahme auch auf einem Twink an. Der Entwickler speichert nur den eingetragenen Namen.
-- Kein Schutz vor Neugierigen: Der Code liegt bei allen; der Schalter verbirgt ihn nur.
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP or "\031"

local T = {}
ns.Tester = T

T.LIST = {
    { key = "probe", name = L["Probe: eine Zeile unter „Heute“ auf der Übersicht"], state = "test" },
    { key = "chatBudget", name = L["Chat-Budget: Zeilen des Addons warten, wenn zu viele auf einmal kämen"], state = "test" },
}

local function DB() return type(GuildPrideDB) == "table" and GuildPrideDB or {} end
local function IsDev() return ns.IsDev and ns.IsDev() or false end

---------------------------------------------------------------------
-- Testfunktionen
---------------------------------------------------------------------
function ns.IsTester() return DB().testerId ~= nil and DB().testFeatures == true end

function ns.Feature(key)
    for _, f in ipairs(T.LIST) do
        if f.key == key then
            if f.state == "all" then return true end
            if f.state ~= "test" then return false end
            if type(GuildPrideDB) ~= "table" then return false end
            return ns.IsTester() or (IsDev() and GuildPrideDB.devAsPlayer ~= true)
        end
    end
    return false
end

-- Vermerk für den Fehlerbericht (GuildPrideErrors.lua)
function ns.TesterMark() return ns.IsTester() and " test=yes" or "" end

local function ValidId(id) return type(id) == "string" and id:match("^%w+$") ~= nil and #id <= 20 end
local function Whisper(to, kind, ...)
    if ns.ErrorShare and ns.ErrorShare.Whisper then ns.ErrorShare.Whisper(to, kind .. ":" .. table.concat({ ... }, SEP)) end
end

---------------------------------------------------------------------
-- Spieler: Einladung, Antwort, Meldung
---------------------------------------------------------------------
local ANSWER_GAP = 540
local asked, waiting, lastReport = {}, nil, nil

local function Reply(to, gid, code) Whisper(to, "DVR", gid, code, code == "x" and "" or (ns.VERSION or "")) end
local function Changed() if ns.RefreshUI then ns.RefreshUI() end end

function T.Choose(yes, gid, to)
    DB().testerId, DB().testFeatures = gid, yes and true or false
    Reply(to, gid, yes and "1" or "0")
    if yes then ns.Print(L["Danke! Du siehst jetzt neue Funktionen vor allen anderen. Abschalten: /gp tester aus oder Einstellungen › Teilen."]) end
    Changed()
end

StaticPopupDialogs["GUILDPRIDE_TESTER"] = {
    text = L["Der Entwickler von GuildPride (%s) möchte dich als Tester freischalten. Du siehst neue Funktionen dann früher als andere; sie können noch Fehler haben.\n\nSagst du Ja, meldet sich dein GuildPride bei ihm, wenn er online ist: mit deiner Zusage, deiner Version und dem Namen des Charakters, der gerade spielt. Er speichert nur den Namen, den er eingeladen hat. Hast du das Senden von Fehlern erlaubt, steht in deinen Berichten „Tester“.\n\nJederzeit abschaltbar: Einstellungen › Teilen."],
    button1 = L["Ja, ich teste mit"], button2 = L["Nein"],
    OnAccept = function(_, data) if data then T.Choose(true, data.gid, data.to) end end,
    OnCancel = function(_, data, reason) if data and reason == "clicked" then T.Choose(false, data.gid, data.to) end end,
    timeout = 0, whileDead = true, preferredIndex = 3, wide = true,
}

local ev = CreateFrame("Frame")
local function Ask()
    if not waiting then return end
    if InCombatLockdown() then ev:RegisterEvent("PLAYER_REGEN_ENABLED"); return end
    local data = waiting
    waiting = nil
    StaticPopup_Show("GUILDPRIDE_TESTER", Ambiguate(data.to, "none"), nil, data)
end

local function OnGrant(value, sender)
    if IsDev() or not (ns.IsMarked and ns.IsMarked(sender)) then return end
    local tag, on, gid = strsplit(SEP, value)
    if tag ~= ns.CLIENT_TAG or not ValidId(gid) then return end
    if on == "0" then
        if DB().testerId == gid then
            DB().testerId, DB().testFeatures = nil, nil
            ns.Print(L["Deine Freischaltung als Tester wurde beendet. Danke fürs Testen!"])
            Changed()
        end
        Reply(sender, gid, "x")
    elseif on == "1" then
        if DB().testerId == gid then
            Reply(sender, gid, DB().testFeatures == true and "1" or "0")
        elseif not asked[gid] then
            asked[gid] = true
            waiting = { gid = gid, to = sender }
            Ask()
        end
    end
end

-- Entwickler ist da (DVA): Eingeladene melden ihren Stand
local function OnHello(value, sender)
    if value ~= ns.CLIENT_TAG or IsDev() or not ValidId(DB().testerId) then return end
    if not (ns.IsMarked and ns.IsMarked(sender)) then return end
    if lastReport and GetTime() - lastReport < ANSWER_GAP then return end
    lastReport = GetTime()
    C_Timer.After(2 + math.random() * 20, function()
        if ValidId(DB().testerId) then Reply(sender, DB().testerId, DB().testFeatures == true and "1" or "0") end
    end)
end

---------------------------------------------------------------------
-- Entwickler: Liste
---------------------------------------------------------------------
-- GuildPrideDB.devTesters[Name] = { name, gid, s = "wait"/"yes"/"no"/"revoke", t, sent, v, seen }
local function Store()
    if type(DB().devTesters) ~= "table" then DB().devTesters = {} end
    return DB().devTesters
end
local function NewId() return ("%x%06x"):format(GetServerTime(), math.random(0, 16777215)) end

-- Alle, von denen wir wissen, dass sie gerade da sind
local function Online()
    local out = {}
    for _, m in ipairs(ns.RosterList and ns.RosterList() or {}) do if m.online then out[m.full] = true end end
    for name in pairs(ns.Players and ns.Players.public or {}) do out[name] = true end
    return out
end

function T.Deliver(force)
    if not IsDev() then return end
    local online, now = Online(), GetServerTime()
    for name, e in pairs(Store()) do
        if (e.s == "wait" or e.s == "revoke") and (force or (online[name] and now - (e.sent or 0) >= ANSWER_GAP)) then
            e.sent = now
            Whisper(name, "DVT", ns.CLIENT_TAG, e.s == "revoke" and "0" or "1", e.gid)
        end
    end
end

-- Name eintragen; Schreibweise wie in der Gilden- oder Spielerliste. nil = geht nicht
function T.Add(text)
    if not IsDev() then return nil end
    text = strtrim(tostring(text or "")):gsub(" +", " ")   -- Forever: „Vorname Nachname“
    if text == "" or #text > 60 or text:find("[%c|]") then return nil end
    local name
    for full in pairs(Online()) do
        if full:lower() == text:lower() or Ambiguate(full, "none"):lower() == text:lower() then name = full end
    end
    name = name or ns.Normalize(text)
    if not name or name == ns.Me() then return nil end
    local e = Store()[name]
    if not e then
        e = { name = name, gid = NewId(), s = "wait", t = GetServerTime() }
        Store()[name] = e
        T.Deliver()
    end
    if T.Refresh then T.Refresh() end
    return e
end

-- Erneut einladen: neue Kennung, der Spieler wird wieder gefragt
function T.Invite(name)
    local e = IsDev() and Store()[name]
    if not e then return end
    e.gid, e.s, e.sent, e.t = NewId(), "wait", nil, GetServerTime()
    T.Deliver()
end

-- Zurücknehmen: bleibt in der Liste, bis es beim Spieler angekommen ist
function T.Revoke(name)
    local e = IsDev() and Store()[name]
    if not e then return end
    if e.s == "wait" and not e.sent then Store()[name] = nil
    else e.s, e.sent = "revoke", nil; T.Deliver() end
end

local function OnReply(value, sender)
    if not IsDev() then return end
    local gid, code, ver = strsplit(SEP, value)
    for name, e in pairs(Store()) do
        if e.gid == gid then
            e.seen = GetServerTime()
            if type(ver) == "string" and #ver <= 20 and ver:match("^[%d%.]+$") then e.v = ver end
            if code == "x" then
                if e.s == "revoke" then Store()[name] = nil else e.s = "no" end
            elseif e.s == "revoke" then
                Whisper(sender, "DVT", ns.CLIENT_TAG, "0", e.gid)
            elseif code == "1" or code == "0" then
                local s = code == "1" and "yes" or "no"
                if e.s ~= s then
                    e.s = s
                    ns.Print(("Tester: %s %s."):format(Ambiguate(name, "none"), s == "yes" and "testet mit" or "testet nicht (mehr) mit"))
                end
            end
            break
        end
    end
    if T.Refresh then T.Refresh() end
end

-- Aus GuildPrideErrorShare.lua (DVA kommt dort an und wird weitergereicht)
function T.OnMessage(kind, value, sender, channel)
    if kind == "DVA" then OnHello(value, sender)
    elseif channel ~= "WHISPER" then return
    elseif kind == "DVT" then OnGrant(value, sender)
    elseif kind == "DVR" then OnReply(value, sender) end
end

---------------------------------------------------------------------
-- Ereignisse und Befehl
---------------------------------------------------------------------
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent(event)
        C_Timer.After(2, Ask)
        return
    end
    if IsDev() then
        C_Timer.After(60, function() T.Deliver() end)
        C_Timer.NewTicker(300, function() T.Deliver() end)
    end
end)

local function ChatStatus()
    if not DB().testerId then return ns.Print(L["Du bist kein Tester. Der Entwickler kann dich freischalten."]) end
    ns.Print(ns.IsTester() and L["Du bist Tester: neue Funktionen sind an. /gp tester aus schaltet sie ab."]
        or L["Testfunktionen sind aus. /gp tester an schaltet sie ein."])
    for _, f in ipairs(T.LIST) do if f.state == "test" then ns.Print("  " .. f.name) end end
end
ns.Command({ "tester" }, function(rest)
    rest = strtrim(rest or ""):lower()
    if DB().testerId and (rest == "an" or rest == "on" or rest == "aus" or rest == "off") then
        DB().testFeatures = rest == "an" or rest == "on"
        T.SwitchChanged()
    end
    ChatStatus()
end)
-- Schalter geändert (Befehl oder Einstellungen): beim nächsten Mal gleich melden
function T.SwitchChanged()
    lastReport = nil
    Changed()
end

---------------------------------------------------------------------
-- Fenster des Entwicklers (/gp dev › Tester) – nur für ihn, deshalb ohne Übersetzung
---------------------------------------------------------------------
local STATE = { yes = "|cff40ff40testet|r", no = "|cffff6060hat abgelehnt|r", wait = "|cffffd100eingeladen|r", revoke = "|cff999999wird zurückgenommen|r" }
local MIN_VERSION = "2.45.0"   -- ältere Versionen kennen die Einladung noch nicht

-- Haken an: einladen. Haken aus: zurücknehmen.
function T.Toggle(name)
    if not IsDev() then return end
    local e = Store()[name]
    if not e then
        if not T.Add(name) then ns.Print("Tester: " .. tostring(name) .. " lässt sich nicht einladen.") end
    elseif e.s == "wait" or e.s == "yes" then T.Revoke(name)
    else T.Invite(name) end
end

-- Alle Zeilen: Spieler mit GuildPride, die online sind, darunter eingeladene, die gerade fehlen:
-- { name, on (Haken), text }. Die Reihenfolge hängt nicht am Haken, damit beim Klicken nichts springt.
function T.View()
    local out, seen, me = {}, {}, ns.Me()
    local function Put(name, p)
        local e = Store()[name]
        local ver = p and type(p.ver) == "string" and p.ver:match("^[%d%.]+$") or nil
        seen[name] = true
        out[#out + 1] = { name = name, online = p and true or false, guild = p and p.guild and true or false,
            ok = ver ~= nil and ns.CompareVersion(ver, MIN_VERSION) >= 0, on = e ~= nil and (e.s == "wait" or e.s == "yes"),
            text = ("%s%s|r  |cff999999%s|r  %s"):format(p and (p.guild and "|cff40ff40" or "|cffffffff") or "|cff999999", Ambiguate(name, "none"),
                p and (ver or "Version unbekannt") or "offline", e and STATE[e.s] or "") }
        local r = out[#out]
        if p and not r.ok then r.text = r.text .. "  |cff999999(fragt erst ab " .. MIN_VERSION .. ")|r" end
    end
    for _, p in ipairs(ns.Players and ns.Players.List and ns.Players.List() or {}) do
        if p.name ~= me and not p.self and not seen[p.name] then Put(p.name, p) end
    end
    for name in pairs(Store()) do if not seen[name] then Put(name, nil) end end
    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        if a.ok ~= b.ok then return a.ok end
        if a.guild ~= b.guild then return a.guild end
        return a.name < b.name
    end)
    return out
end

local function AddFrom(eb) if not T.Add(eb:GetText()) then ns.Print("Tester: Diesen Namen gibt es so nicht.") end end
StaticPopupDialogs["GUILDPRIDE_DEV_TESTER"] = {
    text = "Wen als Tester einladen? (Charaktername)",
    button1 = OKAY or "OK", button2 = CANCEL,
    hasEditBox = true, editBoxWidth = 200, maxLetters = 60,
    OnAccept = function(self) AddFrom(self.editBox or self.EditBox) end,
    EditBoxOnEnterPressed = function(eb) AddFrom(eb); eb:GetParent():Hide() end,
    EditBoxOnEscapePressed = function(eb) eb:GetParent():Hide() end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local win
function T.Refresh()
    if not win or not win:IsShown() then return end
    win.list = T.View()
    local lines, n = {}, 0
    for i, l in ipairs(win.list) do
        lines[i] = l.text
        if l.on then n = n + 1 end
    end
    win.title:SetText("Tester: " .. n)
    win.view:SetText(DB().devAsPlayer and "Ansicht: wie ein Spieler" or "Ansicht: mit Testfunktionen")
    win:SetLines(lines)
end

function T.Open()
    if not IsDev() then return end
    if not win then
        win = ns.ListWindow({ name = "GuildPrideDevTester", title = "Tester", rows = 18, width = 560,
            sub = "Haken an: einladen. Haken aus: zurücknehmen. Grün = Gilde. Mausrad blättert.",
            empty = "Gerade ist niemand mit GuildPride online." })
        for i, row in ipairs(win.rows) do
            local function Click()
                local l = win.list and win.list[i + win.offset]
                if l then T.Toggle(l.name) end
                T.Refresh()
            end
            row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.check:SetSize(20, 20); row.check:SetPoint("LEFT", 2, 0)
            row.check:SetScript("OnClick", Click)
            row.text:ClearAllPoints()
            row.text:SetPoint("LEFT", 28, 0); row.text:SetPoint("RIGHT", -4, 0)
            row:EnableMouse(true)
            row:SetScript("OnMouseUp", Click)
        end
        local paint = win.Paint
        function win:Paint()
            paint(self)
            for i, row in ipairs(self.rows) do
                local l = self.list and self.list[i + self.offset]
                row.check:SetChecked(l ~= nil and l.on)
            end
        end
        local function Button(label, x, w, fn)
            local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
            if ns.SkinButton then ns.SkinButton(b) end
            b:SetSize(w, 22); b:SetPoint("TOPLEFT", x, win.bottomY); b:SetText(label)
            b:SetScript("OnClick", fn)
            return b
        end
        Button("Name eingeben …", 14, 150, function() StaticPopup_Show("GUILDPRIDE_DEV_TESTER") end)
        win.view = Button("Ansicht", 170, 230, function()
            DB().devAsPlayer = not DB().devAsPlayer or nil
            Changed(); T.Refresh()
        end)
        win:SetScript("OnShow", function()
            win.offset = 0
            if ns.Players and ns.Players.Ask then ns.Try(ns.Players.Ask) end   -- Liste auffrischen
            T.Refresh()
            C_Timer.After(5, T.Refresh)
        end)
    end
    win:SetShown(not win:IsShown())
end
