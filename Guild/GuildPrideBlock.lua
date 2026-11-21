-- GuildPride: Blockliste – Spieler, die nicht in die Gilde eingeladen werden sollen.
--
-- Forever lässt Addons nicht selbst in die Gilde einladen: GuildPride öffnet nur Blizzards
-- Einladefenster, den Namen tippt man dort selbst (GuildPrideInvite.lua). Eine Einladung
-- lässt sich darum nicht hart sperren. Die Blockliste schützt überall, wo GuildPride den Namen kennt:
--   • Einladen über GuildPride (/gp einladen, Bewerbungen): gesperrte Spieler werden abgelehnt
--   • Blizzards Einladefenster: Tippt man einen gesperrten Namen, erscheint daneben eine Warnung
--   • Tritt ein gesperrter Spieler trotzdem bei, bekommen Offiziere eine deutliche Warnung
-- Die Liste gilt für die ganze Gilde: nur Offiziere ändern sie, alle gleichen sie ab.
--   BLK  name · ver · by · gelöscht (0/1) · Grund     (nur von Offizieren übernommen)
--   BLQ  1                                            (Liste anfragen; Offiziere antworten)
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP

local Block = {}
ns.Block = Block

local MAX_REASON = 80
local function DB() return ns.GuildTable("blocklist") end   -- [Name] = { ver, by, reason, deleted }
local function Now() return GetServerTime() end
local function Me() return ns.Me() end
local function Clean(s, max) return (tostring(s or ""):gsub("|", ""):gsub("[%c]", " ")):sub(1, max) end
local function IsOfficer() return ns.IsOfficer and ns.IsOfficer() and true or false end

-- Namen vergleichbar machen: wie im Rest von GuildPride
local function Key(name)
    name = strtrim(Clean(name, 60))
    if name == "" then return nil end
    return ns.Normalize and ns.Normalize(name) or name
end

local function Find(name)
    local key = Key(name)
    if not key then return nil end
    local db = DB()
    local e = db[key]
    if e and not e.deleted then return key, e end
    local low = key:lower()
    for k, v in pairs(db) do
        if not v.deleted and k:lower() == low then return k, v end
    end
    return nil
end

-- Steht der Spieler auf der Blockliste? Gibt den Eintrag zurück ({ by, reason, ver })
function Block.IsBlocked(name)
    local _, e = Find(name)
    return e
end

function Block.List()
    local out = {}
    for name, e in pairs(DB()) do
        if not e.deleted then out[#out + 1] = { name = name, by = e.by, reason = e.reason, ver = e.ver } end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local function Send(target, name)
    local e = DB()[name]
    if not e then return end
    ns.Queue("BLK", target, name, e.ver, e.by or "", e.deleted and 1 or 0, e.reason or "")
end

local function Apply(name, ver, by, deleted, reason)
    local db = DB()
    local old = db[name]
    if old and ver <= (old.ver or 0) then return false end
    db[name] = { ver = ver, by = by, deleted = deleted or nil, reason = (reason and reason ~= "") and reason or nil }
    return true
end

local function Refresh()
    if Block.RefreshWindow then Block.RefreshWindow() end
    if ns.RefreshUI then ns.RefreshUI() end
end

ns.On("BLK", function(payload, sender)
    if sender == Me() then return end
    -- nur Offiziere dürfen die Blockliste ändern
    if not (ns.IsOfficerName and ns.IsOfficerName(sender)) then return end
    local a = { strsplit(SEP, payload) }
    local name, ver = Key(a[1]), ns.Stamp(a[2])
    if not name or ver == 0 then return end
    if Apply(name, ver, Clean(a[3], 60), a[4] == "1", Clean(a[5], MAX_REASON)) then Refresh() end
end)

ns.On("BLQ", function(_, sender)
    if sender == Me() or not IsOfficer() then return end
    local names = {}
    for name in pairs(DB()) do names[#names + 1] = name end
    if #names == 0 then return end
    C_Timer.After(1 + math.random() * 5, function()
        for _, name in ipairs(names) do Send(sender, name) end
    end)
end)

-- Rückgabe: true oder false, Grund ("name", "recht")
function Block.Add(name, reason)
    if not IsOfficer() then return false, "recht" end
    local key = Key(name)
    if not key then return false, "name" end
    local old = DB()[key]
    Apply(key, math.max(Now(), (old and old.ver or 0) + 1), Me(), false, strtrim(Clean(reason, MAX_REASON)))
    Send(nil, key)
    Refresh()
    return true
end

function Block.Remove(name)
    if not IsOfficer() then return false end
    local key, e = Find(name)
    if not key then return false end
    Apply(key, math.max(Now(), (e.ver or 0) + 1), Me(), true, e.reason)
    Send(nil, key)
    Refresh()
    return true
end

-- Hinweis im Chat, warum nicht eingeladen wird; true, wenn gesperrt
function Block.Refuse(name)
    local e = Block.IsBlocked(name)
    if not e then return false end
    ns.Print((L["|cffff4040%s steht auf der Blockliste|r – nicht einladen."]):format(Ambiguate(name, "none"))
        .. (e.reason and (" (" .. e.reason .. ")") or ""))
    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
    return true
end

---------------------------------------------------------------------
-- Gesperrter Spieler ist trotzdem beigetreten: Offiziere deutlich warnen
---------------------------------------------------------------------
do
    local origAddLog = ns.AddLog
    if origAddLog then
        ns.AddLog = function(kind, who, ...)
            local new = origAddLog(kind, who, ...)
            if new and kind == "JOIN" and IsOfficer() then
                local e = Block.IsBlocked(who)
                if e then
                    local text = (L["|cffff4040Achtung:|r %s steht auf der Blockliste und ist der Gilde beigetreten!"]):format(Ambiguate(who, "none"))
                        .. (e.reason and (" (" .. e.reason .. ")") or "")
                    ns.Print(text)
                    if RaidNotice_AddMessage and RaidWarningFrame then
                        RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 1, g = 0.3, b = 0.1 })
                    end
                    if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
                end
            end
            return new
        end
    end
end

---------------------------------------------------------------------
-- Warnung neben Blizzards Einladefenster. Nur lesen und ein eigenes Fenster daneben zeigen:
-- Blizzards Fenster selbst wird nicht verändert, sonst sperrt Forever die Einladung (Taint).
---------------------------------------------------------------------
local warn
local function Warn(popup, name)
    if not warn then
        warn = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        warn:SetFrameStrata("TOOLTIP")
        warn:SetSize(320, 40)
        warn.text = warn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        warn.text:SetPoint("TOPLEFT", 10, -6); warn.text:SetPoint("BOTTOMRIGHT", -10, 6)
        warn.text:SetJustifyH("CENTER"); warn.text:SetTextColor(1, 0.35, 0.3)
        if ns.SkinDialog then ns.SkinDialog(warn) end
    end
    local e = name and Block.IsBlocked(name)
    if not e then warn:Hide() return end
    warn:ClearAllPoints()
    warn:SetPoint("BOTTOM", popup, "TOP", 0, 6)
    warn.text:SetText((L["%s steht auf der Blockliste!"]):format(Ambiguate(name, "none"))
        .. (e.reason and ("\n|cffcccccc" .. e.reason .. "|r") or ""))
    warn:Show()
end

local hookedBoxes = {}
local function WatchInvitePopup(which)
    if which ~= "ADD_GUILDMEMBER" or not StaticPopup_FindVisible then return end
    local popup = StaticPopup_FindVisible(which)
    local box = popup and (popup.editBox or popup.EditBox)
    if not box then return end
    if not hookedBoxes[box] then
        hookedBoxes[box] = true
        box:HookScript("OnTextChanged", function(self)
            local p = self:GetParent()
            if p and p.which == "ADD_GUILDMEMBER" then Warn(p, self:GetText()) elseif warn then warn:Hide() end
        end)
        popup:HookScript("OnHide", function() if warn then warn:Hide() end end)
    end
end
if hooksecurefunc and StaticPopup_Show then hooksecurefunc("StaticPopup_Show", WatchInvitePopup) end

---------------------------------------------------------------------
-- Fenster (Verwaltung › Blockliste …)
---------------------------------------------------------------------
local win
local ROWS = 10

local function Build()
    win = CreateFrame("Frame", "GuildPrideBlockList", UIParent, "BackdropTemplate")
    win:SetSize(460, 120 + ROWS * 22)
    win:SetPoint("CENTER", 0, 60)
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true); win:EnableMouse(true); win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    if ns.SkinDialog then ns.SkinDialog(win) end
    tinsert(UISpecialFrames, "GuildPrideBlockList")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    if ns.SkinClose then ns.SkinClose(close) end
    close:SetScript("OnClick", function() win:Hide() end)
    local title = win:CreateFontString(nil, "OVERLAY", "GPFont_Large")
    title:SetPoint("TOPLEFT", 14, -12); title:SetText(L["Blockliste"])
    if ns.Paint then ns.Paint(title, "heading") end
    local sub = win:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    sub:SetPoint("TOPLEFT", 14, -34); sub:SetPoint("RIGHT", -14, 0); sub:SetJustifyH("LEFT")
    sub:SetText(L["Diese Spieler werden nicht in die Gilde eingeladen. Gilt für die ganze Gilde, nur Offiziere ändern sie."])

    win.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, win)
        r:SetSize(432, 20)
        r:SetPoint("TOPLEFT", 14, -54 - (i - 1) * 22)
        if ns.Paint and i % 2 == 0 then ns.Paint(r:CreateTexture(nil, "BACKGROUND"), "glow", 0.05):SetAllPoints() end
        r.text = r:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
        r.text:SetPoint("LEFT", 4, 0); r.text:SetPoint("RIGHT", -96, 0)
        r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
        r.del = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        if ns.SkinButton then ns.SkinButton(r.del) end
        r.del:SetSize(86, 18); r.del:SetPoint("RIGHT", -2, 0); r.del:SetText(L["Entfernen"])
        r.del:SetScript("OnClick", function() if r.name then Block.Remove(r.name) end end)
        win.rows[i] = r
    end
    win.empty = win:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
    win.empty:SetPoint("TOPLEFT", 18, -58); win.empty:SetText(L["Niemand auf der Blockliste."])
    win:EnableMouseWheel(true)
    win:SetScript("OnMouseWheel", function(_, delta)
        win.offset = math.max(0, (win.offset or 0) - delta * 3)
        Block.RefreshWindow()
    end)

    local y = -58 - ROWS * 22
    local nameBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    nameBox:SetSize(150, 22); nameBox:SetPoint("TOPLEFT", 20, y)
    nameBox:SetAutoFocus(false); nameBox:SetMaxLetters(60)
    local reasonBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    reasonBox:SetSize(160, 22); reasonBox:SetPoint("LEFT", nameBox, "RIGHT", 10, 0)
    reasonBox:SetAutoFocus(false); reasonBox:SetMaxLetters(MAX_REASON)
    for _, b in ipairs({ nameBox, reasonBox }) do
        if ns.SkinEditBox then ns.SkinEditBox(b) end
        b:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    end
    local nameHint = nameBox:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    nameHint:SetPoint("LEFT", 2, 0); nameHint:SetText(L["Name"])
    local reasonHint = reasonBox:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    reasonHint:SetPoint("LEFT", 2, 0); reasonHint:SetText(L["Grund (optional)"])
    nameBox:SetScript("OnTextChanged", function(self) nameHint:SetShown(self:GetText() == "") end)
    reasonBox:SetScript("OnTextChanged", function(self) reasonHint:SetShown(self:GetText() == "") end)
    local add = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    if ns.SkinButton then ns.SkinButton(add) end
    add:SetSize(90, 22); add:SetPoint("LEFT", reasonBox, "RIGHT", 8, 0); add:SetText(L["Sperren"])
    local function DoAdd()
        local ok, why = Block.Add(nameBox:GetText(), reasonBox:GetText())
        if ok then
            nameBox:SetText(""); reasonBox:SetText(""); nameBox:ClearFocus(); reasonBox:ClearFocus()
        elseif why == "recht" then
            ns.Print(L["Nur Offiziere können die Blockliste ändern."])
        end
    end
    add:SetScript("OnClick", DoAdd)
    nameBox:SetScript("OnEnterPressed", DoAdd)
    reasonBox:SetScript("OnEnterPressed", DoAdd)
    win.add, win.nameBox, win.reasonBox = add, nameBox, reasonBox
    win:SetScript("OnShow", function()
        win.offset = 0
        ns.Queue("BLQ", nil, "1")
        Block.RefreshWindow()
    end)
    win:Hide()
end

function Block.RefreshWindow()
    if not win or not win:IsShown() then return end
    local list, officer = Block.List(), IsOfficer()
    win.offset = math.max(0, math.min(win.offset or 0, #list - ROWS))
    for i = 1, ROWS do
        local r, e = win.rows[i], list[i + win.offset]
        r:SetShown(e ~= nil)
        if e then
            r.name = e.name
            r.text:SetText("|cffff6060" .. Ambiguate(e.name, "none") .. "|r"
                .. (e.reason and ("  |cffcccccc" .. e.reason .. "|r") or "")
                .. (e.by and e.by ~= "" and ("  |cff777777(" .. Ambiguate(e.by, "guild") .. ")|r") or ""))
            r.del:SetShown(officer)
        end
    end
    win.empty:SetShown(#list == 0)
    win.add:SetEnabled(officer)
    win.nameBox:SetEnabled(officer); win.reasonBox:SetEnabled(officer)
end

function Block.Toggle()
    if not win then Build() end
    win:SetShown(not win:IsShown())
end

---------------------------------------------------------------------
-- /gp block Name [Grund] · /gp unblock Name · /gp blockliste
-- Forever-Namen haben Vor- und Nachname: Namen mit Leerzeichen in Anführungszeichen
---------------------------------------------------------------------
function Block.ParseArgs(rest)
    rest = strtrim(rest or "")
    local quoted, after = rest:match('^"([^"]+)"%s*(.*)$')
    if quoted then return quoted, after end
    local name, reason = rest:match("^(%S+)%s*(.*)$")
    return name, reason or ""
end

local origSlash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local raw = strtrim(arg or "")
    local cmd, rest = raw:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower()
    if cmd == "blockliste" or cmd == "blocklist" then
        Block.Toggle()
    elseif cmd == "block" or cmd == "sperren" then
        local name, reason = Block.ParseArgs(rest)
        local ok, why = Block.Add(name or "", reason or "")
        if ok then ns.Print((L["%s steht jetzt auf der Blockliste."]):format(name))
        elseif why == "recht" then ns.Print(L["Nur Offiziere können die Blockliste ändern."])
        else ns.Print(L["/gp block Name [Grund] – Name mit Leerzeichen in Anführungszeichen"]) end
    elseif cmd == "unblock" or cmd == "entsperren" then
        local name = Block.ParseArgs(rest)
        if name and Block.Remove(name) then ns.Print((L["%s ist nicht mehr auf der Blockliste."]):format(name))
        else ns.Print(L["Nicht auf der Blockliste (oder du bist kein Offizier)."]) end
    elseif origSlash then
        origSlash(arg)
    end
end

-- Nach dem Einloggen einmal die Liste anfragen
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    C_Timer.After(25, function() if IsInGuild() then ns.Queue("BLQ", nil, "1") end end)
end)
