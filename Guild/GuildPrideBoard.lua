-- GuildPride: Schwarzes Brett
-- Offiziere schreiben eine Mitteilung; jedes Mitglied mit GuildPride bekommt sie
-- einmal als Fenster angezeigt (beim Einloggen oder sofort), danach steht sie in
-- der Übersicht unter der Nachricht des Tages. Auf Wunsch auch nach Discord.
--   BRD: id, ver, autor, zeit, gelöscht (0/1), text
--   BRQ: Anfrage (Login) -> Antwort per Flüstern
-- Von Offizieren sofort, über andere Mitglieder erst bei zwei gleichen Meldungen.
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP

local Board = {}
ns.Board = Board
local MAX_LEN, KEEP_DAYS = 250, 30

local function DB() return ns.GuildTable("board") end   -- { id, ver, author, t, deleted, text }
local function Me() return ns.Me() end
local function Now() return GetServerTime() end
local function CanManage() return CanEditMOTD and CanEditMOTD() and true or false end
local function Clean(s, max) return (tostring(s or ""):gsub("|", ""):gsub("[%c]", " ")):sub(1, max) end

local function Current()
    local b = DB()
    if not b.id or b.deleted or not b.text or b.text == "" then return nil end
    if Now() - (b.t or 0) > KEEP_DAYS * 86400 then return nil end
    return b
end
Board.Current = Current

-- Für die Übersicht: Überschrift + Text, oder nil
function ns.BoardText()
    local b = Current()
    if not b then return nil end
    return ("|cffffd100%s|r |cff999999(%s, %s)|r\n%s"):format(L["Schwarzes Brett"], Ambiguate(b.author or "?", "guild"),
        ns.FormatDay(b.t or 0), b.text)
end

---------------------------------------------------------------------
-- Anzeige-Fenster
---------------------------------------------------------------------
local win
local function Seen()
    GuildPrideDB.boardSeen = GuildPrideDB.boardSeen or {}
    return GuildPrideDB.boardSeen
end
local function MarkSeen(b)
    local id = ns.GuildId()
    if id and b then Seen()[id] = b.id end
end

local function BuildWin()
    win = CreateFrame("Frame", "GuildPrideBoardFrame", UIParent, "BasicFrameTemplateWithInset")
    win:SetSize(420, 230); win:SetPoint("TOP", 0, -140); win:SetFrameStrata("DIALOG")
    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
    tinsert(UISpecialFrames, "GuildPrideBoardFrame")
    local title = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5); title:SetText(L["Schwarzes Brett"])
    win.head = win:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    win.head:SetPoint("TOPLEFT", 16, -34)
    win.body = win:CreateFontString(nil, "OVERLAY", "GPFont_Text")
    win.body:SetPoint("TOPLEFT", 16, -54); win.body:SetWidth(388); win.body:SetJustifyH("LEFT"); win.body:SetJustifyV("TOP")
    win.body:SetSpacing(3)
    local ok = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    ok:SetSize(120, 24); ok:SetPoint("BOTTOM", 0, 12); ok:SetText(L["Gelesen"])
    ok:SetScript("OnClick", function() win:Hide() end)
    win:SetScript("OnHide", function() MarkSeen(Current()) end)
    if ns.SkinWindow then pcall(ns.SkinWindow, win) end
end

function Board.Show()
    local b = Current()
    if not b then ns.Print(L["Am Schwarzen Brett hängt gerade nichts."]) return end
    if not win then BuildWin() end
    win.head:SetText((L["von %s · %s"]):format(Ambiguate(b.author or "?", "guild"), ns.FormatDate(b.t or 0, "long")))
    win.body:SetText(b.text)
    win:SetHeight(math.max(160, 110 + (tonumber(win.body:GetStringHeight()) or 60)))
    win:Show()
end

-- Noch nicht gesehen? Dann zeigen (nicht im Kampf, nicht dem Verfasser)
local function ShowIfNew()
    local b = Current()
    if not b or b.author == Me() then return end
    local id = ns.GuildId()
    if not id or Seen()[id] == b.id then return end
    if InCombatLockdown() then C_Timer.After(10, ShowIfNew) return end
    if GuildPrideDB.sound then PlaySound(SOUNDKIT.RAID_WARNING) end
    Board.Show()
end

---------------------------------------------------------------------
-- Senden / Anwenden
---------------------------------------------------------------------
local function Send(target)
    local b = DB()
    if b.id then ns.Queue("BRD", target, b.id, b.ver, b.author, b.t, b.deleted and 1 or 0, b.text or "") end
end

local function Apply(id, ver, author, t, deleted, text)
    local b = DB()
    if b.id and ver <= (b.ver or 0) then return false end
    b.id, b.ver, b.author, b.t, b.deleted, b.text = id, ver, author, t, deleted, text
    return true
end

ns.On("BRD", function(payload, sender)
    if sender == Me() then return end
    local a = { strsplit(SEP, payload) }
    local id, ver, author = Clean(a[1], 80), ns.Stamp(a[2]), Clean(a[3], 60)
    if id == "" or ver == 0 or author == "" or id:sub(1, #author + 1) ~= author .. "-" then return end
    -- Aushängen dürfen nur Offiziere
    if not ns.IsOfficerName(author) then return end
    if not ns.IsOfficerName(sender) and not ns.Confirmed("BRD\030" .. payload, sender) then return end
    local text = Clean(a[6], MAX_LEN)
    if a[5] ~= "1" and strtrim(text) == "" then return end
    if Apply(id, ver, author, ns.Stamp(a[4]), a[5] == "1", text) then
        if ns.RefreshUI then ns.RefreshUI() end
        ShowIfNew()
    end
end)

ns.On("BRQ", function(_, sender)
    if sender == Me() or not DB().id then return end
    C_Timer.After(math.random() * 4, function() Send(sender) end)
end)

---------------------------------------------------------------------
-- Aktionen (nur Offiziere, aus einem Klick)
---------------------------------------------------------------------
function Board.Post(text, toDiscord)
    if not CanManage() then return false end
    text = strtrim(Clean(text, MAX_LEN))
    if text == "" then return false end
    local id = Me() .. "-" .. Now() .. "-" .. math.random(1000, 9999)
    Apply(id, math.max(Now(), (DB().ver or 0) + 1), Me(), Now(), false, text)
    MarkSeen(DB())
    Send()
    if toDiscord and ns.Discord then
        ns.Discord.Post((ns.IS_GERMAN and "Ankündigung: %s" or "Announcement: %s"):format(text), true)
    end
    if ns.RefreshUI then ns.RefreshUI() end
    return true
end

function Board.Remove()
    if not CanManage() or not DB().id then return end
    local b = DB()
    Apply(b.id, math.max(Now(), (b.ver or 0) + 1), b.author, b.t, true, b.text)
    Send()
    if ns.RefreshUI then ns.RefreshUI() end
end

---------------------------------------------------------------------
-- Ereignisse und Befehl
---------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
local started = false
ev:SetScript("OnEvent", function()
    if started or not GuildPrideDB then return end
    started = true
    C_Timer.After(35, function()
        if not IsInGuild() then return end
        ns.Queue("BRQ", nil, "1")
        -- Schon bekannte, ungelesene Mitteilung nach dem Abgleich zeigen
        C_Timer.After(15, ShowIfNew)
    end)
end)

local slash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd = strtrim(arg or ""):lower()
    if cmd == "brett" or cmd == "board" then Board.Show() return end
    return slash(arg)
end
