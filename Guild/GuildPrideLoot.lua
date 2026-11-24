-- GuildPride: Loot-Verlauf – wer hat in Instanzen was bekommen (ab selten)
-- Aus den Beutemeldungen im Chat. Beim Öffnen des Fensters fragt man nach Neuerem (LTQ); es antworten
-- nur Offiziere (LTL: zeit · wer · item · qualität), und nur von ihnen wird etwas angenommen.
-- GuildTable("loot") = { { t, who, item, q, inst }, … }
local ADDON, ns = ...
local L = ns.L

local Lo = {}
ns.Loot = Lo
local MAX, MIN_QUALITY = 1500, 3

local function DB() return ns.GuildTable("loot") end

-- Blizzards Textbaustein ("%s bekommt Beute: %sx%d.") als Suchmuster
local cache = {}
local function Pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    if cache[fmt] == nil then
        local p = fmt:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%%d?%$?s", "(.+)"):gsub("%%%d?%$?d", "(%%d+)")
        cache[fmt] = "^" .. p .. "$"
    end
    return cache[fmt]
end

-- Meldung -> Name, Item-ID, Link
function Lo.Parse(text)
    if type(text) ~= "string" or (issecretvalue and issecretvalue(text)) then return nil end
    for _, fmt in ipairs({ LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_SELF }) do
        local p = Pattern(fmt)
        local link = p and text:match(p)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then return ns.Me(), id, link end
    end
    for _, fmt in ipairs({ LOOT_ITEM_MULTIPLE, LOOT_ITEM }) do
        local p = Pattern(fmt)
        local who, link
        if p then who, link = text:match(p) end
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then return ns.Normalize(who), id, link end
    end
    return nil
end

function Lo.Add(who, id, quality, inst)
    if type(who) ~= "string" or not id or (tonumber(quality) or 0) < MIN_QUALITY then return false end
    local db = DB()
    db[#db + 1] = { t = GetServerTime(), who = who, item = id, q = quality, inst = inst }
    while #db > MAX do table.remove(db, 1) end
    if Lo.Refresh then Lo.Refresh() end
    return true
end

local function Known(t, who, id)
    for _, e in ipairs(DB()) do
        if e.item == id and e.who == who and math.abs(e.t - t) <= 120 then return true end
    end
    return false
end
local SEP = ns.SEP
ns.On("LTL", function(payload, sender)
    if sender == ns.Me() or not ns.IsOfficerName(sender) then return end
    local t, who, id, q = strsplit(SEP, payload)
    t, id, q = tonumber(t), tonumber(id), tonumber(q)
    who = tostring(who or ""):gsub("[%c|]", ""):sub(1, 60)
    if not t or t > GetServerTime() + 300 or t < GetServerTime() - 400 * 86400 or who == "" then return end
    if not id or id < 1 or id % 1 ~= 0 or id > 9999999 or not q or q < MIN_QUALITY or q > 5 or q % 1 ~= 0 then return end
    if Known(t, who, id) then return end
    local db = DB()
    db[#db + 1] = { t = t, who = who, item = id, q = q }
    table.sort(db, function(a, b) return a.t < b.t end)
    while #db > MAX do table.remove(db, 1) end
    if Lo.Refresh then Lo.Refresh() end
end)
ns.On("LTQ", function(payload, sender)
    if sender == ns.Me() or not ns.IsOfficerName(ns.Me()) then return end
    local since = tonumber(payload) or 0
    C_Timer.After(1 + math.random() * 5, function()
        local db, sentN = DB(), 0
        for i = #db, 1, -1 do
            if db[i].t <= since or sentN >= 40 then break end
            ns.Queue("LTL", sender, db[i].t, db[i].who, db[i].item, db[i].q)
            sentN = sentN + 1
        end
    end)
end)
local lastAsk = -999
local function AskNewer()
    if not IsInGuild() or GetTime() - lastAsk < 300 then return end
    lastAsk = GetTime()
    local db = DB()
    ns.Queue("LTQ", nil, db[#db] and db[#db].t or 1)
end

local function ItemName(id)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name = f and f(id)
    return type(name) == "string" and name or (L["Gegenstand %d"]):format(id)
end

-- Neueste zuerst; Filter: Teil des Spieler- oder Gegenstandsnamens
function Lo.Find(filter)
    filter = strtrim(filter or ""):lower()
    local out, db = {}, DB()
    for i = #db, 1, -1 do
        local e = db[i]
        if filter == "" or e.who:lower():find(filter, 1, true) or ItemName(e.item):lower():find(filter, 1, true) then out[#out + 1] = e end
    end
    return out
end

local HEX = { [3] = "0070dd", [4] = "a335ee", [5] = "ff8000" }
local win
function Lo.Refresh()
    if not win or not win:IsShown() then return end
    win.list = Lo.Find(win.box:GetText())
    local lines, n = {}, {}
    for _, e in ipairs(win.list) do
        n[e.who] = true
        lines[#lines + 1] = ("|cff999999%s|r  %s  |cff%s%s|r  |cff777777%s|r"):format(ns.FormatDay(e.t), Ambiguate(e.who, "guild"),
            HEX[e.q] or "ffffff", ItemName(e.item), e.inst or "")
    end
    local players = 0
    for _ in pairs(n) do players = players + 1 end
    win.sub:SetText((L["%d Gegenstände an %d Spieler. Maus über eine Zeile zeigt den Gegenstand."]):format(#lines, players))
    win:SetLines(lines)
end

function Lo.Open()
    if not win then
        win = ns.ListWindow({ name = "GuildPrideLoot", title = L["Loot-Verlauf"], rows = 16, width = 540,
            empty = L["Noch keine Beute aufgezeichnet (ab selten, in Dungeons und Raids)."] })
        local box = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
        box:SetSize(220, 22); box:SetPoint("TOPLEFT", 20, win.bottomY); box:SetAutoFocus(false); box:SetMaxLetters(40)
        if ns.SkinEditBox then ns.SkinEditBox(box) end
        local hint = box:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
        hint:SetPoint("LEFT", 2, 0); hint:SetText(L["Spieler oder Gegenstand"])
        box:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == ""); win.offset = 0; Lo.Refresh() end)
        box:SetScript("OnEscapePressed", box.ClearFocus)
        win.box = box
        for i, row in ipairs(win.rows) do
            row:EnableMouse(true)
            row:SetScript("OnEnter", function(self)
                local e = win.list and win.list[i + win.offset]
                if not e then return end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink("item:" .. e.item)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", GameTooltip_Hide)
        end
        win:SetScript("OnShow", function() win.offset = 0; AskNewer(); Lo.Refresh() end)
    end
    win:SetShown(not win:IsShown())
end

local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "CHAT_MSG_LOOT")
ev:SetScript("OnEvent", function(_, _, text)
    if not IsInGuild() or not IsInInstance() then return end
    local who, id, link = Lo.Parse(text)
    if not who then return end
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, _, quality = f(link)
    local inst = GetInstanceInfo and GetInstanceInfo() or nil
    if issecretvalue and issecretvalue(inst) then inst = nil end
    Lo.Add(who, id, quality, inst)
end)

ns.Command({ "loot", "beute" }, function() Lo.Open() end)
