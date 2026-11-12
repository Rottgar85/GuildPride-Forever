-- GuildPride: Bieterrunde für Loot und Raid-Zusammenfassung
-- Bieterrunde: ein Offizier startet sie im DKP-Fenster (Item als Grund, Mindestgebot
-- als Punkte). Alle in der Gruppe sehen ein Bieterfenster, Gebote gehen per
-- Addon-Nachricht an den Offizier. Nach 30 Sekunden zahlt der Höchstbietende
-- sein Gebot (DKP-Abzug wie "Loot an Ziel"). Gleichstand: das frühere Gebot gewinnt.
-- Raid-Zusammenfassung: Instanz, Dauer, Bosse und Spieler werden mitgeschrieben;
-- "Raid-Zusammenfassung senden" schickt sie an Discord (GameBot rechnet DKP und Loot dazu).
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP or "\031"
local DURATION = 30

local Raid = {}
ns.Raid = Raid

local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function CanManage() return CanEditMOTD and CanEditMOTD() end
local function Short(n) return Ambiguate(n or "", "guild") end
local function Clean(s, max) return (tostring(s or ""):gsub("[%c|]", "")):sub(1, max or 60) end

-- "|cff...|Hitem:...|h[Name]|h|r" -> "Name"
local function ItemName(text)
    text = tostring(text or "")
    return Clean(text:match("%[(.-)%]") or text, 50)
end

---------------------------------------------------------------------
-- Bieterfenster (für alle)
---------------------------------------------------------------------
local cur          -- laufende Auktion: { id, item, min, ends, by, high, highBy }
local bidWin

local function UpdateBidWin()
    if not bidWin or not cur then return end
    bidWin.item:SetText(cur.item)
    bidWin.high:SetText(cur.high and (L["Höchstgebot: %d (%s)"]):format(cur.high, Short(cur.highBy))
        or (L["Mindestgebot: %d"]):format(cur.min))
    local mine = ns.DKP and ns.DKP.Of(ns.Me()) or 0
    bidWin.mine:SetText((L["Deine DKP: %d"]):format(mine or 0))
end

local function BuildBidWin()
    bidWin = CreateFrame("Frame", "GuildPrideBidFrame", UIParent, "BasicFrameTemplateWithInset")
    bidWin:SetSize(300, 170)
    bidWin:SetPoint("TOP", 0, -140)
    bidWin:SetFrameStrata("DIALOG")
    bidWin:SetMovable(true); bidWin:EnableMouse(true)
    bidWin:RegisterForDrag("LeftButton")
    bidWin:SetScript("OnDragStart", bidWin.StartMoving)
    bidWin:SetScript("OnDragStop", bidWin.StopMovingOrSizing)
    local t = bidWin:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetPoint("TOP", 0, -5); t:SetText(L["Bieterrunde"])
    bidWin.item = bidWin:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    bidWin.item:SetPoint("TOP", 0, -34); bidWin.item:SetWidth(270)
    bidWin.high = bidWin:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bidWin.high:SetPoint("TOP", 0, -60)
    bidWin.mine = bidWin:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    bidWin.mine:SetPoint("TOP", 0, -78)
    bidWin.time = bidWin:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    bidWin.time:SetPoint("TOPRIGHT", -14, -30)

    bidWin.edit = CreateFrame("EditBox", nil, bidWin, "InputBoxTemplate")
    bidWin.edit:SetSize(70, 22); bidWin.edit:SetPoint("BOTTOMLEFT", 22, 18)
    bidWin.edit:SetAutoFocus(false); bidWin.edit:SetNumeric(true)
    local function Bid()
        local n = tonumber(bidWin.edit:GetText())
        if n then Raid.Bid(n) end
        bidWin.edit:ClearFocus()
    end
    bidWin.edit:SetScript("OnEnterPressed", Bid)
    local b = CreateFrame("Button", nil, bidWin, "UIPanelButtonTemplate")
    b:SetSize(80, 22); b:SetPoint("LEFT", bidWin.edit, "RIGHT", 6, 0); b:SetText(L["Bieten"])
    b:SetScript("OnClick", Bid)
    local plus = CreateFrame("Button", nil, bidWin, "UIPanelButtonTemplate")
    plus:SetSize(70, 22); plus:SetPoint("LEFT", b, "RIGHT", 6, 0); plus:SetText("+10")
    plus:SetScript("OnClick", function()
        if not cur then return end
        Raid.Bid((cur.high or (cur.min - 10)) + 10)
    end)
    bidWin:SetScript("OnUpdate", function(self, el)
        self.acc = (self.acc or 0) + el
        if self.acc < 0.25 then return end
        self.acc = 0
        if not cur then return end
        local left = math.max(0, cur.ends - GetServerTime())
        self.time:SetText(("%d s"):format(left))
    end)
    if ns.SkinAll then pcall(ns.SkinAll, bidWin) end
end

local function ShowBidWin()
    if not bidWin then BuildBidWin() end
    bidWin.edit:SetText("")
    bidWin:Show()
    UpdateBidWin()
end

---------------------------------------------------------------------
-- Ablauf
---------------------------------------------------------------------
local bids   -- beim Auktionator: [name] = { amount, t }

function Raid.Start(item, min)
    if not CanManage() then ns.Print(L["Nur Offiziere dürfen DKP buchen."]); return end
    if cur then ns.Print(L["Es läuft schon eine Bieterrunde."]); return end
    item = ItemName(item)
    if item == "" then ns.Print(L["Bitte das Item als Grund eintragen."]); return end
    min = math.max(0, math.floor(tonumber(min) or 0))
    local id = tostring(math.random(100000, 999999))
    cur = { id = id, item = item, min = min, ends = GetServerTime() + DURATION, by = ns.Me() }
    bids = {}
    ns.Queue("AUC", nil, id, item, min, cur.ends, cur.by)
    ShowBidWin()
    C_Timer.After(DURATION, function() Raid.Finish(id) end)
end

function Raid.Bid(amount)
    if not cur then return end
    amount = math.floor(amount)
    if amount < cur.min or (cur.high and amount <= cur.high) then
        ns.Print(L["Gebot zu niedrig."]); return
    end
    local mine = ns.DKP and ns.DKP.Of(ns.Me()) or 0
    if amount > (mine or 0) then ns.Print(L["So viele DKP hast du nicht."]); return end
    if cur.by == ns.Me() then
        Raid.OnBid(cur.id, amount, ns.Me())
    else
        ns.Queue("BID", cur.by, cur.id, amount)
    end
end

-- Beim Auktionator: Gebot prüfen und das neue Höchstgebot bekannt geben
function Raid.OnBid(id, amount, who)
    if not cur or cur.id ~= id or cur.by ~= ns.Me() or not bids then return end
    if GetServerTime() > cur.ends then return end
    local have = ns.DKP and ns.DKP.Of(who) or 0
    if amount < cur.min or amount > (have or 0) or (cur.high and amount <= cur.high) then return end
    bids[who] = { amount, GetTime() }
    cur.high, cur.highBy = amount, who
    ns.Queue("AUH", nil, id, amount, who)
    UpdateBidWin()
end

function Raid.Finish(id)
    if not cur or cur.id ~= id then return end
    local a = cur
    cur, bids = nil, nil
    if a.high and a.highBy then
        ns.DKP.Award({ a.highBy }, -a.high, L["Loot"] .. " " .. a.item)
        ns.Queue("AUE", nil, id, a.highBy, a.high, a.item)
        ns.Print((L["%s geht an %s für %d DKP."]):format(a.item, Short(a.highBy), a.high))
    else
        ns.Queue("AUE", nil, id, "", 0, a.item)
        ns.Print((L["Keine Gebote für %s."]):format(a.item))
    end
    if bidWin then bidWin:Hide() end
end

ns.On("AUC", function(payload, sender)
    if sender == ns.Me() or not IsInGroup() then return end
    local p = { strsplit(SEP, payload) }
    local ends = ns.Num(p[4], 0, GetServerTime() + 120)
    if not ends or ends < GetServerTime() then return end
    cur = { id = Clean(p[1], 10), item = ItemName(p[2]), min = ns.Num(p[3], 0, 100000) or 0, ends = ends, by = sender }
    ShowBidWin()
    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.RAID_WARNING) end
end)
ns.On("BID", function(payload, sender)
    local p = { strsplit(SEP, payload) }
    local amount = ns.Num(p[2], 0, 100000)
    if amount then Raid.OnBid(Clean(p[1], 10), amount, sender) end
end)
ns.On("AUH", function(payload, sender)
    local p = { strsplit(SEP, payload) }
    if not cur or cur.id ~= p[1] or cur.by ~= sender then return end
    cur.high, cur.highBy = ns.Num(p[2], 0, 100000), Clean(p[3], 60)
    UpdateBidWin()
end)
ns.On("AUE", function(payload, sender)
    local p = { strsplit(SEP, payload) }
    if not cur or cur.id ~= p[1] or cur.by ~= sender then return end
    local winner, price = Clean(p[2], 60), ns.Num(p[3], 0, 100000) or 0
    if winner ~= "" then
        ns.Print((L["%s geht an %s für %d DKP."]):format(cur.item, Short(winner), price))
    else
        ns.Print((L["Keine Gebote für %s."]):format(cur.item))
    end
    cur = nil
    if bidWin then bidWin:Hide() end
end)

---------------------------------------------------------------------
-- Raid-Zusammenfassung
---------------------------------------------------------------------
local function Session() return GuildPrideDB and GuildPrideDB.raidSession end

local function CheckInstance()
    if not GuildPrideDB then return end
    local inside, kind = IsInInstance()
    if not inside or kind ~= "raid" then return end
    local zone = GetInstanceInfo()
    if not zone or Secret(zone) then return end
    local s = Session()
    -- Neue Instanz oder älter als 8 Stunden: neue Sitzung
    if not s or s.zone ~= zone or GetServerTime() - (s.start or 0) > 8 * 3600 then
        GuildPrideDB.raidSession = { zone = zone, start = GetServerTime(), bosses = {}, players = {} }
    end
end

local function AddPlayers()
    local s = Session()
    if not s or not ns.DKP then return end
    for _, n in ipairs(ns.DKP.GroupNames()) do s.players[n] = true end
end

local rf = CreateFrame("Frame")
rf:RegisterEvent("PLAYER_ENTERING_WORLD")
rf:RegisterEvent("ZONE_CHANGED_NEW_AREA")
rf:RegisterEvent("GROUP_ROSTER_UPDATE")
rf:RegisterEvent("ENCOUNTER_END")
rf:SetScript("OnEvent", function(_, event, ...)
    if event == "ENCOUNTER_END" then
        local _, name, _, _, success = ...
        local s = Session()
        if s and success == 1 and name and not Secret(name) then
            for _, b in ipairs(s.bosses) do if b == name then return end end
            s.bosses[#s.bosses + 1] = name
            AddPlayers()
        end
    elseif event == "GROUP_ROSTER_UPDATE" then
        AddPlayers()
    else
        CheckInstance()
        AddPlayers()
    end
end)

function Raid.SendSummary()
    if not CanManage() then ns.Print(L["Nur Offiziere dürfen DKP buchen."]); return end
    local s = Session()
    if not s then ns.Print(L["Kein Raid mitgeschrieben. Die Zusammenfassung beginnt beim Betreten einer Raid-Instanz."]); return end
    AddPlayers()
    local mins = math.floor((GetServerTime() - s.start) / 60)
    local n = 0
    for _ in pairs(s.players) do n = n + 1 end
    local DE = ns.IS_GERMAN
    local bosses = table.concat(s.bosses, ", ")
    local line = ("Raid: %s · %d:%02d · %d %s%s · %d %s"):format(Clean(s.zone, 40), math.floor(mins / 60), mins % 60,
        #s.bosses, DE and "Bosse" or "bosses", #s.bosses > 0 and (": " .. bosses) or "", n, DE and "Spieler" or "players")
    if #line > 240 then
        line = ("Raid: %s · %d:%02d · %d %s · %d %s"):format(Clean(s.zone, 40), math.floor(mins / 60), mins % 60,
            #s.bosses, DE and "Bosse" or "bosses", n, DE and "Spieler" or "players")
    end
    if ns.Discord then ns.Discord.Post(line, true) end
    ns.Print(L["Raid-Zusammenfassung gesendet."])
    GuildPrideDB.raidSession = nil
end

local slash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local a = strtrim(arg or ""):lower()
    if a == "raid" then return Raid.SendSummary() end
    return slash(arg)
end
