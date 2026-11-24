-- GuildPride: Paten für neue Mitglieder
-- Wer mag, meldet sich als Pate. Neue (höchstens 30 Tage dabei) sehen die Paten, die online sind,
-- und schreiben sie mit einem Klick an; Paten sehen, welche Neuen online sind.
--   PAT  ver · 1/0    nur für sich selbst, nie weitergeleitet
--   PAQ  1            Anfrage nach dem Einloggen, Paten antworten
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP

local M = {}
ns.Mentor = M
local NEW_DAYS = 30

local function DB() return ns.GuildTable("mentors") end
local function Me() return ns.Me() end

function M.Is(name)
    local e = DB()[name]
    return type(e) == "table" and e.on == true
end
local function Store(name, ver, on)
    local e = DB()[name]
    if type(e) == "table" and (e.ver or 0) >= ver then return false end
    DB()[name] = { on = on, ver = ver }
    if M.Refresh then M.Refresh() end
    return true
end
local function Send(target)
    local e = DB()[Me()]
    if e then ns.Queue("PAT", target, e.ver, e.on and 1 or 0) end
end
function M.Set(on)
    Store(Me(), math.max(GetServerTime(), ((DB()[Me()] or {}).ver or 0) + 1), on and true or false)
    Send()
end

ns.On("PAT", function(payload, sender)
    if sender == Me() or not ns.IsGuildMember(sender) then return end
    local ver, on = strsplit(SEP, payload)
    ver = ns.Stamp(ver)
    if ver > 0 then Store(sender, ver, on == "1") end
end)
ns.On("PAQ", function(_, sender)
    if sender == Me() or not M.Is(Me()) then return end
    ns.AnswerSoon("PAT", function() Send("@CHANNEL") end)
end)

function M.IsNew(name)
    local e = ns.HistoryOf and ns.HistoryOf(name)
    return e ~= nil and e.first ~= nil and not e.approx and not e.left and GetServerTime() - e.first <= NEW_DAYS * 86400
end

-- Online-Mitglieder, für die fn(Name) wahr ist
local function OnlineWhere(fn)
    local out = {}
    for i = 1, GetNumGuildMembers() or 0 do
        local name, _, _, level, _, zone, _, _, online = GetGuildRosterInfo(i)
        local full = name and ns.Normalize(name)
        if full and online and full ~= Me() and fn(full) then out[#out + 1] = { name = full, level = level, zone = zone } end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

-- Paten: einmal je Sitzung sagen, dass jemand Neues online ist
local greeted = {}
function M.CheckNew()
    if not M.Is(Me()) then return end
    for _, e in ipairs(OnlineWhere(M.IsNew)) do
        if not greeted[e.name] then
            greeted[e.name] = true
            ns.Print((L["Neu in der Gilde und online: %s  |cff888888(/gp paten)|r"]):format(Ambiguate(e.name, "guild")))
        end
    end
end
ns.Every(60, function() if IsInGuild() and not InCombatLockdown() then M.CheckNew() end end)

local win
function M.Refresh()
    if not win or not win:IsShown() then return end
    win.list = {}
    local lines = {}
    local function Part(title, list, empty)
        lines[#lines + 1] = "|cffffd100" .. title .. "|r"
        win.list[#lines] = false
        if #list == 0 then lines[#lines + 1] = "   |cff888888" .. empty .. "|r" end
        for _, e in ipairs(list) do
            lines[#lines + 1] = ("   %s  |cff999999%s · %s|r"):format(Ambiguate(e.name, "guild"), tostring(e.level or "?"), tostring(e.zone or ""))
            win.list[#lines] = e.name
        end
    end
    Part(L["Paten online"], OnlineWhere(M.Is), L["Gerade ist kein Pate online."])
    Part(L["Neue online (höchstens 30 Tage dabei)"], OnlineWhere(M.IsNew), L["Gerade ist niemand Neues online."])
    win:SetLines(lines)
    win.check:SetChecked(M.Is(Me()))
end

function M.Open()
    if not win then
        win = ns.ListWindow({ name = "GuildPrideMentor", title = L["Paten für Neue"], rows = 14, width = 440,
            sub = L["Klick auf einen Namen öffnet das Flüstern."] })
        for i, row in ipairs(win.rows) do
            row:EnableMouse(true)
            row:SetScript("OnMouseUp", function()
                local who = win.list and win.list[i + win.offset]
                if who then
                    local f = ChatFrame_SendTell or (ChatFrameUtil and ChatFrameUtil.SendTell)
                    if f then f(Ambiguate(who, "none")) end
                end
            end)
        end
        local cb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
        cb:SetSize(24, 24); cb:SetPoint("TOPLEFT", 12, win.bottomY + 2)
        local fs = win:CreateFontString(nil, "OVERLAY", "GPFont_Text")
        fs:SetPoint("LEFT", cb, "RIGHT", 4, 0); fs:SetText(L["Ich bin Pate und helfe Neuen gern"])
        cb:SetScript("OnClick", function(self) M.Set(self:GetChecked()) end)
        win.check = cb
        win:SetScript("OnShow", function() win.offset = 0; M.Refresh() end)
    end
    win:SetShown(not win:IsShown())
end

local ev, asked = CreateFrame("Frame"), false
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function()
    if asked then return end
    asked = true
    C_Timer.After(52 + math.random() * 30, function()
        if not IsInGuild() then return end
        if DB()[Me()] then Send() end
        ns.Queue("PAQ", nil, "1")
    end)
    -- Neue: einmal je Sitzung auf die Paten hinweisen
    C_Timer.After(75, function()
        if not IsInGuild() or not M.IsNew(Me()) then return end
        local list, names = OnlineWhere(M.Is), {}
        for i = 1, math.min(3, #list) do names[i] = Ambiguate(list[i].name, "guild") end
        if #names > 0 then ns.Print((L["Fragen? Diese Paten helfen dir gern: %s  |cff888888(/gp paten)|r"]):format(table.concat(names, ", "))) end
    end)
end)

ns.Command({ "paten", "pate", "mentor" }, function() M.Open() end)
