-- GuildPride: Raid-Bereitschaft
-- Der Leiter (oder ein Assistent) fragt seine Gruppe: Haltbarkeit, „Satt“, Tränke, Elixiere,
-- Buff-Food in den Taschen. Jeder meldet nur sich selbst, nur an Leiter oder Assistenten der
-- eigenen Gruppe und nur per Flüstern; abschaltbar (raidReady).
--   RDQ  1            Anfrage an die Gilde (antwortet nur, wer in der Gruppe ist)
--   RDY  Haltbarkeit · kaputte Teile · satt (1/0/-) · Tränke · Elixiere · Buff-Food
-- Beim Bereitschaftscheck antworten alle von selbst an den, der ihn gestartet hat.
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP

local R = {}
ns.Ready = R
R.data = {}                 -- [Name] = { Status, t = GetTime() }
local LOW_DUR = 40          -- darunter ist es ein Problem
local MAX_AGE = 600

local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function Enabled() return not (type(GuildPrideDB) == "table" and GuildPrideDB.raidReady == false) end

-- Gruppe: { [Name] = { leader, assist } }, dazu die Namen in Reihenfolge
local function Group()
    local out, order = {}, {}
    local n = IsInGroup() and GetNumGroupMembers() or 0
    local realm = GetNormalizedRealmName() or ""
    for i = 1, n do
        local unit = IsInRaid() and ("raid" .. i) or (i == n and "player" or ("party" .. i))
        local name, r = (ns.IS_FOREVER and UnitFullName or UnitName)(unit)
        if name and not Secret(name) and not Secret(r) then
            local full = ns.Normalize(name .. "-" .. ((r and r ~= "") and r or realm))
            out[full] = { leader = UnitIsGroupLeader(unit) and true or false, assist = UnitIsGroupAssistant(unit) and true or false }
            order[#order + 1] = full
        end
    end
    return out, order
end

local function MayAsk(name)
    local g = Group()[name]
    return g ~= nil and (g.leader or g.assist)
end

---------------------------------------------------------------------
-- Eigener Status
---------------------------------------------------------------------
-- Trank oder Elixier am Namen erkennen (die Unterarten der Items sind je Client verschieden)
function R.KindOf(name)
    if type(name) ~= "string" or Secret(name) then return nil end
    local low = name:lower()
    if low:find("^rezept") or low:find("^recipe") or low:find("rezept$") then return nil end
    if low:find("elixier") or low:find("elixir") or low:find("fläschchen", 1, true) or low:find("flask") then return "elix" end
    if low:find("trank$") or low:find("trank ") or low:find("potion") then return "pot" end
    return nil
end

local function Bags()
    local pots, elix = 0, 0
    local C = C_Container
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local slots = C and C.GetContainerNumSlots and C.GetContainerNumSlots(bag) or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
        for slot = 1, tonumber(slots) or 0 do
            local info = C and C.GetContainerItemInfo and C.GetContainerItemInfo(bag, slot)
            local id, count
            if type(info) == "table" then id, count = info.itemID, info.stackCount
            elseif GetContainerItemID then id, count = GetContainerItemID(bag, slot), select(2, GetContainerItemInfo(bag, slot)) end
            if id then
                local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
                local kind = f and R.KindOf((f(id)))
                count = tonumber(count) or 1
                if kind == "pot" then pots = pots + count elseif kind == "elix" then elix = elix + count end
            end
        end
    end
    return pots, elix
end

local function Durability()
    local cur, max, broken = 0, 0, 0
    for slot = 1, 18 do
        local c, m = GetInventoryItemDurability(slot)
        if type(c) == "number" and type(m) == "number" and m > 0 and not Secret(c) then
            cur, max = cur + c, max + m
            if c == 0 then broken = broken + 1 end
        end
    end
    return max > 0 and math.floor(cur / max * 100 + 0.5) or 100, broken
end

function R.Status()
    local dur, broken = Durability()
    local pots, elix = Bags()
    local food, foods = nil, 0
    if ns.Buffs and ns.Buffs.ReadAuras then
        food = ns.Buffs.ReadAuras()
        local ok, list = pcall(ns.Buffs.FoodInBags)
        for _, f in ipairs(ok and type(list) == "table" and list or {}) do foods = foods + (tonumber(f.count) or 1) end
    end
    return { dur = dur, broken = broken, food = food, pots = pots, elix = elix, foods = foods }
end

function R.Encode(s)
    return table.concat({ s.dur, s.broken, s.food == nil and "-" or (s.food and 1 or 0), s.pots, s.elix, s.foods }, SEP)
end
function R.Decode(text)
    local a = { strsplit(SEP, tostring(text or "")) }
    local dur = ns.Num(a[1], 0, 100)
    if not dur or #a < 6 then return nil end
    local food
    if a[3] == "1" then food = true elseif a[3] == "0" then food = false end
    return { dur = dur, broken = ns.Num(a[2], 0, 19) or 0, food = food, pots = ns.Num(a[4], 0, 999) or 0,
             elix = ns.Num(a[5], 0, 999) or 0, foods = ns.Num(a[6], 0, 999) or 0 }
end

---------------------------------------------------------------------
-- Fragen und Antworten
---------------------------------------------------------------------
local function Answer(to)
    if not Enabled() or to == ns.Me() or not ns.IsGuildMember(to) or not MayAsk(to) then return end
    C_Timer.After(0.5 + math.random() * 3, function()
        if not Enabled() or (C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()) then return end
        ns.SendAddonMsg("GuildPride", "RDY:" .. R.Encode(R.Status()), "WHISPER", to)
    end)
end

ns.On("RDQ", function(_, sender)
    if sender ~= ns.Me() then Answer(sender) end
end)
ns.On("RDY", function(payload, sender)
    local s = R.Decode(payload)
    if not s or not Group()[sender] then return end
    s.t = GetTime()
    R.data[sender] = s
    if R.Refresh then R.Refresh() end
end)

function R.CanAsk() return IsInGroup() and MayAsk(ns.Me()) or false end

local lastAsk = -999
function R.Ask()
    if not R.CanAsk() then ns.Print(L["Nach der Bereitschaft fragen kann nur, wer Leiter oder Assistent der Gruppe ist."]); return false end
    local mine = R.Status()
    mine.t = GetTime()
    R.data[ns.Me()] = mine
    if GetTime() - lastAsk >= 10 then
        lastAsk = GetTime()
        ns.Queue("RDQ", nil, "1")
    end
    if R.Refresh then R.Refresh() end
    return true
end

-- Was fehlt? Gibt Texte zurück
local function Problems(s)
    local out = {}
    if s.broken > 0 then out[#out + 1] = (L["%d Teile kaputt"]):format(s.broken)
    elseif s.dur < LOW_DUR then out[#out + 1] = (L["Haltbarkeit %d %%"]):format(s.dur) end
    if s.food == false then out[#out + 1] = s.foods > 0 and L["nicht satt (Essen dabei)"] or L["nicht satt, kein Buff-Food"] end
    if s.pots == 0 then out[#out + 1] = L["keine Tränke"] end
    return out
end

-- Alle in der Gruppe: Probleme zuerst, dann bereit, zuletzt ohne Antwort
function R.List()
    local _, order = Group()
    local list, now = {}, GetTime()
    for _, name in ipairs(order) do
        local s = R.data[name]
        if s and now - (s.t or 0) > MAX_AGE then s = nil end
        local p = s and Problems(s) or {}
        list[#list + 1] = { name = name, status = s, text = p, problems = #p }
    end
    table.sort(list, function(a, b)
        if (a.status ~= nil) ~= (b.status ~= nil) then return a.status ~= nil end
        if a.problems ~= b.problems then return a.problems > b.problems end
        return a.name < b.name
    end)
    return list
end

---------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------
local win
function R.Refresh()
    if not win or not win:IsShown() then return end
    local lines, ready, bad = {}, 0, 0
    for _, e in ipairs(R.List()) do
        local who = Ambiguate(e.name, "guild")
        if not e.status then
            lines[#lines + 1] = "|cff777777" .. who .. "  –  " .. L["keine Antwort (kein GuildPride oder abgeschaltet)"] .. "|r"
        else
            local s = e.status
            local info = ("|cff999999%d %% · %s · %s|r"):format(s.dur, (L["%d Tränke"]):format(s.pots), (L["%d Elixiere"]):format(s.elix))
            if e.problems > 0 then bad = bad + 1; lines[#lines + 1] = ("|cffff6060%s|r  %s  %s"):format(who, table.concat(e.text, ", "), info)
            else ready = ready + 1; lines[#lines + 1] = ("|cff40ff40%s|r  %s  %s"):format(who, L["bereit"], info) end
        end
    end
    win.sub:SetText((L["%d bereit · %d mit Problem · %d ohne Antwort"]):format(ready, bad, #lines - ready - bad))
    win:SetLines(lines)
end

function R.Open()
    if not win then
        win = ns.ListWindow({ name = "GuildPrideReady", title = L["Raid-Bereitschaft"], rows = 16, width = 560,
            empty = L["Du bist in keiner Gruppe."] })
        local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        if ns.SkinButton then ns.SkinButton(b) end
        b:SetSize(160, 22); b:SetPoint("TOPLEFT", 14, win.bottomY); b:SetText(L["Gruppe fragen"])
        b:SetScript("OnClick", function() R.Ask() end)
        win:SetScript("OnShow", function() win.offset = 0; R.Refresh() end)
    end
    win:Show()
    if R.CanAsk() then R.Ask() end
    R.Refresh()
end

local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "READY_CHECK")
ev:SetScript("OnEvent", function(_, _, initiator)
    if type(initiator) ~= "string" or Secret(initiator) then return end
    local who = ns.Normalize(initiator)
    -- eigener Bereitschaftscheck: die Antworten laufen ein, das Fenster zeigt sie, wenn es offen ist
    if who == ns.Me() then
        local mine = R.Status()
        mine.t = GetTime()
        R.data[who] = mine
        R.Refresh()
    else
        Answer(who)
    end
end)

local slash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd = strtrim(arg or ""):lower()
    if cmd == "bereit" or cmd == "ready" then return R.Open() end
    return slash(arg)
end
