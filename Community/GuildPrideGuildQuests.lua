-- GuildPride: Quests der Gilde
-- Wer in der Gilde hat gerade dieselbe Quest? Jeder teilt nur die Nummern seiner Quests (nie
-- den Fortschritt), nur mit der Gilde; abschaltbar (guildQuests).
--   GQL  Liste      "100,200" (höchstens 25), "-" = keine
--   GQQ  1          Anfrage nach dem Einloggen
-- Nur für diese Sitzung im Speicher, nichts davon wird gespeichert.
local ADDON, ns = ...
local L = ns.L

local Q = {}
ns.GuildQuests = Q
Q.data = {}                 -- [Name] = { set = { [questID] = true } }
local MAX_QUESTS, MAX_ID, GAP = 25, 999999, 30

local function Me() return ns.Me() end
function Q.Enabled() return not (type(GuildPrideDB) == "table" and GuildPrideDB.guildQuests == false) end
local function Log() return ns.QuestLogList and ns.QuestLogList() or {} end

---------------------------------------------------------------------
-- Teilen
---------------------------------------------------------------------
local lastText, lastSent = nil, -999
local function Text()
    local ids = {}
    for _, q in ipairs(Log()) do if #ids < MAX_QUESTS then ids[#ids + 1] = q.id end end
    table.sort(ids)
    return #ids > 0 and table.concat(ids, ",") or "-"
end
function Q.Share(force)
    if not IsInGuild() or not Q.Enabled() then return end
    local t = Text()
    if not force and (t == lastText or GetTime() - lastSent < GAP) then return end
    lastText, lastSent = t, GetTime()
    ns.Queue("GQL", "@CHANNEL", t)
end

ns.On("GQL", function(payload, sender)
    if sender == Me() or not ns.IsGuildMember(sender) then return end
    local set, n = {}, 0
    for part in tostring(payload or ""):sub(1, 250):gmatch("[^,]+") do
        local id = part:match("^%d+$") and tonumber(part)
        if id and n < MAX_QUESTS and id >= 1 and id <= MAX_ID and not set[id] then set[id] = true; n = n + 1 end
    end
    Q.data[sender] = { set = set }
    if Q.Refresh then Q.Refresh() end
end)
ns.On("GQQ", function(_, sender)
    if sender == Me() or not Q.Enabled() then return end
    ns.AnswerSoon("GQL", function() Q.Share(true) end)
end)

---------------------------------------------------------------------
-- Wer hat dieselben Quests (nur online), eigene Zone zuerst
---------------------------------------------------------------------
local function Online()
    local on = {}
    for i = 1, GetNumGuildMembers() or 0 do
        local name, _, _, level, _, zone, _, _, online, _, class = GetGuildRosterInfo(i)
        if name and online then on[ns.Normalize(name)] = { zone = zone, level = level, class = class } end
    end
    return on
end

function Q.Who(questID, online)
    online = online or Online()
    local here = GetRealZoneText and GetRealZoneText()
    local out, n = {}, 0
    for name, d in pairs(Q.data) do
        local o = online[name]
        if o and d.set[questID] and name ~= Me() then
            local same = type(here) == "string" and here ~= "" and o.zone == here
            if same then n = n + 1 end
            out[#out + 1] = { name = name, level = o.level, class = o.class, zone = o.zone, here = same }
        end
    end
    table.sort(out, function(a, b)
        if a.here ~= b.here then return a.here end
        return a.name < b.name
    end)
    return out, n
end

function Q.List()
    local online, list = Online(), {}
    for _, q in ipairs(Log()) do
        local who, here = Q.Who(q.id, online)
        if #who > 0 then list[#list + 1] = { id = q.id, name = q.name, level = q.level, who = who, here = here } end
    end
    table.sort(list, function(a, b)
        if a.here ~= b.here then return a.here > b.here end
        if #a.who ~= #b.who then return #a.who > #b.who end
        return a.id < b.id
    end)
    return list
end

local function Names(who, max)
    local out = {}
    for i, w in ipairs(who) do
        if i > max then out[#out + 1] = "…"; break end
        out[#out + 1] = (w.here and "|cff40ff40" or "|cffe6e0da") .. Ambiguate(w.name, "guild") .. "|r"
    end
    return table.concat(out, ", ")
end

function Q.Invite(entry)
    local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if not invite then return 0 end
    local n = 0
    for _, w in ipairs(entry.who) do
        local short = Ambiguate(w.name, "none")
        if n < 4 and not (UnitInParty and UnitInParty(short)) then pcall(invite, short); n = n + 1 end
    end
    ns.Print((L["%s: %d Einladungen verschickt."]):format(entry.name, n))
    return n
end

---------------------------------------------------------------------
-- Fenster (/gp quests)
---------------------------------------------------------------------
local win
function Q.Refresh()
    if not win or not win:IsShown() then return end
    win.list = Q.List()
    local lines = {}
    for _, q in ipairs(win.list) do
        lines[#lines + 1] = ("|cffffd100[%d] %s|r  %s%s"):format(q.level or 0, q.name, Names(q.who, 5),
            q.here > 0 and ("  |cff40ff40" .. (L["%d in deiner Zone"]):format(q.here) .. "|r") or "")
    end
    win:SetLines(lines)
end

function Q.Open()
    if not win then
        win = ns.ListWindow({ name = "GuildPrideQuests", title = L["Quests der Gilde"], rows = 14, width = 600,
            sub = L["Wer online ist und dieselbe Quest hat (nur Mitglieder mit GuildPride). Klick auf eine Zeile lädt bis zu vier ein."],
            empty = L["Gerade hat niemand aus der Gilde dieselbe Quest wie du."] })
        for i, row in ipairs(win.rows) do
            row:EnableMouse(true)
            row:SetScript("OnMouseUp", function()
                local q = win.list and win.list[i + win.offset]
                if q then Q.Invite(q) end
            end)
        end
        win:SetScript("OnShow", function() win.offset = 0; Q.Refresh() end)
    end
    win:SetShown(not win:IsShown())
    Q.Refresh()
end

---------------------------------------------------------------------
-- Ereignisse
---------------------------------------------------------------------
local hinted, waiting = {}, false
local function Soon()
    if waiting then return end
    waiting = true
    -- frühestens nach der Sendepause: mehrere Änderungen gehen als eine Nachricht raus
    C_Timer.After(math.max(5, GAP - (GetTime() - lastSent)), function() waiting = false; Q.Share() end)
end
local function Hint(questID)
    if hinted[questID] or not Q.Enabled() then return end
    local who, here = Q.Who(questID)
    if #who == 0 then return end
    hinted[questID] = true
    for _, q in ipairs(Log()) do
        if q.id == questID then
            ns.Print((L["„%s“ haben auch: %s"]):format(q.name, Names(who, 4))
                .. (here > 0 and ("  " .. (L["%d in deiner Zone"]):format(here)) or "") .. "  |cff888888(/gp quests)|r")
            return
        end
    end
end

local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "PLAYER_LOGIN", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN")
ev:SetScript("OnEvent", function(_, event, a, b)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(38 + math.random() * 30, function()
            if not IsInGuild() or not Q.Enabled() then return end
            Q.Share(true)
            ns.Queue("GQQ", nil, "1")
        end)
        return
    end
    Soon()
    if event == "QUEST_ACCEPTED" then
        -- je nach Client (questID) oder (Platz im Log, questID)
        local id = tonumber(b) or tonumber(a)
        if id then C_Timer.After(3, function() Hint(id) end) end
    end
end)

-- Einstellungen: ausschalten zieht die eigene Liste zurück
function Q.Changed()
    if Q.Enabled() then Q.Share(true)
    elseif IsInGuild() then lastText = nil; ns.Queue("GQL", "@CHANNEL", "-") end
    Q.Refresh()
end

ns.Command({ "quests", "quest" }, function() Q.Open() end)
