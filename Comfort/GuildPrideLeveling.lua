-- GuildPride: Leveln-Anzeige und Ruf automatisch verfolgen
-- * Leveln (levelInfo): EP pro Stunde (letzte Stunde), Zeit bis zum nächsten Level,
--   Ruhebonus und was du heute geschafft hast. Steht unter „Heute“, kommt beim
--   Levelaufstieg in den Chat und mit /gp leveln.
-- * Ruf (repTrack): Bekommst du Ruf bei einer Fraktion, zeigt die Rufleiste sie an.
-- Gespeichert: GuildPrideDB.levelDay[Charakter] = { key = "JJJJMMTT", xp, rested, levels }
local ADDON, ns = ...
local L = ns.L

local Lv = {}
ns.Level = Lv

local WINDOW = 3600       -- EP pro Stunde aus der letzten Stunde
local MIN_SPAN = 120      -- darunter ist die Rate nur Zufall

local function Opt(key) return type(GuildPrideDB) == "table" and GuildPrideDB[key] ~= false end

---------------------------------------------------------------------
-- Rechnen (rein, getestet)
---------------------------------------------------------------------
-- EP-Gewinn zwischen zwei Ständen { xp, max, rest, level }; Ruhebonus = verbrauchter Ruhezustand
function Lv.Gain(prev, cur)
    local gain
    if (cur.level or 0) > (prev.level or 0) then
        gain = math.max(0, (prev.max or 0) - (prev.xp or 0)) + (cur.xp or 0)
    else
        gain = math.max(0, (cur.xp or 0) - (prev.xp or 0))
    end
    local rested = math.max(0, (prev.rest or 0) - (cur.rest or 0))
    return gain, math.min(rested, gain)
end

function Lv.NewState(dayKey)
    return { window = {}, day = { key = dayKey, xp = 0, rested = 0, levels = 0 } }
end

-- Gewinn merken: Fenster für die Rate, Tageswerte (Level-Anteil am jeweiligen Levelbedarf)
function Lv.Record(st, now, gain, rested, max, dayKey)
    if gain <= 0 then return end
    st.window[#st.window + 1] = { t = now, g = gain }
    st.start = st.start or now
    while st.window[1] and st.window[1].t < now - WINDOW do table.remove(st.window, 1) end
    if st.day.key ~= dayKey then st.day = { key = dayKey, xp = 0, rested = 0, levels = 0 } end
    st.day.xp = st.day.xp + gain
    st.day.rested = st.day.rested + (rested or 0)
    if max and max > 0 then st.day.levels = st.day.levels + gain / max end
end

-- EP pro Stunde; nil, solange zu kurz gemessen wurde. Gemessen ab dem Start (höchstens eine Stunde).
function Lv.Rate(st, now)
    if not st.start then return nil end
    local span = math.min(WINDOW, now - st.start)
    if span < MIN_SPAN then return nil end
    local sum = 0
    for _, e in ipairs(st.window) do if e.t >= now - WINDOW then sum = sum + e.g end end
    return math.floor(sum * 3600 / span + 0.5)
end

-- 12345 → „12.345“ (deutsch) bzw. „12,345“ (englisch)
local function Num(n)
    local s = tostring(math.floor(n + 0.5))
    local sep = ns.IS_GERMAN == false and "," or "."
    local out = s:reverse():gsub("(%d%d%d)", "%1" .. sep):reverse()
    return (out:gsub("^%" .. sep, ""))
end
Lv.Num = Num

local function Minutes(sec)
    local m = math.max(1, math.floor(sec / 60 + 0.5))
    if m < 60 then return (L["%d Min."]):format(m) end
    return (L["%d Std. %d Min."]):format(math.floor(m / 60), m % 60)
end

function Lv.Line(st, now, xp, max, rest)
    local parts = {}
    local rate = Lv.Rate(st, now)
    if rate and rate > 0 then
        parts[#parts + 1] = (L["%s EP/Std."]):format(Num(rate))
        local left = math.max(0, (max or 0) - (xp or 0))
        parts[#parts + 1] = (L["nächstes Level in %s"]):format(Minutes(left / rate * 3600))
    end
    if rest and rest > 0 then parts[#parts + 1] = (L["Ruhebonus %s EP"]):format(Num(rest)) end
    local d = st.day
    if d.xp > 0 then
        local lv = ("%.1f"):format(d.levels)
        if ns.IS_GERMAN ~= false then lv = lv:gsub("%.", ",") end
        local share = math.floor(d.rested / d.xp * 100 + 0.5)
        parts[#parts + 1] = (L["heute %s Level (%d %% mit Ruhebonus)"]):format(lv, share)
    end
    if #parts == 0 then return nil end
    return L["Leveln: "] .. table.concat(parts, " · ")
end

-- Balken: Anteil der EP und wie weit der Ruhebonus reicht (je 0 bis 1)
function Lv.BarValues(xp, max, rest)
    if not max or max <= 0 then return 0, 0 end
    local a = math.min(1, math.max(0, (xp or 0) / max))
    return a, math.min(1, ((xp or 0) + (rest or 0)) / max)
end

-- Text auf dem Balken: „Level 23 · 25 % · 7.200 EP/Std. · 8 Min.“
function Lv.BarText(level, xp, max, rate)
    local pct = max and max > 0 and math.floor((xp or 0) / max * 100) or 0
    local text = (L["Level %d · %d %%"]):format(level or 0, pct)
    if rate and rate > 0 then
        local left = math.max(0, (max or 0) - (xp or 0))
        text = text .. " · " .. (L["%s EP/Std."]):format(Num(rate)) .. " · " .. Minutes(left / rate * 3600)
    end
    return text
end

-- Sichtbar nur mit beiden Schaltern und unter der Höchststufe
function Lv.BarWanted(levelInfo, levelBar, level, maxLevel)
    return levelInfo and levelBar and (tonumber(level) or 0) < (tonumber(maxLevel) or 60) or false
end

-- Ruf: Blizzard-Text („Reputation with %s increased by %d.“) → Lua-Muster
function Lv.RepPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("([%%%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")
    p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "%%d+")
    return "^" .. p .. "$"
end

function Lv.RepName(msg, patterns)
    if type(msg) ~= "string" then return nil end
    for _, p in ipairs(patterns) do
        local name = p and msg:match(p)
        if name then return name end
    end
    return nil
end

-- list = { { name, factionID, isHeader } } → Index, factionID (Überschriften nie)
function Lv.FindFaction(list, name)
    for i, f in ipairs(list) do
        if f.name == name and not f.isHeader then return i, f.factionID end
    end
    return nil
end

---------------------------------------------------------------------
-- Spiel
---------------------------------------------------------------------
local Secret = ns.IsSecret
local function Me() return ns.Me and ns.Me() or UnitName("player") end
local function DayKey() return ((os and os.date) or date)("%Y%m%d") end
local function MaxLevel() return (GetMaxPlayerLevel and GetMaxPlayerLevel()) or MAX_PLAYER_LEVEL or 60 end

local function Read()
    local xp, max = UnitXP("player"), UnitXPMax("player")
    local rest = GetXPExhaustion and GetXPExhaustion() or 0
    if Secret(xp) or Secret(max) or Secret(rest) then return nil end
    if type(xp) ~= "number" or type(max) ~= "number" then return nil end
    if type(rest) ~= "number" then rest = 0 end
    return { xp = xp or 0, max = max or 0, rest = rest or 0, level = UnitLevel("player") or 0 }
end

local state = Lv.NewState(DayKey())
local last

-- Tageswerte des Charakters laden/merken (überlebt /reload und Ausloggen)
local function DayStore()
    if type(GuildPrideDB) ~= "table" then return nil end
    GuildPrideDB.levelDay = GuildPrideDB.levelDay or {}
    return GuildPrideDB.levelDay
end
local function LoadDay()
    local store = DayStore()
    local d = store and store[Me()]
    if type(d) == "table" and d.key == DayKey() then state.day = d end
end
local function SaveDay()
    local store = DayStore()
    if store then store[Me()] = state.day end
end

function Lv.CurrentLine()
    if not Opt("levelInfo") or (UnitLevel("player") or 0) >= MaxLevel() then return nil end
    local cur = Read()
    if not cur then return nil end
    return Lv.Line(state, GetTime(), cur.xp, cur.max, cur.rest)
end

local function OnXP()
    local cur = Read()
    if not cur then return end
    if last then
        local gain, rested = Lv.Gain(last, cur)
        Lv.Record(state, GetTime(), gain, rested, last.max, DayKey())
        SaveDay()
    end
    last = cur
end

---------------------------------------------------------------------
-- Balken (levelBar): verschiebbar, Ruhebonus heller dahinter, Details im Tooltip.
-- Rechtsklick blendet ihn aus (wieder an in den Einstellungen oder mit /gp leveln balken).
---------------------------------------------------------------------
local bar
local BAR_TEX = "Interface\\TargetingFrame\\UI-StatusBar"
local function BuildBar()
    if bar then return bar end
    bar = CreateFrame("Frame", "GuildPrideLevelBar", UIParent, "BackdropTemplate")
    bar:SetSize(280, 18)
    local p = GuildPrideDB.levelBarPos
    if type(p) == "table" and p.point then bar:SetPoint(p.point, UIParent, p.point, p.x or 0, p.y or 0)
    else bar:SetPoint("TOP", UIParent, "TOP", 0, -90) end
    bar:SetFrameStrata("LOW")
    bar:SetClampedToScreen(true)
    bar:SetMovable(true); bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", bar.StartMoving)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint(1)
        GuildPrideDB.levelBarPos = { point = point, x = x, y = y }
    end)
    if bar.SetBackdrop then
        bar:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        bar:SetBackdropColor(0, 0, 0, 0.55); bar:SetBackdropBorderColor(0.8, 0.65, 0.2, 0.9)
    end
    -- Ruhebonus (hell) liegt hinter den EP (kräftig)
    bar.rest = CreateFrame("StatusBar", nil, bar)
    bar.rest:SetPoint("TOPLEFT", 1, -1); bar.rest:SetPoint("BOTTOMRIGHT", -1, 1)
    bar.rest:SetStatusBarTexture(BAR_TEX); bar.rest:SetStatusBarColor(0.25, 0.45, 1, 0.45)
    bar.rest:SetMinMaxValues(0, 1)
    bar.xp = CreateFrame("StatusBar", nil, bar)
    bar.xp:SetAllPoints(bar.rest)
    bar.xp:SetStatusBarTexture(BAR_TEX); bar.xp:SetStatusBarColor(0.58, 0.2, 0.95, 1)
    bar.xp:SetMinMaxValues(0, 1)
    bar.xp:SetFrameLevel((tonumber(bar.rest:GetFrameLevel()) or 1) + 1)
    bar.text = bar.xp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Leveln"])
        local cur = Read()
        if cur then
            GameTooltip:AddLine(("%s / %s EP"):format(Num(cur.xp), Num(cur.max)), 1, 1, 1)
            local line = Lv.Line(state, GetTime(), cur.xp, cur.max, cur.rest)
            if line then GameTooltip:AddLine(line:gsub("^" .. L["Leveln: "], ""):gsub(" · ", "\n"), 0.9, 0.9, 0.9, true) end
        end
        GameTooltip:AddLine(L["Ziehen verschiebt · Rechtsklick blendet aus"], 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", GameTooltip_Hide)
    bar:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            GuildPrideDB.levelBar = false
            bar:Hide()
            ns.Print(L["Leveln-Balken aus – wieder an mit /gp leveln balken oder in den Einstellungen (Komfort)."])
        end
    end)
    bar:Hide()
    return bar
end

function Lv.RefreshBar()
    if type(GuildPrideDB) ~= "table" then return end
    local want = Lv.BarWanted(Opt("levelInfo"), Opt("levelBar"), UnitLevel("player"), MaxLevel())
    if not want then if bar then bar:Hide() end; return end
    local cur = Read()
    if not cur then return end   -- geschützt (Kampf): alter Stand bleibt stehen
    BuildBar()
    local a, r = Lv.BarValues(cur.xp, cur.max, cur.rest)
    bar.xp:SetValue(a); bar.rest:SetValue(r)
    bar.text:SetText(Lv.BarText(cur.level, cur.xp, cur.max, Lv.Rate(state, GetTime())))
    bar:Show()
end

-- Ruf
local repPatterns
local function RepPatterns()
    if repPatterns then return repPatterns end
    repPatterns = {}
    for _, g in ipairs({ FACTION_STANDING_INCREASED, FACTION_STANDING_INCREASED_GENERIC }) do
        local p = Lv.RepPattern(g)
        if p then repPatterns[#repPatterns + 1] = p end
    end
    -- Rückfall, falls der Client die Vorlage nicht kennt
    repPatterns[#repPatterns + 1] = "^Reputation with (.+) increased by %d+"
    repPatterns[#repPatterns + 1] = "Ruf bei der Fraktion '?(.-)'? hat sich um %d+ verbessert"
    return repPatterns
end

local function Factions()
    local R = C_Reputation
    local list = {}
    if R and R.GetNumFactions and R.GetFactionDataByIndex then
        for i = 1, R.GetNumFactions() or 0 do
            local d = R.GetFactionDataByIndex(i)
            if type(d) == "table" then list[i] = { name = d.name, factionID = d.factionID, isHeader = d.isHeader and not d.isHeaderWithRep } end
        end
    end
    return list
end

local function OnRep(msg)
    if not Opt("repTrack") or Secret(msg) then return end
    local name = Lv.RepName(msg, RepPatterns())
    if not name then return end
    local R = C_Reputation
    local i, id = Lv.FindFaction(Factions(), name)
    if not i then return end
    if R.GetWatchedFactionData then
        local w = R.GetWatchedFactionData()
        if type(w) == "table" and w.factionID == id then return end
    end
    if R.SetWatchedFactionByID and id then pcall(R.SetWatchedFactionByID, id)
    elseif R.SetWatchedFactionByIndex then pcall(R.SetWatchedFactionByIndex, i) end
end

-- Zeile auf „Heute“
if ns.Today and ns.Today.EXTRA then
    table.insert(ns.Today.EXTRA, function(add) local l = Lv.CurrentLine(); if l then add(l) end end)
end

local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "PLAYER_LOGIN", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "CHAT_MSG_COMBAT_FACTION_CHANGE",
    "UPDATE_EXHAUSTION", "PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_LOGIN" then
        LoadDay()
        last = Read()
        ns.Try(Lv.RefreshBar)
        -- EP/Std. und Restzeit ändern sich auch ohne neue EP
        if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(15, function() ns.Try(Lv.RefreshBar) end) end
    elseif event == "PLAYER_XP_UPDATE" then
        ns.Try(OnXP)
        ns.Try(Lv.RefreshBar)
    elseif event == "UPDATE_EXHAUSTION" or event == "PLAYER_REGEN_ENABLED" then
        ns.Try(Lv.RefreshBar)
    elseif event == "PLAYER_LEVEL_UP" then
        -- erst nach dem Aufstieg stehen die neuen Werte bereit
        C_Timer.After(1, function()
            ns.Try(OnXP)
            ns.Try(Lv.RefreshBar)
            if Opt("levelInfo") then
                local line = Lv.CurrentLine()
                if line then ns.Print(line) end
            end
        end)
    elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        ns.Try(OnRep, arg1)
    end
end)

local orig = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd = strtrim(arg or ""):lower()
    if cmd == "leveln balken" or cmd == "level bar" then
        if type(GuildPrideDB) ~= "table" then return end
        GuildPrideDB.levelBar = not Opt("levelBar")
        if GuildPrideDB.levelBar then GuildPrideDB.levelInfo = true end
        Lv.RefreshBar()
        ns.Print(GuildPrideDB.levelBar and L["Leveln-Balken an (ziehen zum Verschieben)."] or L["Leveln-Balken aus."])
    elseif cmd == "leveln" or cmd == "level" or cmd == "xp" or cmd == "ep" then
        if (UnitLevel("player") or 0) >= MaxLevel() then ns.Print(L["Du hast schon die Höchststufe."]); return end
        local cur = Read()
        local line = cur and Lv.Line(state, GetTime(), cur.xp, cur.max, cur.rest)
        ns.Print(line or L["Leveln: noch keine Werte – erst ein paar EP sammeln."])
    elseif orig then
        orig(arg)
    end
end
