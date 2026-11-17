-- GuildPride Auktionshaus: Briefkasten – Post nach Sorte abholen
-- Über dem Postfenster eine Leiste mit Knöpfen (mit Anzahl):
--   Abgelaufene  – abgelaufene und abgebrochene Auktionen (Items zurück)
--   Gold         – verkaufte Auktionen und Überboten-Rückzahlungen
--   Gekauftes    – gewonnene Auktionen
--   Andere Post  – alles, was nicht vom Auktionshaus kommt (z. B. vom Twink)
-- Abgeholt wird Brief für Brief mit kurzer Pause (wie Blizzards „Alle öffnen“).
-- Nachnahme-Post wird nie angefasst; bei vollen Taschen hält das Abholen an.
local ADDON, GP = ...
GP.AH = GP.AH or {}
local AH = GP.AH
local L = GP.L or setmetatable({}, { __index = function(_, k) return k end })

local STEP = 0.4                 -- Sekunden zwischen zwei Briefen
local MAX_TRIES = 3              -- so oft derselbe Brief, dann überspringen (z. B. Einzigartig-Item)
local CATS = { "expired", "gold", "won", "other" }
local LABEL = { expired = L["Abgelaufene"], gold = L["Gold"], won = L["Gekauftes"], other = L["Andere Post"] }
local TIP = {
    expired = L["Holt nur abgelaufene und abgebrochene Auktionen ab (die Items kommen zurück in die Taschen)."],
    gold = L["Holt nur das Gold aus verkauften Auktionen und Überboten-Rückzahlungen ab."],
    won = L["Holt nur gewonnene Auktionen ab (gekaufte Items)."],
    other = L["Holt alle Post ab, die nicht vom Auktionshaus kommt – z. B. von deinen Twinks. Nachnahme bleibt liegen."],
}

-- Betreff-Vorlagen des Spiels („Auktion abgelaufen: %s“) als Suchmuster
local function Pattern(fmt)
    if type(fmt) ~= "string" or fmt == "" then return nil end
    local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%%%d?%$?s", ".+"):gsub("%%%%%d?%$?d", "%%d+")
    return "^" .. p
end

local function Patterns()
    return {
        { "expired", Pattern(AUCTION_EXPIRED_MAIL_SUBJECT) }, { "expired", Pattern(AUCTION_REMOVED_MAIL_SUBJECT) },
        { "gold", Pattern(AUCTION_SOLD_MAIL_SUBJECT) }, { "gold", Pattern(AUCTION_OUTBID_MAIL_SUBJECT) },
        { "won", Pattern(AUCTION_WON_MAIL_SUBJECT) },
    }
end

-- Sorte eines Briefs: Kategorie, Gold, Itemzahl (nil = nichts abzuholen oder Nachnahme)
function AH.MailCategory(i)
    if not GetInboxHeaderInfo then return nil end
    local _, _, sender, subject, money, cod, _, items = GetInboxHeaderInfo(i)
    if sender == nil and subject == nil then return nil end
    money, cod, items = tonumber(money) or 0, tonumber(cod) or 0, tonumber(items) or 0
    if cod > 0 or (money <= 0 and items <= 0) then return nil end
    if type(subject) == "string" then
        for _, p in ipairs(Patterns()) do
            if p[2] and subject:match(p[2]) then return p[1], money, items end
        end
    end
    -- Rechnung des Auktionshauses (falls der Betreff anders lautet)
    if type(GetInboxInvoiceInfo) == "function" then
        local ok, kind = pcall(GetInboxInvoiceInfo, i)
        if ok and kind == "seller" then return "gold", money, items end
        if ok and kind == "buyer" then return "won", money, items end
    end
    return "other", money, items
end

local function NumMails()
    if not GetInboxNumItems then return 0 end
    return tonumber((GetInboxNumItems())) or 0
end

function AH.MailCounts()
    local c = { expired = 0, gold = 0, won = 0, other = 0, goldSum = 0 }
    for i = 1, NumMails() do
        local cat, money = AH.MailCategory(i)
        if cat then
            c[cat] = c[cat] + 1
            if cat == "gold" then c.goldSum = c.goldSum + money end
        end
    end
    return c
end

local function FreeSlots()
    local f = C_Container and C_Container.GetContainerNumFreeSlots
    if not f then return 99 end
    local n = 0
    for bag = 0, tonumber(NUM_BAG_SLOTS) or 4 do
        local ok, v = pcall(f, bag)
        n = n + (ok and tonumber(v) or 0)
    end
    return n
end

---------------------------------------------------------------------
-- Abholen
---------------------------------------------------------------------
local run          -- { cat, money, mails, tries, last, skip }
local UpdateBar

local function Finish(reason)
    local r = run
    run = nil
    if not r then return end
    AH.Print((L["Briefkasten (%s): %d Briefe abgeholt, %s."]):format(LABEL[r.cat], r.mails, AH.Money(r.money))
        .. (reason and (" " .. reason) or ""))
    if UpdateBar then UpdateBar() end
end

local function Step()
    if not run then return end
    for i = NumMails(), 1, -1 do        -- von hinten: die Nummern davor verschieben sich nicht
        local cat, money, items = AH.MailCategory(i)
        local _, _, sender, subject = GetInboxHeaderInfo(i)
        local key = tostring(sender) .. "\031" .. tostring(subject) .. "\031" .. tostring(money) .. "\031" .. tostring(items)
        if cat == run.cat and not run.skip[key] then
            if run.last == key then run.tries = run.tries + 1 else run.last, run.tries = key, 1 end
            if run.tries > MAX_TRIES then
                run.skip[key] = true          -- klappt nicht (z. B. Einzigartig-Item): liegen lassen
            else
                if items > 0 then
                    if FreeSlots() < 1 then return Finish(L["Taschen voll – angehalten."]) end
                    AutoLootMailItem(i)
                else
                    TakeInboxMoney(i)
                end
                if run.tries == 1 then run.money, run.mails = run.money + money, run.mails + 1 end
                if UpdateBar then UpdateBar() end
                if C_Timer and C_Timer.After then C_Timer.After(STEP, Step) end
                return
            end
        end
    end
    Finish()
end

function AH.CollectMail(cat)
    if not LABEL[cat] or not GetInboxNumItems or run then return false end
    run = { cat = cat, money = 0, mails = 0, tries = 0, skip = {} }
    Step()
    return true
end

function AH.StopMail() if run then Finish(L["Angehalten."]) end end
function AH.MailRunning() return run ~= nil end

---------------------------------------------------------------------
-- Leiste über dem Postfenster
---------------------------------------------------------------------
local bar

UpdateBar = function()
    if not bar then return end
    local c = AH.MailCounts()
    for _, cat in ipairs(CATS) do
        local b = bar.buttons[cat]
        b:SetText(("%s (%d)"):format(LABEL[cat], c[cat]))
        b:SetEnabled(c[cat] > 0 and not run)
    end
    bar.goldSum = c.goldSum
    bar.stop:SetShown(run ~= nil)
end

local function BuildBar()
    if bar then return end
    local parent = MailFrame or UIParent
    bar = CreateFrame("Frame", "GuildPrideMailBar", parent, "BackdropTemplate")
    bar:SetSize(560, 30)
    bar:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", 0, 4)
    bar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    bar:SetBackdropColor(0.06, 0.06, 0.08, 0.92)
    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("LEFT", 10, 0); title:SetText(L["GuildPride-Post:"])
    bar.buttons = {}
    local prev = title
    for _, cat in ipairs(CATS) do
        local b = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        b:SetSize(cat == "other" and 120 or 104, 22)
        b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
        if GP.SkinButton then GP.SkinButton(b) end
        b:SetScript("OnClick", function() AH.CollectMail(cat); UpdateBar() end)
        b:SetScript("OnEnter", function()
            GameTooltip:SetOwner(b, "ANCHOR_TOP")
            GameTooltip:SetText(LABEL[cat])
            GameTooltip:AddLine(TIP[cat], 1, 1, 1, true)
            if cat == "gold" and (bar.goldSum or 0) > 0 then
                GameTooltip:AddLine((L["Zusammen: %s"]):format(AH.Money(bar.goldSum)), 1, 0.82, 0)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        bar.buttons[cat] = b
        prev = b
    end
    bar.stop = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    bar.stop:SetSize(70, 22); bar.stop:SetPoint("LEFT", prev, "RIGHT", 6, 0)
    bar.stop:SetText(L["Stopp"])
    if GP.SkinButton then GP.SkinButton(bar.stop) end
    bar.stop:SetScript("OnClick", function() AH.StopMail() end)
    bar.stop:Hide()
end

function AH._MailBar() return bar end   -- für Tests

AH.Listen("MAIL_SHOW", function() BuildBar(); bar:Show(); UpdateBar() end)
AH.Listen("MAIL_INBOX_UPDATE", function() if bar and bar:IsShown() then UpdateBar() end end)
AH.Listen("MAIL_CLOSED", function() if run then Finish(L["Briefkasten geschlossen."]) end end)
