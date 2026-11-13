-- GuildPride: Beitrittsdatum und Mitglieds-Verlauf
--
-- Blizzard kennt kein Beitrittsdatum. GuildPride merkt sich je Mitglied:
--   first  = frühestes bekanntes Beitrittsdatum (exakt, wenn GuildPride den
--            Beitritt gesehen hat oder er im Gilden-Ereignisprotokoll stand,
--            sonst "spätestens seit" = erstes Mal gesehen, approx = true)
--   joins  = Beitritte, leaves = Austritte/Entfernungen (Zeitpunkte)
--   ranks  = letzte Rangwechsel { t, Rangname, auf = true/false }
--   left   = gesetzt, solange er nicht mehr in der Gilde ist
-- Ehemalige bleiben gespeichert: Tritt jemand erneut bei, sieht man das.
--
-- Abgleich: Offiziere schicken ihren Stand auf Anfrage (JHQ -> JHL). Fremde
-- Listen werden nur von Offizieren angenommen (manipulierte Addons sollen
-- keine Daten erfinden können), und es gilt immer das frühere Datum.
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP or "\031"

local MAX_EVENTS = 10
local MAX_NAMES = 2000
local DAY = 86400

local function Store() return ns.GuildTable("history") end
local function Now() return GetServerTime() end
local function Secret(v) return issecretvalue and issecretvalue(v) or false end

local function Entry(name, create)
    local s = Store()
    local e = s[name]
    if type(e) ~= "table" then e = nil end
    if not e and create then
        e = { joins = {}, leaves = {}, ranks = {} }
        s[name] = e
    end
    return e
end

-- Zeitpunkt in eine Liste, Doppelte (gleicher Tag) zusammenfassen
local function AddTime(list, t)
    for _, x in ipairs(list) do if math.abs(x - t) < DAY then return false end end
    list[#list + 1] = t
    table.sort(list)
    while #list > MAX_EVENTS do table.remove(list, 1) end
    return true
end

local function SetFirst(e, t, exact)
    if not e.first or t < e.first then e.first = t; e.approx = not exact or nil
    elseif exact and e.approx and math.abs(t - e.first) < DAY then e.approx = nil end
end

function ns.HistoryOf(name)
    local e = name and Store()[name]
    return type(e) == "table" and e or nil
end

---------------------------------------------------------------------
-- Quellen
---------------------------------------------------------------------
function ns.HistoryJoin(name, t)
    if not name then return end
    t = t or Now()
    local e = Entry(name, true)
    AddTime(e.joins, t)
    SetFirst(e, t, true)
    e.left = nil
end

function ns.HistoryLeave(name, t)
    if not name then return end
    local e = Entry(name, true)
    t = t or Now()
    AddTime(e.leaves, t)
    e.left = t
end

local function AddRank(name, t, rankName, up)
    local e = Entry(name, true)
    for _, r in ipairs(e.ranks) do if math.abs(r[1] - t) < 3600 and r[2] == rankName then return end end
    e.ranks[#e.ranks + 1] = { t, rankName, up and true or false }
    table.sort(e.ranks, function(a, b) return a[1] < b[1] end)
    while #e.ranks > MAX_EVENTS do table.remove(e.ranks, 1) end
end

-- Gilden-Ereignisprotokoll (Beitritt, Austritt, Entfernt, Befördert, Degradiert)
local function ReadEventLog()
    if not (GetNumGuildEvents and GetGuildEventInfo) or not IsInGuild() then return end
    local now = Now()
    for i = 1, GetNumGuildEvents() do
        local kind, p1, p2, rank, y, mo, d, h = GetGuildEventInfo(i)
        if not Secret(kind) and not Secret(p1) and not Secret(p2) then
            local t = now - (((y or 0) * 365 + (mo or 0) * 30 + (d or 0)) * 24 + (h or 0)) * 3600
            local who = (kind == "join" or kind == "quit") and p1 or p2
            if type(who) == "string" and who ~= "" then
                who = ns.Normalize(who)
                if kind == "join" then
                    local e = Entry(who, true)
                    AddTime(e.joins, t); SetFirst(e, t, true)
                elseif kind == "quit" or kind == "remove" then
                    local e = Entry(who, true)
                    AddTime(e.leaves, t)
                elseif (kind == "promote" or kind == "demote") and type(rank) == "string" and not Secret(rank) then
                    AddRank(who, t, rank, kind == "promote")
                end
            end
        end
    end
end

-- Gildenliste: Unbekannte bekommen "spätestens seit jetzt", Ehemalige werden
-- erkannt. Nur wenn auch Offline-Mitglieder geliefert werden.
local lastScan = 0
local function ScanRoster()
    if not IsInGuild() or GetTime() - lastScan < 30 then return end
    if GetGuildRosterShowOffline and not GetGuildRosterShowOffline() then return end
    local n = GetNumGuildMembers()
    if n == 0 then return end
    lastScan = GetTime()
    local now, present = Now(), {}
    for i = 1, n do
        local name, rankName = GetGuildRosterInfo(i)
        if type(name) == "string" and not Secret(name) then
            name = ns.Normalize(name)
            present[name] = true
            local e = Entry(name, true)
            if not e.first then SetFirst(e, now, false) end
            if e.left then e.left = nil; AddTime(e.joins, now); SetFirst(e, now, false) end
            if type(rankName) == "string" and not Secret(rankName) and e.rank ~= rankName then
                if e.rank then AddRank(name, now, rankName, nil) end
                e.rank = rankName
            end
        end
    end
    -- Austritte nur, wenn die Liste vollständig wirkt (beim Einloggen kommt sie
    -- manchmal erst teilweise): nicht deutlich kürzer als beim letzten Mal
    local g = Store()
    local known = g["\001count"] or 0
    if type(known) ~= "number" then known = 0 end
    if n >= known * 0.9 then
        for name, e in pairs(g) do
            if type(e) == "table" and not present[name] and not e.left then e.left = now; AddTime(e.leaves, now) end
        end
    end
    g["\001count"] = n
end

---------------------------------------------------------------------
-- Abgleich (nur von Offizieren angenommen)
---------------------------------------------------------------------
local CHUNK = 3000
ns.On("JHQ", function(_, sender)
    if sender == ns.Me() or not ns.IsGuildMember(sender) then return end
    if not (ns.CanSetAlts and ns.CanSetAlts()) then return end   -- nur Offiziere antworten
    C_Timer.After(2 + math.random() * 6, function()
        local buf, len = {}, 0
        local function flush()
            if #buf > 0 then ns.Queue("JHL", sender, table.concat(buf, ";")) end
            buf, len = {}, 0
        end
        for name, e in pairs(Store()) do
            if type(e) == "table" and e.first then
                local item = ("%s=%d=%s=%s=%s"):format(name, e.first, e.approx and 1 or 0,
                    table.concat(e.joins, ","), table.concat(e.leaves, ","))
                if len + #item + 1 > CHUNK then flush() end
                buf[#buf + 1] = item
                len = len + #item + 1
            end
        end
        flush()
    end)
end)

local function Times(s, out)
    for v in (s or ""):gmatch("[^,]+") do
        local t = ns.Num(v, 0, Now() + 300)
        if t and t > 1000000000 and #out < 50 then out[#out + 1] = t end
    end
    return out
end

ns.On("JHL", function(payload, sender)
    if not ns.IsOfficerName(sender) then return end
    local s, count = Store(), 0
    for _, e in pairs(s) do if type(e) == "table" then count = count + 1 end end
    for item in payload:gmatch("[^;]+") do
        local name, first, approx, joins, leaves = item:match("^([^=]+)=(%d+)=([01])=([%d,]*)=([%d,]*)$")
        name = name and ns.Clean(name, 60)
        first = ns.Num(first, 1000000000, Now() + 300)
        if name and name ~= "" and first and (s[name] or count < MAX_NAMES) then
            if not s[name] then count = count + 1 end
            local e = Entry(name, true)
            SetFirst(e, first, approx == "0")
            for _, t in ipairs(Times(joins, {})) do AddTime(e.joins, t) end
            for _, t in ipairs(Times(leaves, {})) do AddTime(e.leaves, t) end
        end
    end
end)

---------------------------------------------------------------------
-- Anzeige
---------------------------------------------------------------------
local function D(t) return date("%d.%m.%Y", t) end

-- Kurzzeile fürs Mitgliederfenster
function ns.HistoryLine(name)
    local e = ns.HistoryOf(name)
    if not (e and e.first) then return nil end
    local days = math.floor((Now() - e.first) / DAY)
    local text = (e.approx and L["Mitglied spätestens seit %s (%d Tage)"] or L["Mitglied seit %s (%d Tage)"]):format(D(e.first), days)
    if #e.joins > 1 then text = text .. "  ·  " .. (L["%d× beigetreten"]):format(#e.joins) end
    return text
end

-- Ausführlicher Verlauf (Tooltip)
function ns.HistoryTooltip(tt, name)
    local e = ns.HistoryOf(name)
    if not e then return end
    tt:AddLine(L["Verlauf"], 0.94, 0.78, 0.55)
    local rows = {}
    for _, t in ipairs(e.joins) do rows[#rows + 1] = { t, L["beigetreten"] } end
    for _, t in ipairs(e.leaves) do rows[#rows + 1] = { t, L["ausgetreten / entfernt"] } end
    for _, r in ipairs(e.ranks) do
        rows[#rows + 1] = { r[1], (r[3] == true and L["befördert zu %s"] or r[3] == false and L["degradiert zu %s"] or L["Rang: %s"]):format(r[2]) }
    end
    table.sort(rows, function(a, b) return a[1] > b[1] end)
    for i = 1, math.min(#rows, 12) do tt:AddDoubleLine(D(rows[i][1]), rows[i][2], 0.7, 0.7, 0.7, 1, 1, 1) end
    if #rows == 0 then tt:AddLine(L["Noch nichts aufgezeichnet."], 0.5, 0.5, 0.5) end
end

-- Hinweis beim Beitritt: war schon einmal da?
function ns.HistoryRejoinText(name)
    local e = ns.HistoryOf(name)
    if not (e and #e.leaves > 0) then return nil end
    return (L["War schon Mitglied (zuletzt ausgetreten am %s)."]):format(D(e.leaves[#e.leaves]))
end

---------------------------------------------------------------------
-- Events
---------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(f.RegisterEvent, f, "GUILD_EVENT_LOG_UPDATE")
local asked = false
f:SetScript("OnEvent", function(_, event, isLogin, isReload)
    if not GuildPrideDB then return end
    if event == "GUILD_ROSTER_UPDATE" then ScanRoster()
    elseif event == "GUILD_EVENT_LOG_UPDATE" then ReadEventLog()
    elseif event == "PLAYER_ENTERING_WORLD" and (isLogin or isReload) and not asked then
        asked = true
        C_Timer.After(35, function()
            if IsInGuild() and ns.Queue then ns.Queue("JHQ", nil, "1") end
        end)
    end
end)
