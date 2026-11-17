-- GuildPride Briefkasten: eigenes Fenster „GuildPride – Briefkasten“ statt Blizzards Postfenster
-- (wie beim Auktionshaus): Liste aller Briefe mit Sorte, Abholen je Brief, Sorten-Knöpfe,
-- „Alles abholen“. Knopf „Blizzard-Briefkasten“ schaltet zurück (z. B. zum Schreiben),
-- Knopf „GuildPride“ in Blizzards Fenster wieder hierher; die Wahl wird gemerkt.
-- Blizzards Fenster wird nur unsichtbar gemacht (Schließen würde den Briefkasten schließen).
-- Aus (Einstellungen › „GuildPride-Briefkasten nutzen“): nur Blizzards Fenster mit der Sorten-Leiste.
local ADDON, GP = ...
GP.AH = GP.AH or {}
local AH = GP.AH
local L = GP.L or setmetatable({}, { __index = function(_, k) return k end })

local WIN_W, WIN_H = 780, 500
local ROWS, ROW_H = 16, 22
local CAT_COLOR = { expired = "|cff66ccff", gold = "|cffffd100", won = "|cff40ff40", other = "|cffd8d0c0" }

local panel, button
local list, offset = {}, 0
local hidden, saved, switching = false, nil, false

local function Skin(b) if GP.SkinButton then GP.SkinButton(b) end return b end
local function Button(parent, text, w)
    local b = Skin(CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"))
    b:SetSize(w or 100, 22); b:SetText(text)
    return b
end
local function Label(parent, text, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormal")
    fs:SetText(text or ""); fs:SetJustifyH("LEFT")
    return fs
end
local function Tip(b, title, text)
    b:SetScript("OnEnter", function()
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOM")
        GameTooltip:SetText(title)
        if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
local function Enabled() return GuildPrideDB == nil or GuildPrideDB.mailUI ~= false end

---------------------------------------------------------------------
-- Liste
---------------------------------------------------------------------
local function Refresh()
    if not panel or not panel:IsShown() then return end
    list = AH.MailList()
    offset = math.max(0, math.min(offset, #list - ROWS))
    local running = AH.MailRunning()
    for i, row in ipairs(panel.rows) do
        local m = list[offset + i]
        row.mail = m
        if not m then row:Hide() else
            row:Show()
            row.icon:SetTexture(m.icon or "Interface\\Icons\\INV_Letter_15")
            row.sender:SetText(tostring(m.sender or "?"))
            row.subject:SetText(tostring(m.subject or ""))
            row.money:SetText(m.money > 0 and AH.Money(m.money) or (m.cod > 0 and ("|cffff4040" .. L["Nachnahme"] .. "|r") or ""))
            row.items:SetText(m.items > 0 and (L["%d Items"]):format(m.items) or "")
            row.days:SetText(m.days and (L["%d Tage"]):format(math.floor(m.days)) or "")
            row.cat:SetText(m.cat and ((CAT_COLOR[m.cat] or "") .. AH.MAIL_LABEL[m.cat] .. "|r") or "")
            row.take:SetShown(m.cat ~= nil)
            row.take:SetEnabled(not running)
        end
    end
    local c = AH.MailCounts()
    for _, cat in ipairs(AH.MAIL_CATS) do
        local b = panel.cats[cat]
        b:SetText(("%s (%d)"):format(AH.MAIL_LABEL[cat], c[cat]))
        b:SetEnabled(c[cat] > 0 and not running)
    end
    local total = c.expired + c.gold + c.won + c.other
    panel.allBtn:SetEnabled(total > 0 and not running)
    panel.stop:SetShown(running)
    panel.empty:SetText(#list == 0 and L["Der Briefkasten ist leer."] or "")
    panel.summary:SetText((L["%d Briefe · %d zum Abholen · Gold aus dem Auktionshaus: %s"]):format(#list, total, AH.Money(c.goldSum)))
end
AH.onMailChanged = Refresh

---------------------------------------------------------------------
-- Umschalten zwischen GuildPride und Blizzard
---------------------------------------------------------------------
local function HideBlizzard()
    if hidden or not MailFrame then return end
    saved = { scale = MailFrame:GetScale(), alpha = MailFrame:GetAlpha() }
    hidden = true
    MailFrame:SetAlpha(0)
    MailFrame:SetScale(0.001)   -- winzig: nichts davon lässt sich anklicken
end

local function RestoreBlizzard()
    if not hidden then return end
    hidden = false
    MailFrame:SetScale(saved and saved.scale or 1)
    MailFrame:SetAlpha(saved and saved.alpha or 1)
end

local function Remember(blizzard)
    if type(GuildPrideDB) == "table" then GuildPrideDB.mailBlizzard = blizzard end
end

local function ShowGuildPride()
    Remember(false)
    HideBlizzard()
    panel:Show()
    Refresh()
end

local function ShowBlizzard(remember)
    if remember ~= false then Remember(true) end
    switching = true
    panel:Hide()
    switching = false
    RestoreBlizzard()
end

-- X oder ESC am GuildPride-Fenster: den Briefkasten schließen wie bei Blizzard
local function OnWindowHide()
    if switching or not hidden then return end
    RestoreBlizzard()
    if CloseMail then CloseMail() end
end

-- Blizzards Fenster sichtbar auf „Brief schreiben“ stellen. Erst Blizzards eigener Weg
-- (Reiter-Funktion bzw. Klick auf den Reiter); klappt das nicht, Schreib-Fenster direkt zeigen.
function AH.OpenSendMail()
    if not MailFrame then return false end
    if hidden then RestoreBlizzard() end
    if MailFrame:GetScale() < 0.1 then MailFrame:SetScale(1) end   -- nie winzig zurücklassen
    if MailFrame:GetAlpha() < 0.1 then MailFrame:SetAlpha(1) end
    if not MailFrame:IsShown() then
        if ShowUIPanel then ShowUIPanel(MailFrame) else MailFrame:Show() end
    end
    local tab = MailFrameTab2
    if tab then
        if MailFrameTab_OnClick then pcall(MailFrameTab_OnClick, tab, 2)
        elseif tab.Click then pcall(tab.Click, tab) end
    end
    if SendMailFrame and not SendMailFrame:IsShown() then
        if InboxFrame then InboxFrame:Hide() end
        if OpenMailFrame and OpenMailFrame.Hide then OpenMailFrame:Hide() end
        SendMailFrame:Show()
        if PanelTemplates_SetTab then pcall(PanelTemplates_SetTab, MailFrame, 2) end
    end
    if SendMailNameEditBox and SendMailNameEditBox.SetFocus then SendMailNameEditBox:SetFocus() end
    return SendMailFrame == nil or SendMailFrame:IsShown()
end

local function MakeButton()
    local b = Skin(CreateFrame("Button", "GuildPrideMailOpenButton", MailFrame, "UIPanelButtonTemplate"))
    b:SetSize(96, 20); b:SetText("GuildPride")
    local close = MailFrame.CloseButton or MailFrameCloseButton
    if close then b:SetPoint("RIGHT", close, "LEFT", -4, 0)
    else b:SetPoint("TOPRIGHT", MailFrame, "TOPRIGHT", -30, -2) end
    b:SetFrameStrata("HIGH")
    b:SetFrameLevel(MailFrame:GetFrameLevel() + 50)
    b:SetScript("OnClick", function() ShowGuildPride() end)
    Tip(b, L["GuildPride – Briefkasten"], L["Zum GuildPride-Briefkasten wechseln."])
    return b
end

local function Build()
    panel = CreateFrame("Frame", "GuildPrideMailWindow", UIParent, "BackdropTemplate")
    panel:SetSize(WIN_W, WIN_H)
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    panel:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
    })
    panel:SetBackdropColor(0.05, 0.05, 0.07, 0.97)
    panel:SetFrameStrata("HIGH")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true); panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:SetScript("OnHide", OnWindowHide)
    panel:Hide()
    tinsert(UISpecialFrames, "GuildPrideMailWindow")   -- ESC schließt

    local title = Label(panel, L["GuildPride – Briefkasten"], "GameFontNormalLarge"); title:SetPoint("TOPLEFT", 20, -16)
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", -4, -4)
    panel.blizzard = Button(panel, L["Blizzard-Briefkasten"], 150); panel.blizzard:SetPoint("RIGHT", close, "LEFT", -4, 0)
    panel.blizzard:SetScript("OnClick", function() ShowBlizzard() end)
    Tip(panel.blizzard, L["Blizzard-Briefkasten"], L["Zurück zu Blizzards Postfenster. Der Knopf „GuildPride“ dort bringt dich wieder hierher."])
    panel.write = Button(panel, L["Brief schreiben"], 130); panel.write:SetPoint("RIGHT", panel.blizzard, "LEFT", -6, 0)
    panel.write:SetScript("OnClick", function()
        ShowBlizzard(false)                      -- nur kurz: die Wahl bleibt GuildPride
        AH.OpenSendMail()
    end)
    Tip(panel.write, L["Brief schreiben"], L["Öffnet Blizzards Fenster zum Schreiben. Beim nächsten Öffnen kommt wieder GuildPride."])

    -- Sorten-Knöpfe
    panel.cats = {}
    local prev
    for _, cat in ipairs(AH.MAIL_CATS) do
        local b = Button(panel, AH.MAIL_LABEL[cat], cat == "other" and 130 or 120)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 20, -50) end
        b:SetScript("OnClick", function() AH.CollectMail(cat); Refresh() end)
        panel.cats[cat] = b
        prev = b
    end
    Tip(panel.cats.expired, L["Abgelaufene"], L["Holt nur abgelaufene und abgebrochene Auktionen ab (die Items kommen zurück in die Taschen)."])
    Tip(panel.cats.gold, L["Gold"], L["Holt nur das Gold aus verkauften Auktionen und Überboten-Rückzahlungen ab."])
    Tip(panel.cats.won, L["Gekauftes"], L["Holt nur gewonnene Auktionen ab (gekaufte Items)."])
    Tip(panel.cats.other, L["Andere Post"], L["Holt alle Post ab, die nicht vom Auktionshaus kommt – z. B. von deinen Twinks. Nachnahme bleibt liegen."])
    panel.allBtn = Button(panel, L["Alles abholen"], 120); panel.allBtn:SetPoint("LEFT", prev, "RIGHT", 16, 0)
    panel.allBtn:SetScript("OnClick", function() AH.CollectMail("all"); Refresh() end)
    Tip(panel.allBtn, L["Alles abholen"], L["Holt alle Briefe mit Gold oder Items ab. Nachnahme bleibt liegen."])
    panel.stop = Button(panel, L["Stopp"], 70); panel.stop:SetPoint("LEFT", panel.allBtn, "RIGHT", 6, 0)
    panel.stop:SetScript("OnClick", function() AH.StopMail(); Refresh() end)
    panel.stop:Hide()

    -- Liste
    local cols = { { L["Absender"], 50 }, { L["Betreff"], 190 }, { L["Gold"], 420 }, { L["Items"], 520 }, { L["Rest"], 580 }, { L["Sorte"], 630 } }
    for _, c in ipairs(cols) do
        local h = Label(panel, c[1], "GameFontNormalSmall"); h:SetPoint("TOPLEFT", c[2], -84)
    end
    panel.empty = Label(panel, "", "GameFontDisableSmall"); panel.empty:SetPoint("TOPLEFT", 24, -106)
    panel.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, panel)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 16, -100 - (i - 1) * ROW_H); row:SetPoint("RIGHT", panel, "RIGHT", -16, 0)
        row.icon = row:CreateTexture(nil, "ARTWORK"); row.icon:SetSize(ROW_H - 2, ROW_H - 2); row.icon:SetPoint("LEFT", 4, 0)
        row.sender = Label(row, "", "GameFontHighlightSmall"); row.sender:SetPoint("LEFT", 34, 0); row.sender:SetWidth(136)
        row.subject = Label(row, "", "GameFontHighlightSmall"); row.subject:SetPoint("LEFT", 174, 0); row.subject:SetWidth(220)
        row.money = Label(row, "", "GameFontHighlightSmall"); row.money:SetPoint("LEFT", 400, 0); row.money:SetWidth(100)
        row.items = Label(row, "", "GameFontHighlightSmall"); row.items:SetPoint("LEFT", 504, 0); row.items:SetWidth(60)
        row.days = Label(row, "", "GameFontDisableSmall"); row.days:SetPoint("LEFT", 564, 0); row.days:SetWidth(50)
        row.cat = Label(row, "", "GameFontHighlightSmall"); row.cat:SetPoint("LEFT", 614, 0); row.cat:SetWidth(70)
        row.take = Button(row, L["Abholen"], 70); row.take:SetPoint("RIGHT", -2, 0)
        row.take:SetScript("OnClick", function()
            if row.mail then AH.CollectOne(row.mail.index); Refresh() end
        end)
        row:Hide()
        panel.rows[i] = row
    end
    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, d)
        offset = math.max(0, math.min(offset - d * 3, math.max(0, #list - ROWS)))
        Refresh()
    end)
    panel.summary = Label(panel, "", "GameFontHighlightSmall"); panel.summary:SetPoint("BOTTOMLEFT", 22, 18)

    button = MakeButton()
end

local function Setup()
    if panel or not MailFrame or not Enabled() then return end
    Build()
end

function AH._MailWindow() return button, panel end   -- für Tests

-- Eigenes Fenster an/aus (Einstellungen) – wirkt sofort, auch bei offenem Briefkasten
function AH.SetMailUI(on)
    if type(GuildPrideDB) == "table" then GuildPrideDB.mailUI = on and true or false end
    if on then
        Setup()
        if button then button:Show() end
    else
        if panel and (panel:IsShown() or hidden) then ShowBlizzard(false) end
        if button then button:Hide() end
    end
end

AH.Listen("MAIL_SHOW", function()
    Setup()
    if button then button:SetShown(Enabled()) end
    if panel and Enabled() and not (GuildPrideDB and GuildPrideDB.mailBlizzard) then ShowGuildPride() end
end)
AH.Listen("MAIL_INBOX_UPDATE", Refresh)
AH.Listen("MAIL_CLOSED", function()
    RestoreBlizzard()   -- zuerst, damit das Ausblenden unten den Briefkasten nicht erneut schließt
    if panel then panel:Hide() end
end)
