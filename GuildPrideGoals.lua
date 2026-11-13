-- GuildPride: Gildenziele
-- Offiziere legen gemeinsame Ziele an, alle sehen den Fortschritt als Balken.
-- Arten: Mitgliederzahl (zählt das Spiel), Spieler auf Stufe X (zählt die
-- Gildenliste) und eigene Ziele, deren Stand Offiziere von Hand setzen.
--   GOL: id, ver, art, ziel, stufe, stand, gelöscht (0/1), titel
--   GOQ: Anfrage (Login) -> Antwort per Flüstern
-- Von Offizieren sofort, über andere Mitglieder erst bei zwei gleichen Meldungen.
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP

local Goals = {}
ns.Goals = Goals
local KINDS = { members = true, level = true, manual = true }
local MAX_GOALS = 30

local function DB() return ns.GuildTable("goals") end
local function Me() return ns.Me() end
local function Now() return GetServerTime() end
local function CanManage() return CanEditMOTD and CanEditMOTD() and true or false end
local function Clean(s, max) return (tostring(s or ""):gsub("[%c|]", "")):sub(1, max) end

---------------------------------------------------------------------
-- Fortschritt
---------------------------------------------------------------------
local function RosterCount(minLevel)
    local n = 0
    for i = 1, GetNumGuildMembers() do
        local name, _, _, level = GetGuildRosterInfo(i)
        if name and (not minLevel or (tonumber(level) or 0) >= minLevel) then n = n + 1 end
    end
    return n
end

function Goals.Progress(g)
    if g.kind == "members" then return math.min(RosterCount(), g.target) end
    if g.kind == "level" then return math.min(RosterCount(g.param), g.target) end
    return math.min(g.progress or 0, g.target)
end

function Goals.Describe(g)
    if g.kind == "members" then return (L["%d Mitglieder"]):format(g.target) end
    if g.kind == "level" then return (L["%d Spieler auf Stufe %d"]):format(g.target, g.param or 0) end
    return L["Eigenes Ziel"]
end

---------------------------------------------------------------------
-- Senden / Anwenden (neuere Version gewinnt)
---------------------------------------------------------------------
local function Send(g, target)
    ns.Queue("GOL", target, g.id, g.ver, g.kind, g.target, g.param or 0, g.progress or 0, g.deleted and 1 or 0, g.title or "")
end

local function Count()
    local n = 0
    for _, g in pairs(DB()) do if not g.deleted then n = n + 1 end end
    return n
end

local function Apply(id, ver, kind, target, param, progress, deleted, title)
    local g = DB()[id]
    if g and ver <= g.ver then return false end
    if not g and (deleted or Count() >= MAX_GOALS) then return false end
    g = g or { id = id }
    g.ver, g.kind, g.target, g.param, g.progress, g.deleted, g.title = ver, kind, target, param, progress, deleted, title
    DB()[id] = g
    return true
end

-- Erreicht? Gefeiert (und von Offizieren an Discord gemeldet) wird nur, wenn
-- dieser Client das Ziel in dieser Sitzung noch offen gesehen hat – sonst
-- gäbe es nach jedem Login oder beim ersten Abgleich alte Erfolgsmeldungen.
local seenOpen = {}
local function CheckDone()
    for _, g in pairs(DB()) do
        if not g.deleted and g.title then
            local reached = Goals.Progress(g) >= g.target
            if not reached then
                seenOpen[g.id] = true
                if g.doneAt and g.kind == "manual" then g.doneAt = nil end   -- von Hand zurückgesetzt
            elseif not g.doneAt then
                g.doneAt = Now()
                if seenOpen[g.id] then
                    ns.Print((L["|cff40ff40Gildenziel erreicht:|r %s"]):format(g.title))
                    if GuildPrideDB.sound then PlaySound(SOUNDKIT.READY_CHECK) end
                    if CanManage() and ns.Discord then
                        ns.Discord.Post((ns.IS_GERMAN and "Meilenstein: Gildenziel erreicht – %s" or "Milestone: guild goal reached – %s"):format(g.title))
                    end
                end
            end
        end
    end
end
Goals.CheckDone = CheckDone

ns.On("GOL", function(payload, sender)
    if sender == Me() then return end
    local a = { strsplit(SEP, payload) }
    local id, ver, kind = Clean(a[1], 80), ns.Stamp(a[2]), a[3]
    local target = ns.Num(a[4], 1, 100000)
    if id == "" or ver == 0 or not KINDS[kind] or not target then return end
    -- Ein Ziel gehört dem, dessen Name vorne in der ID steht; angelegt nur von Offizieren
    local author = id:match("^(.+)%-%d+%-%d+$")
    if not author or not ns.IsOfficerName(author) then return end
    if not ns.IsOfficerName(sender) and not ns.Confirmed("GOL\030" .. payload, sender) then return end
    local title = Clean(a[8], 60)
    if title == "" then return end
    if Apply(id, ver, kind, target, ns.Num(a[5], 0, 1000) or 0, ns.Num(a[6], 0, 100000) or 0, a[7] == "1", title) then
        CheckDone()
        if ns.RefreshUI then ns.RefreshUI() end
    end
end)

ns.On("GOQ", function(_, sender)
    if sender == Me() then return end
    C_Timer.After(math.random() * 4, function()
        for _, g in pairs(DB()) do if g.title then Send(g, sender) end end
    end)
end)

---------------------------------------------------------------------
-- Aktionen (nur Offiziere)
---------------------------------------------------------------------
function Goals.Create(title, kind, target, param)
    if not CanManage() then return end
    title = Clean(strtrim(title or ""), 60)
    target = ns.Num(target, 1, 100000)
    if title == "" or not KINDS[kind] or not target then return false end
    local id = Me() .. "-" .. Now() .. "-" .. math.random(1000, 9999)
    if not Apply(id, Now(), kind, target, ns.Num(param, 0, 1000) or 0, 0, false, title) then return false end
    Send(DB()[id])
    CheckDone()
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

local function Change(g, fn)
    if not CanManage() then return end
    fn(g)
    g.ver = math.max(Now(), g.ver + 1)
    Send(g)
    CheckDone()
    if ns.RefreshUI then ns.RefreshUI() end
end
function Goals.Step(g, d) Change(g, function(x) x.progress = math.max(0, math.min(x.target, (x.progress or 0) + d)) end) end
function Goals.Delete(g) Change(g, function(x) x.deleted = true end) end

-- Offene zuerst (nach Fortschritt), erreichte danach
function Goals.List()
    local list = {}
    for _, g in pairs(DB()) do if g.title and not g.deleted then list[#list + 1] = g end end
    table.sort(list, function(a, b)
        local da, db = a.doneAt and true or false, b.doneAt and true or false
        if da ~= db then return not da end
        local pa, pb = Goals.Progress(a) / a.target, Goals.Progress(b) / b.target
        if pa ~= pb then return pa > pb end
        return a.id < b.id
    end)
    return list
end

---------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("GUILD_ROSTER_UPDATE")
local started, lastCheck = false, 0
ev:SetScript("OnEvent", function(_, event)
    if not GuildPrideDB or not IsInGuild() then return end
    if event == "PLAYER_ENTERING_WORLD" then
        if started then return end
        started = true
        C_Timer.After(45, function() if IsInGuild() then ns.Queue("GOQ", nil, "1") end end)
    elseif GetTime() - lastCheck > 30 then
        lastCheck = GetTime()
        CheckDone()
    end
end)

---------------------------------------------------------------------
-- Reiter "Ziele"
---------------------------------------------------------------------
if not ns.AddTab then return end
local page = ns.AddTab(L["Ziele"], 65)

-- Anlegen (nur Offiziere)
local form = CreateFrame("Frame", nil, page)
form:SetPoint("TOPLEFT", 0, 0); form:SetPoint("TOPRIGHT", 0, 0); form:SetHeight(58)
local KIND_ORDER = { "members", "level", "manual" }
local KIND_LABEL = { members = L["Mitgliederzahl"], level = L["Spieler auf Stufe"], manual = L["Eigenes Ziel"] }
local newKind = "manual"

local function Box(w, x, maxLetters, numeric)
    local b = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
    b:SetSize(w, 22); b:SetPoint("TOPLEFT", x, -24)
    b:SetAutoFocus(false); b:SetMaxLetters(maxLetters)
    if numeric then b:SetNumeric(true) end
    b:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return b
end
local function Label(x, text)
    local fs = form:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    fs:SetPoint("TOPLEFT", x, -8); fs:SetText(text)
    return fs
end
Label(10, L["Neues Ziel"])
local titleBox = Box(220, 12, 60)
Label(244, L["Art"])
local kindBtn = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
kindBtn:SetSize(140, 22); kindBtn:SetPoint("TOPLEFT", 240, -24)
Label(390, L["Ziel"])
local targetBox = Box(50, 392, 6, true)
local levelLabel = Label(452, L["Stufe"])
local levelBox = Box(40, 454, 3, true)
local bCreate = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
bCreate:SetSize(100, 22); bCreate:SetPoint("TOPLEFT", 504, -24); bCreate:SetText(L["Anlegen"])
if ns.SkinButton then pcall(ns.SkinButton, kindBtn); pcall(ns.SkinButton, bCreate) end

local function ShowKind()
    kindBtn:SetText(KIND_LABEL[newKind])
    levelLabel:SetShown(newKind == "level"); levelBox:SetShown(newKind == "level")
    if newKind == "members" and titleBox:GetText() == "" then titleBox:SetText(L["Gilde wächst"]) end
end
kindBtn:SetScript("OnClick", function()
    for i, k in ipairs(KIND_ORDER) do
        if k == newKind then newKind = KIND_ORDER[i % #KIND_ORDER + 1]; break end
    end
    ShowKind()
end)
bCreate:SetScript("OnClick", function()
    local ok = Goals.Create(titleBox:GetText(), newKind, tonumber(targetBox:GetText()), tonumber(levelBox:GetText()))
    if ok then
        titleBox:SetText(""); targetBox:SetText(""); levelBox:SetText("")
        titleBox:ClearFocus(); targetBox:ClearFocus(); levelBox:ClearFocus()
    else
        ns.Print(L["Bitte Titel und Zielwert angeben (bei „Spieler auf Stufe“ auch die Stufe)."])
    end
end)
ShowKind()

local scroll = ns.NewScroll(page)
scroll:SetPoint("BOTTOMRIGHT", -26, 0)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(620, 10)
scroll:SetScrollChild(content)
local empty = page:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
empty:SetPoint("TOP", 0, -110); empty:SetWidth(560)

local rows = {}
local ROW_H = 54
local function Row(i)
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, content)
    r:SetSize(620, ROW_H - 6)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(0, 0, 0, 0.35)
    r.title = r:CreateFontString(nil, "OVERLAY", "GPFont_TextBold")
    r.title:SetPoint("TOPLEFT", 10, -6)
    r.kind = r:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    r.kind:SetPoint("LEFT", r.title, "RIGHT", 8, 0)
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetSize(380, 12); r.bar:SetPoint("BOTTOMLEFT", 10, 8)
    r.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    r.barBg = r.bar:CreateTexture(nil, "BACKGROUND"); r.barBg:SetAllPoints(); r.barBg:SetColorTexture(0.2, 0.16, 0.14, 1)
    r.value = r:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    r.value:SetPoint("LEFT", r.bar, "RIGHT", 10, 0)
    local function B(label, w)
        local b = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        b:SetSize(w, 20); b:SetText(label)
        if ns.SkinButton then pcall(ns.SkinButton, b) end
        return b
    end
    r.del = B(L["Löschen"], 70); r.del:SetPoint("RIGHT", -6, 0)
    r.plus = B("+1", 34); r.plus:SetPoint("RIGHT", r.del, "LEFT", -6, 0)
    r.minus = B("−1", 34); r.minus:SetPoint("RIGHT", r.plus, "LEFT", -4, 0)
    rows[i] = r
    return r
end

StaticPopupDialogs["GUILDPRIDE_DELETE_GOAL"] = {
    text = L["Gildenziel \"%s\" wirklich löschen?"],
    button1 = YES, button2 = NO,
    OnAccept = function(_, g) Goals.Delete(g) end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

function page:Refresh()
    local officer = CanManage()
    form:SetShown(officer)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", 0, officer and -64 or -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 0)
    local list = Goals.List()
    local ember = ns.Theme and ns.Theme().ember or { 0.9, 0.5, 0.2 }
    for i, g in ipairs(list) do
        local r = Row(i)
        local p = Goals.Progress(g)
        r.title:SetText(g.title)
        r.kind:SetText(Goals.Describe(g) .. (g.doneAt and ("  |cff40ff40" .. (L["erreicht am %s"]):format(ns.FormatDay(g.doneAt)) .. "|r") or ""))
        r.bar:SetMinMaxValues(0, g.target); r.bar:SetValue(p)
        if g.doneAt then r.bar:SetStatusBarColor(0.25, 0.8, 0.3) else r.bar:SetStatusBarColor(ember[1], ember[2], ember[3]) end
        r.value:SetText(("%d / %d  |cff999999(%d %%)|r"):format(p, g.target, math.floor(p / g.target * 100)))
        r.del:SetShown(officer)
        r.plus:SetShown(officer and g.kind == "manual"); r.minus:SetShown(officer and g.kind == "manual")
        r.plus:SetScript("OnClick", function() Goals.Step(g, 1) end)
        r.minus:SetScript("OnClick", function() Goals.Step(g, -1) end)
        r.del:SetScript("OnClick", function() StaticPopup_Show("GUILDPRIDE_DELETE_GOAL", g.title, nil, g) end)
        r:Show()
    end
    for i = #list + 1, #rows do rows[i]:Hide() end
    content:SetHeight(math.max(10, #list * ROW_H))
    empty:SetShown(#list == 0)
    empty:SetText(officer and L["Noch keine Gildenziele. Lege oben das erste an, z. B. „Geschmolzener Kern besiegt“ (Eigenes Ziel, Ziel 1)."]
        or L["Noch keine Gildenziele. Die Gildenleitung kann welche anlegen."])
end
