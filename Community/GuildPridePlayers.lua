-- GuildPride: Wer nutzt GuildPride? Liste aller GuildPride-Spieler auf dem Server (mit Zone),
-- Gildenmitglieder grün. Früher Teil des Layer-Wechsels (GuildPrideLayer.lua), der seit Blizzards
-- Hotfix vom 20.11.2026 nicht mehr geht; die Meldungen behalten ihre Namen, damit ältere
-- Versionen weiter mitzählen:
--   LYS  F · Karte · ""    „ich bin da“ im offenen GuildPride-Kanal (das dritte Feld war der Layer)
--   LYP  F                 alle fragen; geantwortet wird öffentlich, höchstens einmal pro Minute
-- Gildenmitglieder mit GuildPride kommen zusätzlich aus der Versionsabfrage (ns.Versions).
-- Öffnen: Knopf über „Einstellungen“ im Gildenfenster oder /gp spieler.
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP or "\031"

local P = { public = {} }   -- public["Name"] = { map, t }
ns.Players = P

local MAX_AGE = 25 * 60     -- s: so lange gilt eine Meldung (danach offline oder ohne Kanal)
local HEARTBEAT = 10 * 60   -- s: so oft meldet man sich von selbst
local PUBLIC_MAX = 400
local publicCount = 0

local function Secret(v) return issecretvalue and issecretvalue(v) or false end

local function MapId()
    local m = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    return type(m) == "number" and not Secret(m) and m or nil
end

-- Gehört zur serverweiten Gruppensuche: nur mit „Serverweite Gruppensuche“ an
local function Available()
    return ns.IS_FOREVER and ns.PublicLFGOn and ns.PublicLFGOn() and ns.PublicChannelId and ns.PublicChannelId()
        and not ns.PUBLIC_VIA_CHAT and true or false
end
P.Available = Available

---------------------------------------------------------------------
-- Melden und fragen
---------------------------------------------------------------------
local lastShareAt, sharePending, lastMap = -999, false, nil
function P.Share(force)
    if not Available() or IsInInstance() then return end
    local map = MapId() or 0
    if not force and map == lastMap and GetTime() - lastShareAt < HEARTBEAT then return end
    -- höchstens alle 30 s; den letzten Stand dann nachholen
    local wait = 30 - (GetTime() - lastShareAt)
    if wait > 0 then
        if not sharePending and C_Timer and C_Timer.After then
            sharePending = true
            C_Timer.After(wait + 0.1, function() sharePending = false; P.Share(force) end)
        end
        return
    end
    lastShareAt, lastMap = GetTime(), map
    ns.Queue("LYS", "@PUBLIC", ns.CLIENT_TAG, map, "")
end

local function Store(sender, map)
    if type(sender) ~= "string" or Secret(sender) or #sender > 60 or sender:find("|", 1, true) then return end
    map = tonumber(map)
    if map and (map <= 0 or map > 999999) then map = nil end
    if not P.public[sender] then
        if publicCount >= PUBLIC_MAX then return end
        publicCount = publicCount + 1
    end
    P.public[sender] = { map = map, t = GetTime() }
    if P.Refresh then P.Refresh() end
end

local lastAnswer = -999
local function Answer()
    if GetTime() - lastAnswer < 60 then return end
    lastAnswer = GetTime()
    local function go() P.Share(true) end
    if C_Timer and C_Timer.After then C_Timer.After(1 + math.random() * 9, go) else go() end
end

-- Aus GuildPride.lua: LYS/LYP aus dem offenen Kanal (andere LY-Arten gibt es nicht mehr)
function ns.OnPlayersMessage(message, sender)
    if not ns.IS_FOREVER or type(message) ~= "string" or sender == ns.Me() then return end
    local kind, value = message:match("^(LY%u):(.*)$")
    if not kind then return end
    local f = { strsplit(SEP, value) }
    if f[1] ~= ns.CLIENT_TAG then return end
    if kind == "LYS" then Store(sender, f[2])
    elseif kind == "LYP" and Available() then Answer() end
end

-- Gilde und Server fragen (Liste öffnen / Aktualisieren)
local lastAsk, lastVerAsk = -999, -999
function P.Ask()
    if IsInGuild() and ns.VERSION and ns.Queue and GetTime() - lastVerAsk > 120 then
        lastVerAsk = GetTime()
        ns.Queue("VER", nil, ns.VERSION, "")
    end
    if not Available() or GetTime() - lastAsk < 60 then return end
    lastAsk = GetTime()
    ns.Queue("LYP", "@PUBLIC", ns.CLIENT_TAG)
    P.Share(true)
end

---------------------------------------------------------------------
-- Liste: gleiche Zone zuerst, dann Gilde, dann Name
---------------------------------------------------------------------
function P.List()
    local list, seen, now, myMap = {}, {}, GetTime(), MapId()
    -- Gildenmitglieder mit GuildPride (Versionsabfrage), die online sind
    if ns.Versions and GetNumGuildMembers and GetGuildRosterInfo then
        for i = 1, GetNumGuildMembers() or 0 do
            local rname, _, _, _, _, zone, _, _, online = GetGuildRosterInfo(i)
            local full = rname and (ns.FullName and ns.FullName(rname) or rname)
            if online and full and ns.Versions[full] and full ~= ns.Me() then
                seen[full] = true
                list[#list + 1] = { name = full, guild = true, zoneText = type(zone) == "string" and zone or nil }
            end
        end
    end
    for name, e in pairs(P.public) do
        if now - e.t > MAX_AGE then
            P.public[name] = nil
            publicCount = publicCount - 1
        elseif name ~= ns.Me() then
            if seen[name] then
                for _, x in ipairs(list) do if x.name == name then x.map = e.map end end
            else
                list[#list + 1] = { name = name, map = e.map, guild = ns.IsGuildMember and ns.IsGuildMember(name) or false }
            end
        end
    end
    for _, x in ipairs(list) do x.here = x.map ~= nil and x.map == myMap end
    table.sort(list, function(a, b)
        if a.here ~= b.here then return a.here end
        if a.guild ~= b.guild then return a.guild end
        return a.name < b.name
    end)
    return list
end

-- Anzahl samt dir selbst (für Knopf und Tooltip)
function P.Count()
    local n, g = 1, 0
    for _, e in ipairs(P.List()) do
        n = n + 1
        if e.guild then g = g + 1 end
    end
    return n, g
end

---------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------
local win
local ROWS = 12

local function ZoneName(map)
    local info = map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
    return info and info.name or L["unbekannt"]
end

local function Refresh()
    if P.button then P.button:SetText(tostring((P.Count()))) end
    if not win or not win:IsShown() then return end
    local entries = P.List()
    local maxOff = math.max(0, #entries - ROWS)
    win.offset = math.min(win.offset or 0, maxOff)
    for i = 1, ROWS do
        local row, e = win.rows[i], entries[i + win.offset]
        if e then
            row.name:SetText((ns.NameMark and ns.NameMark(e.name) or "") .. (e.guild and "|cff60d060" or "|cffe6e0da")
                .. Ambiguate(e.name, "none") .. "|r")
            local zoneTxt = e.zoneText or ZoneName(e.map)
            row.zone:SetText((e.here and "|cffe6e0da" or "|cff888888") .. zoneTxt .. "|r")
            row:Show()
        else
            row:Hide()
        end
    end
    local guildN = 0
    for _, e in ipairs(entries) do if e.guild then guildN = guildN + 1 end end
    local more = #entries - ROWS - win.offset
    win.empty:SetShown(#entries == 0)
    win.empty:SetText(Available() and L["Noch keine Meldungen – die Liste füllt sich in den nächsten Sekunden."]
        or L["Für alle Spieler auf dem Server: Einstellungen › Serverweite Gruppensuche einschalten. Ohne sie siehst du nur deine Gilde."])
    win.count:SetText((L["%d Spieler mit GuildPride (%d aus der Gilde, grün)"]):format(#entries + 1, guildN)
        .. (more > 0 and ("  ·  " .. (L["… und %d weitere"]):format(more) .. " " .. L["(Mausrad)"]) or ""))
end
P.Refresh = Refresh

function P.Toggle()
    if not ns.IS_FOREVER then return end
    if not win then
        win = CreateFrame("Frame", "GuildPridePlayersList", UIParent, "BackdropTemplate")
        win:SetSize(340, 104 + ROWS * 22)
        win:SetPoint("CENTER", 0, 60)
        win:SetFrameStrata("DIALOG")
        win:SetMovable(true); win:EnableMouse(true); win:SetClampedToScreen(true)
        win:RegisterForDrag("LeftButton")
        win:SetScript("OnDragStart", win.StartMoving)
        win:SetScript("OnDragStop", win.StopMovingOrSizing)
        if ns.SkinDialog then ns.SkinDialog(win) end
        tinsert(UISpecialFrames, "GuildPridePlayersList")   -- Escape schließt
        -- Schließen-Kreuz, Titel, Spaltenköpfe und Zeilen wie im Rare-Fenster (GuildPride-Design)
        local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -6, -6)
        if ns.SkinClose then ns.SkinClose(close) end
        close:SetScript("OnClick", function() win:Hide() end)
        local title = win:CreateFontString(nil, "OVERLAY", "GPFont_Large")
        title:SetPoint("TOPLEFT", 14, -12)
        title:SetText(L["GuildPride-Spieler"])
        if ns.Paint then ns.Paint(title, "heading") end
        local headName = win:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
        headName:SetPoint("TOPLEFT", 16, -34); headName:SetText(L["Name"])
        local headZone = win:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
        headZone:SetPoint("TOPLEFT", 172, -34); headZone:SetText(L["Zone"])
        if ns.Paint then ns.Paint(headName, "title"); ns.Paint(headZone, "title") end
        win:EnableMouseWheel(true)
        win:SetScript("OnMouseWheel", function(_, delta)
            win.offset = math.max(0, (win.offset or 0) - delta * 3)
            Refresh()
        end)
        win.rows = {}
        for i = 1, ROWS do
            local row = CreateFrame("Frame", nil, win)
            row:SetSize(312, 20)
            row:SetPoint("TOPLEFT", 14, -48 - (i - 1) * 22)
            if ns.Paint then
                if i % 2 == 0 then ns.Paint(row:CreateTexture(nil, "BACKGROUND"), "glow", 0.05):SetAllPoints() end
            end
            row.name = row:CreateFontString(nil, "OVERLAY", "GPFont_Text")
            row.name:SetPoint("LEFT", 0, 0); row.name:SetWidth(150); row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
            row.zone = row:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
            row.zone:SetPoint("LEFT", 156, 0); row.zone:SetWidth(156); row.zone:SetJustifyH("LEFT"); row.zone:SetWordWrap(false)
            win.rows[i] = row
        end
        win.empty = win:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
        win.empty:SetPoint("TOPLEFT", 14, -48); win.empty:SetPoint("RIGHT", -14, 0)
        win.empty:SetJustifyH("LEFT")
        win.count = win:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
        win.count:SetPoint("BOTTOMLEFT", 14, 44); win.count:SetPoint("RIGHT", -14, 0)
        win.count:SetJustifyH("LEFT")
        local refresh = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        if ns.SkinButton then ns.SkinButton(refresh) end
        refresh:SetSize(110, 22)
        refresh:SetPoint("BOTTOMRIGHT", -14, 12)
        refresh:SetText(L["Aktualisieren"])
        refresh:SetScript("OnClick", function() P.Ask(); Refresh() end)
        win:SetScript("OnShow", function() win.offset = 0; P.Ask(); Refresh() end)
        win:Hide()
    end
    win:SetShown(not win:IsShown())
end

---------------------------------------------------------------------
-- Unauffälliger Zugang: nur eine kleine, blasse Zahl unten rechts in der Seitenleiste,
-- auf Höhe der Versionsnummer; wird erst beim Drüberfahren hell (sonst /gp spieler)
---------------------------------------------------------------------
local parts = ns.UIParts
local versionText = parts and parts.versionText
if ns.IS_FOREVER and versionText then
    local b = CreateFrame("Button", nil, parts.frame)
    b:SetSize(28, 12)
    b:SetPoint("BOTTOMRIGHT", parts.frame, "BOTTOMLEFT", 174, 14)   -- Seitenleiste 180 px, wie die Versionszeile
    b:SetFrameLevel(parts.frame:GetFrameLevel() + 20)
    b:SetNormalFontObject("GPFont_MutedSmall")
    b:SetText("1")
    local fs = b:GetFontString()
    if fs then fs:ClearAllPoints(); fs:SetPoint("RIGHT"); fs:SetJustifyH("RIGHT") end
    b:SetAlpha(0.35)
    b:SetScript("OnClick", function() P.Toggle() end)
    b:SetScript("OnShow", function() Refresh() end)
    b:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        local n, g = P.Count()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["GuildPride-Spieler"], 1, 1, 1)
        GameTooltip:AddLine((L["%d Spieler mit GuildPride (%d aus der Gilde, grün)"]):format(n, g), 0.9, 0.8, 0.5)
        GameTooltip:AddLine(L["Klick: Liste aller GuildPride-Spieler auf dem Server mit Zone."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self) self:SetAlpha(0.35); GameTooltip:Hide() end)
    P.button = b
end

---------------------------------------------------------------------
-- Von selbst melden: beim Einloggen, bei Zonenwechsel, alle 10 Minuten
---------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        if C_Timer and C_Timer.After then C_Timer.After(20, function() P.Share(true) end) end
        if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(60, function() P.Share() end) end
    else
        P.Share()
    end
end)

-- /gp spieler
local slash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd = strtrim(arg or ""):lower():match("^(%S*)")
    if cmd == "spieler" or cmd == "players" then return P.Toggle() end
    return slash(arg)
end
