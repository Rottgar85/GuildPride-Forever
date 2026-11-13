-- GuildPride: Warnung bei Beitritt / Austritt (nur Info, begrüßt wird von Hand)
local ADDON, ns = ...
local L = ns.L

-- Blizzard-Systemtexte (sprachunabhängig) in Lua-Muster umwandeln
local function ToPattern(fmt)
    if not fmt then return nil end
    local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%%%d%%%$s", "(.+)")   -- %1$s
    p = p:gsub("%%%%s", "(.+)")         -- %s
    return "^" .. p .. "$"
end

local JOIN  = ToPattern(ERR_GUILD_JOIN_S)
local LEAVE = ToPattern(ERR_GUILD_LEAVE_S)
local KICK  = ToPattern(ERR_GUILD_REMOVE_SS)


---------------------------------------------------------------------
-- Hinweisfenster oben am Bildschirm
---------------------------------------------------------------------
local toast = CreateFrame("Frame", "GuildPrideMemberToast", UIParent, "BackdropTemplate")
toast:SetSize(420, 96)
toast:SetPoint("TOP", 0, -140)
toast:SetFrameStrata("DIALOG")
toast:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
    tile = true, tileSize = 32, edgeSize = 24,
    insets = { left = 6, right = 6, top = 6, bottom = 6 },
})
toast:Hide()

local icon = toast:CreateTexture(nil, "ARTWORK")
icon:SetSize(48, 48)
icon:SetPoint("LEFT", 16, 6)

local headline = toast:CreateFontString(nil, "OVERLAY", "GPFont_Large")
headline:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -2)

local line = toast:CreateFontString(nil, "OVERLAY", "GPFont_Text")
line:SetPoint("TOPLEFT", headline, "BOTTOMLEFT", 0, -6)
line:SetWidth(320); line:SetJustifyH("LEFT")

local dismiss = CreateFrame("Button", nil, toast, "UIPanelCloseButton")
dismiss:SetPoint("TOPRIGHT", -2, -2)
dismiss:SetScript("OnClick", function() toast:Hide() end)

local hideTimer
local rejoinNote   -- "War schon Mitglied …" für den nächsten Beitritts-Hinweis
local function ShowToast(kind, name)
    local short = Ambiguate(name, "guild")
    if kind == "join" then
        headline:SetText(L["|cff40ff40Neues Gildenmitglied!|r"])
        line:SetText((L["|cffffd100%s|r ist der Gilde beigetreten.\nSag Hallo!"]):format(short)
            .. (rejoinNote and ("\n|cffaaaaaa" .. rejoinNote .. "|r") or ""))
        rejoinNote = nil
        icon:SetTexture("Interface\\AddOns\\GuildPrideForever\\Media\\logo")
    else
        headline:SetText(L["|cffff4040Mitglied hat die Gilde verlassen|r"])
        line:SetText(("|cffffd100%s|r %s"):format(short, kind == "kick" and L["wurde aus der Gilde entfernt."] or L["hat die Gilde verlassen."]))
        icon:SetTexture("Interface\\Icons\\Ability_Rogue_FeignDeath")
    end
    toast:Show()
    if GuildPrideDB.sound then
        PlaySound(kind == "join" and SOUNDKIT.READY_CHECK or SOUNDKIT.RAID_WARNING)
    end
    if hideTimer then hideTimer:Cancel() end
    hideTimer = C_Timer.NewTimer(kind == "join" and 30 or 12, function() toast:Hide() end)

    -- Im Verlauf (Reiter Meilensteine) festhalten
    ns.AddLog(kind == "join" and "JOIN" or (kind == "kick" and "KICK" or "LEAVE"), short)
    -- Wer geht, kennt den Kanal-Schlüssel: Gildenleitung erzeugt einen neuen
    if kind ~= "join" and ns.RotateChannelKey then ns.RotateChannelKey() end
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
end

---------------------------------------------------------------------
-- Systemnachrichten auswerten
---------------------------------------------------------------------
---------------------------------------------------------------------
-- Automatische Begrüßung (Einstellung). Jeder mit GuildPride wartet zufällig
-- 2–8 s; wer zuerst begrüßt, meldet das ("WEL"), die anderen schweigen.
---------------------------------------------------------------------
ns.WELCOME_DEFAULT = L["Willkommen in der Gilde, {name}!"]
local welcomed = {}   -- [Name] = Zeit, zu der jemand begrüßt hat

ns.On("WEL", function(payload)
    if payload and payload ~= "" then welcomed[Ambiguate(payload, "none")] = GetTime() end
end)

-- Chat-Sperre (Midnight, z. B. in Instanzen): dann nicht senden
local function Locked()
    return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
end

local function Welcome(name)
    if not GuildPrideDB.welcome then return end
    local short = Ambiguate(name, "none")
    C_Timer.After(2 + math.random() * 6, function()
        if welcomed[short] and GetTime() - welcomed[short] < 60 then return end
        if Locked() or not IsInGuild() then return end
        welcomed[short] = GetTime()
        ns.Queue("WEL", nil, short)
        local text = strtrim(GuildPrideDB.welcomeText or "")
        if text == "" then text = ns.WELCOME_DEFAULT end
        local SendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
        SendChat((text:gsub("{name}", Ambiguate(name, "guild"))), "GUILD")
    end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_SYSTEM")
f:SetScript("OnEvent", function(_, _, msg)
    if not GuildPrideDB then return end
    if issecretvalue and issecretvalue(msg) then return end
    if type(msg) ~= "string" then return end

    local name = JOIN and msg:match(JOIN)
    if name then
        if ns.HistoryRejoinText then rejoinNote = ns.HistoryRejoinText(ns.Normalize(name)) end
        if ns.HistoryJoin then ns.HistoryJoin(ns.Normalize(name)) end
        if ns.ResetRankSince then ns.ResetRankSince(name) end
        if Ambiguate(name, "none") ~= UnitName("player") then
            Welcome(name)
            if GuildPrideDB.memberAlerts ~= false then ShowToast("join", name) end
        end
        return
    end
    local gone = (LEAVE and msg:match(LEAVE)) or (KICK and select(1, msg:match(KICK)))
    if gone and ns.HistoryLeave then ns.HistoryLeave(ns.Normalize(gone)) end
    if GuildPrideDB.memberAlerts == false then return end
    name = LEAVE and msg:match(LEAVE)
    if name then ShowToast("leave", name); return end
    name = KICK and msg:match(KICK)
    if name then ShowToast("kick", name) end
end)

---------------------------------------------------------------------
-- Beförderung nach Zeit: Blizzard kennt kein Beitrittsdatum. GuildPride merkt
-- sich daher je Mitglied, seit wann es seinen aktuellen Rang hat (zuerst
-- gesehen oder Rangwechsel). Wer schon vor dem Update in der Gilde war,
-- zählt ab dem ersten Login mit dieser Version. Regeln: Rang A -> Rang B
-- nach N Tagen, je Gilde gespeichert.
---------------------------------------------------------------------
local function GuildStore(key)
    local guild = GetGuildInfo("player")
    if not guild then return end
    GuildPrideDB[key] = GuildPrideDB[key] or {}
    GuildPrideDB[key][guild] = GuildPrideDB[key][guild] or {}
    return GuildPrideDB[key][guild]
end

function ns.PromoteRules() return GuildStore("promoteRules") or {} end

-- Rangname -> Rangnummer (0 = Gildenleitung)
function ns.RankIndexByName(rankName)
    local num = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
    for r = 0, num - 1 do
        if GuildControlGetRankName(r + 1) == rankName then return r end
    end
end

-- Seit wann (Serverzeit) hat das Mitglied seinen Rang? nil = unbekannt
function ns.RankSince(full)
    local store = GuildStore("rankSince")
    local e = store and store[full]
    return e and e.t
end

-- Gilden-Ereignisprotokoll (Beitritt, Beförderung, Degradierung mit "vor …"):
-- je Spieler die Zeit des letzten Rangwechsels, dazu die Zeit des ältesten
-- Eintrags. Wer nicht im Protokoll steht, hat seinen Rang mindestens so lange.
local function LogTimes(now)
    local times, oldest = {}, nil
    if not (GetNumGuildEvents and GetGuildEventInfo) then return times end
    for i = 1, GetNumGuildEvents() do
        local kind, p1, p2, _, y, mo, d, h = GetGuildEventInfo(i)
        local t = now - (((y or 0) * 365 + (mo or 0) * 30 + (d or 0)) * 24 + (h or 0)) * 3600
        if not oldest or t < oldest then oldest = t end
        local who = (kind == "join" and p1) or ((kind == "promote" or kind == "demote") and p2)
        if type(who) == "string" and who ~= "" then
            who = ns.FullName and ns.FullName(who) or who
            if not times[who] or t > times[who] then times[who] = t end
        end
    end
    return times, oldest
end

local function TrackRanks()
    if not GuildPrideDB or not IsInGuild() then return end
    local store = GuildStore("rankSince")
    local n = GetNumGuildMembers()
    if not store or n == 0 then return end
    local now = GetServerTime()
    local times, oldest = LogTimes(now)
    for i = 1, n do
        local name, rank = GetGuildRosterInfo(i)
        if name and rank then
            local full = ns.FullName and ns.FullName(name) or name
            local e = store[full]
            if e and e.r ~= rank then
                -- Rangwechsel gesehen: Zeit aus dem Protokoll, sonst jetzt
                store[full] = { r = rank, t = times[full] or now }
            else
                local t = times[full] or oldest or now
                if not e then store[full] = { r = rank, t = t }
                elseif t < e.t then e.t = t end   -- Protokoll weiß es genauer (früher)
            end
        end
    end
end

-- Neu beigetreten: Zeit ab jetzt (auch bei Wiedereintritt)
function ns.ResetRankSince(name)
    local store = GuildStore("rankSince")
    -- leerer Rang: beim nächsten Abgleich zählt das als Rangwechsel (Zeit ab jetzt)
    if store then store[ns.FullName and ns.FullName(name) or name] = { r = "", t = GetServerTime() } end
end

-- Zielrang (Nummer) und Regel, wenn eine Beförderung fällig ist und ich sie darf
function ns.PromoteTarget(m)
    if not (m and m.guild and m.rank and m.full) or m.isSelf then return end
    local since = ns.RankSince(m.full)
    if not since then return end
    local _, _, my = GetGuildInfo("player")
    for _, rule in ipairs(ns.PromoteRules()) do
        if rule.from == m.rank and GetServerTime() - since >= rule.days * 86400 then
            local target = ns.RankIndexByName(rule.to)
            if target and my and target < m.rankIndex and target > my then return target, rule end
        end
    end
end

-- Protokoll beim Einloggen anfordern; es kommt mit GUILD_EVENT_LOG_UPDATE
function ns.QueryRankLog()
    if IsInGuild() and QueryGuildEventLog then QueryGuildEventLog() end
end

local tracker = CreateFrame("Frame")
tracker:RegisterEvent("GUILD_ROSTER_UPDATE")
tracker:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(tracker.RegisterEvent, tracker, "GUILD_EVENT_LOG_UPDATE")
tracker:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then C_Timer.After(5, ns.QueryRankLog) return end
    TrackRanks()
end)
