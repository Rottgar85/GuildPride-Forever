-- GuildPride: Umfragen (Offiziere legen an, alle stimmen ab; Abgleich über Addon-Nachrichten)
--   POL: id, ver, t, creator, closed (0/1, 2 = gelöscht), ends, frage, antwort1 ... antwortN  (ends 0 = ohne Ende)
--   VOT: id, name, wahl, ver
--   PLQ: Anfrage (Reiter geöffnet) -> Antwort per Flüstern
local ADDON, ns = ...
local L = ns.L

local MAX_OPTS = 6

local function DB()
    return ns.GuildTable("polls")   -- je Gilde getrennt
end

local function Me() return ns.Me() end
local function CanManage() return CanEditMOTD and CanEditMOTD() end
local function Now() return GetServerTime() end
local function Clean(s, max) return (tostring(s or ""):gsub("[%c|]", "")):sub(1, max) end

local STORE_MAX = 200   -- Obergrenze für gespeicherte Umfragen (gegen Speicherfluten)

local function StoreCount()
    local n = 0
    for _ in pairs(DB()) do n = n + 1 end
    return n
end

-- Voll? Dann zuerst Umfragen wegräumen, die seit 60 Tagen unverändert sind
local function GetOrStub(id)
    local p = DB()[id]
    if not p and StoreCount() >= STORE_MAX then
        local old = Now() - 60 * 86400
        for k, x in pairs(DB()) do
            if (x.ver or 0) < old then DB()[k] = nil end
        end
        if StoreCount() >= STORE_MAX then return nil end
    end
    if not p then p = { id = id, ver = 0, votes = {} }; DB()[id] = p end
    p.votes = p.votes or {}
    return p
end

-- Beendet von Hand oder Zeit abgelaufen
local function IsClosed(p)
    return p.closed or ((p.ends or 0) > 0 and GetServerTime() >= p.ends)
end

local function Remaining(p)
    local left = (p.ends or 0) - GetServerTime()
    if (p.ends or 0) == 0 or left <= 0 then return nil end
    if left >= 86400 then return (L["noch %d Tage"]):format(math.ceil(left / 86400)) end
    if left >= 3600 then return (L["noch %d Std."]):format(math.ceil(left / 3600)) end
    return (L["noch %d Min."]):format(math.ceil(left / 60))
end

local DURATIONS = {
    { secs = 0,          label = L["Ohne Ende"] },
    { secs = 86400,      label = L["1 Tag"] },
    { secs = 3 * 86400,  label = L["3 Tage"] },
    { secs = 7 * 86400,  label = L["1 Woche"] },
    { secs = 14 * 86400, label = L["2 Wochen"] },
}

---------------------------------------------------------------------
-- Senden / Anwenden (neuere Version gewinnt)
---------------------------------------------------------------------
local function SendPoll(p, target)
    ns.Queue("POL", target, p.id, p.ver, p.t, p.creator, p.deleted and 2 or (p.closed and 1 or 0), p.ends or 0, p.question, unpack(p.opts))
end
local function SendVote(id, name, v, target) ns.Queue("VOT", target, id, name, v.c, v.v) end

local function ApplyPoll(id, ver, t, creator, closed, ends, question, opts, fromOther)
    local p = GetOrStub(id)
    if not p or ver <= p.ver then return end
    local isNew = not p.question
    p.ver, p.t, p.creator, p.closed, p.ends, p.question, p.opts = ver, t, creator, closed, ends, question, opts
    if isNew and fromOther and not IsClosed(p) then
        ns.Print((L["Neue Umfrage: |cffffd100%s|r"]):format(question))
    end
end

local function ApplyVote(id, name, choice, ver)
    local p = GetOrStub(id)
    if not p then return end
    local cur = p.votes[name]
    if not cur or ver > cur.v then p.votes[name] = { c = choice, v = ver } end
end

local function SendAll(target)
    local cutoff = Now() - 30 * 86400
    for _, p in pairs(DB()) do
        if p.question and (p.t or 0) > cutoff then
            SendPoll(p, target)
            for name, v in pairs(p.votes) do SendVote(p.id, name, v, target) end
        end
    end
end

-- Ersteller kommt online: eigene Stimmen zu seinen Umfragen direkt nachliefern
if ns.OnMemberOnline then
    ns.OnMemberOnline(function(who)
        local me = Me()
        for _, p in pairs(DB()) do
            local v = p.votes[me]
            if v and p.creator == who and not p.deleted then SendVote(p.id, me, v, who) end
        end
    end)
end

ns.On("POL", function(payload, sender)
    if sender == Me() then return end
    local a = { strsplit(ns.SEP, payload) }
    local opts = {}
    for i = 8, math.min(#a, 7 + MAX_OPTS) do
        local o = Clean(a[i], 40)
        if o ~= "" then opts[#opts + 1] = o end
    end
    -- Fremde Werte prüfen: ID und Ersteller ohne Codes, Versionen nicht in der Zukunft
    local id = Clean(a[1], 80)
    if id == "" or #opts < 2 then return end
    if a[5] == "2" then
        local p = GetOrStub(id)
        local ver = ns.Stamp(a[2])
        if p and ver >= p.ver then p.deleted, p.ver = true, ver end
        if ns.RefreshUI then ns.RefreshUI() end
        return
    end
    ApplyPoll(id, ns.Stamp(a[2]), ns.Stamp(a[3]), Clean(a[4], 60), a[5] == "1", ns.Num(a[6], 0, 2 ^ 31) or 0,
        Clean(a[7], 80), opts, true)
    if ns.RefreshUI then ns.RefreshUI() end
end)

ns.On("VOT", function(payload, sender)
    if sender == Me() then return end
    local id, name, c, v = strsplit(ns.SEP, payload)
    id, name, c, v = Clean(id, 80), Clean(name, 60), ns.Num(c, 0, MAX_OPTS + 1), ns.Stamp(v)
    -- Nur gültige Antwortnummern und nur Stimmen von Gildenmitgliedern
    if id == "" or name == "" or not c or c < 1 or c > MAX_OPTS or v == 0 then return end
    if not ns.IsGuildMember(name) then return end
    ApplyVote(id, name, c, v)
    if ns.RefreshUI then ns.RefreshUI() end
end)

ns.On("PLQ", function(_, sender)
    if sender == Me() then return end
    C_Timer.After(math.random() * 3, function() SendAll(sender) end)
end)

---------------------------------------------------------------------
-- Aktionen
---------------------------------------------------------------------
local function CreatePoll(question, opts, duration)
    local id = Me() .. "-" .. Now() .. "-" .. math.random(1000, 9999)
    ApplyPoll(id, Now(), Now(), Me(), false, duration > 0 and Now() + duration or 0, Clean(question, 80), opts)
    if not DB()[id] then return end
    SendPoll(DB()[id])
    -- An Discord: Frage und Antworten (abgestimmt wird im Spiel)
    local p = DB()[id]
    if ns.Discord then
        local word = ns.IS_GERMAN and "Umfrage" or "Poll"
        ns.Discord.Post(("%s #%s: %s – %s"):format(word, ns.Discord.ShortId(id), p.question, table.concat(p.opts, " | ")), true)
    end
    ns.RefreshUI()
end

-- Ergebnis an Discord, wenn eine Umfrage geschlossen wird
local function PostResult(p)
    if not ns.Discord or not p or not p.opts then return end
    local counts = {}
    for _, v in pairs(p.votes or {}) do local c = tonumber(v.c); if c then counts[c] = (counts[c] or 0) + 1 end end
    local parts = {}
    for i, o in ipairs(p.opts) do parts[#parts + 1] = ("%s: %d"):format(o, counts[i] or 0) end
    ns.Discord.Post(("%s #%s %s: %s"):format(ns.IS_GERMAN and "Umfrage" or "Poll", ns.Discord.ShortId(p.id),
        ns.IS_GERMAN and "Ergebnis" or "result", table.concat(parts, " | ")), true)
end

local function SetClosed(p, closed)
    -- Wieder öffnen hebt eine abgelaufene Zeitbegrenzung auf
    local ends = p.ends or 0
    if not closed and ends > 0 and Now() >= ends then ends = 0 end
    ApplyPoll(p.id, math.max(Now(), p.ver + 1), p.t, p.creator, closed, ends, p.question, p.opts)
    SendPoll(p)
    if closed then PostResult(p) end
    ns.RefreshUI()
end

local function DeletePoll(p)
    p.deleted, p.ver = true, math.max(Now(), p.ver + 1)
    SendPoll(p)
    ns.RefreshUI()
end

StaticPopupDialogs["GUILDPRIDE_DELETE_POLL"] = {
    text = L["Umfrage \"%s\" wirklich löschen?"],
    button1 = YES, button2 = NO,
    OnAccept = function(_, p) DeletePoll(p) end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local function Vote(p, choice)
    if IsClosed(p) then return end
    local cur = p.votes[Me()]
    ApplyVote(p.id, Me(), choice, math.max(Now(), cur and cur.v + 1 or 0))
    SendVote(p.id, Me(), p.votes[Me()])
    if ns.TellCreator then ns.TellCreator(p.creator, function(who) SendVote(p.id, Me(), p.votes[Me()], who) end) end
    ns.RefreshUI()
end

-- Offene zuerst, dann die neuesten
local function Sorted()
    local list = {}
    for _, p in pairs(DB()) do if p.question and p.opts and not p.deleted then list[#list + 1] = p end end
    table.sort(list, function(a, b)
        local ca, cb = IsClosed(a) and true or false, IsClosed(b) and true or false
        if ca ~= cb then return not ca end
        return (a.t or 0) > (b.t or 0)
    end)
    return list
end

---------------------------------------------------------------------
-- Oberfläche
---------------------------------------------------------------------
local page = ns.AddTab(L["Umfragen"], 50)
local selected

local empty = page:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
empty:SetPoint("TOP", 0, -60)
empty:SetText(L["Noch keine Umfragen."])

local rows = {}
for i = 1, 6 do
    local b = CreateFrame("Button", nil, page)
    b:SetSize(640, 26)
    b:SetPoint("TOPLEFT", 0, -(i - 1) * 28)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
    b.title = b:CreateFontString(nil, "OVERLAY", "GPFont_Text")
    b.title:SetPoint("LEFT", 8, 0); b.title:SetWidth(470); b.title:SetJustifyH("LEFT")
    b.info = b:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    b.info:SetPoint("RIGHT", -8, 0)
    b:SetScript("OnClick", function(self) selected = self.poll and self.poll.id; page:Refresh() end)
    rows[i] = b
end

local detail = CreateFrame("Frame", nil, page, "BackdropTemplate")
detail:SetPoint("TOPLEFT", 0, -176)
detail:SetPoint("BOTTOMRIGHT", 0, 32)
detail:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
detail:SetBackdropColor(0, 0, 0, 0.35)

local dTitle = detail:CreateFontString(nil, "OVERLAY", "GPFont_Large")
dTitle:SetPoint("TOPLEFT", 8, -8); dTitle:SetWidth(620); dTitle:SetJustifyH("LEFT")
local dInfo = detail:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
dInfo:SetPoint("TOPLEFT", dTitle, "BOTTOMLEFT", 0, -4)

-- Je Antwort: Knopf zum Abstimmen, Balken und wer sie gewählt hat
local optRows = {}
for i = 1, MAX_OPTS do
    local b = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    b:SetSize(200, 22)
    b:SetPoint("TOPLEFT", 8, -52 - (i - 1) * 26)
    local bar = detail:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("LEFT", b, "RIGHT", 8, 0); bar:SetHeight(14)
    bar:SetColorTexture(1, 0.82, 0, 0.35)
    local txt = detail:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    txt:SetPoint("LEFT", b, "RIGHT", 12, 0)
    b.bar, b.txt, b.index = bar, txt, i
    b:SetScript("OnClick", function(self)
        local p = selected and DB()[selected]
        if p then Vote(p, self.index) end
    end)
    optRows[i] = b
end

local function Btn(text, w, anchor, x, onClick)
    local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    b:SetSize(w, 24); b:SetText(text)
    b:SetPoint("BOTTOMLEFT", anchor or page, anchor and "BOTTOMRIGHT" or "BOTTOMLEFT", x or 0, 0)
    b:SetScript("OnClick", onClick)
    return b
end

local bNew = Btn(L["Neue Umfrage"], 120, nil, 0, function() ns.ShowPollDialog() end)
local bClose = Btn(L["Beenden"], 120, bNew, 8, function()
    local p = selected and DB()[selected]
    if p then SetClosed(p, not IsClosed(p)) end
end)
local bDelete = Btn(L["Löschen"], 100, bClose, 8, function()
    local p = selected and DB()[selected]
    if p and CanManage() then StaticPopup_Show("GUILDPRIDE_DELETE_POLL", p.question, nil, p) end
end)

function page:Refresh()
    local list = Sorted()
    empty:SetShown(#list == 0)
    for i, b in ipairs(rows) do
        local p = list[i]
        b.poll = p
        b:SetShown(p ~= nil)
        if p then
            local n = 0
            for _ in pairs(p.votes) do n = n + 1 end
            b.title:SetText(IsClosed(p) and ("|cff888888" .. p.question .. "|r") or p.question)
            b.info:SetText((L["%d Stimmen"]):format(n) .. (p.votes[Me()] and "  |cff40ff40●|r" or ""))
            b.bg:SetColorTexture(1, 0.82, 0, p.id == selected and 0.18 or (i % 2 == 0 and 0.04 or 0))
        end
    end

    local p = selected and DB()[selected]
    if not (p and p.question and not p.deleted) then p = list[1]; selected = p and p.id end
    detail:SetShown(p ~= nil)
    bNew:SetShown(CanManage())
    bClose:SetShown(CanManage() and p ~= nil)
    bDelete:SetShown(CanManage() and p ~= nil)
    if not p then return end
    local closed = IsClosed(p)
    bClose:SetText(closed and L["Wieder öffnen"] or L["Beenden"])

    local counts, total, names = {}, 0, {}
    for name, v in pairs(p.votes) do
        if p.opts[v.c] then
            local c = tonumber(v.c); if c then counts[c] = (counts[c] or 0) + 1 end
            total = total + 1
            names[v.c] = names[v.c] or {}
            table.insert(names[v.c], Ambiguate(name, "guild"))
        end
    end
    dTitle:SetText(p.question)
    dInfo:SetText((L["von %s · %d Stimmen"]):format(Ambiguate(p.creator or "?", "guild"), total)
        .. (closed and ("  |cffff4040" .. L["beendet"] .. "|r")
            or (Remaining(p) and ("  |cffffd100" .. Remaining(p) .. "|r") or "")))
    local mine = p.votes[Me()]
    for i, b in ipairs(optRows) do
        local o = p.opts[i]
        b:SetShown(o ~= nil); b.bar:SetShown(o ~= nil); b.txt:SetShown(o ~= nil)
        if o then
            b:SetText(o)
            b:SetEnabled(not closed)
            if mine and mine.c == i then b:LockHighlight() else b:UnlockHighlight() end
            local c = counts[i] or 0
            b.bar:SetWidth(math.max(1, total > 0 and 400 * c / total or 1))
            if names[i] then table.sort(names[i]) end
            local who = names[i] and table.concat(names[i], ", ") or ""
            if #who > 60 then who = who:sub(1, 57) .. "…" end
            b.txt:SetText(("%d%s"):format(c, who ~= "" and ("  |cffdddddd" .. who .. "|r") or ""))
        end
    end
end

-- Beim Öffnen des Reiters fehlende Umfragen abfragen (höchstens alle 2 Minuten)
local lastAsk = 0
page:HookScript("OnShow", function()
    if GetTime() - lastAsk > 120 and IsInGuild() then
        lastAsk = GetTime()
        ns.Queue("PLQ", nil, "1")
    end
end)

---------------------------------------------------------------------
-- Dialog: Umfrage anlegen
---------------------------------------------------------------------
local dlg = CreateFrame("Frame", "GuildPridePollDialog", UIParent, "BackdropTemplate")
dlg:SetSize(420, 140 + MAX_OPTS * 30)
dlg:SetPoint("CENTER")
dlg:SetFrameStrata("DIALOG")
dlg:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
dlg:SetBackdropColor(0.07, 0.05, 0.04, 0.97)
ns.Paint(dlg, "accent")
dlg:EnableMouse(true)
dlg:Hide()
tinsert(UISpecialFrames, "GuildPridePollDialog")

local function Field(y, label, max)
    local fs = dlg:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    fs:SetPoint("TOPLEFT", 16, y); fs:SetText(label)
    local eb = CreateFrame("EditBox", nil, dlg, "InputBoxTemplate")
    eb:SetSize(270, 22); eb:SetPoint("TOPLEFT", 126, y + 4)
    eb:SetAutoFocus(false); eb:SetMaxLetters(max)
    eb:SetScript("OnEscapePressed", function() dlg:Hide() end)
    return eb
end

local fQuestion = Field(-20, L["Frage"], 80)
local fOpts = {}
for i = 1, MAX_OPTS do fOpts[i] = Field(-20 - i * 30, (L["Antwort %d"]):format(i), 40) end

-- Laufzeit: Auswahlmenü
local durLabel = dlg:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
durLabel:SetPoint("TOPLEFT", 16, -20 - (MAX_OPTS + 1) * 30)
durLabel:SetText(L["Laufzeit"])
local durIndex = 1
local bDur = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
bDur:SetSize(160, 22); bDur:SetPoint("TOPLEFT", 122, -16 - (MAX_OPTS + 1) * 30)
local function ShowDur() bDur:SetText(DURATIONS[durIndex].label) end
bDur:SetScript("OnClick", function(self)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        durIndex = durIndex % #DURATIONS + 1; ShowDur(); return
    end
    MenuUtil.CreateContextMenu(self, function(_, root)
        root:CreateTitle(L["Laufzeit"])
        for i, d in ipairs(DURATIONS) do
            root:CreateRadio(d.label, function() return durIndex == i end, function() durIndex = i; ShowDur() end)
        end
    end)
end)

local bSave = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
bSave:SetSize(110, 24); bSave:SetPoint("BOTTOMRIGHT", -16, 14); bSave:SetText(L["Erstellen"])
local bCancel = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
bCancel:SetSize(110, 24); bCancel:SetPoint("RIGHT", bSave, "LEFT", -8, 0); bCancel:SetText(CANCEL)
bCancel:SetScript("OnClick", function() dlg:Hide() end)
bSave:SetScript("OnClick", function()
    local q = strtrim(fQuestion:GetText())
    local opts = {}
    for _, eb in ipairs(fOpts) do
        local o = Clean(strtrim(eb:GetText()), 40)
        if o ~= "" then opts[#opts + 1] = o end
    end
    if q == "" or #opts < 2 then
        ns.Print(L["|cffff4040Bitte eine Frage und mindestens zwei Antworten eingeben.|r"])
        return
    end
    CreatePoll(q, opts, DURATIONS[durIndex].secs)
    dlg:Hide()
end)

function ns.ShowPollDialog()
    if not CanManage() then return end
    fQuestion:SetText("")
    for i, eb in ipairs(fOpts) do eb:SetText(i == 1 and L["Ja"] or i == 2 and L["Nein"] or "") end
    durIndex = 4   -- Vorgabe: 1 Woche
    ShowDur()
    dlg:Show()
    fQuestion:SetFocus()
end
