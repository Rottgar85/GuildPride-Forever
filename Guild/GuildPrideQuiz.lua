-- GuildPride: Gildenquiz
-- Ein Offizier stellt eine Frage, Antworten gehen per Flüstern nur an ihn; die erste richtige
-- gewinnt einen Punkt. Die Lösung verlässt seinen Client erst am Ende.
--   QZQ  id · Sekunden · frage        (nur Offiziere)
--   QZA  id · antwort                 (per Flüstern an den Fragesteller)
--   QZR  id · gewinner ("-" = niemand) · lösung   (nur vom Fragesteller)
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP

local Q = {}
ns.Quiz = Q
Q.cur = nil    -- Frage eines anderen: { id, by, text, till }
Q.own = nil    -- eigene Frage: { id, text, answer, open }
local TIME, TEXT_MAX, ANSWER_MAX = 60, 150, 40

local function DB() return ns.GuildTable("quizPoints") end
local function Me() return ns.Me() end
local function CanManage() return CanEditMOTD and CanEditMOTD() and true or false end
local function Clean(s, max) return strtrim((tostring(s or ""):gsub("[%c|]", " "))):sub(1, max) end
local function Same(a, b) return Clean(a, 80):lower() == Clean(b, 80):lower() end
local function Say(text) ns.Print("|cffffd100" .. L["Quiz:"] .. "|r " .. text) end
function Q.Points(name) return DB()[name] or 0 end
local function AddPoint(name) DB()[name] = Q.Points(name) + 1 end

---------------------------------------------------------------------
-- Fragesteller
---------------------------------------------------------------------
local function Finish(winner)
    local o = Q.own
    if not o or not o.open then return end
    o.open = false
    if winner then AddPoint(winner) end
    ns.Queue("QZR", nil, o.id, winner or "-", o.answer)
    Say(winner and (L["%s hat es gewusst: %s"]):format(Ambiguate(winner, "guild"), o.answer) or (L["Niemand wusste es: %s"]):format(o.answer))
    if Q.Refresh then Q.Refresh() end
end
function Q.Start(text, answer)
    text, answer = Clean(text, TEXT_MAX), Clean(answer, ANSWER_MAX)
    if not CanManage() or text == "" or answer == "" or (Q.own and Q.own.open) then return false end
    local id = Me() .. "-" .. GetServerTime()
    Q.own = { id = id, text = text, answer = answer, open = true }
    ns.Queue("QZQ", nil, id, TIME, text)
    local own = Q.own
    -- im Test laufen Timer sofort: erst wirklich nach Ablauf beenden
    local start = GetTime()
    C_Timer.After(TIME + 3, function() if Q.own == own and GetTime() - start >= TIME then Finish(nil) end end)
    Say((L["Frage gestellt: %s"]):format(text))
    return true
end
ns.On("QZA", function(payload, sender)
    local o = Q.own
    if not o or not o.open or sender == Me() or not ns.IsGuildMember(sender) then return end
    local id, text = strsplit(SEP, payload)
    if id == o.id and Same(text, o.answer) then Finish(sender) end
end)

---------------------------------------------------------------------
-- Mitspieler
---------------------------------------------------------------------
ns.On("QZQ", function(payload, sender)
    if sender == Me() or not ns.IsOfficerName(sender) then return end
    local id, secs, text = strsplit(SEP, payload)
    id, text = Clean(id, 60), Clean(text, TEXT_MAX)
    if id == "" or text == "" then return end
    Q.cur = { id = id, by = sender, text = text, till = GetTime() + (ns.Num(secs, 10, 300) or TIME) }
    Say(("%s  |cff888888(%s)|r"):format(text, L["antworten: /gp quiz <Antwort>"]))
    if GuildPrideDB.sound then PlaySound(SOUNDKIT.READY_CHECK) end
    if Q.Refresh then Q.Refresh() end
end)
ns.On("QZR", function(payload, sender)
    local c = Q.cur
    local id, winner, answer = strsplit(SEP, payload)
    if not c or c.by ~= sender or c.id ~= id then return end
    Q.cur = nil
    answer = Clean(answer, ANSWER_MAX)
    if winner and winner ~= "-" and ns.IsGuildMember(winner) then
        AddPoint(winner)
        Say((L["%s hat es gewusst: %s"]):format(Ambiguate(winner, "guild"), answer))
    else
        Say((L["Niemand wusste es: %s"]):format(answer))
    end
    if Q.Refresh then Q.Refresh() end
end)
function Q.Answer(text)
    local c = Q.cur
    text = Clean(text, ANSWER_MAX)
    if not c or GetTime() > c.till or text == "" then Say(L["Gerade läuft keine Frage."]); return false end
    ns.SendAddonMsg("GuildPride", "QZA:" .. c.id .. SEP .. text, "WHISPER", c.by)
    Say((L["Deine Antwort: %s"]):format(text))
    return true
end

---------------------------------------------------------------------
-- Fenster: Rangliste, Frage stellen
---------------------------------------------------------------------
local win
function Q.Refresh()
    if not win or not win:IsShown() then return end
    local list, lines = {}, {}
    for name, n in pairs(DB()) do list[#list + 1] = { name = name, n = n } end
    table.sort(list, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
    if Q.cur then lines[#lines + 1] = "|cffffd100" .. Q.cur.text .. "|r" end
    for i, e in ipairs(list) do lines[#lines + 1] = ("%d.  %s  |cffffd100%d|r"):format(i, Ambiguate(e.name, "guild"), e.n) end
    win:SetLines(lines)
    for _, f in ipairs(win.officer) do f:SetShown(CanManage()) end
end
function Q.Open()
    if not win then
        win = ns.ListWindow({ name = "GuildPrideQuiz", title = L["Gildenquiz"], rows = 12, width = 460, extra = 80,
            sub = L["Rangliste auf diesem PC. Antworten: /gp quiz <Antwort>"], empty = L["Noch keine Punkte."] })
        win.officer = {}
        local function Box(w, x, y, max, text)
            local e = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
            e:SetSize(w, 22); e:SetPoint("BOTTOMLEFT", x, y); e:SetAutoFocus(false); e:SetMaxLetters(max)
            if ns.SkinEditBox then ns.SkinEditBox(e) end
            local hint = e:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
            hint:SetPoint("LEFT", 2, 0); hint:SetText(text)
            e:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)
            e:SetScript("OnEscapePressed", e.ClearFocus)
            win.officer[#win.officer + 1] = e
            return e
        end
        local ask, sol = Box(410, 20, 44, TEXT_MAX, L["Frage"]), Box(220, 20, 14, ANSWER_MAX, L["Lösung"])
        local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        if ns.SkinButton then ns.SkinButton(b) end
        b:SetSize(150, 22); b:SetPoint("BOTTOMLEFT", 270, 14); b:SetText(L["Frage stellen"])
        b:SetScript("OnClick", function()
            if Q.Start(ask:GetText(), sol:GetText()) then ask:SetText(""); sol:SetText("")
            else Say(L["Bitte Frage und Lösung eintragen (nur eine Frage gleichzeitig)."]) end
        end)
        win.officer[#win.officer + 1] = b
        win:SetScript("OnShow", function() win.offset = 0; Q.Refresh() end)
    end
    win:SetShown(not win:IsShown())
end

local slash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd, rest = strtrim(arg or ""):match("^(%S*)%s*(.*)$")
    if cmd:lower() ~= "quiz" then return slash(arg) end
    if rest ~= "" then Q.Answer(rest) else Q.Open() end
end
