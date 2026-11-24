-- GuildPride: Dialog „Event erstellen / bearbeiten“ (früher Teil von GuildPrideEvents.lua)
local ADDON, ns = ...
local L = ns.L
local X = ns.EventsX
local CanManage, Clean, CreateEvent, EditEvent, InstOf, Me, ParseDate =
    X.CanManage, X.Clean, X.CreateEvent, X.EditEvent, X.InstOf, X.Me, X.ParseDate

---------------------------------------------------------------------
-- Dialog: Event erstellen
---------------------------------------------------------------------
local dlg = CreateFrame("Frame", "GuildPrideCreateEvent", UIParent, "BackdropTemplate")
dlg:SetSize(360, 330)
dlg:SetPoint("CENTER")
dlg:SetFrameStrata("DIALOG")
dlg:EnableMouse(true)
ns.GoldFrame(dlg)   -- Goldrahmen wie das Gildenfenster
dlg:Hide()
tinsert(UISpecialFrames, "GuildPrideCreateEvent")

local dh = dlg:CreateFontString(nil, "OVERLAY", "GPFont_Large")
dh:SetPoint("TOP", 0, -16); dh:SetText(L["Neues Gildenevent"])

local function Field(label, y, width, maxLen, x)
    x = x or 24
    local l = dlg:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    l:SetPoint("TOPLEFT", x, y); l:SetText(label)
    local eb = CreateFrame("EditBox", nil, dlg, "InputBoxTemplate")
    eb:SetSize(width, 22); eb:SetPoint("TOPLEFT", x + 4, y - 14)
    eb:SetAutoFocus(false); eb:SetMaxLetters(maxLen)
    return eb
end
local fTitle = Field(L["Titel"], -44, 300, 40)
local fDate  = Field(L["Datum (TT.MM.JJJJ)"], -86, 130, 10)
local fTime  = Field(L["Uhrzeit (HH:MM)"], -86, 80, 8, 190)
local fDesc  = Field(L["Beschreibung (optional)"], -128, 300, 120)

-- Tab springt ins nächste Feld
local order = { fTitle, fDate, fTime, fDesc }
for i, eb in ipairs(order) do
    eb:SetScript("OnTabPressed", function() order[i % #order + 1]:SetFocus() end)
end
local fRepeat = CreateFrame("CheckButton", nil, dlg, "UICheckButtonTemplate")
fRepeat:SetSize(24, 24); fRepeat:SetPoint("TOPLEFT", 24, -210)
local fRepeatText = dlg:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
fRepeatText:SetPoint("LEFT", fRepeat, "RIGHT", 2, 0); fRepeatText:SetText(L["Jede Woche wiederholen"])
local fErr   = dlg:CreateFontString(nil, "OVERLAY", "GPFont_Red")
fErr:SetPoint("BOTTOM", 0, 48)

-- Art: normales Event, Dungeon oder Raid (Liste aus GuildPrideInstances.lua).
-- Die Wahl geht mit an Discord, dort legt der Bot die passende Gruppe an.
local fKind, fInst = "", ""          -- "" / "dungeon" / "raid", Instanz-Schlüssel
local autoTitle                      -- zuletzt automatisch gesetzter Titel
local kindLabel = dlg:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
kindLabel:SetPoint("TOPLEFT", 24, -170); kindLabel:SetText(L["Art"])
-- Je ein Knopf für Dungeon und Raid; der gewählte zeigt den Namen der Instanz
local bDungeon = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
bDungeon:SetSize(150, 22); bDungeon:SetPoint("TOPLEFT", 26, -184)
local bRaid = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
bRaid:SetSize(150, 22); bRaid:SetPoint("LEFT", bDungeon, "RIGHT", 6, 0)
local KIND_BTN = { dungeon = bDungeon, raid = bRaid }
local CHOOSE = { dungeon = L["Dungeon wählen …"], raid = L["Raid wählen …"] }

local function UpdateKind()
    local x = ns.Instances.Find(fKind, fInst)
    for kind, b in pairs(KIND_BTN) do
        if x and x.kind == kind then
            b:SetText(("%s (%d)"):format(x.name, x.size)); b:LockHighlight()
        else
            b:SetText(CHOOSE[kind]); b:UnlockHighlight()
        end
    end
end
-- Instanz wählen (x = nil: wieder normales Event). Der Name wird der Titel.
local function SetInst(x)
    fKind, fInst = x and x.kind or "", x and x.key or ""
    if x then
        autoTitle = x.name:sub(1, 40)
        fTitle:SetText(autoTitle)
    elseif strtrim(fTitle:GetText()) == autoTitle then
        fTitle:SetText(""); autoTitle = nil
    end
    fErr:SetText("")
    UpdateKind()
end

local function OpenList(self, kind)
    local list = ns.Instances.list[kind]
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle(CHOOSE[kind])
            if fKind == kind then
                root:CreateButton("|cff999999" .. L["Keine Auswahl"] .. "|r", function() SetInst(nil) end)
            end
            for _, x in ipairs(list) do
                root:CreateButton(("%s  |cff999999%s · %d|r"):format(x.name, (L["Stufe %s"]):format(x.level), x.size),
                    function() SetInst(x) end)
            end
        end)
    else
        -- Ältere Clients ohne Menü: jeder Klick nimmt die nächste Instanz
        local n = 1
        for i, x in ipairs(list) do if fKind == kind and x.key == fInst then n = i % #list + 1 end end
        SetInst(list[n])
    end
end
bDungeon:SetScript("OnClick", function(self) OpenList(self, "dungeon") end)
bRaid:SetScript("OnClick", function(self) OpenList(self, "raid") end)

local ok = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
ok:SetSize(120, 24); ok:SetPoint("BOTTOMLEFT", 40, 18); ok:SetText(L["Erstellen"])
local cancel = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
cancel:SetSize(120, 24); cancel:SetPoint("BOTTOMRIGHT", -40, 18); cancel:SetText(CANCEL)
cancel:SetScript("OnClick", function() dlg:Hide() end)

local editing   -- Event, das gerade bearbeitet wird (nil = neues Event)
ok:SetScript("OnClick", function()
    local title = strtrim(fTitle:GetText())
    if title == "" then fErr:SetText(L["Bitte einen Titel eingeben."]); return end
    local t, bad = ParseDate(strtrim(fDate:GetText()), strtrim(fTime:GetText()))
    if bad == "date" then fErr:SetText(L["Datum bitte als TT.MM.JJJJ eingeben (z. B. 24.12.2026)."]); return end
    if bad == "time" then fErr:SetText(L["Uhrzeit bitte als HH:MM eingeben (z. B. 20:00)."]); return end
    if t < time() then fErr:SetText(L["Der Termin liegt in der Vergangenheit."]); return end
    local rep = fRepeat:GetChecked() and 7 or 0
    if fKind ~= "" and not ns.Instances.Find(fKind, fInst) then
        fErr:SetText(fKind == "raid" and L["Bitte einen Raid auswählen."] or L["Bitte einen Dungeon auswählen."]); return
    end
    local kind, inst = fKind, fKind ~= "" and fInst or ""
    if editing then
        local e = editing
        if not e.deleted and e.title then EditEvent(e, title, t, strtrim(fDesc:GetText()), rep, kind, inst) end
    else
        CreateEvent(title, t, strtrim(fDesc:GetText()), rep, kind, inst)
    end
    dlg:Hide()
end)
for _, eb in ipairs(order) do
    eb:SetScript("OnEnterPressed", function() ok:Click() end)
    eb:SetScript("OnEscapePressed", function() dlg:Hide() end)
end

-- Vorlagen: häufige Events (z. B. "Raid Donnerstag 20 Uhr") mit einem Klick ausfüllen.
-- Je Gilde auf diesem Rechner: [Titel] = { title, desc, time = "HH:MM", rep, wday }
local function Templates() return ns.GuildTable("eventTemplates") end
local WDAYS = { L["Sonntag"], L["Montag"], L["Dienstag"], L["Mittwoch"], L["Donnerstag"], L["Freitag"], L["Samstag"] }

local function ApplyTemplate(tpl)
    fTitle:SetText(tpl.title or ""); fDesc:SetText(tpl.desc or "")
    fTime:SetText(tpl.time or "20:00"); fRepeat:SetChecked((tpl.rep or 0) > 0)
    local x = ns.Instances.Find(tpl.kind, tpl.inst)
    fKind, fInst, autoTitle = x and x.kind or "", x and x.key or "", nil
    UpdateKind()
    fErr:SetText("")
    if tpl.wday then
        -- nächster passender Wochentag (heute nur, wenn die Uhrzeit noch kommt)
        local h, m = (tpl.time or "20:00"):match("^(%d+):(%d+)$")
        local now = time()
        for add = 0, 7 do
            local t = now + add * 86400
            local d = date("*t", t)
            d.hour, d.min, d.sec = tonumber(h) or 20, tonumber(m) or 0, 0
            if d.wday == tpl.wday and time(d) > now then fDate:SetText(date("%d.%m.%Y", t)); break end
        end
    end
end

local function SortedTemplates()
    local list = {}
    for _, tpl in pairs(Templates()) do if type(tpl) == "table" and tpl.title then list[#list + 1] = tpl end end
    table.sort(list, function(a, b) return a.title < b.title end)
    return list
end

local function TemplateLabel(tpl)
    return tpl.title .. (tpl.wday and ("  |cff999999" .. WDAYS[tpl.wday] .. " " .. (tpl.time or "") .. "|r") or "")
end

local bTpl = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
bTpl:SetSize(140, 22); bTpl:SetPoint("TOPLEFT", 26, -244); bTpl:SetText(L["Vorlage …"])
local bTplSave = CreateFrame("Button", nil, dlg, "UIPanelButtonTemplate")
bTplSave:SetSize(160, 22); bTplSave:SetPoint("LEFT", bTpl, "RIGHT", 8, 0); bTplSave:SetText(L["Als Vorlage speichern"])
local tplCycle = 0

bTplSave:SetScript("OnClick", function()
    local title = strtrim(fTitle:GetText())
    if title == "" then fErr:SetText(L["Bitte einen Titel eingeben."]); return end
    local t = ParseDate(strtrim(fDate:GetText()), strtrim(fTime:GetText()))
    local clock = strtrim(fTime:GetText())
    Templates()[title] = { title = Clean(title, 40), desc = Clean(strtrim(fDesc:GetText()), 120),
        time = clock:match("^%d%d?:%d%d$") and clock or "20:00",
        rep = fRepeat:GetChecked() and 7 or 0, wday = t and date("*t", t).wday or nil,
        kind = fKind ~= "" and fKind or nil, inst = fKind ~= "" and fInst ~= "" and fInst or nil }
    fErr:SetText("")
    ns.Print((L["Vorlage |cffffd100%s|r gespeichert."]):format(title))
end)

bTpl:SetScript("OnClick", function(self)
    local list = SortedTemplates()
    if #list == 0 then fErr:SetText(L["Noch keine Vorlagen – fülle das Event aus und speichere es als Vorlage."]); return end
    if MenuUtil and MenuUtil.CreateContextMenu then
        MenuUtil.CreateContextMenu(self, function(_, root)
            root:CreateTitle(L["Vorlage verwenden"])
            for _, tpl in ipairs(list) do
                root:CreateButton(TemplateLabel(tpl), function() ApplyTemplate(tpl) end)
            end
            local del = root:CreateButton(L["Vorlage löschen"])
            for _, tpl in ipairs(list) do
                del:CreateButton(tpl.title, function()
                    Templates()[tpl.title] = nil
                    ns.Print((L["Vorlage |cffffd100%s|r gelöscht."]):format(tpl.title))
                end)
            end
        end)
    else
        -- Ältere Clients ohne Menü: jeder Klick nimmt die nächste Vorlage
        tplCycle = tplCycle % #list + 1
        ApplyTemplate(list[tplCycle])
    end
end)

function ns.ShowCreateDialog()
    if not CanManage() then ns.Print(L["Nur Offiziere können Events erstellen."]); return end
    -- Vorschlag: heute um 20:00 (nach 20 Uhr: morgen)
    local start = time()
    if tonumber(date("%H")) >= 20 then start = start + 86400 end
    fTitle:SetText(""); fDate:SetText(date("%d.%m.%Y", start)); fTime:SetText("20:00")
    fDesc:SetText(""); fErr:SetText(""); fRepeat:SetChecked(false)
    fKind, fInst, autoTitle = "", "", nil
    UpdateKind()
    tplCycle = 0
    editing = nil
    dh:SetText(L["Neues Gildenevent"]); ok:SetText(L["Erstellen"])
    bTpl:Show(); bTplSave:Show()
    dlg:Show(); fTitle:SetFocus()
end

function ns.ShowEditDialog(e)
    if not e or e.deleted or not e.title then return end
    if not (CanManage() or e.creator == Me()) then ns.Print(L["Nur der Ersteller oder Offiziere können das Event ändern."]); return end
    editing = e
    fTitle:SetText(e.title or ""); fDesc:SetText(e.desc or "")
    fDate:SetText(date("%d.%m.%Y", e.t)); fTime:SetText(date("%H:%M", e.t))
    fRepeat:SetChecked((e.rep or 0) > 0); fErr:SetText("")
    local x = InstOf(e)
    fKind, fInst, autoTitle = x and x.kind or "", x and x.key or "", nil
    UpdateKind()
    dh:SetText(L["Event bearbeiten"]); ok:SetText(L["Speichern"])
    bTpl:Hide(); bTplSave:Hide()
    dlg:Show(); fTitle:SetFocus()
end
