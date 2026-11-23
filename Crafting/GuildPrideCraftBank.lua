-- GuildPride Handwerk: Bank-Helfer und Twink-Post
--   Bank:       „Mats holen“ holt, was Tracker und Guide (bis zum Ende deines Rangs) noch in den
--               Taschen brauchen. „Mats einlagern“ legt Berufsmaterial in die Bank, das gerade
--               nichts davon braucht. Bewegt werden ganze Stapel (wie Rechtsklick im Bankfach).
--   Briefkasten: „Mats für Twink“ – Twink wählen, Empfänger wird eingetragen und angehängt, was
--               dessen Guide noch braucht (aus deinen Taschen, bis 12 Stapel). Abschicken: du selbst.
-- Schalter: craftBank
local ADDON, ns = ...
local L = ns.L
local Craft, G = ns.Craft, ns.CraftGuides

local B = {}
ns.CraftBank = B

local function Opt() return not (type(GuildPrideDB) == "table" and GuildPrideDB.craftBank == false) end
local C = C_Container or {}
local GetSlots = C.GetContainerNumSlots or GetContainerNumSlots
local GetID = C.GetContainerItemID or GetContainerItemID
local UseItem = C.UseContainerItem or UseContainerItem
local Pickup = C.PickupContainerItem or PickupContainerItem

local function StackCount(bag, slot)
    if C.GetContainerItemInfo then
        local ok, info = pcall(C.GetContainerItemInfo, bag, slot)
        if ok and type(info) == "table" then return tonumber(info.stackCount) or 1 end
    elseif GetContainerItemInfo then
        local _, n = GetContainerItemInfo(bag, slot)
        return tonumber(n) or 1
    end
    return 1
end

local function BagList()
    local out = {}
    for b = 0, (NUM_BAG_SLOTS or 4) do out[#out + 1] = b end
    return out
end
local function BankList()
    local out = { BANK_CONTAINER or -1 }
    for b = (NUM_BAG_SLOTS or 4) + 1, (NUM_BAG_SLOTS or 4) + (NUM_BANKBAGSLOTS or 6) do out[#out + 1] = b end
    return out
end

-- Alle Plätze mit diesem Item: { { bag, slot, count } }
local function Find(bags, id)
    local out = {}
    if not (GetSlots and GetID) then return out end
    for _, b in ipairs(bags) do
        local ok, n = pcall(GetSlots, b)
        for s = 1, (ok and tonumber(n) or 0) do
            local ok2, x = pcall(GetID, b, s)
            if ok2 and x == id then out[#out + 1] = { b, s, StackCount(b, s) } end
        end
    end
    return out
end

---------------------------------------------------------------------
-- Was brauchst du in den Taschen? Tracker + Guide bis zum Rangende
---------------------------------------------------------------------
function B.Wanted()
    local want = {}
    if ns.CraftTrack then
        for id, n in pairs(ns.CraftTrack.Needs()) do want[id] = (want[id] or 0) + n end
    end
    for _, p in ipairs(Craft.MyProfessions()) do
        local target = math.min(300, math.max(p.max or 75, (p.skill or 0) + 1))
        local _, items = Craft.RouteNeeds(p.line, target, p.skill)
        for _, it in ipairs(items) do want[it.id] = math.max(want[it.id] or 0, it.need) end
    end
    return want
end

-- Was fehlt in den Taschen und liegt in der Bank? { [id] = Menge }
function B.ToFetch()
    local out = {}
    for id, n in pairs(B.Wanted()) do
        local bags, bank = Craft.Count(id)
        local m = math.min(n - bags, bank)
        if m > 0 then out[id] = m end
    end
    return out
end

-- Holen: ganze Stapel aus der Bank in die Taschen, bis genug da ist
function B.Fetch()
    if not (UseItem and Craft.bankOpen) then return 0 end
    local moved = 0
    for id, m in pairs(B.ToFetch()) do
        local got = 0
        for _, p in ipairs(Find(BankList(), id)) do
            if got >= m or moved >= 40 then break end
            pcall(UseItem, p[1], p[2])
            got = got + p[3]; moved = moved + 1
        end
    end
    return moved
end

-- Berufsmaterial in den Taschen (Handwerkswaren), das gerade nichts braucht
local function IsTradeGood(id)
    local f = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not f then return false end
    local _, _, _, _, _, classID = f(id)
    return classID == 7    -- Handwerkswaren
end
B.IsTradeGood = IsTradeGood

function B.Deposit()
    if not (UseItem and GetSlots and GetID and Craft.bankOpen) then return 0 end
    local want, moved = B.Wanted(), 0
    for _, b in ipairs(BagList()) do
        local ok, n = pcall(GetSlots, b)
        for s = 1, (ok and tonumber(n) or 0) do
            local ok2, id = pcall(GetID, b, s)
            if ok2 and id and not want[id] and IsTradeGood(id) and moved < 60 then
                pcall(UseItem, b, s)
                moved = moved + 1
            end
        end
    end
    return moved
end

---------------------------------------------------------------------
-- Twink-Post: was braucht ein anderer Charakter für seinen Guide?
---------------------------------------------------------------------
-- { [itemID] = Menge }, die dem Twink bis zum Ende seines Rangs fehlt (abzüglich seines Bestands)
function B.AltNeeds(name)
    local e = Craft.Chars()[name]
    local out = {}
    if type(e) ~= "table" or not e.profs then return out end
    for line, p in pairs(e.profs) do
        local skill = p.skill or 0
        local target = math.min(300, math.max(p.max or 75, skill + 1))
        for _, s in ipairs(G.Steps(line)) do
            if s.spell and s.to > skill and s.from < target then
                local n = G.Remaining(s, skill) or 0
                for _, x in ipairs(Craft.KnownReagents(s.spell) or {}) do
                    out[x[1]] = (out[x[1]] or 0) + x[2] * n
                end
            end
        end
    end
    for id, n in pairs(out) do
        local have = e.items and tonumber(e.items[id]) or 0
        out[id] = n - have > 0 and (n - have) or nil
    end
    return out
end

-- Twinks, denen du gerade etwas schicken kannst: { { name, mail, items = { [id] = Menge } } }
function B.AltTargets()
    local me, out = Craft.Me(), {}
    for name, e in pairs(Craft.Chars()) do
        if name ~= me and type(e) == "table" then
            local send = {}
            for id, n in pairs(B.AltNeeds(name)) do
                local bags = Craft.Count(id)
                if bags > 0 then send[id] = math.min(n, bags) end
            end
            if next(send) then out[#out + 1] = { name = name, mail = e.mailName or (name:match("^(%S+)")), items = send } end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function B.MailTo(target)
    if not (SendMailFrame and Pickup and ClickSendMailItemButton) then return 0 end
    if MailFrameTab2 and not SendMailFrame:IsShown() then MailFrameTab2:Click() end
    if SendMailNameEditBox then SendMailNameEditBox:SetText(target.mail or target.name) end
    local slot, max = 0, ATTACHMENTS_MAX_SEND or 12
    for id, n in pairs(target.items) do
        local got = 0
        for _, p in ipairs(Find(BagList(), id)) do
            if got >= n or slot >= max then break end
            slot = slot + 1
            ClearCursor()
            pcall(Pickup, p[1], p[2])
            pcall(ClickSendMailItemButton, slot)
            got = got + p[3]
        end
    end
    ClearCursor()
    return slot
end

---------------------------------------------------------------------
-- Knöpfe an Bank und Briefkasten
---------------------------------------------------------------------
local function Button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    if ns.SkinButton then ns.SkinButton(b) end
    b:SetScript("OnClick", onClick)
    return b
end

local bankBar, mailBar, picker
local function BuildBank()
    if bankBar then return end
    bankBar = CreateFrame("Frame", "GuildPrideCraftBankBar", UIParent, "BackdropTemplate")
    bankBar:SetSize(250, 62)
    bankBar:SetFrameStrata("HIGH")
    if ns.SkinDialog then ns.SkinDialog(bankBar) end
    local t = bankBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t:SetPoint("TOPLEFT", 10, -8); t:SetText(L["GuildPride Handwerk"])
    local get = Button(bankBar, L["Mats holen"], 112, function()
        local n = B.Fetch()
        ns.Print(n > 0 and (L["%d Stapel aus der Bank geholt."]):format(n) or L["In der Bank liegt nichts, was du brauchst."])
    end)
    get:SetPoint("BOTTOMLEFT", 10, 10)
    get:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Mats holen"], 1, 0.82, 0)
        GameTooltip:AddLine(L["Holt aus der Bank, was dein Tracker und dein Guide bis zum Ende deines Rangs noch brauchen."], 1, 1, 1, true)
        local n = 0
        for id, m in pairs(B.ToFetch()) do
            n = n + 1
            if n <= 10 then GameTooltip:AddDoubleLine(Craft.ItemName(id), m, 0.8, 0.8, 0.8, 1, 1, 1) end
        end
        GameTooltip:Show()
    end)
    get:SetScript("OnLeave", GameTooltip_Hide)
    local put = Button(bankBar, L["Mats einlagern"], 112, function()
        local n = B.Deposit()
        ns.Print(n > 0 and (L["%d Stapel in die Bank gelegt."]):format(n) or L["Nichts zum Einlagern."])
    end)
    put:SetPoint("LEFT", get, "RIGHT", 6, 0)
    put:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(L["Mats einlagern"], 1, 0.82, 0)
        GameTooltip:AddLine(L["Legt Handwerkswaren aus deinen Taschen in die Bank – außer dem, was Tracker oder Guide gerade brauchen."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    put:SetScript("OnLeave", GameTooltip_Hide)
    bankBar:Hide()
end

local function PlaceBank()
    bankBar:ClearAllPoints()
    if BankFrame and BankFrame:IsShown() then bankBar:SetPoint("TOPLEFT", BankFrame, "TOPRIGHT", 4, 0)
    else bankBar:SetPoint("TOP", UIParent, "TOP", 0, -120) end
end

local function ShowPicker(anchor)
    local list = B.AltTargets()
    if #list == 0 then ns.Print(L["Keiner deiner Twinks braucht gerade etwas aus deinen Taschen."]); return end
    if not picker then
        picker = CreateFrame("Frame", "GuildPrideCraftMailPicker", UIParent, "BackdropTemplate")
        picker:SetFrameStrata("DIALOG")
        if ns.SkinDialog then ns.SkinDialog(picker) end
        picker.buttons = {}
        tinsert(UISpecialFrames, "GuildPrideCraftMailPicker")
    end
    for _, b in ipairs(picker.buttons) do b:Hide() end
    for i, tgt in ipairs(list) do
        if i > 8 then break end
        local b = picker.buttons[i] or Button(picker, "", 200, nil)
        picker.buttons[i] = b
        local n = 0
        for _ in pairs(tgt.items) do n = n + 1 end
        b:SetText(("%s (%d)"):format(tgt.name, n))
        b:SetPoint("TOPLEFT", 10, -10 - (i - 1) * 24)
        b:SetScript("OnClick", function()
            picker:Hide()
            local k = B.MailTo(tgt)
            ns.Print((L["%d Stapel für %s angehängt – prüfen und abschicken."]):format(k, tgt.name))
        end)
        b:Show()
    end
    picker:SetSize(220, 20 + math.min(8, #list) * 24)
    picker:ClearAllPoints()
    picker:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    picker:Show()
end

local function BuildMail()
    if mailBar or not MailFrame then return end
    mailBar = Button(MailFrame, L["Mats für Twink"], 130, function(self) ShowPicker(self) end)
    mailBar:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 4, -30)
    mailBar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Mats für Twink"], 1, 0.82, 0)
        GameTooltip:AddLine(L["Hängt an, was der Guide deines Twinks noch braucht und du in den Taschen hast. Abschicken musst du selbst."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    mailBar:SetScript("OnLeave", GameTooltip_Hide)
end

local ev = CreateFrame("Frame")
ns.RegisterEvents(ev, "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "MAIL_SHOW", "MAIL_CLOSED")
ev:SetScript("OnEvent", function(_, event)
    if event == "BANKFRAME_OPENED" then
        if not Opt() then return end
        BuildBank()
        C_Timer.After(0.1, function() PlaceBank(); bankBar:Show() end)
    elseif event == "BANKFRAME_CLOSED" then
        if bankBar then bankBar:Hide() end
    elseif event == "MAIL_SHOW" then
        BuildMail()
        if mailBar then mailBar:SetShown(Opt()) end
    elseif event == "MAIL_CLOSED" then
        if picker then picker:Hide() end
    end
end)
