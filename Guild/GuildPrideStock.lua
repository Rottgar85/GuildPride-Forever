-- GuildPride: Materialliste der Gilde
-- Offiziere legen fest, was gebraucht wird (Gegenstand und Menge), jedes Mitglied sagt zu, wie
-- viel es beisteuert. Zusagen gelten nur für sich selbst und werden nie weitergeleitet angenommen.
--   MGO  id · ver · autor · gelöscht (0/1) · itemID · menge    (nur Offiziere)
--   MGC  id · ver · anzahl                                      (eigene Zusage)
--   MGQ  stand   Anfrage nach dem Einloggen (Ziele wie bei den Boss-Notizen, eigene Zusagen immer)
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP

local M = {}
ns.Stock = M
local MAX_GOALS, MAX_QTY = 30, 99999

local function DB() return ns.GuildTable("stock") end        -- [id] = { id, ver, author, deleted, item, qty }
local function Pledges() return ns.GuildTable("pledges") end -- [id] = { [Name] = { n, ver } }
local function Me() return ns.Me() end
local function Now() return GetServerTime() end
local function CanManage() return CanEditMOTD and CanEditMOTD() and true or false end
local function Clean(s, max) return (tostring(s or ""):gsub("[%c|]", "")):sub(1, max) end
local function Changed() if M.Refresh then M.Refresh() end end

local function Count()
    local n = 0
    for _, g in pairs(DB()) do if not g.deleted then n = n + 1 end end
    return n
end

-- Ganze Zahl im Bereich oder nil (anders als ns.Num wird nichts zurechtgebogen)
local function Int(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= v or v % 1 ~= 0 or v < lo or v > hi then return nil end
    return v
end

---------------------------------------------------------------------
-- Senden / Anwenden
---------------------------------------------------------------------
local function SendGoal(g, target) ns.Queue("MGO", target, g.id, g.ver, g.author, g.deleted and 1 or 0, g.item, g.qty) end
local function SendPledge(id, target)
    local p = Pledges()[id] and Pledges()[id][Me()]
    if p then ns.Queue("MGC", target, id, p.ver, p.n) end
end

local function Apply(id, ver, author, deleted, item, qty)
    local g = DB()[id]
    if g and ver <= g.ver then return false end
    if not g and (deleted or Count() >= MAX_GOALS) then return false end
    DB()[id] = { id = id, ver = ver, author = author, deleted = deleted or nil, item = item, qty = qty }
    if deleted then Pledges()[id] = nil end
    Changed()
    return true
end
local function ApplyPledge(id, name, ver, n)
    local g = DB()[id]
    if not g or g.deleted then return false end
    local t = Pledges()[id]
    if type(t) ~= "table" then t = {}; Pledges()[id] = t end
    if t[name] and ver <= t[name].ver then return false end
    t[name] = { n = n, ver = ver }
    Changed()
    return true
end

ns.On("MGO", function(payload, sender)
    if sender == Me() then return end
    ns.SyncHeard("MGO", sender)
    local a = { strsplit(SEP, payload) }
    local id, ver, author = Clean(a[1], 80), ns.Stamp(a[2]), Clean(a[3], 60)
    local item, qty = Int(a[5], 1, 9999999), Int(a[6], 1, MAX_QTY)
    if ver == 0 or not item or not qty or id:match("^(.+)%-%d+%-%d+$") ~= author or not ns.IsOfficerName(author) then return end
    if not ns.IsOfficerName(sender) and not ns.Confirmed("MGO\030" .. payload, sender) then return end
    Apply(id, ver, author, a[4] == "1", item, qty)
end)
ns.On("MGC", function(payload, sender)
    if sender == Me() or not ns.IsGuildMember(sender) then return end
    local id, ver, n = strsplit(SEP, payload)
    ver, n = ns.Stamp(ver), Int(n, 0, MAX_QTY)
    if ver == 0 or not n then return end
    ApplyPledge(Clean(id, 80), sender, ver, n)
end)
ns.On("MGQ", function(payload, sender)
    if sender == Me() then return end
    if payload ~= ns.SyncHash(DB()) then
        ns.SyncAnswer("MGO", function() for _, g in pairs(DB()) do SendGoal(g, sender) end end)
    end
    -- eigene Zusagen nach den Zielen, sonst kennt der Fragende die Ziele noch nicht
    C_Timer.After(20, function()
        ns.AnswerSoon("MGC", function()
            for id, g in pairs(DB()) do if not g.deleted then SendPledge(id, "@CHANNEL") end end
        end)
    end)
end)

---------------------------------------------------------------------
-- Aktionen
---------------------------------------------------------------------
function M.Add(item, qty)
    item, qty = Int(item, 1, 9999999), Int(qty, 1, MAX_QTY)
    if not CanManage() or not item or not qty then return false end
    local id = Me() .. "-" .. Now() .. "-" .. math.random(1000, 9999)
    if not Apply(id, Now(), Me(), false, item, qty) then return false end
    SendGoal(DB()[id])
    return true
end
function M.Remove(id)
    local g = DB()[id]
    if not CanManage() or not g then return false end
    Apply(id, math.max(Now(), g.ver + 1), g.author, true, g.item, g.qty)
    SendGoal(DB()[id])
    return true
end
function M.Pledge(id, n)
    n = Int(n, 0, MAX_QTY)
    local old = Pledges()[id] and Pledges()[id][Me()]
    if not n or not ApplyPledge(id, Me(), math.max(Now(), ((old and old.ver) or 0) + 1), n) then return false end
    SendPledge(id)
    return true
end

-- Bestand der Gildenbank (nur auf diesem PC, vom letzten Öffnen): { t, items = { [id] = Anzahl } }
function M.SetBank(items)
    local b = ns.GuildTable("bankStock")
    b.t, b.items = Now(), items
    Changed()
end
local function InBank(id)
    local b = ns.GuildTable("bankStock")
    return type(b.items) == "table" and b.items[id] or 0
end
function M.ReadBank()
    if not (GetNumGuildBankTabs and GetGuildBankItemLink and GetGuildBankItemInfo) then return false end
    local items, any = {}, false
    for tab = 1, GetNumGuildBankTabs() or 0 do
        for slot = 1, 98 do
            local link = GetGuildBankItemLink(tab, slot)
            local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
            if id then
                local _, count = GetGuildBankItemInfo(tab, slot)
                items[id] = (items[id] or 0) + (tonumber(count) or 1)
                any = true
            end
        end
    end
    -- leere Antwort (Fächer noch nicht geladen) überschreibt nichts
    if any then M.SetBank(items) end
    return any
end

-- Item über Link, ID oder Namen (Taschen, Rezepte, Item-Cache); Teil des Namens reicht
function M.Resolve(text)
    text = strtrim(tostring(text or ""))
    if text == "" then return nil end
    local id = tonumber(text:match("item:(%d+)")) or tonumber(text:match("^(%d+)$"))
    if id then return id end
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local _, link = f(text)
    id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
    if id then return id end
    local q, best = text:lower(), nil
    local seen = {}
    local function Try(x)
        x = tonumber(x)
        if not x or seen[x] then return end
        seen[x] = true
        local name = f(x)
        if type(name) ~= "string" then return end
        name = name:lower()
        if name == q then best = x; return true end
        if not best and name:find(q, 1, true) then best = x end
    end
    local C = C_Container
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local n = C and C.GetContainerNumSlots and tonumber(C.GetContainerNumSlots(bag)) or 0
        for slot = 1, n do
            local info = C.GetContainerItemInfo(bag, slot)
            if type(info) == "table" and Try(info.itemID) then return best end
        end
    end
    for made, e in pairs(type(GuildPrideDB.ahCraft) == "table" and GuildPrideDB.ahCraft or {}) do
        if Try(made) then return best end
        for _, r in ipairs(type(e) == "table" and e.r or {}) do if Try(r[1]) then return best end end
    end
    return best
end

-- Offene Ziele: was noch fehlt zuerst
function M.List()
    local list = {}
    for id, g in pairs(DB()) do
        if not g.deleted then
            local sum, who = 0, {}
            for name, p in pairs(Pledges()[id] or {}) do
                if p.n > 0 and (name == Me() or ns.IsGuildMember(name)) then
                    sum = sum + p.n
                    who[#who + 1] = { name = name, n = p.n }
                end
            end
            table.sort(who, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
            local mine = Pledges()[id] and Pledges()[id][Me()]
            local bank = InBank(g.item)
            list[#list + 1] = { id = id, item = g.item, qty = g.qty, sum = sum, who = who, mine = mine and mine.n or 0,
                bank = bank, open = math.max(0, g.qty - sum - bank) }
        end
    end
    table.sort(list, function(a, b)
        local da, db = a.open == 0, b.open == 0
        if da ~= db then return db end
        return a.id < b.id
    end)
    return list
end

---------------------------------------------------------------------
-- Fenster (/gp material)
---------------------------------------------------------------------
local win
local function ItemName(id)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name = f and f(id)
    return type(name) == "string" and name or (L["Gegenstand %d"]):format(id)
end
local function InBags(id)
    local f = (C_Item and C_Item.GetItemCount) or GetItemCount
    local n = f and f(id)
    return type(n) == "number" and n or 0
end

function M.Refresh()
    if not win or not win:IsShown() then return end
    win.list = M.List()
    local lines = {}
    for _, g in ipairs(win.list) do
        local names = {}
        for i, w in ipairs(g.who) do
            if i > 4 then names[#names + 1] = "…"; break end
            names[#names + 1] = Ambiguate(w.name, "guild") .. " " .. w.n
        end
        lines[#lines + 1] = ("%s%s|r  %s%d/%d|r  |cff999999%s|r"):format(g.id == win.selected and "|cffffd100" or "|cffe6e0da",
            ItemName(g.item), g.open == 0 and "|cff40ff40" or "|cffff8060", g.sum + g.bank, g.qty,
            (g.bank > 0 and ((L["Bank %d"]):format(g.bank) .. (#names > 0 and ", " or "")) or "") .. table.concat(names, ", "))
    end
    win:SetLines(lines)
    for _, f in ipairs(win.officer) do f:SetShown(CanManage()) end
end
local function Selected()
    for _, g in ipairs(win.list or {}) do if g.id == win.selected then return g end end
end

local function Build()
    win = ns.ListWindow({ name = "GuildPrideStock", title = L["Materialliste der Gilde"], rows = 12, width = 560, extra = 84,
        sub = L["Zeile wählen, unten zusagen, wie viel du beisteuerst. Rechtsklick: Rest in deinen Tracker."],
        empty = L["Gerade wird nichts gesammelt."] })
    win.officer = {}
    for i, row in ipairs(win.rows) do
        row:EnableMouse(true)
        row:SetScript("OnMouseUp", function(_, button)
            local g = win.list and win.list[i + win.offset]
            if not g then return end
            if button == "RightButton" then
                local T = ns.CraftTrack or (ns.Craft and ns.Craft.Track)
                if T and T.AddItem and g.open > 0 then
                    T.AddItem(g.item, g.open)
                    ns.Print((L["%s ist jetzt in deinem Tracker."]):format(ItemName(g.item)))
                end
                return
            end
            win.selected = g.id
            win.amount:SetText(tostring(g.mine > 0 and g.mine or math.min(InBags(g.item), g.qty)))
            M.Refresh()
        end)
    end
    local function Button(label, w, x, y, fn, officer)
        local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        if ns.SkinButton then ns.SkinButton(b) end
        b:SetSize(w, 22); b:SetPoint("BOTTOMLEFT", x, y); b:SetText(label)
        b:SetScript("OnClick", fn)
        if officer then win.officer[#win.officer + 1] = b end
    end
    local function Box(w, x, y, max, hintText, officer)
        local e = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
        e:SetSize(w, 22); e:SetPoint("BOTTOMLEFT", x, y); e:SetAutoFocus(false); e:SetMaxLetters(max)
        if ns.SkinEditBox then ns.SkinEditBox(e) end
        local hint = e:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
        hint:SetPoint("LEFT", 2, 0); hint:SetText(hintText)
        e:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)
        e:SetScript("OnEscapePressed", e.ClearFocus)
        if officer then win.officer[#win.officer + 1] = e end
        return e
    end
    win.amount = Box(70, 20, 44, 5, L["Menge"])
    Button(L["Ich steuere bei"], 140, 98, 44, function()
        local g = Selected()
        if not g or not M.Pledge(g.id, win.amount:GetText()) then ns.Print(L["Bitte eine Zeile wählen und eine Menge eintragen (0 = zurückziehen)."]) end
    end)
    win.item = Box(230, 20, 14, 200, L["Neues Ziel: Name, Item-Link oder ID"], true)
    win.qty = Box(60, 262, 14, 5, L["Menge"], true)
    Button(L["Anlegen"], 90, 330, 14, function()
        local id = M.Resolve(win.item:GetText())
        if M.Add(id, win.qty:GetText()) then win.item:SetText(""); win.qty:SetText("")
        else ns.Print(L["Gegenstand nicht gefunden oder Menge fehlt. Am sichersten: Umschalt-Klick auf das Item."]) end
    end, true)
    Button(L["Löschen"], 90, 426, 14, function() local g = Selected(); if g then M.Remove(g.id) end end, true)
    win:SetScript("OnShow", function() win.offset = 0; M.Refresh() end)
end

-- Umschalt-Klick auf ein Item schreibt den Link ins Feld
if hooksecurefunc and ChatEdit_InsertLink then
    hooksecurefunc("ChatEdit_InsertLink", function(link)
        if win and win:IsShown() and win.item:IsVisible() and win.item:HasFocus() and type(link) == "string" then win.item:SetText(link) end
    end)
end

function M.Open()
    if not win then Build() end
    win:SetShown(not win:IsShown())
end

local ev, asked = CreateFrame("Frame"), false
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ns.RegisterEvents(ev, "GUILDBANKBAGSLOTS_CHANGED")
ev:SetScript("OnEvent", function(_, event)
    if event == "GUILDBANKBAGSLOTS_CHANGED" then ns.Try(M.ReadBank) return end
    if asked then return end
    asked = true
    C_Timer.After(48 + math.random() * 30, function()
        if not IsInGuild() then return end
        ns.PruneDeleted(DB())
        ns.Queue("MGQ", nil, ns.SyncHash(DB()))
    end)
end)

ns.Command({ "material", "mats" }, function() M.Open() end)
