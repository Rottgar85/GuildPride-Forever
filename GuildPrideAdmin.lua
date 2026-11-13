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
    if user then GuildPrideDB.recruitText = self:GetText() end
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

---------------------------------------------------------------------
-- DKP und Raids
---------------------------------------------------------------------
y = y - 92
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
tplBg:SetColorTexture(0, 0, 0, 0.45)
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
c:SetHeight(-(y - 100))

---------------------------------------------------------------------
-- Aktualisieren
---------------------------------------------------------------------
function page:Refresh()
    if not recruitBox:HasFocus() then recruitBox:SetText(GuildPrideDB.recruitText or "") end
    if not tplBox:HasFocus() then tplBox:SetText(table.concat(GuildPrideDB.noteTemplates or {}, "\n")) end
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
