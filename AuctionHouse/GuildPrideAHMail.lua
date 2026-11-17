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
local LABEL = { expired = L["Abgelaufene"], gold = L["Gold"], won = L["Gekauftes"], other = L["Andere Post"],
                all = L["Alles"] }
AH.MAIL_CATS, AH.MAIL_LABEL = CATS, LABEL
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
        if cat and (run.cat == "all" or cat == run.cat) and not run.skip[key] then
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

-- Alle Briefe für die Anzeige: { index, sender, subject, money, cod, items, days, icon, cat }
function AH.MailList()
    local out = {}
    for i = 1, NumMails() do
        local icon, _, sender, subject, money, cod, days, items = GetInboxHeaderInfo(i)
        if sender ~= nil or subject ~= nil then
            out[#out + 1] = { index = i, sender = sender, subject = subject, money = tonumber(money) or 0,
                              cod = tonumber(cod) or 0, items = tonumber(items) or 0, days = tonumber(days),
                              icon = icon, cat = (AH.MailCategory(i)) }
        end
    end
    return out
end

-- Einen Brief abholen (Items und Gold); Nachnahme nie
function AH.CollectOne(i)
    local cat, _, items = AH.MailCategory(i)
    if not cat or run then return false end
    if items > 0 then
        if FreeSlots() < 1 then AH.Print(L["Taschen voll – angehalten."]); return false end
        AutoLootMailItem(i)
    else
        TakeInboxMoney(i)
    end
    if UpdateBar then UpdateBar() end
    return true
end

---------------------------------------------------------------------
-- Leiste über dem Postfenster
---------------------------------------------------------------------
local bar

UpdateBar = function()
    if AH.onMailChanged then AH.onMailChanged() end   -- GuildPride-Briefkasten-Fenster (GuildPrideAHMailUI.lua)
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

---------------------------------------------------------------------
-- Twinks als Empfänger: Knopf neben dem Empfänger-Feld beim Schreiben.
-- Bekannt sind alle Charaktere, mit denen du dich mit GuildPride eingeloggt hast
-- (für den ganzen Account, je Fraktion), dazu deine per Ausweis erkannten Twinks in der Gilde.
-- GuildPrideDB.ahChars = { [Fraktion] = { [Anzeigename] = { game = Name fürs Spiel, class } } }
---------------------------------------------------------------------
local function Faction()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return type(f) == "string" and f or "N"
end

local function CharStore()
    if type(GuildPrideDB) ~= "table" then GuildPrideDB = {} end
    if type(GuildPrideDB.ahChars) ~= "table" then GuildPrideDB.ahChars = {} end
    if type(GuildPrideDB.ahCharsHidden) ~= "table" then GuildPrideDB.ahCharsHidden = {} end
    local f = Faction()
    if type(GuildPrideDB.ahChars[f]) ~= "table" then GuildPrideDB.ahChars[f] = {} end
    return GuildPrideDB.ahChars[f], GuildPrideDB.ahCharsHidden
end

-- Den gerade gespielten Charakter merken (beim Einloggen)
function AH.RememberChar()
    local me = GP.Me and GP.Me()
    if not me then return end
    local name, surname
    if UnitFullName then name, surname = UnitFullName("player") end
    local game = name or me
    if GP.IS_FOREVER and type(surname) == "string" and surname ~= "" then game = game .. "-" .. surname end
    local class = UnitClass and select(2, UnitClass("player"))
    local store, hiddenChars = CharStore()
    store[me] = { game = game, class = type(class) == "string" and class or nil }
    hiddenChars[me] = nil
end

-- Deine anderen Charaktere (ohne den aktuellen), sortiert: { show, game, class }
function AH.MyChars()
    local store, hiddenChars = CharStore()
    local me = GP.Me and GP.Me()
    local out, seen = {}, { [me or ""] = true }
    for show, e in pairs(store) do
        if not seen[show] and not hiddenChars[show] and type(e) == "table" then
            seen[show] = true
            out[#out + 1] = { show = show, game = e.game or show, class = e.class }
        end
    end
    if GP.IsMyChar and GetNumGuildMembers and IsInGuild and IsInGuild() then
        for i = 1, tonumber((GetNumGuildMembers())) or 0 do
            local raw, _, _, _, _, _, _, _, _, _, class = GetGuildRosterInfo(i)
            local show = type(raw) == "string" and (GP.Normalize and GP.Normalize(raw) or raw)
            if show and not seen[show] and not hiddenChars[show] and GP.IsMyChar(show) then
                seen[show] = true
                out[#out + 1] = { show = show, game = raw, class = type(class) == "string" and class or nil }
            end
        end
    end
    table.sort(out, function(a, b) return a.show < b.show end)
    return out
end

function AH.ForgetChar(show)
    local store, hiddenChars = CharStore()
    store[show] = nil
    hiddenChars[show] = true
end

local twinkBtn, twinkMenu
local MAX_TWINKS = 20

local function ShowTwinks()
    local chars = AH.MyChars()
    local m = twinkMenu
    for i, b in ipairs(m.buttons) do
        local c = chars[i]
        b.char = c
        if c then
            local col = RAID_CLASS_COLORS and c.class and RAID_CLASS_COLORS[c.class]
            local cs = type(col) == "table" and col.colorStr
            b.text:SetText(type(cs) == "string" and ("|c" .. cs .. c.show .. "|r") or c.show)
            b:Show()
        else b:Hide() end
    end
    local n = math.min(#chars, MAX_TWINKS)
    m.empty:SetShown(n == 0)
    m:SetHeight(n == 0 and 46 or (12 + n * 18))
    m:Show()
end

local function BuildTwinks()
    if twinkBtn or not SendMailNameEditBox then return end
    twinkBtn = CreateFrame("Button", "GuildPrideTwinkButton", SendMailNameEditBox, "UIPanelButtonTemplate")
    twinkBtn:SetSize(70, 20); twinkBtn:SetPoint("LEFT", SendMailNameEditBox, "RIGHT", 6, 0)
    twinkBtn:SetText(L["Twinks"])
    if GP.SkinButton then GP.SkinButton(twinkBtn) end
    local m = CreateFrame("Frame", "GuildPrideTwinkMenu", twinkBtn, "BackdropTemplate")
    m:SetWidth(190); m:SetPoint("TOPLEFT", twinkBtn, "BOTTOMLEFT", 0, -2)
    m:SetFrameStrata("DIALOG")
    m:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    m:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
    m:Hide()
    m.empty = m:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    m.empty:SetPoint("TOPLEFT", 8, -8); m.empty:SetPoint("RIGHT", -8, 0)
    m.empty:SetText(L["Noch keine Twinks bekannt – logge dich einmal mit jedem Charakter ein."])
    m.buttons = {}
    for i = 1, MAX_TWINKS do
        local b = CreateFrame("Button", nil, m)
        b:SetSize(176, 18); b:SetPoint("TOPLEFT", 7, -6 - (i - 1) * 18)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("LEFT", 4, 0); b.text:SetJustifyH("LEFT")
        b:SetScript("OnClick", function(_, mouse)
            if not b.char then return end
            if mouse == "RightButton" then
                AH.ForgetChar(b.char.show)
                ShowTwinks()
            else
                SendMailNameEditBox:SetText(b.char.game)
                m:Hide()
            end
        end)
        b:SetScript("OnEnter", function()
            GameTooltip:SetOwner(b, "ANCHOR_RIGHT")
            GameTooltip:SetText(b.char and b.char.show or "")
            GameTooltip:AddLine(L["Linksklick: als Empfänger eintragen · Rechtsklick: aus der Liste entfernen"], 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        m.buttons[i] = b
    end
    twinkMenu = m
    twinkBtn:SetScript("OnClick", function() if m:IsShown() then m:Hide() else ShowTwinks() end end)
    twinkBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(twinkBtn, "ANCHOR_TOP")
        GameTooltip:SetText(L["An Twinks schicken"])
        GameTooltip:AddLine(L["Deine anderen Charaktere als Empfänger wählen."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    twinkBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function AH._TwinkButton() return twinkBtn end   -- für Tests
function AH._TwinkMenu() return twinkMenu end

AH.Listen("PLAYER_LOGIN", function() AH.RememberChar() end)
AH.Listen("MAIL_SHOW", BuildTwinks)
AH.Listen("MAIL_CLOSED", function() if twinkMenu then twinkMenu:Hide() end end)

AH.Listen("MAIL_SHOW", function() BuildBar(); bar:Show(); UpdateBar() end)
AH.Listen("MAIL_INBOX_UPDATE", function() if bar and bar:IsShown() then UpdateBar() end end)
AH.Listen("MAIL_CLOSED", function() if run then Finish(L["Briefkasten geschlossen."]) end end)
