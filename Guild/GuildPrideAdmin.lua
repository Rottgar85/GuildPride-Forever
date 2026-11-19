-- GuildPride: Reiter "Verwaltung" – alles, was die Gildenleitung braucht,
-- an einem Ort. Nur sichtbar für Ränge, die die Gildennachricht ändern dürfen.
-- So bleiben die Einstellungen für normale Mitglieder schlank.
local ADDON, ns = ...
local L = ns.L

local page = ns.AddTab(L["Verwaltung"], 80)
ns.SetTabOfficerOnly(page)
ns.AdminPage = page

local scroll = ns.NewScroll(page)
scroll:SetPoint("TOPLEFT", 0, 0)
scroll:SetPoint("BOTTOMRIGHT", -26, 0)
local c = CreateFrame("Frame", nil, scroll)
c:SetSize(640, 1)
scroll:SetScrollChild(c)

local function Btn(label, w, anchor, x, y, fn)
    local b = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    b:SetSize(w, 24)
    if anchor then b:SetPoint("LEFT", anchor, "RIGHT", x, 0) else b:SetPoint("TOPLEFT", x, y) end
    b:SetText(label)
    b:SetScript("OnClick", fn)
    return b
end

local function Hint(y, text)
    local fs = c:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    fs:SetPoint("TOPLEFT", 4, y); fs:SetWidth(620); fs:SetJustifyH("LEFT")
    fs:SetTextColor(0.75, 0.72, 0.68)
    fs:SetText(text)
    return fs
end

---------------------------------------------------------------------
-- Bewerbungen
---------------------------------------------------------------------
local y = -4
ns.Section(c, L["Bewerbungen"], nil, y)
local appState = Hint(y - 28, "")
local bApps = Btn(L["Bewerbungen und Steckbrief …"], 220, nil, 4, y - 48, function() if ns.ToggleApps then ns.ToggleApps() end end)

---------------------------------------------------------------------
-- Werbetext: gespeichert und auf Knopfdruck in die Chat-Eingabe gelegt.
-- Abschicken (und Kanal wählen, z. B. "/2 ") macht der Spieler selbst.
---------------------------------------------------------------------
y = y - 92
ns.Section(c, L["Werbung"], nil, y)
Hint(y - 28, L["Werbetext (z. B. „/2 Gilde XY sucht …“)"])
local recruitBox = CreateFrame("EditBox", nil, c, "InputBoxTemplate")
recruitBox:SetSize(440, 22); recruitBox:SetPoint("TOPLEFT", 10, y - 46)
recruitBox:SetAutoFocus(false); recruitBox:SetMaxLetters(250)
recruitBox:SetScript("OnTextChanged", function(self, user)
    if user then ns.RecruitSetText(self:GetText()) end
end)
recruitBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
recruitBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

function ns.PostRecruitText()
    local t = GuildPrideDB.recruitText
    if not t or strtrim(t) == "" then ns.Print(L["Noch kein Werbetext gespeichert (Einstellungen)."]); return end
    -- Bewerbungen offen: Hinweis "!bewerben" anhängen (Chatgrenze 255 Zeichen)
    local suffix = ns.RecruitSuffix and ns.RecruitSuffix() or ""
    if suffix ~= "" and not t:find("!bewerben", 1, true) and not t:find("!apply", 1, true) then
        t = t:sub(1, 255 - #suffix) .. suffix
    end
    if ChatFrame_OpenChat then ChatFrame_OpenChat(t) end
    ns.Print(L["Werbetext steht in der Chat-Eingabe – mit Enter abschicken."])
end
Btn(L["In den Chat legen"], 150, recruitBox, 8, 0, function() ns.PostRecruitText() end)
-- Mehrere Werbetexte: blättern, neu, löschen (Daten in GuildPrideRecruit.lua)
local recruitPos
do
    local function Show()
        local list, i = ns.RecruitList()
        recruitBox:SetText(list[i] or "")
        recruitBox:ClearFocus()
        recruitPos:SetText((L["Text %d/%d"]):format(i, #list))
    end
    local prev = Btn("<", 28, nil, 10, y - 74, function() ns.RecruitSelect(GuildPrideDB.recruitIndex - 1); Show() end)
    recruitPos = c:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    recruitPos:SetPoint("LEFT", prev, "RIGHT", 8, 0); recruitPos:SetWidth(70)
    local nextB = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    nextB:SetSize(28, 24); nextB:SetPoint("LEFT", recruitPos, "RIGHT", 8, 0); nextB:SetText(">")
    nextB:SetScript("OnClick", function() ns.RecruitSelect(GuildPrideDB.recruitIndex + 1); Show() end)
    local add = Btn(L["Neuer Text"], 110, nextB, 12, 0, function()
        if not ns.RecruitAdd() then ns.Print(L["Höchstens 10 Werbetexte."]) end
        Show(); recruitBox:SetFocus()
    end)
    Btn(L["Text löschen"], 110, add, 8, 0, function() ns.RecruitRemove(); Show() end)
    ns.RecruitShow = Show
end

---------------------------------------------------------------------
-- DKP und Raids
---------------------------------------------------------------------
y = y - 120
ns.Section(c, L["DKP und Raids"], nil, y)
local bDkp = Btn(L["DKP-Fenster"], 150, nil, 4, y - 30, function() if ns.DKP then ns.DKP.Toggle() end end)
Btn(L["Protokoll …"], 150, bDkp, 8, 0, function() if ns.DKP and ns.DKP.ToggleLog then ns.DKP.ToggleLog() end end)
Hint(y - 60, L["Raid-Aufstellung: im Reiter Planen bei einem Event „Aufstellung …“."])

---------------------------------------------------------------------
-- Notiz-Vorlagen: eine pro Zeile, nutzbar im Mitglieder-Rechtsklick
---------------------------------------------------------------------
y = y - 96
ns.Section(c, L["Mitglieder"], nil, y)
Hint(y - 28, L["Notiz-Vorlagen (eine pro Zeile, {datum} = heute)"])
local tplScroll = ns.NewScroll(c)
tplScroll:SetPoint("TOPLEFT", 10, y - 48)
tplScroll:SetSize(600, 64)
local tplBg = tplScroll:CreateTexture(nil, "BACKGROUND")
tplBg:SetPoint("TOPLEFT", -4, 4); tplBg:SetPoint("BOTTOMRIGHT", 4, -4)
ns.DarkBg(tplBg, 0.45, "field")
local tplBox = CreateFrame("EditBox", nil, tplScroll)
tplBox:SetMultiLine(true); tplBox:SetAutoFocus(false)
tplBox:SetFontObject(GPFont_TextSmall); tplBox:SetWidth(590)
tplScroll:SetScrollChild(tplBox)
tplScroll:EnableMouse(true)
tplScroll:SetScript("OnMouseDown", function() tplBox:SetFocus() end)
tplBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
tplBox:SetScript("OnTextChanged", function(self, user)
    if not user then return end
    local list = {}
    for line in (self:GetText() .. "\n"):gmatch("([^\n]*)\n") do
        line = strtrim(line)
        if line ~= "" then list[#list + 1] = line:sub(1, 120) end
    end
    GuildPrideDB.noteTemplates = list
end)

-- Vorlagen mit eingesetztem Datum (für GuildPrideManage.lua)
function ns.NoteTemplates()
    local out = {}
    for _, t in ipairs(GuildPrideDB.noteTemplates or {}) do
        out[#out + 1] = (t:gsub("{datum}", date("%d.%m.%Y")):gsub("{date}", date("%Y-%m-%d")))
    end
    return out
end
Hint(y - 122, L["Inaktive entfernen und fällige Beförderungen: im Reiter Gilde & Chat, Mitgliederliste, Knopf „Inaktive“."])

---------------------------------------------------------------------
-- Gildenkanal
---------------------------------------------------------------------
y = y - 160
ns.Section(c, L["Abgesicherter Gildenkanal"], nil, y)
Hint(y - 28, L["Erzeugt einen neuen geheimen Schlüssel für den Hintergrund-Kanal (passiert auch automatisch, wenn jemand die Gilde verlässt)."])
Btn(L["Neuen Schlüssel erzeugen"], 200, nil, 4, y - 64, function()
    if SlashCmdList.GUILDPRIDE then SlashCmdList.GUILDPRIDE("kanal neu") end
end)

---------------------------------------------------------------------
-- Schwarzes Brett: Mitteilung, die jeder einmal als Fenster sieht
---------------------------------------------------------------------
y = y - 100
ns.Section(c, L["Schwarzes Brett"], nil, y)
Hint(y - 28, L["Jedes Mitglied mit GuildPride sieht die Mitteilung einmal als Fenster, danach steht sie in der Übersicht (30 Tage)."])
local boardScroll = ns.NewScroll(c)
boardScroll:SetPoint("TOPLEFT", 10, y - 48)
boardScroll:SetSize(600, 58)
local boardBg = boardScroll:CreateTexture(nil, "BACKGROUND")
boardBg:SetPoint("TOPLEFT", -4, 4); boardBg:SetPoint("BOTTOMRIGHT", 4, -4)
ns.DarkBg(boardBg, 0.45, "field")
local boardBox = CreateFrame("EditBox", nil, boardScroll)
boardBox:SetMultiLine(true); boardBox:SetAutoFocus(false); boardBox:SetMaxLetters(250)
boardBox:SetFontObject(GPFont_TextSmall); boardBox:SetWidth(590)
boardScroll:SetScrollChild(boardBox)
boardScroll:EnableMouse(true)
boardScroll:SetScript("OnMouseDown", function() boardBox:SetFocus() end)
boardBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
-- Für welche Ränge? Je Rang ein Häkchen (anfangs alle). Alle angekreuzt =
-- für alle; sonst sehen nur diese Ränge den Aushang (nicht nach Discord).
local rankChecks = {}
do
    local rl = c:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    rl:SetPoint("TOPLEFT", 4, y - 118); rl:SetText(L["Für Ränge:"])
    for r = 0, 9 do
        local cb = CreateFrame("CheckButton", nil, c, "UICheckButtonTemplate")
        cb:SetSize(24, 24); cb:SetChecked(true)
        cb:SetPoint("TOPLEFT", 80 + (r % 5) * 110, y - 112 - math.floor(r / 5) * 24)
        cb.label = c:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
        cb.label:SetPoint("LEFT", cb, "RIGHT", 1, 0); cb.label:SetWidth(82); cb.label:SetJustifyH("LEFT")
        cb.label:SetWordWrap(false)
        rankChecks[r] = cb
    end
end
local function RankName(r)
    local name = GuildControlGetRankName and GuildControlGetRankName(r + 1)
    return (type(name) == "string" and name ~= "") and name or (L["Rang %d"]):format(r)
end
-- Gewählte Ränge: nil = keiner, "" = alle, sonst { [rang] = true }
local function ChosenRanks()
    local set, all, any = {}, true, false
    for r, cb in pairs(rankChecks) do
        if cb:IsShown() then
            if cb:GetChecked() then set[r] = true; any = true else all = false end
        end
    end
    if not any then return nil end
    return all and "" or set
end

local boardDiscord = CreateFrame("CheckButton", nil, c, "UICheckButtonTemplate")
boardDiscord:SetPoint("TOPLEFT", 4, y - 164)
local bdl = c:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
bdl:SetPoint("LEFT", boardDiscord, "RIGHT", 2, 0); bdl:SetText(L["auch nach Discord"])
local bPost = Btn(L["Aushängen"], 130, nil, 200, y - 166, function()
    local ranks = ChosenRanks()
    if not ranks then ns.Print(L["Bitte mindestens einen Rang ankreuzen."]) return end
    if ns.Board and ns.Board.Post(boardBox:GetText(), boardDiscord:GetChecked(), ranks) then
        boardBox:SetText(""); boardBox:ClearFocus()
        ns.Print(L["Mitteilung hängt am Schwarzen Brett."])
    else
        ns.Print(L["Bitte erst einen Text schreiben."])
    end
end)
Btn(L["Abnehmen"], 130, bPost, 8, 0, function()
    if ns.Board then ns.Board.Remove() end
end)
local boardNow = Hint(y - 198, "")

---------------------------------------------------------------------
-- Abwesenheiten: wer sich von wann bis wann abgemeldet hat
---------------------------------------------------------------------
y = y - 236
ns.Section(c, L["Abwesenheiten"], nil, y)
local absNow = Hint(y - 28, "")
local bAbs = Btn(L["Abwesenheitsliste …"], 200, nil, 4, y - 50, function() if ns.Absence then ns.Absence.ToggleList() end end)
Btn(L["Mich abmelden …"], 160, bAbs, 8, 0, function() if ns.Absence then ns.Absence.ToggleMine() end end)
c:SetHeight(-(y - 90))

---------------------------------------------------------------------
-- Aktualisieren
---------------------------------------------------------------------
function page:Refresh()
    if not recruitBox:HasFocus() then ns.RecruitShow() end
    if not tplBox:HasFocus() then tplBox:SetText(table.concat(GuildPrideDB.noteTemplates or {}, "\n")) end
    local cur = ns.Board and ns.Board.Current(true)
    local only = ""
    if cur and cur.ranks and cur.ranks ~= "" then
        local names = {}
        for d in cur.ranks:gmatch("%d") do names[#names + 1] = RankName(tonumber(d)) end
        only = " " .. (L["(nur: %s)"]):format(table.concat(names, ", "))
    end
    boardNow:SetText(cur and ((L["Hängt gerade: %s"]):format(cur.text) .. only) or L["Am Schwarzen Brett hängt gerade nichts."])
    local num = math.min(10, GuildControlGetNumRanks and GuildControlGetNumRanks() or 0)
    if num == 0 then num = 10 end
    for r, cb in pairs(rankChecks) do
        cb:SetShown(r < num); cb.label:SetShown(r < num)
        cb.label:SetText(RankName(r))
    end
    if ns.Absence then
        local away, total = ns.Absence.AwayToday(), #ns.Absence.List()
        absNow:SetText((L["Heute abwesend: %s  ·  gemeldet insgesamt: %d"]):format(
            #away > 0 and table.concat(away, ", ") or "–", total))
    end
    local open = ns.RecruitOpen and ns.RecruitOpen()
    local n = 0
    for _, app in pairs(ns.GuildTable("apps")) do if app.status == "new" then n = n + 1 end end
    appState:SetText((open and L["Bewerbungen: |cff40ff40offen|r"] or L["Bewerbungen: |cffff6060geschlossen|r"])
        .. "  ·  " .. (L["%d neu"]):format(n))
    ns.SetTabBadge(page, n > 0 and ("(" .. n .. ")") or nil)
end

-- Rang geändert (befördert/degradiert): Reiter ein- oder ausblenden
local was
local f = CreateFrame("Frame")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_GUILD_UPDATE")
f:SetScript("OnEvent", function()
    local now = (CanEditMOTD and CanEditMOTD()) and true or false
    if now ~= was then
        was = now
        if ns.MenuChanged then ns.MenuChanged() end
    end
end)
