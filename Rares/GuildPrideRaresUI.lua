-- GuildPride Rares: Fenster mit allen bekannten Rares und Weltbossen, Slash-Befehle
local ADDON, GP = ...
-- Rare-Scanner läuft in einem eigenen Unter-Namensraum, damit sich nichts mit GuildPride beißt
GP.Rares = GP.Rares or {}
local ns = GP.Rares

local ROWS, ROW_H = 14, 20
local win = CreateFrame("Frame", "GPRaresWindow", UIParent, "BackdropTemplate")
win:SetFrameStrata("HIGH")
win:SetSize(560, 92 + ROWS * ROW_H + 44)
ns.SkinDialog(win)   -- nach SetSize: Ecken passen sich der Größe an
win:SetPoint("CENTER")
win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
win:SetClampedToScreen(true)
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)
win:Hide()
tinsert(UISpecialFrames, "GPRaresWindow")   -- Esc schließt
local title = win:CreateFontString(nil, "OVERLAY", "GPFont_Large")
title:SetPoint("TOPLEFT", 14, -12); title:SetText("Rares & Weltbosse")
ns.Paint(title, "heading")
ns.CloseButton(win)

-- Reiter: Rares / Weltbosse
local mode = "rares"
local function Tab(text, x, m)
    local b = ns.SkinButton(CreateFrame("Button", nil, win, "UIPanelButtonTemplate"))
    b:SetSize(110, 22); b:SetPoint("TOPLEFT", x, -42); b:SetText(text)
    b:SetScript("OnClick", function() mode = m; win.offset = 0; ns.RefreshUI() end)
    return b
end
Tab("Rares", 12, "rares")
Tab("Weltbosse", 128, "bosses")
local status = win:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
status:SetPoint("TOPRIGHT", -14, -48)

local head = win:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
head:SetPoint("TOPLEFT", 16, -72)
ns.Paint(head, "title")

local rows = {}
for i = 1, ROWS do
    local r = CreateFrame("Button", nil, win)
    r:SetSize(530, ROW_H)
    r:SetPoint("TOPLEFT", 14, -86 - (i - 1) * ROW_H)
    -- Zeilenstreifen und Hover in der Glut-Farbe des Styles
    if i % 2 == 0 then ns.Paint(r:CreateTexture(nil, "BACKGROUND"), "glow", 0.05):SetAllPoints() end
    local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); ns.Paint(hl, "glow", 0.15)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r.star = r:CreateFontString(nil, "OVERLAY", "GPFont_Text"); r.star:SetPoint("LEFT", 2, 0); r.star:SetWidth(16)
    r.name = r:CreateFontString(nil, "OVERLAY", "GPFont_Text"); r.name:SetPoint("LEFT", 22, 0)
    r.name:SetWidth(170); r.name:SetJustifyH("LEFT")
    r.zone = r:CreateFontString(nil, "OVERLAY", "GPFont_Text"); r.zone:SetPoint("LEFT", 196, 0)
    r.zone:SetWidth(130); r.zone:SetJustifyH("LEFT")
    r.seen = r:CreateFontString(nil, "OVERLAY", "GPFont_Text"); r.seen:SetPoint("LEFT", 330, 0)
    r.seen:SetWidth(95); r.seen:SetJustifyH("LEFT")
    r.kill = r:CreateFontString(nil, "OVERLAY", "GPFont_Text"); r.kill:SetPoint("LEFT", 428, 0)
    r.kill:SetWidth(100); r.kill:SetJustifyH("LEFT")
    r:SetScript("OnClick", function(self, button)
        if not self.npc then return end
        if button == "RightButton" then
            local f = ns.DB().fav
            f[self.npc] = not f[self.npc] or nil
            ns.RefreshUI()
        elseif ns.DB().seen[self.npc] then
            ns.ShowAlert(self.npc, "")
        end
    end)
    r:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Linksklick: Alarm mit Anvisieren-Knopf und Wegpunkt", 1, 1, 1)
        GameTooltip:AddLine("Rechtsklick: Favorit an/aus (Favoriten alarmieren immer)", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = r
end

win.offset = 0
win:EnableMouseWheel(true)
win:SetScript("OnMouseWheel", function(self, d)
    self.offset = math.max(0, self.offset - d * 3)
    ns.RefreshUI()
end)

-- Einstellungen unten
local function Check(label, key, x)
    local c = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    c:SetSize(22, 22); c:SetPoint("BOTTOMLEFT", x, 10)
    c.text = c.text or c.Text or c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.text:ClearAllPoints(); c.text:SetPoint("LEFT", c, "RIGHT", 2, 0)
    c.text:SetFontObject("GPFont_TextSmall"); c.text:SetText(label)
    c:SetScript("OnShow", function(self) self:SetChecked(ns.Opt(key) and true or false) end)
    c:SetScript("OnClick", function(self) ns.DB().opts[key] = self:GetChecked() and true or false end)
    return c
end
local on = Check("An", "enabled", 12)
on:HookScript("OnClick", function() if ns.UpdateMapToggle then ns.UpdateMapToggle() end end)
Check("Ton", "sound", 62)
Check("Alarm alle Rares", "alertAll", 112)
Check("Weltbosse", "alertBoss", 242)
Check("Karte", "pins", 332)

local function BossWindow(npc)
    local b, k = ns.WORLD_BOSSES[npc], ns.DB().killed[npc]
    if not k then return "kein Tod bekannt" end
    local now = GetServerTime()
    local from, to = k + b.min * 3600, k + b.max * 3600
    if now < from then return ("ab in %d Std."):format((from - now) / 3600) end
    if now < to then return "|cff40ff40jetzt möglich|r" end
    return "überfällig"
end

function ns.RefreshUI()
    if not win:IsShown() then return end
    local db, list = ns.DB(), {}
    if mode == "rares" then
        head:SetText("     Name                                   Gebiet                         Zuletzt gesehen       Zuletzt getötet")
        for npc, e in pairs(db.seen) do if not e.boss then list[#list + 1] = { npc = npc, e = e } end end
        table.sort(list, function(a, b)
            local fa, fb = db.fav[a.npc] and 1 or 0, db.fav[b.npc] and 1 or 0
            if fa ~= fb then return fa > fb end
            return (a.e.t or 0) > (b.e.t or 0)
        end)
    else
        head:SetText("     Weltboss                               Gebiet                         Zuletzt gesehen       Nächstes Fenster")
        for npc, b in pairs(ns.WORLD_BOSSES) do list[#list + 1] = { npc = npc, e = db.seen[npc], boss = b } end
        table.sort(list, function(a, b) return a.boss.name < b.boss.name end)
    end
    win.offset = math.min(win.offset, math.max(0, #list - ROWS))
    local now = GetServerTime()
    for i = 1, ROWS do
        local r, item = rows[i], list[i + win.offset]
        if item then
            local e = item.e
            r.npc = item.npc
            r.star:SetText(db.fav[item.npc] and "|cffffd100★|r" or "")
            local fresh = e and e.t and now - e.t <= ns.FRESH and not (e.dead and e.dead >= e.t)
            local name = e and e.name or item.boss.name
            r.name:SetText(fresh and ("|cff40ff40" .. name .. "|r") or name)
            r.zone:SetText(e and ns.MapName(e.map) or "–")
            r.seen:SetText(e and ns.Ago(e.t) or "–")
            r.kill:SetText(mode == "bosses" and BossWindow(item.npc) or ns.Ago(db.killed[item.npc]))
            r:Show()
        else
            r.npc = nil
            r:Hide()
        end
    end
    status:SetText(ns.ChannelId and ns.ChannelId() and "|cff40ff40serverweit verbunden|r" or "|cffff6060Kanal fehlt|r")
end
win:SetScript("OnShow", function() ns.Repaint(); ns.RefreshUI() end)
C_Timer.NewTicker(15, function() ns.RefreshUI() end)

function ns.OnReady()
    -- nichts weiter nötig; Fenster liest die Daten beim Öffnen
end

---------------------------------------------------------------------
-- Slash-Befehle
---------------------------------------------------------------------
SLASH_GPRARES1, SLASH_GPRARES2 = "/gpr", "/gprares"
SlashCmdList.GPRARES = function(arg)
    local cmd = strtrim(arg or ""):lower()
    if cmd == "an" or cmd == "aus" or cmd == "on" or cmd == "off" then
        ns.DB().opts.enabled = (cmd == "an" or cmd == "on")
        if ns.UpdateMapToggle then ns.UpdateMapToggle() end
        ns.Print(ns.Enabled() and "Rare-Scanner an" or "Rare-Scanner aus")
    elseif cmd == "knopf" then
        ns.DB().opts.mapButton = not ns.Opt("mapButton")
        if ns.UpdateToggleShown then ns.UpdateToggleShown() end
        ns.Print(ns.Opt("mapButton") and "Knopf oben links auf der Weltkarte an." or "Knopf auf der Weltkarte aus – An/Aus jetzt im Kartenfilter.")
    elseif cmd == "weit" then
        -- Namensplaketten weiter sichtbar: Rares werden früher erkannt
        if InCombatLockdown() then
            ns.Print("Im Kampf nicht möglich – bitte nach dem Kampf noch einmal.")
            return
        end
        SetCVar("nameplateMaxDistance", 80)
        ns.Print("Namensplaketten-Reichweite auf 80 gesetzt. Gegner-Namensplaketten müssen eingeschaltet sein (Taste V).")
    elseif cmd == "status" then
        ns.Print(ns.CommStatus())
    elseif cmd == "reset" then
        wipe(ns.DB().seen); wipe(ns.DB().killed)
        ns.Print("Sichtungen und Tode gelöscht (Favoriten bleiben).")
        ns.RefreshUI()
    elseif cmd == "help" or cmd == "hilfe" then
        ns.Print("/gpr – Fenster · /gpr an|aus · /gpr knopf – Kartenknopf an/aus · /gpr weit – größere Reichweite · /gpr status – Kanal · /gpr reset – Daten löschen")
        ns.Print("Taste zum Anvisieren: Makro mit /click GPRaresTarget erstellen und auf eine Leiste legen.")
    else
        win:SetShown(not win:IsShown())
    end
end

-- Auch über /gp rares erreichbar
local gpSlash = SlashCmdList.GUILDPRIDE
if gpSlash then
    SlashCmdList.GUILDPRIDE = function(arg)
        local cmd, rest = strtrim(arg or ""):match("^(%S*)%s*(.-)$")
        if cmd and cmd:lower() == "rares" then SlashCmdList.GPRARES(rest) else gpSlash(arg) end
    end
end
