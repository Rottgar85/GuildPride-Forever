-- GuildPride: Abwesenheiten
-- Mitglieder melden sich von Tag x bis Tag y ab (optional mit Grund).
-- Gildenleitung und Offiziere sehen alle Abmeldungen in einer eigenen Liste
-- (Reiter Verwaltung › Abwesenheiten oder /gp abwesenheiten).
--   ABS: id, ver, wer, von, bis, gelöscht (0/1), grund   (Tage als JJJJMMTT)
--   ABQ: Anfrage beim Einloggen -> Antwort per Flüstern
-- Vertrauen: Eintrag direkt vom Betroffenen oder von einem Offizier zählt sofort,
-- weitergegebene Einträge anderer Mitglieder erst bei zwei gleichen Meldungen.
-- Hinweis: Die Daten laufen wie beim Schwarzen Brett über den Gilden-Addonkanal;
-- angezeigt wird die Gesamtliste nur Offizieren (kein Geheimnisschutz).
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP

local Absence = {}
ns.Absence = Absence
local MAX_REASON, MAX_DAYS, KEEP_PAST_DAYS = 60, 366, 7

local function DB() return ns.GuildTable("absence") end   -- [id] = { who, from, to, reason, ver, deleted }
local function Me() return ns.Me() end
local function Now() return GetServerTime() end
local function Clean(s, max) return (tostring(s or ""):gsub("|", ""):gsub("[%c]", " ")):sub(1, max) end
local function IsOfficer() return ns.IsOfficer() and true or false end

---------------------------------------------------------------------
-- Tage (JJJJMMTT)
---------------------------------------------------------------------
local function Today() return tonumber(date("%Y%m%d")) end
local function DayTime(n)
    return time({ year = math.floor(n / 10000), month = math.floor(n / 100) % 100, day = n % 100, hour = 12 })
end
local function ValidDay(n)
    n = tonumber(n)
    if not n or n < 20000101 or n > 21000101 then return nil end
    local t = date("*t", DayTime(n))
    if t.year * 10000 + t.month * 100 + t.day ~= n then return nil end
    return n
end
local function DaysBetween(a, b) return math.floor((DayTime(b) - DayTime(a)) / 86400 + 0.5) end

-- "24.12.2026", "24.12.26", "24.12." oder "24.12" (ohne Jahr: nächstes Vorkommen)
local function ParseDay(s)
    s = strtrim(tostring(s or ""))
    local d, m, y = s:match("^(%d%d?)%.(%d%d?)%.?(%d*)$")
    if not d then return nil end
    d, m = tonumber(d), tonumber(m)
    local today = Today()
    if y == "" then
        y = math.floor(today / 10000)
        if y * 10000 + m * 100 + d < today then y = y + 1 end
    else
        y = tonumber(y); if y < 100 then y = y + 2000 end
    end
    return ValidDay(y * 10000 + m * 100 + d)
end
Absence.ParseDay = ParseDay

local function FmtDay(n)
    local t = DayTime(n)
    if ns.IS_GERMAN then return date("%d.%m.%Y", t) end
    return date("%d %b %Y", t)
end
Absence.FmtDay = FmtDay

---------------------------------------------------------------------
-- Daten
---------------------------------------------------------------------
-- Alte (seit über 7 Tagen vorbei) und gelöschte Einträge nach einer Weile entfernen
local function Prune()
    local db, today = DB(), Today()
    for id, e in pairs(db) do
        if (e.to or 0) < today and DaysBetween(e.to, today) > KEEP_PAST_DAYS then db[id] = nil end
    end
end

-- Liste aktiver Einträge, sortiert nach Beginn. who = nur diese Person
function Absence.List(who, withPast)
    local out, today = {}, Today()
    for id, e in pairs(DB()) do
        if not e.deleted and (not who or e.who == who) and (withPast or e.to >= today) then
            out[#out + 1] = { id = id, who = e.who, from = e.from, to = e.to, reason = e.reason }
        end
    end
    table.sort(out, function(a, b)
        if a.from ~= b.from then return a.from < b.from end
        return a.who < b.who
    end)
    return out
end

-- Heute abwesende Mitglieder (Namen)
function Absence.AwayToday()
    local names, today = {}, Today()
    for _, e in ipairs(Absence.List()) do
        if e.from <= today and e.to >= today then names[#names + 1] = Ambiguate(e.who, "guild") end
    end
    return names
end

local function Send(target, id)
    local e = DB()[id]
    if not e then return end
    ns.Queue("ABS", target, id, e.ver, e.who, e.from, e.to, e.deleted and 1 or 0, e.reason or "")
end

local function Apply(id, ver, who, from, to, deleted, reason)
    local db = DB()
    local old = db[id]
    if old and ver <= (old.ver or 0) then return false end
    db[id] = { who = who, from = from, to = to, deleted = deleted or nil,
               reason = (reason and reason ~= "") and reason or nil, ver = ver }
    return true, old == nil
end

local function Refresh()
    if ns.RefreshUI then ns.RefreshUI() end
    if Absence.RefreshWindows then Absence.RefreshWindows() end
end

ns.On("ABS", function(payload, sender)
    if sender == Me() then return end
    local a = { strsplit(SEP, payload) }
    local id, ver, who = Clean(a[1], 90), ns.Stamp(a[2]), Clean(a[3], 60)
    local from, to = ValidDay(a[4]), ValidDay(a[5])
    if id == "" or ver == 0 or who == "" or not from or not to or from > to then return end
    if id:sub(1, #who + 1) ~= who .. "-" then return end
    if DaysBetween(from, to) > MAX_DAYS then return end
    if not ns.IsGuildMember(who) then return end
    -- Direkt vom Betroffenen oder von einem Offizier: sofort; sonst bestätigt
    if not ns.IsDirect(sender, who) and not ns.IsOfficerName(sender)
        and not ns.Confirmed("ABS\030" .. payload, sender) then return end
    local deleted = a[6] == "1"
    local ok, new = Apply(id, ver, who, from, to, deleted, Clean(a[7], MAX_REASON))
    if not ok then return end
    -- Offiziere bekommen neue Abmeldungen einmal im Chat angezeigt
    if new and not deleted and IsOfficer() and to >= Today() and ns.IsDirect(sender, who) then
        ns.Print((L["%s meldet sich ab: %s – %s"]):format(Ambiguate(who, "guild"), FmtDay(from), FmtDay(to)))
    end
    Refresh()
end)

ns.On("ABQ", function(_, sender)
    if sender == Me() then return end
    local ids = {}
    for id, e in pairs(DB()) do
        -- eigene Einträge immer, fremde nur als Offizier weitergeben (weniger Verkehr)
        if e.who == Me() or IsOfficer() then ids[#ids + 1] = id end
    end
    if #ids == 0 then return end
    C_Timer.After(1 + math.random() * 5, function()
        for _, id in ipairs(ids) do Send(sender, id) end
    end)
end)

---------------------------------------------------------------------
-- Aktionen
---------------------------------------------------------------------
-- Rückgabe: true oder false, Grund ("datum", "reihenfolge", "vorbei", "lang")
function Absence.Add(fromText, toText, reason)
    local from, to = ParseDay(fromText), ParseDay(toText ~= "" and toText or fromText)
    if not from or not to then return false, "datum" end
    if from > to then return false, "reihenfolge" end
    if to < Today() then return false, "vorbei" end
    if DaysBetween(from, to) > MAX_DAYS then return false, "lang" end
    local id = Me() .. "-" .. Now() .. "-" .. math.random(1000, 9999)
    Apply(id, Now(), Me(), from, to, false, strtrim(Clean(reason, MAX_REASON)))
    Send(nil, id)
    Refresh()
    return true
end

-- Eigene Einträge löschen; Offiziere dürfen jeden löschen
function Absence.Remove(id)
    local e = DB()[id]
    if not e or (e.who ~= Me() and not IsOfficer()) then return end
    Apply(id, math.max(Now(), (e.ver or 0) + 1), e.who, e.from, e.to, true, e.reason)
    Send(nil, id)
    Refresh()
end

---------------------------------------------------------------------
-- Fenster (im GuildPride-Look über ns.SkinWindow)
---------------------------------------------------------------------
local function MakeWindow(name, title, w, h)
    local f = CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(w, h); f:SetPoint("CENTER", 0, 60); f:SetFrameStrata("DIALOG")
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, name)
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("TOP", 0, -5); t:SetText(title)
    f:Hide()
    return f
end

local function Label(parent, text, x, y, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GPFont_TextSmall")
    fs:SetPoint("TOPLEFT", x, y); fs:SetJustifyH("LEFT"); fs:SetText(text)
    return fs
end

local function Box(parent, w, x, y, max)
    local b = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    b:SetSize(w, 22); b:SetPoint("TOPLEFT", x, y)
    b:SetAutoFocus(false); b:SetMaxLetters(max)
    b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    b:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return b
end

-- Scrollbare Zeilenliste mit "Löschen"-Knopf je Zeile
local function RowList(parent, x, y, w, h, rowH, onDelete)
    local scroll = ns.NewScroll(parent)
    scroll:SetPoint("TOPLEFT", x, y); scroll:SetSize(w, h)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(w, 1); scroll:SetScrollChild(child)
    child.rows = {}
    function child:Set(entries, render)
        for i, e in ipairs(entries) do
            local r = self.rows[i]
            if not r then
                r = CreateFrame("Frame", nil, self)
                r:SetSize(w, rowH); r:SetPoint("TOPLEFT", 0, -(i - 1) * rowH)
                r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
                r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
                r.text = r:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
                r.text:SetPoint("LEFT", 6, 0); r.text:SetPoint("RIGHT", -96, 0)
                r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
                r.del = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
                r.del:SetSize(86, 20); r.del:SetPoint("RIGHT", -4, 0); r.del:SetText(L["Entfernen"])
                r.del:SetScript("OnClick", function(btn) onDelete(btn:GetParent().id) end)
                r:EnableMouse(true)
                r:SetScript("OnEnter", function(row)
                    if not row.reason then return end
                    GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
                    GameTooltip:SetText(row.reason, 1, 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                r:SetScript("OnLeave", function() GameTooltip:Hide() end)
                self.rows[i] = r
            end
            r.id, r.reason = e.id, e.reason
            r.text:SetText(render(e))
            r.del:SetShown(e.canDelete ~= false)
            r:Show()
        end
        for i = #entries + 1, #self.rows do self.rows[i]:Hide() end
        self:SetHeight(math.max(1, #entries * rowH))
    end
    return child
end

local function Status(e)
    local today = Today()
    if e.to < today then return "|cff888888" .. L["vorbei"] .. "|r" end
    if e.from <= today then
        local left = DaysBetween(today, e.to)
        return "|cffff9040" .. (left == 0 and L["abwesend (bis heute)"] or (L["abwesend (noch %d Tg.)"]):format(left)) .. "|r"
    end
    return "|cff80c0ff" .. (L["in %d Tg."]):format(DaysBetween(today, e.from)) .. "|r"
end

local function Range(e)
    if e.from == e.to then return FmtDay(e.from) end
    return FmtDay(e.from) .. " – " .. FmtDay(e.to)
end

---------------------------------------------------------------------
-- 1) Für alle: selbst abmelden
---------------------------------------------------------------------
local mine
local function BuildMine()
    mine = MakeWindow("GuildPrideAbsenceFrame", L["Abwesenheit melden"], 460, 330)
    Label(mine, L["Von (TT.MM.JJJJ)"], 18, -34)
    mine.from = Box(mine, 110, 22, -50, 10)
    Label(mine, L["Bis (leer = ein Tag)"], 150, -34)
    mine.to = Box(mine, 110, 154, -50, 10)
    Label(mine, L["Grund (optional, nur Offiziere sehen ihn)"], 18, -80)
    mine.reason = Box(mine, 420, 22, -96, MAX_REASON)
    mine.from:SetScript("OnTabPressed", function() mine.to:SetFocus() end)
    mine.to:SetScript("OnTabPressed", function() mine.reason:SetFocus() end)
    local go = CreateFrame("Button", nil, mine, "UIPanelButtonTemplate")
    go:SetSize(140, 24); go:SetPoint("TOPLEFT", 290, -48); go:SetText(L["Abmelden"])
    local errors = {
        datum = L["Bitte ein Datum wie 24.12.2026 eintragen."],
        reihenfolge = L["„Bis“ liegt vor „Von“."],
        vorbei = L["Der Zeitraum liegt schon in der Vergangenheit."],
        lang = L["Höchstens ein Jahr am Stück."],
    }
    go:SetScript("OnClick", function()
        local ok, why = Absence.Add(mine.from:GetText(), mine.to:GetText(), mine.reason:GetText())
        if ok then
            mine.from:SetText(""); mine.to:SetText(""); mine.reason:SetText("")
            mine.from:ClearFocus(); mine.to:ClearFocus(); mine.reason:ClearFocus()
            ns.Print(L["Abmeldung gespeichert – die Gildenleitung sieht sie."])
        else
            ns.Print(errors[why] or errors.datum)
        end
    end)
    Label(mine, L["Meine Abmeldungen"], 18, -132, "GPFont_Text")
    mine.list = RowList(mine, 16, -152, 404, 140, 22, Absence.Remove)
    mine.empty = Label(mine, L["Keine Abmeldungen."], 22, -158)
    if ns.SkinWindow then pcall(ns.SkinWindow, mine) end
end

local function RefreshMine()
    if not mine or not mine:IsShown() then return end
    local list = Absence.List(Me())
    mine.list:Set(list, function(e)
        return Range(e) .. "  " .. Status(e) .. (e.reason and ("  |cffaaaaaa" .. e.reason .. "|r") or "")
    end)
    mine.empty:SetShown(#list == 0)
end

function Absence.ToggleMine()
    if not IsInGuild() then ns.Print(L["Du bist in keiner Gilde."]) return end
    if not mine then BuildMine() end
    if mine:IsShown() then mine:Hide() return end
    mine:Show()
    if mine.from:GetText() == "" then mine.from:SetText(date("%d.%m.%Y")) end
    RefreshMine()
end

---------------------------------------------------------------------
-- 2) Für Gildenleitung und Offiziere: Liste aller Abmeldungen
---------------------------------------------------------------------
local all
local function BuildAll()
    all = MakeWindow("GuildPrideAbsenceListFrame", L["Abwesenheiten der Gilde"], 640, 420)
    all.head = Label(all, "", 18, -32, "GPFont_MutedSmall")
    all.past = CreateFrame("CheckButton", nil, all, "UICheckButtonTemplate")
    all.past:SetSize(22, 22); all.past:SetPoint("TOPRIGHT", -150, -28)
    local pl = all:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    pl:SetPoint("LEFT", all.past, "RIGHT", 2, 0); pl:SetText(L["Vergangene zeigen"])
    all.past:SetScript("OnClick", function() Absence.RefreshWindows() end)
    all.list = RowList(all, 16, -56, 584, 340, 22, Absence.Remove)
    all.empty = Label(all, L["Niemand hat sich abgemeldet."], 22, -62)
    if ns.SkinWindow then pcall(ns.SkinWindow, all) end
end

local function RefreshAll()
    if not all or not all:IsShown() then return end
    local list = Absence.List(nil, all.past:GetChecked())
    all.list:Set(list, function(e)
        return ("|cfff0c88c%s|r  %s  %s%s"):format(Ambiguate(e.who, "guild"), Range(e), Status(e),
            e.reason and ("  |cffaaaaaa" .. e.reason .. "|r") or "")
    end)
    all.empty:SetShown(#list == 0)
    local away = Absence.AwayToday()
    all.head:SetText((L["Heute abwesend: %d  ·  Einträge: %d"]):format(#away, #list))
end

function Absence.ToggleList()
    if not IsOfficer() then ns.Print(L["Nur für Gildenleitung und Offiziere."]) return end
    if not all then BuildAll() end
    if all:IsShown() then all:Hide() return end
    all:Show(); RefreshAll()
end

function Absence.RefreshWindows() RefreshMine(); RefreshAll() end

---------------------------------------------------------------------
-- Ereignisse und Befehl
---------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
local started = false
ev:SetScript("OnEvent", function()
    if started or not GuildPrideDB then return end
    started = true
    C_Timer.After(40, function()
        if not IsInGuild() then return end
        Prune()
        ns.Queue("ABQ", nil, "1")
    end)
end)

local slash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd = strtrim(arg or ""):lower()
    if cmd == "abwesend" or cmd == "away" or cmd == "abmelden" then Absence.ToggleMine() return end
    if cmd == "abwesenheiten" or cmd == "absences" then Absence.ToggleList() return end
    return slash(arg)
end
