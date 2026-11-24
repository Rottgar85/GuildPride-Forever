-- GuildPride: Schnitzeljagd
-- Ein Offizier legt Stationen an: an die Stelle gehen, Hinweis eintippen (/gp jagd neu <Hinweis>),
-- dann /gp jagd start. Alle bekommen den ersten Hinweis; wer bis auf 30 Meter an die Station kommt,
-- erhält den nächsten. Wer fertig ist, meldet sich der Gilde. Die Orte stehen in den Daten der
-- Mitspieler – ein Spiel auf Ehrenwort.
--   HNT  id · nr · anzahl · karte · x · y (je 0–10000) · hinweis   (nur Offiziere)
--   HNX  id          beendet (nur Offiziere)
--   HNF  id          Absender hat alle Stationen
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP

local H = {}
ns.Hunt = H
local MAX_STATIONS, HINT_MAX, REACH = 10, 120, 30

H.draft = {}        -- eigene Stationen vor dem Start
H.cur = nil         -- { id, n, st = { [i] = { map, x, y, hint } }, at = nächste Station, done = { [Name] = true } }

local function Me() return ns.Me() end
local function CanManage() return CanEditMOTD and CanEditMOTD() and true or false end
local function Clean(s, max) return strtrim((tostring(s or ""):gsub("[%c|]", " "))):sub(1, max) end
local function Say(text) ns.Print("|cffffd100" .. L["Schnitzeljagd:"] .. "|r " .. text) end

local function ShowHint()
    local c = H.cur
    local s = c and c.st[c.at]
    if s then Say((L["Station %d von %d: %s"]):format(c.at, c.n, s.hint)) end
end
local function Complete() for i = 1, H.cur.n do if not H.cur.st[i] then return false end end return true end

ns.On("HNT", function(payload, sender)
    if sender == Me() or not ns.IsOfficerName(sender) then return end
    local a = { strsplit(SEP, payload) }
    local id, i, n = Clean(a[1], 60), tonumber(a[2]), tonumber(a[3])
    local map, x, y, hint = tonumber(a[4]), tonumber(a[5]), tonumber(a[6]), Clean(a[7], HINT_MAX)
    if id == "" or not i or not n or n < 1 or n > MAX_STATIONS or i < 1 or i > n or i % 1 ~= 0 or n % 1 ~= 0 then return end
    if not map or not x or not y or x < 0 or x > 10000 or y < 0 or y > 10000 or hint == "" then return end
    if not H.cur or H.cur.id ~= id then H.cur = { id = id, n = n, st = {}, at = 1, done = {}, by = sender } end
    if H.cur.n ~= n then return end
    H.cur.st[i] = { map = map, x = x / 10000, y = y / 10000, hint = hint }
    if Complete() and not H.cur.told then
        H.cur.told = true
        Say((L["%s startet eine Schnitzeljagd mit %d Stationen!"]):format(Ambiguate(sender, "guild"), n))
        ShowHint()
    end
end)
ns.On("HNX", function(payload, sender)
    if sender == Me() or not ns.IsOfficerName(sender) or not H.cur or H.cur.id ~= payload then return end
    H.cur = nil
    Say(L["beendet."])
end)
ns.On("HNF", function(payload, sender)
    if not H.cur or H.cur.id ~= payload or H.cur.done[sender] or not ns.IsGuildMember(sender) then return end
    H.cur.done[sender] = true
    local place = 0
    for _ in pairs(H.cur.done) do place = place + 1 end
    if sender ~= Me() then Say((L["%s hat alle Stationen gefunden (Platz %d)."]):format(Ambiguate(sender, "guild"), place)) end
end)

-- Station erreicht? Wird alle 2 s geprüft, nur wenn eine Jagd läuft
function H.Check()
    local c = H.cur
    if not c or not c.told or c.at > c.n then return end
    local s = c.st[c.at]
    local d = ns.Zettel and ns.Zettel.Distance and ns.Zettel.Distance(s)
    if not d or d > REACH then return end
    c.at = c.at + 1
    if GuildPrideDB.sound then PlaySound(SOUNDKIT.READY_CHECK) end
    if c.at <= c.n then ShowHint() return end
    Say(L["Geschafft! Du hast alle Stationen gefunden."])
    c.done[Me()] = true
    ns.Queue("HNF", "@CHANNEL", c.id)
end
ns.Every(2, function() if H.cur then H.Check() end end)

-- Offiziere
function H.AddStation(hint)
    hint = Clean(hint, HINT_MAX)
    if not CanManage() or hint == "" or #H.draft >= MAX_STATIONS then return false end
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local pos = map and C_Map.GetPlayerMapPosition(map, "player")
    if not pos then return false end
    local x, y = pos:GetXY()
    if not x or (x == 0 and y == 0) then return false end
    H.draft[#H.draft + 1] = { map = map, x = x, y = y, hint = hint }
    return true
end
function H.Start()
    if not CanManage() or #H.draft == 0 then return false end
    local id = Me() .. "-" .. GetServerTime()
    for i, s in ipairs(H.draft) do
        ns.Queue("HNT", nil, id, i, #H.draft, s.map, math.floor(s.x * 10000 + 0.5), math.floor(s.y * 10000 + 0.5), s.hint)
    end
    H.cur = { id = id, n = #H.draft, st = H.draft, at = #H.draft + 1, done = {}, told = true }   -- der Starter spielt nicht mit
    H.draft = {}
    return true
end
function H.Stop()
    if not CanManage() or not H.cur then return false end
    ns.Queue("HNX", nil, H.cur.id)
    H.cur = nil
    return true
end

-- Fenster (/gp jagd): Stand, für Offiziere Stationen anlegen, starten, beenden
local win
function H.Refresh()
    if not win or not win:IsShown() then return end
    local lines, c = {}, H.cur
    if c then
        if c.at <= c.n then lines[#lines + 1] = (L["Station %d von %d: %s"]):format(c.at, c.n, c.st[c.at] and c.st[c.at].hint or "?")
        else lines[#lines + 1] = L["Läuft gerade."] end
        for name in pairs(c.done) do lines[#lines + 1] = "   |cff40ff40" .. Ambiguate(name, "guild") .. "|r" end
    end
    if CanManage() then
        for i, s in ipairs(H.draft) do lines[#lines + 1] = ("|cff999999%d.|r %s"):format(i, s.hint) end
    end
    win:SetLines(lines)
    for _, f in ipairs(win.officer) do f:SetShown(CanManage()) end
end
function H.Open()
    if not win then
        win = ns.ListWindow({ name = "GuildPrideHunt", title = L["Schnitzeljagd"], rows = 10, width = 460, extra = 80,
            sub = L["Offiziere: an die Stelle gehen, Hinweis eintippen, Station anlegen. Am Ende starten."], empty = L["Es läuft keine."] })
        win.officer = {}
        local e = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
        e:SetSize(410, 22); e:SetPoint("BOTTOMLEFT", 20, 44); e:SetAutoFocus(false); e:SetMaxLetters(HINT_MAX)
        if ns.SkinEditBox then ns.SkinEditBox(e) end
        e:SetScript("OnEscapePressed", e.ClearFocus)
        win.officer[1] = e
        local function Button(label, w, x, fn)
            local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
            if ns.SkinButton then ns.SkinButton(b) end
            b:SetSize(w, 22); b:SetPoint("BOTTOMLEFT", x, 14); b:SetText(label)
            b:SetScript("OnClick", function() fn(); H.Refresh() end)
            win.officer[#win.officer + 1] = b
        end
        Button(L["Station hier anlegen"], 170, 14, function()
            if H.AddStation(e:GetText()) then e:SetText("") else Say(L["Hinweis fehlt oder hier gibt es keine Kartenposition."]) end
        end)
        Button(L["Start"], 80, 190, function() if not H.Start() then Say(L["Erst Stationen anlegen: /gp jagd neu <Hinweis>"]) end end)
        Button(L["Beenden"], 90, 276, function() H.Stop() end)
        Button(L["Leeren"], 80, 372, function() H.draft = {} end)
        win:SetScript("OnShow", function() win.offset = 0; H.Refresh() end)
        ns.Every(3, function() if win:IsShown() then H.Refresh() end end)
    end
    win:SetShown(not win:IsShown())
end

local slash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local raw = strtrim(arg or "")
    local cmd, sub = raw:match("^(%S*)%s*(.*)$")
    if cmd:lower() ~= "jagd" and cmd:lower() ~= "hunt" then return slash(arg) end
    local what, rest = sub:match("^(%S*)%s*(.*)$")
    what = what:lower()
    if what == "neu" or what == "new" then
        if H.AddStation(rest) then Say((L["Station %d gespeichert. Weiter zur nächsten, dann /gp jagd start."]):format(#H.draft))
        else Say(L["Nur Offiziere, mit Hinweis und an einem Ort mit Kartenposition: /gp jagd neu <Hinweis>"]) end
    elseif what == "start" then
        Say(H.Start() and L["gestartet."] or L["Erst Stationen anlegen: /gp jagd neu <Hinweis>"])
    elseif what == "ende" or what == "stop" then
        Say(H.Stop() and L["beendet."] or L["Es läuft keine."])
    else
        if H.cur then ShowHint() end
        H.Open()
    end
end
