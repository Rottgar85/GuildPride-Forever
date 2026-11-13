-- GuildPride: Raid-Aufstellung aus den Event-Anmeldungen
--
-- Links alle Zusagen (mit Rolle und Klasse), rechts 8 Gruppen à 5 Plätze.
-- Einteilen: Spieler ziehen und auf einen Platz fallen lassen – oder Spieler
-- anklicken und dann einen Platz anklicken. Ein belegter Platz tauscht.
-- "Automatisch": Tanks in Gruppe 1, Heiler verteilt, Rest auffüllen.
-- "Einladen" lädt alle Eingeteilten ein, "Gruppen ordnen" verschiebt sie im
-- Raid in ihre Gruppen (Raidleitung oder Assistent nötig).
-- Offiziere können die Aufstellung an die Gilde schicken (LAY): Mitglieder
-- sehen dann ihre Gruppe. Angenommen wird sie nur von Offizieren.
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP or "\031"

local GROUPS, SLOTS = 8, 5
local ROLE_ORDER = { TANK = 1, HEALER = 2, DAMAGER = 3 }
local ROLE_TEXT = { TANK = "|cff6fa8ffT|r", HEALER = "|cff40ff40H|r", DAMAGER = "|cffff6060D|r" }
local InviteToGroup = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
local ConvertToRaidFn = (C_PartyInfo and C_PartyInfo.ConvertToRaid) or ConvertToRaid

local win, ev, picked, dragging

local function CanManage() return CanEditMOTD and CanEditMOTD() end

-- Klasse aus der Gildenliste
local function ClassOf(name)
    for i = 1, GetNumGuildMembers() do
        local n, _, _, _, _, _, _, _, _, _, class = GetGuildRosterInfo(i)
        if type(n) == "string" and not (issecretvalue and issecretvalue(n)) and ns.Normalize(n) == name then return class end
    end
end

local function Colored(name)
    local c = RAID_CLASS_COLORS[ClassOf(name) or ""] or NORMAL_FONT_COLOR
    return ("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255, c.b * 255, Ambiguate(name, "guild"))
end

local function Layout()
    ev.layout = ev.layout or {}   -- [Name] = Gruppe * 10 + Platz
    return ev.layout
end

local function Attending()
    local list = {}
    for name, s in pairs(ev.signups or {}) do
        if s.s == "yes" then list[#list + 1] = { name = name, role = s.r or "DAMAGER" } end
    end
    table.sort(list, function(a, b)
        local ra, rb = ROLE_ORDER[a.role] or 4, ROLE_ORDER[b.role] or 4
        if ra ~= rb then return ra < rb end
        return a.name < b.name
    end)
    return list
end

local function WhoAt(pos)
    for name, p in pairs(Layout()) do if p == pos then return name end end
end

-- Spieler auf einen Platz; ist der belegt, tauschen beide
local function Place(name, pos)
    local lay = Layout()
    local other, from = WhoAt(pos), lay[name]
    lay[name] = pos
    if other and other ~= name then lay[other] = from end
end

local Refresh

---------------------------------------------------------------------
-- Aufbau
---------------------------------------------------------------------
local function NameButton(parent, w)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 18)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(1, 1, 1, 0.04)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 4, 0); b.text:SetPoint("RIGHT", -2, 0); b.text:SetJustifyH("LEFT"); b.text:SetWordWrap(false)
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Buttons\\WHITE8x8"); b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
    return b
end

local function SlotUnderCursor()
    for g = 1, GROUPS do
        for s = 1, SLOTS do
            local slot = win.slots[g * 10 + s]
            if slot:IsMouseOver() then return g * 10 + s end
        end
    end
end

local function StartDrag(name)
    if not CanManage() then return end
    dragging = name
    win.drag.text:SetText(Colored(name))
    win.drag:Show()
end

local function StopDrag()
    if not dragging then return end
    local pos = SlotUnderCursor()
    if pos then Place(dragging, pos)
    elseif win.list:IsMouseOver() then Layout()[dragging] = nil end   -- zurück in die Liste
    dragging = nil
    win.drag:Hide()
    Refresh()
end

local function Build()
    win = CreateFrame("Frame", "GuildPrideRosterFrame", UIParent, "BasicFrameTemplateWithInset")
    win:SetSize(780, 430)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true); win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    tinsert(UISpecialFrames, "GuildPrideRosterFrame")
    win.title = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    win.title:SetPoint("TOP", 0, -5)

    -- Liste der Zusagen
    local lt = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lt:SetPoint("TOPLEFT", 14, -30); lt:SetText(L["Zusagen (nicht eingeteilt)"])
    win.list = CreateFrame("Frame", nil, win)
    win.list:SetPoint("TOPLEFT", 12, -48); win.list:SetSize(150, 330)
    win.listBtns = {}

    -- Gruppen
    win.slots = {}
    for g = 1, GROUPS do
        local col, row = (g - 1) % 4, math.floor((g - 1) / 4)
        local x, y = 176 + col * 148, -30 - row * 160
        local h = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", x, y); h:SetText((L["Gruppe %d"]):format(g))
        for s = 1, SLOTS do
            local slot = NameButton(win, 140)
            slot:SetPoint("TOPLEFT", x, y - 16 - (s - 1) * 22)
            slot.bg:SetColorTexture(1, 1, 1, 0.06)
            local pos = g * 10 + s
            slot.pos = pos
            slot:SetScript("OnClick", function(self, button)
                if not CanManage() then return end
                local who = WhoAt(pos)
                if button == "RightButton" and who then Layout()[who] = nil; Refresh() return end
                if picked then Place(picked, pos); picked = nil
                elseif who then picked = who end
                Refresh()
            end)
            slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            slot:SetScript("OnDragStart", function() local who = WhoAt(pos); if who then StartDrag(who) end end)
            slot:SetScript("OnDragStop", StopDrag)
            win.slots[pos] = slot
        end
    end

    -- Gezogener Name folgt der Maus
    win.drag = CreateFrame("Frame", nil, UIParent)
    win.drag:SetSize(140, 18); win.drag:SetFrameStrata("TOOLTIP")
    win.drag.text = win.drag:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.drag.text:SetPoint("LEFT")
    win.drag:Hide()
    win.drag:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local sc = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / sc + 12, y / sc)
    end)

    -- Knöpfe unten
    local function Btn(label, w, x, fn)
        local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        b:SetSize(w, 22); b:SetPoint("BOTTOMLEFT", x, 12); b:SetText(label)
        b:SetScript("OnClick", fn)
        return b
    end
    win.bAuto = Btn(L["Automatisch"], 110, 176, function() ns.RosterAuto(); Refresh() end)
    win.bClear = Btn(L["Leeren"], 80, 292, function() wipe(Layout()); Refresh() end)
    win.bInvite = Btn(L["Eingeteilte einladen"], 150, 378, function() ns.RosterInvite() end)
    win.bSort = Btn(L["Gruppen ordnen"], 120, 534, function() ns.RosterSort() end)
    win.bShare = Btn(L["An Gilde senden"], 110, 660, function() ns.RosterShare() end)
    win.hint = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.hint:SetPoint("BOTTOMLEFT", 14, 40); win.hint:SetWidth(150); win.hint:SetJustifyH("LEFT")
    win.hint:SetText(L["Ziehen oder anklicken. Rechtsklick auf einen Platz: entfernen."])
end

Refresh = function()
    if not (win and win:IsShown() and ev) then return end
    win.title:SetText((L["Raid-Aufstellung: %s"]):format(ev.title or ""))
    local manage = CanManage()
    for _, b in ipairs({ win.bAuto, win.bClear, win.bInvite, win.bSort, win.bShare }) do b:SetShown(manage) end
    win.hint:SetShown(manage)
    local lay, list, n = Layout(), Attending(), 0
    local attending = {}
    for _, p in ipairs(list) do attending[p.name] = p end
    -- Abgemeldete aus der Aufstellung nehmen
    for name in pairs(lay) do if not attending[name] then lay[name] = nil end end
    for _, p in ipairs(list) do
        if not lay[p.name] then
            n = n + 1
            local b = win.listBtns[n]
            if not b then
                b = NameButton(win.list, 148)
                b:SetPoint("TOPLEFT", 0, -(n - 1) * 20)
                b:SetScript("OnClick", function(self) if CanManage() then picked = self.name; Refresh() end end)
                b:SetScript("OnDragStart", function(self) StartDrag(self.name) end)
                b:SetScript("OnDragStop", StopDrag)
                win.listBtns[n] = b
            end
            b.name = p.name
            b.text:SetText((ROLE_TEXT[p.role] or "") .. " " .. Colored(p.name))
            b.bg:SetColorTexture(1, 0.82, 0, picked == p.name and 0.3 or 0.04)
            b:SetShown(n <= 16)
        end
    end
    for i = n + 1, #win.listBtns do win.listBtns[i]:Hide() end
    for pos, slot in pairs(win.slots) do
        local who = WhoAt(pos)
        local role = who and attending[who] and attending[who].role
        slot.text:SetText(who and ((ROLE_TEXT[role] or "") .. " " .. Colored(who)) or "|cff555555–|r")
        slot.bg:SetColorTexture(1, 0.82, 0, who and picked == who and 0.3 or 0.06)
    end
end

---------------------------------------------------------------------
-- Aktionen
---------------------------------------------------------------------
-- Tanks nach vorn, Heiler auf die Gruppen verteilt, Rest auffüllen
function ns.RosterAuto()
    local lay = wipe(Layout())
    local list = Attending()
    local groupsUsed = math.max(1, math.ceil(#list / SLOTS))
    local fill = {}
    for g = 1, GROUPS do fill[g] = 0 end
    local function put(name, g)
        if fill[g] >= SLOTS then return false end
        fill[g] = fill[g] + 1
        lay[name] = g * 10 + fill[g]
        return true
    end
    local heal = 0
    for _, p in ipairs(list) do
        if p.role == "TANK" then
            if not put(p.name, 1) then for g = 2, GROUPS do if put(p.name, g) then break end end end
        elseif p.role == "HEALER" then
            heal = heal + 1
            local g = (heal - 1) % groupsUsed + 1
            if not put(p.name, g) then for x = 1, GROUPS do if put(p.name, x) then break end end end
        end
    end
    for _, p in ipairs(list) do
        if not lay[p.name] then for g = 1, GROUPS do if put(p.name, g) then break end end end
    end
end

function ns.RosterInvite()
    local names = {}
    for name in pairs(Layout()) do
        if name ~= ns.Me() and not UnitInParty(Ambiguate(name, "none")) then names[#names + 1] = name end
    end
    if #names == 0 then ns.Print(L["Keine weiteren Zusagen zum Einladen."]) return end
    table.sort(names)
    local first = IsInRaid() and #names or math.min(#names, 4)
    for i = 1, first do InviteToGroup(names[i]) end
    if first < #names then
        C_Timer.After(2, function()
            if not IsInRaid() and ConvertToRaidFn then ConvertToRaidFn() end
            C_Timer.After(1.5, function() for i = first + 1, #names do InviteToGroup(names[i]) end end)
        end)
    end
    ns.Print((L["%d Spieler eingeladen."]):format(#names))
end

-- Im Raid in die eingeteilten Gruppen schieben (mehrere Durchgänge, weil volle
-- Gruppen erst durch Tauschen frei werden)
function ns.RosterSort()
    if not IsInRaid() then ns.Print(L["Erst einen Raid bilden, dann ordnen."]) return end
    if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        ns.Print(L["Nur Raidleitung oder Assistenten können Gruppen ordnen."]) return
    end
    if InCombatLockdown() then return end
    local lay = Layout()
    for _ = 1, 3 do
        local index, groupOf = {}, {}
        for i = 1, GetNumGroupMembers() do
            local name, _, sub = GetRaidRosterInfo(i)
            if name then
                name = ns.Normalize(name)
                index[name], groupOf[i] = i, sub
            end
        end
        local moved = false
        for name, pos in pairs(lay) do
            local i, want = index[name], math.floor(pos / 10)
            if i and groupOf[i] ~= want then
                local count, swap = 0, nil
                for j = 1, GetNumGroupMembers() do
                    if groupOf[j] == want then
                        count = count + 1
                        local jn = GetRaidRosterInfo(j)
                        jn = jn and ns.Normalize(jn)
                        local jwant = jn and lay[jn] and math.floor(lay[jn] / 10)
                        if jwant ~= want then swap = j end
                    end
                end
                if count < 5 then pcall(SetRaidSubgroup, i, want); moved = true
                elseif swap then pcall(SwapRaidSubgroup, i, swap); moved = true end
            end
        end
        if not moved then break end
    end
    ns.Print(L["Gruppen geordnet."])
end

-- Aufstellung an die Gilde (nur Offiziere; Empfänger prüfen das)
function ns.RosterShare()
    if not CanManage() then return end
    local parts = {}
    for name, pos in pairs(Layout()) do parts[#parts + 1] = name .. "=" .. pos end
    ns.Queue("LAY", nil, ev.id, table.concat(parts, ";"))
    ns.Print(L["Aufstellung an die Gilde gesendet."])
end

ns.On("LAY", function(payload, sender)
    if sender == ns.Me() or not ns.IsOfficerName(sender) then return end
    local id, list = strsplit(SEP, payload)
    id = ns.Clean(id, 80)
    local e = ns.GuildTable("events")[id]
    if not e or not list then return end
    local lay, n = {}, 0
    for item in list:gmatch("[^;]+") do
        local name, pos = item:match("^([^=]+)=(%d%d)$")
        pos = tonumber(pos)
        n = n + 1
        if n > 40 then break end
        if name and pos and pos >= 11 and pos <= GROUPS * 10 + SLOTS and pos % 10 >= 1 and pos % 10 <= SLOTS then
            lay[ns.Clean(name, 60)] = pos
        end
    end
    e.layout = lay
    local mine = lay[ns.Me()]
    if mine then
        ns.Print((L["Raid-Aufstellung für %s: du bist in Gruppe %d."]):format(e.title or "", math.floor(mine / 10)))
    end
    Refresh()
end)

function ns.ShowRoster(e)
    if not e then return end
    if not win then Build() end
    ev, picked = e, nil
    win:Show()
    Refresh()
end
