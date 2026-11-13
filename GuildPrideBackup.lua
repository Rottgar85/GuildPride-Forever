-- GuildPride: Datensicherung per Knopfdruck
--
-- Sichert ALLE GuildPride-Daten dieses Accounts (Einstellungen, alle Gilden mit
-- DKP, Events, Umfragen, Verlauf, Ausweise …) als Kopie in GuildPrideBackupDB.
-- Bis zu MAX_SNAPSHOTS Sicherungen; die älteste fliegt raus. Zusätzlich einmal
-- pro Woche automatisch beim Login.
--
-- Ehrlich: Beide liegen in derselben Datei (WTF\Account\…\SavedVariables\
-- GuildPrideForever.lua). Die Sicherung schützt vor Fehlern im Spiel (falsche
-- DKP-Buchung, versehentlich gelöscht, kaputtes Update), nicht davor, dass die
-- Datei selbst verloren geht. Dafür die Datei zusätzlich kopieren.
local ADDON, ns = ...
local L = ns.L

local MAX_SNAPSHOTS = 5
local AUTO_DAYS = 7

local function Copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = Copy(x) end
    return t
end

-- grobe Größe (Anzahl Werte), damit man Sicherungen vergleichen kann
local function Count(v)
    if type(v) ~= "table" then return 1 end
    local n = 0
    for _, x in pairs(v) do n = n + Count(x) end
    return n
end

local function DB()
    GuildPrideBackupDB = GuildPrideBackupDB or {}
    GuildPrideBackupDB.snaps = GuildPrideBackupDB.snaps or {}
    return GuildPrideBackupDB
end

-- Neue Sicherung anlegen; note = "Hand" oder "Auto"
function ns.BackupNow(note)
    if not GuildPrideDB then return end
    local snaps = DB().snaps
    table.insert(snaps, 1, { t = time(), note = note or "Hand", who = ns.Me and ns.Me() or "?",
                             size = Count(GuildPrideDB), data = Copy(GuildPrideDB) })
    while #snaps > MAX_SNAPSHOTS do table.remove(snaps) end
    DB().last = time()
    if ns.RefreshBackupWindow then ns.RefreshBackupWindow() end
    return true
end

-- Sicherung zurückspielen: vorher den jetzigen Stand sichern, dann neu laden
local function Restore(i)
    local snap = DB().snaps[i]
    if not snap then return end
    local data = Copy(snap.data)
    ns.BackupNow("Vor Wiederherstellung")
    wipe(GuildPrideDB)
    for k, v in pairs(data) do GuildPrideDB[k] = v end
    ReloadUI()
end

StaticPopupDialogs["GUILDPRIDE_RESTORE"] = {
    text = L["Sicherung vom %s wiederherstellen? Der jetzige Stand wird vorher gesichert, danach lädt das Interface neu."],
    button1 = YES, button2 = NO,
    OnAccept = function(_, i) Restore(i) end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

---------------------------------------------------------------------
-- Fenster: Liste der Sicherungen, "Jetzt sichern", je Zeile "Wiederherstellen"
---------------------------------------------------------------------
local win
local function DateText(t) return date("%d.%m.%Y %H:%M", t) end

local function Build()
    win = CreateFrame("Frame", "GuildPrideBackupFrame", UIParent, "BackdropTemplate")
    win:SetSize(460, 96 + MAX_SNAPSHOTS * 28)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true); win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    tinsert(UISpecialFrames, "GuildPrideBackupFrame")   -- ESC schließt

    local title = win:CreateFontString(nil, "OVERLAY", "GPFont_Large")
    title:SetPoint("TOPLEFT", 18, -16)
    title:SetText(L["Datensicherung"])
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local save = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    save:SetSize(140, 24); save:SetPoint("TOPRIGHT", -36, -14)
    save:SetText(L["Jetzt sichern"])
    save:SetScript("OnClick", function()
        ns.BackupNow("Hand")
        ns.Print(L["Alle GuildPride-Daten wurden gesichert."])
    end)

    local hint = win:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    hint:SetPoint("BOTTOMLEFT", 18, 14); hint:SetPoint("BOTTOMRIGHT", -18, 14)
    hint:SetJustifyH("LEFT"); hint:SetWordWrap(true)
    hint:SetText(L["Sichert alles (Einstellungen, DKP, Events, Umfragen, Verlauf, Twinks). Wöchentlich automatisch. Gegen Datenverlust zusätzlich die Datei WTF\\Account\\…\\SavedVariables\\GuildPrideForever.lua kopieren."])

    win.rows = {}
    for i = 1, MAX_SNAPSHOTS do
        local row = CreateFrame("Frame", nil, win)
        row:SetSize(424, 26)
        row:SetPoint("TOPLEFT", 18, -46 - (i - 1) * 28)
        row.text = row:CreateFontString(nil, "OVERLAY", "GPFont_Text")
        row.text:SetPoint("LEFT")
        row.btn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.btn:SetSize(130, 22); row.btn:SetPoint("RIGHT")
        row.btn:SetText(L["Wiederherstellen"])
        row.btn:SetScript("OnClick", function()
            local snap = DB().snaps[i]
            if snap then StaticPopup_Show("GUILDPRIDE_RESTORE", DateText(snap.t), nil, i) end
        end)
        win.rows[i] = row
    end
    win.empty = win:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
    win.empty:SetPoint("TOPLEFT", 18, -52)
    win.empty:SetText(L["Noch keine Sicherung vorhanden."])
    if ns.SkinWindow then pcall(ns.SkinWindow, win) end
end

function ns.RefreshBackupWindow()
    if not (win and win:IsShown()) then return end
    local snaps = DB().snaps
    win.empty:SetShown(#snaps == 0)
    for i, row in ipairs(win.rows) do
        local s = snaps[i]
        row:SetShown(s ~= nil)
        if s then
            local kind = s.note == "Auto" and L["automatisch"] or s.note == "Hand" and L["von Hand"] or L["vor Wiederherstellung"]
            row.text:SetText(("%s  |cff999999%s · %d %s|r"):format(DateText(s.t), kind, s.size or 0, L["Einträge"]))
        end
    end
end

function ns.ToggleBackupWindow()
    if not win then Build() end
    win:SetShown(not win:IsShown())
    ns.RefreshBackupWindow()
end

---------------------------------------------------------------------
-- Automatisch: einmal pro Woche beim Login (nach dem Laden aller Daten)
---------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    C_Timer.After(60, function()
        if not GuildPrideDB then return end
        local last = DB().last or 0
        if time() - last >= AUTO_DAYS * 86400 then ns.BackupNow("Auto") end
    end)
end)
