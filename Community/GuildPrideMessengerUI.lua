-- GuildPride Messenger: Fenster (links Unterhaltungen, rechts Verlauf und Eingabe), Knopf in der
-- Kopfleiste des Gildenfensters mit Zahl der ungelesenen Nachrichten, Zahl am Minimap-Knopf.
--   /gp nachrichten [Name]   öffnet das Fenster (mit Name gleich diese Unterhaltung)
--   /gp nachricht Name Text  schickt direkt
local ADDON, ns = ...
local L = ns.L
local M = ns.Messenger
if not M then return end

local ROWS = 14            -- höchstens so viele Zeilen in der Liste; je nach Höhe weniger sichtbar
local MIN_W, MIN_H, MAX_W, MAX_H = 480, 300, 1100, 800
local win, current

local function Short(main) return Ambiguate(main or "", "guild") end

-- Unterhaltungen: Gildenmitglied (Main, GuildPride-Nachrichten) oder "W:Name" (Flüstern, GuildPrideWhisper.lua)
local function IsWhisper(key) return type(key) == "string" and key:sub(1, 2) == "W:" end
local function WhisperName(key) return key:sub(3) end
local function Wh() return ns.Whisper end
local function ConvOf(key)
    if IsWhisper(key) then return Wh() and Wh().Conv(WhisperName(key)) or {} end
    return M.Conv(key)
end
local function KeyName(key) return Short(IsWhisper(key) and WhisperName(key) or key) end
-- alle ungelesenen (Nachrichten und Flüstern)
function M.AllUnread() return M.UnreadTotal() + (Wh() and Wh().UnreadTotal() or 0) end
local WHISPER_ICON = "|TInterface\\ChatFrame\\UI-ChatWhisperIcon:12:12|t "

-- „14:32“ heute, sonst „20.11. 14:32“
function M.TimeText(t, now)
    now = now or GetServerTime()
    if date("%Y%m%d", t) == date("%Y%m%d", now) then return date("%H:%M", t) end
    return date(ns.IS_GERMAN and "%d.%m. %H:%M" or "%d %b %H:%M", t)
end

local STATE = {
    sent = "|cff888888" .. "%s" .. "|r",
    stored = "|cffffd100" .. "%s" .. "|r",
    delivered = "|cff40ff40" .. "%s" .. "|r",
    expired = "|cffff6060" .. "%s" .. "|r",
}
local function StateText(state)
    local text = state == "delivered" and L["zugestellt"] or state == "stored" and L["wartet – wird zugestellt, wenn online"]
        or state == "expired" and L["nicht zugestellt"] or L["gesendet"]
    return (STATE[state] or STATE.sent):format(text)
end

-- Eine Zeile im Verlauf; partner = Name bei Flüster-Unterhaltungen (dort gibt es keinen Zustellstatus)
function M.LineText(e, now, partner)
    if partner then
        local who = e.out and ("|cffd4af37" .. L["Du"] .. "|r") or ("|cffff80ff" .. Short(partner) .. "|r")
        return ("|cff999999%s|r  %s: %s"):format(M.TimeText(e.t or 0, now), who, e.text or "")
    end
    local who = e.out and ("|cffd4af37" .. L["Du"] .. "|r") or ("|cff8cc8ff" .. Short(e.author or "") .. "|r")
    if e.q then who = "|cffffd100[" .. L["Frage"] .. "]|r " .. who end
    local tail = e.out and ("  " .. StateText(e.state)) or (e.via and ("  |cff777777" .. L["(später zugestellt)"] .. "|r") or "")
    return ("|cff999999%s|r  %s: %s%s"):format(M.TimeText(e.t or 0, now), who, e.text or "", tail)
end

function M.IsOpenOn(main) return win and win:IsShown() and current == main end

local function Paint(obj, role, a) if ns.Paint then return ns.Paint(obj, role, a) end return obj end

---------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------
local function Build()
    win = CreateFrame("Frame", "GuildPrideMessenger", UIParent, "BackdropTemplate")
    local size = type(GuildPrideDB.messengerSize) == "table" and GuildPrideDB.messengerSize or {}
    win:SetSize(math.max(MIN_W, math.min(MAX_W, tonumber(size.w) or 660)), math.max(MIN_H, math.min(MAX_H, tonumber(size.h) or 460)))
    win:SetPoint("CENTER", 0, 40)
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true); win:EnableMouse(true); win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    if ns.SkinDialog then ns.SkinDialog(win) end
    tinsert(UISpecialFrames, "GuildPrideMessenger")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    if ns.SkinClose then ns.SkinClose(close) end
    close:SetScript("OnClick", function() win:Hide() end)
    local title = win:CreateFontString(nil, "OVERLAY", "GPFont_Large")
    title:SetPoint("TOPLEFT", 14, -12); title:SetText(L["Nachrichten"])
    Paint(title, "heading")
    local sub = win:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    sub:SetPoint("TOPLEFT", 14, -34); sub:SetPoint("RIGHT", -40, 0); sub:SetJustifyH("LEFT")
    win.sub = sub
    sub:SetText(L["Flüstern und Nachrichten an Gildenmitglieder (auch offline). Offline-Nachrichten heben andere Mitglieder bis zur Zustellung auf – nichts Geheimes schreiben."])

    -- links: neue Unterhaltung und Liste
    local nameBox = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    nameBox:SetSize(130, 22); nameBox:SetPoint("TOPLEFT", 20, -58)
    nameBox:SetAutoFocus(false); nameBox:SetMaxLetters(60)
    if ns.SkinEditBox then ns.SkinEditBox(nameBox) end
    local nameHint = nameBox:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    nameHint:SetPoint("LEFT", 2, 0); nameHint:SetText(L["Name …"])
    nameBox:SetScript("OnTextChanged", function(self) nameHint:SetShown(self:GetText() == "") end)
    local newBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    if ns.SkinButton then ns.SkinButton(newBtn) end
    newBtn:SetSize(44, 22); newBtn:SetPoint("LEFT", nameBox, "RIGHT", 6, 0); newBtn:SetText(L["Neu"])
    -- Gildenmitglied: GuildPride-Nachricht (auch offline); sonst Flüstern
    local function StartNew()
        local text = strtrim(nameBox:GetText() or "")
        if text == "" then return end
        local main = M.Resolve(text)
        nameBox:SetText(""); nameBox:ClearFocus()
        if main then M.Open(main); return end
        if not Wh() then return end
        local key = Wh().Key(text)
        Wh().DB().target[key] = Wh().DB().target[key] or text
        M.Open("W:" .. key)
    end
    newBtn:SetScript("OnClick", StartNew)
    nameBox:SetScript("OnEnterPressed", StartNew)
    nameBox:SetScript("OnEscapePressed", nameBox.ClearFocus)

    win.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Button", nil, win)
        r:SetSize(190, 24)
        r:SetPoint("TOPLEFT", 14, -86 - (i - 1) * 24)
        if i % 2 == 0 then Paint(r:CreateTexture(nil, "BACKGROUND"), "glow", 0.05):SetAllPoints() end
        r.sel = r:CreateTexture(nil, "BORDER"); r.sel:SetAllPoints(); Paint(r.sel, "glow", 0.22); r.sel:Hide()
        local hl = r:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); Paint(hl, "glow", 0.15)
        r.name = r:CreateFontString(nil, "OVERLAY", "GPFont_Text")
        r.name:SetPoint("LEFT", 6, 0); r.name:SetPoint("RIGHT", -44, 0); r.name:SetJustifyH("LEFT"); r.name:SetWordWrap(false)
        r.info = r:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
        r.info:SetPoint("RIGHT", -6, 0)
        r:SetScript("OnClick", function(self) if self.key then M.Open(self.key) end end)
        win.rows[i] = r
    end
    win.offset = 0
    win.none = win:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    win.none:SetPoint("TOPLEFT", 18, -92); win.none:SetWidth(180); win.none:SetJustifyH("LEFT")
    win.none:SetText(L["Noch keine Unterhaltung. Name eintragen und „Neu“ klicken."])

    -- Trennlinie
    local line = win:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", 212, -58); line:SetPoint("BOTTOMLEFT", 212, 14); line:SetWidth(1)
    Paint(line, "accent", 0.4)

    -- rechts: Kopf, Verlauf, Eingabe
    win.head = win:CreateFontString(nil, "OVERLAY", "GPFont_TextBold")
    win.head:SetPoint("TOPLEFT", 224, -60); win.head:SetPoint("RIGHT", -110, 0); win.head:SetJustifyH("LEFT")
    win.status = win:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    win.status:SetPoint("TOPLEFT", win.head, "BOTTOMLEFT", 0, -2)
    local del = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    if ns.SkinButton then ns.SkinButton(del) end
    del:SetSize(90, 20); del:SetPoint("TOPRIGHT", -16, -58); del:SetText(L["Löschen"])
    del:SetScript("OnClick", function()
        if current then
            if IsWhisper(current) then if Wh() then Wh().Delete(WhisperName(current)) end else M.Delete(current) end
            current = nil; M.Refresh()
        end
    end)
    win.del = del

    local hist = CreateFrame("ScrollingMessageFrame", nil, win)
    hist:SetPoint("TOPLEFT", 224, -96); hist:SetPoint("BOTTOMRIGHT", -16, 52)
    hist:SetFontObject(GPFont_Text or GameFontHighlight)
    hist:SetJustifyH("LEFT")
    hist:SetFading(false)
    hist:SetMaxLines(250)
    hist:EnableMouseWheel(true)
    hist:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    end)
    win.hist = hist

    local box = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    box:SetSize(330, 24); box:SetPoint("BOTTOMLEFT", 230, 18)
    box:SetAutoFocus(false); box:SetMaxLetters(400)
    if ns.SkinEditBox then ns.SkinEditBox(box) end
    local send = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    if ns.SkinButton then ns.SkinButton(send) end
    send:SetSize(80, 24); send:SetPoint("LEFT", box, "RIGHT", 8, 0); send:SetText(L["Senden"])
    local function DoSend()
        if not current then return end
        if IsWhisper(current) then
            if Wh() and Wh().Send(WhisperName(current), box:GetText()) then box:SetText("") end
            return
        end
        local id, why = M.Send(current, box:GetText())
        if id then box:SetText("")
        elseif why == "unbekannt" then ns.Print(L["Dieses Mitglied ist nicht mehr in der Gilde."]) end
    end
    send:SetScript("OnClick", DoSend)
    box:SetScript("OnEnterPressed", DoSend)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    win.box, win.send = box, send

    win:EnableMouseWheel(true)
    win:SetScript("OnMouseWheel", function(_, delta)
        win.offset = math.max(0, win.offset - delta * 3)
        M.Refresh()
    end)
    -- Größe ziehen (Griff unten rechts), wird gespeichert
    win:SetResizable(true)
    if win.SetResizeBounds then win:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    elseif win.SetMinResize then win:SetMinResize(MIN_W, MIN_H); win:SetMaxResize(MAX_W, MAX_H) end
    local grip = CreateFrame("Button", nil, win)
    grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() win:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        win:StopMovingOrSizing()
        GuildPrideDB.messengerSize = { w = math.floor(win:GetWidth() + 0.5), h = math.floor(win:GetHeight() + 0.5) }
    end)
    win:SetScript("OnSizeChanged", function() M.Layout() end)
    win:SetScript("OnShow", function() M.Layout(); M.Refresh() end)
    win:SetScript("OnHide", function() if win.box then win.box:ClearFocus() end end)
    win:Hide()
end

local function FillHistory()
    local hist = win.hist
    hist:Clear()
    if not current then return end
    local now = GetServerTime()
    local partner = IsWhisper(current) and WhisperName(current) or nil
    for _, e in ipairs(ConvOf(current)) do hist:AddMessage(M.LineText(e, now, partner)) end
    hist:ScrollToBottom()
end

local lastFill
-- Nach Größenänderung: Eingabe so breit wie Platz ist, so viele Listenzeilen wie passen
function M.Layout()
    if not win then return end
    local w = tonumber(win:GetWidth()) or 660
    local h = tonumber(win:GetHeight()) or 460
    if win.box then win.box:SetWidth(math.max(120, w - 230 - 16 - 88 - 8)) end
    win.visibleRows = math.max(1, math.min(ROWS, math.floor((h - 86 - 16) / 24)))
    if win.sub then win.sub:SetShown(w >= 560) end
    if win:IsShown() then M.Refresh() end
end

function M.Refresh()
    if M.UpdateBadges then M.UpdateBadges() end
    if not win or not win:IsShown() then return end
    if current then M.MarkReadQuiet(current) end
    -- Nachrichten und Flüstern gemeinsam, neueste zuerst
    local list = {}
    for _, c in ipairs(M.Conversations()) do c.key = c.main; list[#list + 1] = c end
    for _, c in ipairs(Wh() and Wh().Conversations() or {}) do list[#list + 1] = c end
    table.sort(list, function(a, b) return (a.last.t or 0) > (b.last.t or 0) end)
    local visible = win.visibleRows or ROWS
    win.offset = math.max(0, math.min(win.offset, #list - visible))
    for i = 1, ROWS do
        local r, c = win.rows[i], list[i + win.offset]
        if i > visible then c = nil end
        r:SetShown(c ~= nil)
        if c then
            r.key = c.key
            r.name:SetText((c.whisper and WHISPER_ICON or "") .. (c.unread > 0 and "|cffffd100" or "")
                .. KeyName(c.key) .. (c.unread > 0 and "|r" or ""))
            r.info:SetText(c.unread > 0 and ("|cffffd100" .. c.unread .. "|r") or M.TimeText(c.last.t or 0))
            r.sel:SetShown(c.key == current)
        end
    end
    win.none:SetShown(#list == 0)
    local has = current ~= nil
    win.box:SetShown(has); win.send:SetShown(has); win.del:SetShown(has)
    if has and IsWhisper(current) then
        win.head:SetText(KeyName(current))
        win.status:SetText("|cffff80ff" .. L["Flüstern"] .. "|r |cff888888" .. L["– geht nur, wenn der Spieler online ist"] .. "|r")
    elseif has then
        local online = #M.OnlineChars(current) > 0
        win.head:SetText(Short(current))
        win.status:SetText(online and ("|cff40ff40" .. L["online"] .. "|r") or ("|cff888888" .. L["offline – wird zugestellt, wenn online"] .. "|r"))
    else
        win.head:SetText(L["Unterhaltung links wählen oder neu anfangen."])
        win.status:SetText("")
    end
    -- Verlauf nur neu aufbauen, wenn sich etwas geändert hat
    local c = has and ConvOf(current) or {}
    local last = c[#c]
    local key = tostring(current) .. "|" .. #c .. "|" .. tostring(last and last.id) .. "|" .. tostring(last and last.state)
    local states = ""
    for i = math.max(1, #c - 20), #c do states = states .. (c[i].state or "") end
    key = key .. states
    if key ~= lastFill then lastFill = key; FillHistory() end
end

-- Gelesen markieren ohne erneutes Neuzeichnen (aus Refresh heraus)
function M.MarkReadQuiet(key)
    if IsWhisper(key) then
        if Wh() then Wh().MarkRead(WhisperName(key)) end
    else
        M.DB().unread[key] = nil
    end
end

function M.Open(main)
    if not win then Build() end
    current = main
    if main then M.MarkReadQuiet(main) end
    win:Show()
    lastFill = nil
    M.Refresh()
    if main then win.box:SetFocus() end
end

-- Eingehendes Flüstern: Fenster aufgehen lassen, aber nie die Tastatur wegnehmen und nicht aus einer
-- anderen Unterhaltung reißen, in der gerade getippt wird
function M.ShowIncoming(key)
    if not win then Build() end
    if win:IsShown() and current and current ~= key
        and (win.box:HasFocus() or (win.box:GetText() or "") ~= "") then
        M.Refresh()   -- nur Zähler und Liste
        return
    end
    current = key
    M.MarkReadQuiet(key)
    win:Show()
    lastFill = nil
    M.Refresh()
end

-- Selbst flüstern: Unterhaltung mit diesem Namen öffnen, Eingabe dort (nach Blizzards eigenem Fokus)
function M.OpenWhisper(raw)
    local W = ns.Whisper
    if not W then return end
    local key = W.Key(raw)
    W.DB().target[key] = raw
    M.Open("W:" .. key)
    C_Timer.After(0, function() if win and win:IsShown() and current == "W:" .. key then win.box:SetFocus() end end)
end

function M.Toggle()
    if not win then Build() end
    if win:IsShown() then win:Hide() else M.Open(current) end
end
ns.OpenMessenger = function(name) M.Open(name and ns.MainOf(ns.Normalize(name)) or nil) end

---------------------------------------------------------------------
-- Knopf in der Kopfleiste und Zahl am Minimap-Knopf
---------------------------------------------------------------------
local headBtn, miniBadge
local function Badge(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size); f:SetPoint("TOPRIGHT", 4, 4)
    f:SetFrameLevel((tonumber(parent:GetFrameLevel()) or 1) + 5)
    local bg = f:CreateTexture(nil, "OVERLAY"); bg:SetAllPoints(); bg:SetColorTexture(0.8, 0.1, 0.1, 0.95)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("CENTER", 0, 0)
    f:Hide()
    return f
end

local function PlaceHead()
    if not headBtn then return end
    local community = _G.GuildPrideCommunityButton
    local discord = _G.GuildPrideDiscordButton
    local anchor = (community and community:IsShown()) and community or discord
    headBtn:ClearAllPoints()
    headBtn:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
end

local function SetupHead()
    local discord = _G.GuildPrideDiscordButton
    if headBtn or not discord then return end
    local frame = discord:GetParent()
    headBtn = CreateFrame("Button", "GuildPrideMessengerButton", frame)
    headBtn:SetSize(26, 26)
    headBtn:SetFrameLevel(discord:GetFrameLevel())
    local icon = headBtn:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints()
    icon:SetTexture("Interface\\ChatFrame\\UI-ChatWhisperIcon")
    local hl = headBtn:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetColorTexture(1, 1, 1, 0.2)
    headBtn.badge = Badge(headBtn, 14)
    headBtn:SetScript("OnClick", function() M.Toggle() end)
    headBtn:SetScript("OnEnter", function(b)
        GameTooltip:SetOwner(b, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(L["Nachrichten"])
        GameTooltip:AddLine(L["Nachrichten an Gildenmitglieder, auch wenn sie offline sind."], 1, 1, 1, true)
        local n = M.AllUnread()
        if n > 0 then GameTooltip:AddLine((L["%d ungelesen"]):format(n), 1, 0.82, 0) end
        GameTooltip:Show()
    end)
    headBtn:SetScript("OnLeave", GameTooltip_Hide)
    frame:HookScript("OnShow", function() C_Timer.After(0, PlaceHead) end)
    PlaceHead()
end

function M.UpdateBadges()
    local n = M.AllUnread()
    local text = n > 9 and "9+" or tostring(n)
    if headBtn then headBtn.badge.text:SetText(text); headBtn.badge:SetShown(n > 0) end
    local mini = _G.GuildPrideMinimapButton
    if mini and not miniBadge then miniBadge = Badge(mini, 14) end
    if miniBadge then miniBadge.text:SetText(text); miniBadge:SetShown(n > 0) end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    SetupHead()
    M.UpdateBadges()
end)

---------------------------------------------------------------------
-- /gp nachrichten [Name] · /gp nachricht Name Text
---------------------------------------------------------------------
-- Name und Text trennen; Namen mit Leerzeichen in Anführungszeichen
function M.ParseArgs(rest)
    rest = strtrim(rest or "")
    local quoted, after = rest:match('^"([^"]+)"%s*(.*)$')
    if quoted then return quoted, after end
    local name, text = rest:match("^(%S+)%s*(.*)$")
    return name, text or ""
end

local origSlash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local raw = strtrim(arg or "")
    local cmd, rest = raw:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower()
    if cmd == "nachrichten" or cmd == "messages" or cmd == "msg" then
        local main = rest ~= "" and M.Resolve(rest) or nil
        if rest ~= "" and not main then ns.Print(L["Diesen Namen gibt es in der Gilde nicht."]) end
        M.Open(main)
    elseif cmd == "nachricht" or cmd == "message" then
        local name, text = M.ParseArgs(rest)
        local main = name and M.Resolve(name)
        if not main then ns.Print(L["/gp nachricht Name Text – Name mit Leerzeichen in Anführungszeichen"]); return end
        local id, why = M.Send(main, text)
        if id then ns.Print((L["Nachricht an %s verschickt."]):format(Short(main)))
        elseif why == "leer" then M.Open(main)
        elseif why == "selbst" then ns.Print(L["Das bist du selbst."])
        else ns.Print(L["Diesen Namen gibt es in der Gilde nicht."]) end
    elseif origSlash then
        origSlash(arg)
    end
end
