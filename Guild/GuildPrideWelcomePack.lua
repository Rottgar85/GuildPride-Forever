-- GuildPride: Willkommens-Paket für neue Mitglieder
-- Tritt man während des Spielens einer Gilde bei, öffnet sich einmal ein Fenster mit der Nachricht
-- des Tages, den Gildenregeln (Gildeninfo), dem Discord- und dem Community-Link. Über ein Feld kann
-- man den Offizieren eine Frage schicken (GuildPrideQuestions.lua: über den Messenger, auch an
-- Offiziere, die gerade offline sind). /gp willkommen öffnet das Fenster jederzeit.
local ADDON, ns = ...
local L = ns.L

local W = {}
ns.WelcomePack = W
local MAX_Q = 200

local function InfoText()
    if ns.GuildTextLocked and ns.GuildTextLocked() then return "" end
    local t = GetGuildInfoText and GetGuildInfoText() or ""
    if issecretvalue and issecretvalue(t) then return "" end
    return type(t) == "string" and t or ""
end

local function Clean(s) return (tostring(s or ""):gsub("|", ""):gsub("[%c]", " ")):sub(1, MAX_Q) end
W.Clean = Clean

-- Frage an die Offiziere: gibt Anzahl Offiziere und davon online zurück, oder nil, Grund
function W.Ask(text)
    if not ns.Questions then return nil, "gilde" end
    return ns.Questions.Ask(Clean(text))
end

-- Ehrliche Rückmeldung nach dem Senden (sent = Anzahl Offiziere oder nil; dann ist why der Grund)
function W.AskResultText(sent, online, why)
    if sent then
        if online == sent then return (L["Deine Frage ist bei %d Offizier(en) angekommen, die gerade online sind. Antworten kommen in deine Nachrichten (/gp nachrichten)."]):format(sent) end
        if online > 0 then return (L["Deine Frage ging an %d Offizier(e): %d gerade online, die anderen bekommen sie beim Einloggen. Antworten kommen in deine Nachrichten (/gp nachrichten)."]):format(sent, online) end
        return (L["Gerade ist kein Offizier online. Deine Frage geht an %d Offizier(e), sobald sie einloggen. Antworten kommen in deine Nachrichten (/gp nachrichten)."]):format(sent)
    end
    if why == "wait" then return L["Bitte einen Moment warten, bevor du die nächste Frage schickst."] end
    if why == "keine" then return L["In dieser Gilde ist kein Offizier bekannt."] end
    return nil
end

-- Text des Fensters (für Tests getrennt)
function W.Body()
    local parts = {}
    local guild = GetGuildInfo and GetGuildInfo("player")
    if type(guild) ~= "string" then guild = nil end
    parts[#parts + 1] = (L["Schön, dass du bei |cffd4af37%s|r bist!"]):format(guild or L["der Gilde"])
    local motd = ns.GuildMOTD and ns.GuildMOTD() or ""
    if type(motd) ~= "string" then motd = "" end
    if motd ~= "" then parts[#parts + 1] = "|cffffd100" .. L["Nachricht des Tages"] .. "|r\n" .. motd end
    local info = InfoText()
    if info ~= "" then
        if #info > 700 then info = info:sub(1, 700) .. " …" end
        parts[#parts + 1] = "|cffffd100" .. L["Gildeninfo und Regeln"] .. "|r\n" .. info
    end
    local GL = ns.GuildLinks
    if GL and (GL.Get("discord") or GL.Get("community")) then
        parts[#parts + 1] = L["Discord und Community der Gilde: Knöpfe unten."]
    end
    parts[#parts + 1] = L["Alle Gildenfenster findest du im GuildPride-Fenster (/gp)."]
    return table.concat(parts, "\n\n")
end

local win
local function Build()
    win = CreateFrame("Frame", "GuildPrideWelcomePack", UIParent, "BackdropTemplate")
    win:SetSize(460, 420)
    win:SetPoint("CENTER", 0, 40)
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true); win:EnableMouse(true); win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    if ns.SkinDialog then ns.SkinDialog(win) end
    tinsert(UISpecialFrames, "GuildPrideWelcomePack")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)
    if ns.SkinClose then ns.SkinClose(close) end
    close:SetScript("OnClick", function() win:Hide() end)
    local title = win:CreateFontString(nil, "OVERLAY", "GPFont_Large")
    title:SetPoint("TOPLEFT", 14, -12); title:SetText(L["Willkommen in der Gilde!"])
    if ns.Paint then ns.Paint(title, "heading") end

    local scroll = CreateFrame("ScrollFrame", nil, win, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -40); scroll:SetPoint("BOTTOMRIGHT", -32, 110)
    local view = CreateFrame("Frame", nil, scroll); view:SetSize(400, 1)
    scroll:SetScrollChild(view)
    win.body = view:CreateFontString(nil, "OVERLAY", "GPFont_Text")
    win.body:SetPoint("TOPLEFT", 2, -2); win.body:SetWidth(396)
    win.body:SetJustifyH("LEFT"); win.body:SetSpacing(3)

    local function Btn(text, x, fn)
        local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        if ns.SkinButton then ns.SkinButton(b) end
        b:SetSize(136, 22); b:SetPoint("BOTTOMLEFT", x, 78); b:SetText(text)
        b:SetScript("OnClick", fn)
        return b
    end
    -- Links der eigenen Gilde (Verwaltung › Links der Gilde); ohne Link ausgegraut
    win.discordBtn = Btn(L["Discord-Link"], 14, function() if ns.GuildLinks then ns.GuildLinks.Show("discord") end end)
    win.communityBtn = Btn(L["Community-Link"], 162, function() if ns.GuildLinks then ns.GuildLinks.Show("community") end end)
    Btn(L["Gildenfenster"], 310, function() if ns.ToggleUI then ns.ToggleUI() end end)

    local label = win:CreateFontString(nil, "OVERLAY", "GPFont_TextBold")
    label:SetPoint("BOTTOMLEFT", 16, 56); label:SetText(L["Frage an die Offiziere:"])
    local box = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    box:SetSize(320, 22); box:SetPoint("BOTTOMLEFT", 20, 26)
    box:SetAutoFocus(false); box:SetMaxLetters(MAX_Q)
    if ns.SkinEditBox then ns.SkinEditBox(box) end
    local send = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    if ns.SkinButton then ns.SkinButton(send) end
    send:SetSize(90, 22); send:SetPoint("LEFT", box, "RIGHT", 8, 0); send:SetText(L["Senden"])
    local function DoSend()
        local sent, second = W.Ask(box:GetText())
        if sent then box:SetText(""); box:ClearFocus() end
        local text = sent and W.AskResultText(sent, second) or W.AskResultText(nil, 0, second)
        if text then ns.Print(text) end
    end
    send:SetScript("OnClick", DoSend)
    box:SetScript("OnEnterPressed", DoSend)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    win:SetScript("OnShow", function()
        local GL = ns.GuildLinks
        win.discordBtn:SetEnabled(GL and GL.Get("discord") ~= nil or false)
        win.communityBtn:SetEnabled(GL and GL.Get("community") ~= nil or false)
        win.body:SetText(W.Body())
        view:SetHeight(math.max(1, (win.body:GetStringHeight() or 0) + 8))
    end)
    win:Hide()
end

-- Links der Gilde angekommen oder geändert: Fenster neu füllen
if ns.GuildLinks then
    ns.GuildLinks.Changed = function()
        if win and win:IsShown() then win:GetScript("OnShow")(win) end
    end
end

function W.Show()
    if not IsInGuild() then ns.Print(L["Du bist in keiner Gilde."]); return end
    if not win then Build() end
    win:Show()
end

-- Beitritt erkennen: beim Einloggen den Stand merken, dann auf den Wechsel „keine Gilde -> Gilde“ warten
local known
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_GUILD_UPDATE")
ev:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(15, function() known = IsInGuild() and true or false end)
    elseif known == false and IsInGuild() then
        known = true
        -- Links der Gilde gleich anfragen: das neue Mitglied hat sie noch nicht
        ns.Queue("GLQ", nil, "1")
        if GuildPrideDB and GuildPrideDB.welcomePack ~= false then C_Timer.After(5, W.Show) end
    elseif known ~= nil then
        known = IsInGuild() and true or false
    end
end)

local origSlash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd = strtrim(arg or ""):match("^(%S+)")
    cmd = cmd and cmd:lower()
    if cmd == "willkommen" or cmd == "welcome" then W.Show()
    elseif origSlash then origSlash(arg) end
end
