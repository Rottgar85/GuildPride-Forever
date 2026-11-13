-- GuildPride: Wunschliste
-- Jedes Mitglied markiert Items, die es haben möchte (normal, hoch, BiS).
-- Im Item-Tooltip steht dann, wer in der Gilde das Item sucht (mit DKP-Stand),
-- und bei einem Drop im Raid sieht man sofort, wer in der Gruppe es will.
-- Abgleich: jeder schickt nur seine EIGENE Liste (WSH), nie über Weiterleitung.
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP or "\031"

local MAX_ITEMS, MAX_PEOPLE = 60, 1000
local Wish = {}
ns.Wish = Wish

local function DB() return ns.GuildTable("wish") end   -- [Name] = { v, i = { [itemID] = Stufe } }
local function Me() return ns.Me() end
local function Now() return GetServerTime() end

-- Stufen: 1 normal, 2 hoch, 3 BiS
local PRIO_COLOR = { "|cffd8d0c0", "|cffffb040", "|cffff6a3d" }
local function PrioName(p)
    if p == 3 then return L["BiS"] elseif p == 2 then return L["hoch"] end
    return L["normal"]
end
Wish.PrioName = PrioName

local function ItemID(v)
    if type(v) == "number" then return v > 0 and v < 2 ^ 31 and math.floor(v) or nil end
    if type(v) ~= "string" then return nil end
    local id = tonumber(v:match("item:(%d+)") or v:match("^%s*(%d+)%s*$"))
    return id and id > 0 and id < 2 ^ 31 and id or nil
end
Wish.ItemID = ItemID

---------------------------------------------------------------------
-- Kodieren: "id36:stufe,id36:stufe"
---------------------------------------------------------------------
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function B36(n)
    if n == 0 then return "0" end
    local s = ""
    while n > 0 do
        local d = n % 36
        s = DIGITS:sub(d + 1, d + 1) .. s
        n = math.floor(n / 36)
    end
    return s
end

function Wish.Encode(items)
    local ids = {}
    for id in pairs(items or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        if #parts >= MAX_ITEMS then break end
        parts[#parts + 1] = B36(id) .. ":" .. items[id]
    end
    return table.concat(parts, ",")
end

function Wish.Decode(s)
    local items, n = {}, 0
    for code, p in tostring(s or ""):gmatch("([0-9a-z]+):([123])") do
        local id = tonumber(code, 36)
        if id and id > 0 and id < 2 ^ 31 and not items[id] then
            items[id] = tonumber(p)
            n = n + 1
            if n >= MAX_ITEMS then break end
        end
    end
    return items
end

---------------------------------------------------------------------
-- Eigene Liste
---------------------------------------------------------------------
local function Mine()
    local e = DB()[Me()]
    if not e then
        e = { v = 0, i = {} }
        DB()[Me()] = e
    end
    e.i = e.i or {}
    return e
end
Wish.Mine = Mine

local function Send(target)
    local e = DB()[Me()]
    if e and e.v and e.v > 0 then ns.Queue("WSH", target, e.v, Wish.Encode(e.i)) end
end

local sendPending = false
local function SendSoon()
    if sendPending then return end
    sendPending = true
    C_Timer.After(3, function()
        sendPending = false
        local e = DB()[Me()]
        if e then e.sent = Now() end
        Send()
    end)
end

local function Changed()
    if Wish.Refresh then Wish.Refresh() end
end

function Wish.Count(items)
    local n = 0
    for _ in pairs(items or {}) do n = n + 1 end
    return n
end

-- Stufe setzen (0 oder nil = entfernen); gibt true zurück, wenn sich etwas änderte
function Wish.Set(item, prio)
    local id = ItemID(item)
    if not id then return false end
    prio = tonumber(prio) or 0
    if prio < 0 or prio > 3 then return false end
    local e = Mine()
    if (e.i[id] or 0) == prio then return false end
    if prio == 0 then
        e.i[id] = nil
    else
        if not e.i[id] and Wish.Count(e.i) >= MAX_ITEMS then
            ns.Print((L["Die Wunschliste ist voll (höchstens %d Items)."]):format(MAX_ITEMS))
            return false
        end
        e.i[id] = prio
    end
    e.v = math.max(Now(), (e.v or 0) + 1)
    SendSoon()
    Changed()
    return true
end

-- Schalter für Klicks: fehlt -> normal, sonst entfernen
function Wish.Toggle(item)
    local id = ItemID(item)
    if not id then return false end
    local e = Mine()
    if e.i[id] then
        Wish.Set(id, 0)
        ns.Print((L["Von der Wunschliste entfernt: %s"]):format(Wish.Link(id)))
    elseif Wish.Set(id, 1) then
        ns.Print((L["Auf die Wunschliste gesetzt: %s"]):format(Wish.Link(id)))
    end
    return true
end

-- Stufe weiterschalten: normal -> hoch -> BiS -> normal
function Wish.Cycle(id)
    local cur = Mine().i[id]
    if not cur then return end
    Wish.Set(id, cur % 3 + 1)
end

---------------------------------------------------------------------
-- Wer sucht was?
---------------------------------------------------------------------
-- Liste { name, prio, dkp } für ein Item, Wichtigste zuerst
function Wish.Who(item, onlyNames)
    local id = ItemID(item)
    local out = {}
    if not id then return out end
    for name, e in pairs(DB()) do
        local p = e.i and e.i[id]
        if p and (not onlyNames or onlyNames[name]) and (name == Me() or ns.IsGuildMember(name)) then
            out[#out + 1] = { name = name, prio = p, dkp = ns.DKP and ns.DKP.Of(name) or nil }
        end
    end
    table.sort(out, function(a, b)
        if a.prio ~= b.prio then return a.prio > b.prio end
        if (a.dkp or 0) ~= (b.dkp or 0) then return (a.dkp or 0) > (b.dkp or 0) end
        return a.name < b.name
    end)
    return out
end

-- Alle gesuchten Items der Gilde: { id, count, top = höchste Stufe, names }
function Wish.GuildItems()
    local byId = {}
    for name, e in pairs(DB()) do
        if name ~= Me() and ns.IsGuildMember(name) then
            for id, p in pairs(e.i or {}) do
                local x = byId[id]
                if not x then x = { id = id, count = 0, top = 0, names = {} }; byId[id] = x end
                x.count = x.count + 1
                if p > x.top then x.top = p end
                x.names[#x.names + 1] = name
            end
        end
    end
    local list = {}
    for _, x in pairs(byId) do list[#list + 1] = x end
    table.sort(list, function(a, b)
        if a.top ~= b.top then return a.top > b.top end
        if a.count ~= b.count then return a.count > b.count end
        return a.id < b.id
    end)
    return list
end

---------------------------------------------------------------------
-- Itemnamen und Links (nicht zwischengespeicherte Items kommen später)
---------------------------------------------------------------------
local function ItemInfo(id)
    local name, link, quality, _, _, _, _, _, _, icon
    if C_Item and C_Item.GetItemInfo then
        name, link, quality, _, _, _, _, _, _, icon = C_Item.GetItemInfo(id)
    elseif GetItemInfo then
        name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(id)
    end
    if not icon then
        icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or (GetItemIcon and GetItemIcon(id))
    end
    if not name and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return name, link, quality, icon
end
Wish.ItemInfo = ItemInfo

function Wish.Link(id)
    local name, link = ItemInfo(id)
    return link or (name and ("[" .. name .. "]")) or ("item:" .. id)
end

---------------------------------------------------------------------
-- Empfangen
---------------------------------------------------------------------
local function Accept(sender)
    return sender ~= Me() and ns.IsDirect(sender, sender) and ns.IsGuildMember(sender)
end

ns.On("WSH", function(payload, sender)
    if not Accept(sender) then return end
    local ver, list = strsplit(SEP, payload)
    ver = ns.Stamp(ver)
    if ver == 0 then return end
    local e = DB()[sender]
    if e and ver <= (e.v or 0) then return end
    if not e and Wish.Count(DB()) >= MAX_PEOPLE then return end
    local items = Wish.Decode(list)
    if next(items) == nil then
        DB()[sender] = nil   -- Liste geleert
    else
        DB()[sender] = { v = ver, i = items }
    end
    Changed()
end)

-- Anfrage: höchstens alle 30 Minuten je Fragendem antworten
local answered = {}
ns.On("WSQ", function(_, sender)
    if sender == Me() or not ns.IsGuildMember(sender) then return end
    local now = GetTime()
    if answered[sender] and now - answered[sender] < 1800 then return end
    answered[sender] = now
    C_Timer.After(math.random() * 5, function() Send(sender) end)
end)

---------------------------------------------------------------------
-- Drop im Raid: wer in der Gruppe will das Item? (aufgerufen aus GuildPrideDKP.lua)
---------------------------------------------------------------------
local function GroupSet()
    local set = { [Me()] = true }
    if ns.DKP and ns.DKP.GroupNames then
        for _, n in ipairs(ns.DKP.GroupNames()) do set[n] = true end
    end
    return set
end

function Wish.DropText(link)
    local who = Wish.Who(link, GroupSet())
    if #who == 0 then return nil end
    local parts = {}
    for i, w in ipairs(who) do
        if i > 6 then parts[#parts + 1] = ("+%d"):format(#who - 6) break end
        parts[#parts + 1] = ("%s%s|r (%s%s)"):format(PRIO_COLOR[w.prio], Ambiguate(w.name, "guild"), PrioName(w.prio),
            w.dkp and (", " .. w.dkp .. " DKP") or "")
    end
    return table.concat(parts, ", ")
end

local announced = {}
function ns.WishDrop(link)
    if not GuildPrideDB or GuildPrideDB.wishDropHint == false then return end
    local text = Wish.DropText(link)
    if not text then return end
    local id = ItemID(link)
    local key = id .. ":" .. math.floor(Now() / 120)
    if announced[key] then return end
    announced[key] = true
    ns.Print((L["Gewünscht: %s – %s"]):format(link, text))
end

---------------------------------------------------------------------
-- Item-Tooltip: "Gesucht in der Gilde"
---------------------------------------------------------------------
local function AddTooltipLines(tip, id)
    if not GuildPrideDB or not IsInGuild() or GuildPrideDB.wishTooltip == false then return end
    local who = Wish.Who(id)
    if #who == 0 then return end
    local mine = Mine().i[id]
    local others = {}
    for _, w in ipairs(who) do if w.name ~= Me() then others[#others + 1] = w end end
    if mine then
        tip:AddLine(("|cffffd100GuildPride:|r " .. L["auf deiner Wunschliste (%s)"]):format(PrioName(mine)), 1, 1, 1)
    end
    if #others == 0 then return end
    tip:AddLine(("|cffffd100GuildPride:|r " .. L["gesucht von %d in der Gilde"]):format(#others), 1, 1, 1)
    for i, w in ipairs(others) do
        if i > 5 then
            tip:AddLine(("   " .. L["… und %d weitere"]):format(#others - 5), 0.7, 0.7, 0.7)
            break
        end
        tip:AddDoubleLine("   " .. PRIO_COLOR[w.prio] .. Ambiguate(w.name, "guild") .. "|r",
            PrioName(w.prio) .. (w.dkp and ("  ·  " .. w.dkp .. " DKP") or ""), 1, 1, 1, 0.8, 0.8, 0.8)
    end
end
Wish.AddTooltipLines = AddTooltipLines

local function OnItemTooltip(tip, data)
    if tip ~= GameTooltip and tip ~= ItemRefTooltip then return end
    local id = data and type(data.id) == "number" and data.id
    if not id and tip.GetItem then
        local ok, _, link = pcall(tip.GetItem, tip)
        if ok then id = ItemID(link) end
    end
    if id then pcall(AddTooltipLines, tip, id) end
end
if TooltipDataProcessor and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnItemTooltip)
elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetItem", function(tip) OnItemTooltip(tip) end)
end

---------------------------------------------------------------------
-- Ereignisse: eigene Liste nach dem Einloggen melden (bei Änderung oder alle 3 Tage)
---------------------------------------------------------------------
local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "PLAYER_ENTERING_WORLD", "GET_ITEM_INFO_RECEIVED")
local started, infoPending = false, false
ev:SetScript("OnEvent", function(_, event)
    if not GuildPrideDB or not IsInGuild() then return end
    if event == "GET_ITEM_INFO_RECEIVED" then
        if infoPending then return end
        infoPending = true
        C_Timer.After(0.5, function() infoPending = false; Changed() end)
        return
    end
    if started then return end
    started = true
    C_Timer.After(55, function()
        local e = DB()[Me()]
        if e and (e.v or 0) > 0 and Now() - (e.sent or 0) > 3 * 86400 then
            e.sent = Now()
            Send()
        end
    end)
end)

-- /gp wunsch [Item]
local slash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd, rest = strtrim(arg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "wunsch" or cmd == "wish" then
        if rest ~= "" and Wish.Toggle(rest) then return end
        if Wish.Open then Wish.Open() end
        return
    end
    return slash(arg)
end

---------------------------------------------------------------------
-- Reiter "Wünsche"
---------------------------------------------------------------------
if not ns.AddTab then return end
local page = ns.AddTab(L["Wünsche"], 45)
ns.WishPage = page

local input = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
input:SetSize(250, 22); input:SetPoint("TOPLEFT", 8, -6)
input:SetAutoFocus(false); input:SetMaxLetters(300)
local ph = input:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
ph:SetPoint("LEFT", 4, 0); ph:SetText(L["Item mit Umschalt+Klick hier einfügen"])

local function AddButton(text, prio, anchor, x)
    local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    b:SetSize(64, 22); b:SetPoint("LEFT", anchor, "RIGHT", x, 0)
    b:SetText(text)
    b:SetScript("OnClick", function()
        local id = ItemID(input:GetText())
        if not id then ns.Print(L["Bitte zuerst ein Item einfügen (Umschalt+Klick auf ein Item)."]); return end
        Wish.Set(id, prio)
        input:SetText(""); input:ClearFocus()
    end)
    if ns.SkinButton then pcall(ns.SkinButton, b) end
    return b
end
local b1 = AddButton(L["normal"], 1, input, 10)
local b2 = AddButton(L["hoch"], 2, b1, 4)
AddButton(L["BiS"], 3, b2, 4)

local info = page:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
info:SetPoint("TOPLEFT", 8, -34); info:SetWidth(600); info:SetJustifyH("LEFT")
info:SetText(L["Im Item-Tooltip sieht die Gilde, wer ein Item sucht. Klick auf deinen Wunsch ändert die Stufe, Rechtsklick entfernt ihn."])

local holder = CreateFrame("Frame", nil, page)
holder:SetPoint("TOPLEFT", 0, -52); holder:SetPoint("BOTTOMRIGHT")
local list = ns.CreateList(holder, 24)

-- Umschalt+Klick auf ein Item fügt den Link ins Feld ein
hooksecurefunc("ChatEdit_InsertLink", function(link)
    if link and input:HasFocus() then input:SetText(link) end
end)

local function ItemLabel(id)
    local name, link, _, icon = ItemInfo(id)
    local tex = icon and ("|T" .. icon .. ":18:18:0:0:64:64:5:59:5:59|t ") or ""
    return tex .. (link or name or ("item:" .. id)), link
end

local function Row(i)
    local row = list:GetRow(i)
    row:EnableMouse(true)
    row.left:ClearAllPoints(); row.left:SetPoint("LEFT", 8, 0)
    row.mid:ClearAllPoints(); row.mid:SetPoint("LEFT", 330, 0)
    row:SetScript("OnEnter", nil); row:SetScript("OnLeave", nil); row:SetScript("OnMouseUp", nil)
    return row
end

local function ItemTooltip(row, id)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local ok = pcall(GameTooltip.SetItemByID, GameTooltip, id)
        if not ok then GameTooltip:SetText("item:" .. id) end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
end

local function Header(n, text)
    local row = Row(n)
    row.left:SetText("|cffffd100" .. text .. "|r")
    row.mid:SetText(""); row.right:SetText("")
end

function page:Refresh()
    ph:SetShown((input:GetText() or "") == "" and not input:HasFocus())
    local n = 0
    -- Eigene Wünsche
    local mine = {}
    for id, p in pairs(Mine().i) do mine[#mine + 1] = { id = id, prio = p } end
    table.sort(mine, function(a, b) if a.prio ~= b.prio then return a.prio > b.prio end return a.id < b.id end)
    n = n + 1
    Header(n, (L["Meine Wunschliste (%d)"]):format(#mine))
    if #mine == 0 then
        n = n + 1
        local row = Row(n)
        row.left:SetText("|cff999999" .. L["Noch leer. Item oben einfügen oder /gp wunsch [Item]."] .. "|r")
        row.mid:SetText(""); row.right:SetText("")
    end
    for _, w in ipairs(mine) do
        n = n + 1
        local row = Row(n)
        local label, link = ItemLabel(w.id)
        row.left:SetText("   " .. label)
        local others = 0
        for _, x in ipairs(Wish.Who(w.id)) do if x.name ~= Me() then others = others + 1 end end
        row.mid:SetText(PRIO_COLOR[w.prio] .. PrioName(w.prio) .. "|r"
            .. (others > 0 and ("|cff999999  ·  " .. (L["%d andere wollen es auch"]):format(others) .. "|r") or ""))
        row.right:SetText(L["Klick: Stufe · Rechtsklick: entfernen"])
        ItemTooltip(row, w.id)
        row:SetScript("OnMouseUp", function(_, button)
            if IsModifiedClick("CHATLINK") and link then ChatEdit_InsertLink(link) return end
            if button == "RightButton" then Wish.Set(w.id, 0) else Wish.Cycle(w.id) end
        end)
    end
    -- Was die Gilde sucht
    local guild = Wish.GuildItems()
    n = n + 1
    Header(n, (L["Die Gilde sucht (%d Items)"]):format(#guild))
    for _, x in ipairs(guild) do
        n = n + 1
        local row = Row(n)
        local label, link = ItemLabel(x.id)
        row.left:SetText("   " .. label)
        local names = {}
        for i, name in ipairs(x.names) do
            if i > 3 then names[#names + 1] = "…" break end
            names[#names + 1] = Ambiguate(name, "guild")
        end
        row.mid:SetText(PRIO_COLOR[x.top] .. table.concat(names, ", ") .. "|r")
        row.right:SetText(Mine().i[x.id] and "" or L["Klick: auch wünschen"])
        ItemTooltip(row, x.id)
        row:SetScript("OnMouseUp", function()
            if IsModifiedClick("CHATLINK") and link then ChatEdit_InsertLink(link) return end
            if not Mine().i[x.id] then Wish.Set(x.id, 1) end
        end)
    end
    list:Finish(n)
end

function Wish.Refresh()
    if page:IsVisible() then page:Refresh() end
end

function Wish.Open()
    if not ns.GuildFrame:IsShown() then ns.ToggleUI() end
    if ns.GuildFrame:IsShown() then ns.SelectTab(page.tabId) end
end

input:SetScript("OnTextChanged", function() ph:SetShown((input:GetText() or "") == "" and not input:HasFocus()) end)
input:SetScript("OnEditFocusGained", function() ph:Hide() end)
input:SetScript("OnEditFocusLost", function() ph:SetShown((input:GetText() or "") == "") end)
input:SetScript("OnEnterPressed", function(self)
    local id = ItemID(self:GetText())
    if id then Wish.Set(id, 1); self:SetText("") end
    self:ClearFocus()
end)
input:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

-- Beim Öffnen die Listen der anderen anfragen (höchstens alle 10 Minuten)
local lastAsk = -600
page:HookScript("OnShow", function()
    page:Refresh()
    if GetTime() - lastAsk < 600 then return end
    lastAsk = GetTime()
    ns.Queue("WSQ", nil, "1")
end)
