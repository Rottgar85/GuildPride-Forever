-- GuildPride: DKP (Punkte für Anwesenheit und Bosse, Abzug für Loot)
-- Jede Buchung ist ein Eintrag im Gilden-Buch, das alle mit GuildPride
-- abgleichen (Addon-Nachrichten). Der Punktestand ist die Summe aller nicht
-- zurückgenommenen Buchungen. Zusätzlich geht jede Buchung als "[GP] DKP ..."-
-- Zeile an Discord (GuildPrideDiscord.lua), wo GameBot dasselbe Buch führt.
-- Buchen dürfen nur Offiziere (wer die Gildennachricht ändern darf).
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP or "\031"

local DKP = {}
ns.DKP = DKP

local function Secret(v) return issecretvalue and issecretvalue(v) or false end
local function Clean(s, max) return (tostring(s or ""):gsub("[%c|,:]", "")):sub(1, max or 60) end
local function CanManage() return CanEditMOTD and CanEditMOTD() end
local function Now() return GetServerTime() end

local function Book() return ns.GuildTable("dkp") end   -- [id] = { d, r, by, t, n = {names}, x = void }

---------------------------------------------------------------------
-- Stände
---------------------------------------------------------------------
local cache
function DKP.Standings()
    if cache then return cache end
    cache = {}
    for _, tx in pairs(Book()) do
        if not tx.x and tx.n then
            for _, name in ipairs(tx.n) do cache[name] = (cache[name] or 0) + (tx.d or 0) end
        end
    end
    return cache
end
local function Changed()
    cache = nil
    if DKP.Refresh then DKP.Refresh() end
end

function DKP.Of(name) return DKP.Standings()[name] end

---------------------------------------------------------------------
-- Abgleich
---------------------------------------------------------------------
local function SendTx(id, tx, target)
    ns.Queue("DKP", target, id, tx.d, tx.r, tx.by, tx.t, tx.x and 1 or 0, table.concat(tx.n or {}, ","))
end

local function Apply(id, d, r, by, t, x, names)
    if id == "" or not d or not names then return end
    local book = Book()
    local cur = book[id]
    if cur then
        if x and not cur.x then cur.x = true; Changed() end
        return
    end
    book[id] = { d = d, r = r, by = by, t = t, x = x or nil, n = names }
    Changed()
end

ns.On("DKP", function(payload, sender)
    if sender == ns.Me() or not ns.IsGuildMember(sender) then return end
    local a = { strsplit(SEP, payload) }
    local d = ns.Num(a[2], -100000, 100000)
    local names = {}
    for n in (a[7] or ""):gmatch("[^,]+") do
        n = Clean(n, 60)
        if n ~= "" and #names < 80 then names[#names + 1] = n end
    end
    Apply(Clean(a[1], 20), d, Clean(a[3], 60), Clean(a[4], 60), ns.Stamp(a[5]), a[6] == "1", names)
end)

local function SendAll(target)
    for id, tx in pairs(Book()) do SendTx(id, tx, target) end
end
for _, k in ipairs({ "REQ", "DKPQ" }) do
    ns.On(k, function(_, sender)
        if sender == ns.Me() then return end
        C_Timer.After(1 + math.random() * 4, function() SendAll(sender) end)
    end)
end

---------------------------------------------------------------------
-- Buchen (nur aus Klicks heraus aufrufen)
---------------------------------------------------------------------
local function NewId()
    local chars, out = "0123456789abcdefghijklmnopqrstuvwxyz", ""
    for _ = 1, 6 do local r = math.random(1, 36); out = out .. chars:sub(r, r) end
    return out
end

local function Short(name) return Ambiguate(name or "", "guild") end

local function PostDiscord(id, d, r, names)
    if not ns.Discord then return end
    local head = ("DKP #%s %+d %s: "):format(id, d, r)
    local chunks, cur = {}, {}
    for _, n in ipairs(names) do
        local test = head .. table.concat(cur, ", ") .. (#cur > 0 and ", " or "") .. Short(n)
        if #cur > 0 and #test > 230 then chunks[#chunks + 1] = cur; cur = {} end
        cur[#cur + 1] = Short(n)
    end
    if #cur > 0 then chunks[#chunks + 1] = cur end
    for i, c in ipairs(chunks) do
        local tag = #chunks > 1 and ("DKP #%s(%d/%d)"):format(id, i, #chunks) or ("DKP #%s"):format(id)
        ns.Discord.Post(("%s %+d %s: %s"):format(tag, d, r, table.concat(c, ", ")), i == 1)
    end
end

local seq = 0
function DKP.Award(names, d, reason)
    if not CanManage() then ns.Print(L["Nur Offiziere dürfen DKP buchen."]); return end
    d = math.floor(tonumber(d) or 0)
    if d == 0 or #names == 0 then return end
    local id, r = NewId(), Clean(reason, 40)
    if r == "" then r = d > 0 and L["Bonus"] or L["Abzug"] end
    Apply(id, d, r, ns.Me(), Now(), false, names)
    seq = seq + 1
    Book()[id].s = seq   -- Reihenfolge eigener Buchungen (gleiche Sekunde)
    SendTx(id, Book()[id])
    PostDiscord(id, d, r, names)
    ns.Print((L["DKP gebucht: %+d %s für %d Spieler"]):format(d, r, #names))
end

function DKP.Undo()
    if not CanManage() then return end
    local lastId, last
    for id, tx in pairs(Book()) do
        if not tx.x and tx.by == ns.Me() and (not last or (tx.t or 0) > (last.t or 0)
            or ((tx.t or 0) == (last.t or 0) and (tx.s or 0) > (last.s or 0))) then lastId, last = id, tx end
    end
    if not last then ns.Print(L["Keine eigene Buchung zum Zurücknehmen."]); return end
    last.x = true
    Changed()
    SendTx(lastId, last)
    if ns.Discord then ns.Discord.Post(("DKP #%s zurückgenommen"):format(lastId), true) end
    ns.Print((L["Zurückgenommen: %+d %s"]):format(last.d, last.r or ""))
end

-- Alle im Raid bzw. in der Gruppe (inkl. mir)
function DKP.GroupNames()
    local names = {}
    local function add(unit)
        if not UnitExists(unit) then return end
        local n, s = UnitFullName(unit)
        if not n or Secret(n) then return end
        if Secret(s) then s = nil end
        names[#names + 1] = ns.Normalize((s and s ~= "") and (n .. "-" .. s) or n)
    end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do add("raid" .. i) end
    else
        add("player")
        for i = 1, GetNumSubgroupMembers() do add("party" .. i) end
    end
    return names
end

function DKP.TargetName()
    if not UnitIsPlayer("target") then return end
    local n, s = UnitFullName("target")
    if not n or Secret(n) then return end
    if Secret(s) then s = nil end
    return ns.Normalize((s and s ~= "") and (n .. "-" .. s) or n)
end

---------------------------------------------------------------------
-- Tooltip: "DKP: 125" bei Spielern
---------------------------------------------------------------------
local function OnUnitTooltip(tip)
    if not GuildPrideDB or not IsInGuild() then return end
    local ok, _, unit = pcall(tip.GetUnit, tip)
    if not ok or not unit or Secret(unit) or not UnitIsPlayer(unit) then return end
    local n, s = UnitFullName(unit)
    if not n or Secret(n) or Secret(s) then return end
    local pts = DKP.Of(ns.Normalize((s and s ~= "") and (n .. "-" .. s) or n))
    if pts then tip:AddLine(("|cffffd100DKP:|r %d"):format(pts)) end
end
if TooltipDataProcessor and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, OnUnitTooltip)
end

---------------------------------------------------------------------
-- Fenster: /gp dkp
---------------------------------------------------------------------
local win
local function Button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    if ns.SkinButton then pcall(ns.SkinButton, b) end
    return b
end
local function Edit(parent, w, text)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(w, 20)
    e:SetAutoFocus(false)
    e:SetText(text or "")
    if ns.SkinEditBox then pcall(ns.SkinEditBox, e) end
    return e
end

local function Build()
    win = CreateFrame("Frame", "GuildPrideDKPFrame", UIParent, "BasicFrameTemplateWithInset")
    win:SetSize(340, 470)
    win:SetPoint("CENTER")
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetFrameStrata("DIALOG")
    tinsert(UISpecialFrames, "GuildPrideDKPFrame")
    win.title = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    win.title:SetPoint("TOP", 0, -5)
    win.title:SetText("GuildPride – DKP")

    local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -30)
    scroll:SetPoint("BOTTOMRIGHT", -32, 175)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(280, 10)
    scroll:SetScrollChild(content)
    win.list = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.list:SetPoint("TOPLEFT")
    win.list:SetWidth(280)
    win.list:SetJustifyH("LEFT")
    win.content = content

    -- Offiziers-Bereich
    local box = CreateFrame("Frame", nil, win)
    box:SetPoint("BOTTOMLEFT", 12, 10)
    box:SetPoint("BOTTOMRIGHT", -12, 10)
    box:SetHeight(160)
    win.officer = box

    local lAmt = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lAmt:SetPoint("TOPLEFT", 0, 0); lAmt:SetText(L["Punkte"])
    win.amount = Edit(box, 50, "10"); win.amount:SetPoint("TOPLEFT", 6, -14)
    local lReason = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lReason:SetPoint("TOPLEFT", 70, 0); lReason:SetText(L["Grund / Item"])
    win.reason = Edit(box, 230, L["Anwesenheit"]); win.reason:SetPoint("TOPLEFT", 76, -14)

    local function amount() return tonumber(win.amount:GetText()) or 0 end
    local function reason() return win.reason:GetText() end

    local bRaid = Button(box, L["An Raid/Gruppe"], 150, function()
        DKP.Award(DKP.GroupNames(), amount(), reason())
    end)
    bRaid:SetPoint("TOPLEFT", 0, -42)
    local bTarget = Button(box, L["An Ziel"], 150, function()
        local n = DKP.TargetName()
        if not n then ns.Print(L["Bitte zuerst einen Spieler anvisieren."]); return end
        DKP.Award({ n }, amount(), reason())
    end)
    bTarget:SetPoint("TOPRIGHT", 0, -42)

    local bBoss = Button(box, L["Boss-Kill (+5 Raid)"], 150, function()
        DKP.Award(DKP.GroupNames(), 5, L["Boss"])
    end)
    bBoss:SetPoint("TOPLEFT", 0, -68)
    local bLoot = Button(box, L["Loot an Ziel (abziehen)"], 150, function()
        local n = DKP.TargetName()
        if not n then ns.Print(L["Bitte zuerst einen Spieler anvisieren."]); return end
        local a = math.abs(amount())
        DKP.Award({ n }, -a, L["Loot"] .. " " .. reason())
    end)
    bLoot:SetPoint("TOPRIGHT", 0, -68)

    local bUndo = Button(box, L["Letzte Buchung zurücknehmen"], 316, function() DKP.Undo() end)
    bUndo:SetPoint("TOPLEFT", 0, -98)

    local hint = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 0, -126); hint:SetWidth(316); hint:SetJustifyH("LEFT")
    hint:SetText(L["Loot: Item als Grund eintragen, Preis als Punkte, Spieler anvisieren."])

    if ns.SkinAll then pcall(ns.SkinAll, win) end
end

function DKP.Refresh()
    if not win or not win:IsShown() then return end
    local rows = {}
    for name, pts in pairs(DKP.Standings()) do rows[#rows + 1] = { name, pts } end
    table.sort(rows, function(a, b) if a[2] ~= b[2] then return a[2] > b[2] end return a[1] < b[1] end)
    local lines = {}
    for i, r in ipairs(rows) do
        lines[#lines + 1] = ("%2d.  %s  |cffffd100%d|r"):format(i, Short(r[1]), r[2])
    end
    win.list:SetText(#lines > 0 and table.concat(lines, "\n") or L["Noch keine DKP-Buchungen."])
    win.content:SetHeight(win.list:GetStringHeight() + 10)
    win.officer:SetShown(CanManage())
end

function DKP.Toggle()
    if not win then Build() end
    if win:IsShown() then win:Hide() return end
    win:Show()
    DKP.Refresh()
    ns.Queue("DKPQ", nil, "1")
end

local slash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    if strtrim(arg or ""):lower() == "dkp" then return DKP.Toggle() end
    return slash(arg)
end
