-- GuildPride: Offene Dungeons – wer in der Gilde braucht noch welchen Dungeon oder Raid
-- (Quest, Ruf, Ausrüstung). Jeder hakt für seinen Charakter an, was er noch braucht; die Seite
-- „Offene Dungeons“ (unter „Planen“) zeigt je Instanz, wer sie braucht und wer davon online ist.
-- Die Gruppensuche schlägt diese Mitspieler beim eigenen Eintrag zuerst vor.
--   DND  ver · Liste   (Liste = "dm,sfk,r:ony"; Raids mit "r:")
--   DNQ  1             (Anfrage nach dem Einloggen; jeder antwortet mit seiner Liste)
-- Gespeichert: GuildPrideDB.myNeeds[Charakter] = { [key] = true } (key wie "dm" oder "r:ony"),
--              GuildTable("needs")[Name] = { ver, keys = { … } }
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP

local Needs = {}
ns.Needs = Needs
local Inst = ns.Instances
local MAX_KEYS = 40

local function Me() return ns.Me() end
local function DB() return ns.GuildTable("needs") end

-- Schlüssel einer Instanz: Dungeons "dm", Raids "r:ony"
function Needs.Key(inst) return (inst.kind == "raid" and "r:" or "") .. inst.key end
function Needs.Find(key)
    if type(key) ~= "string" then return nil end
    local raid = key:match("^r:(.+)$")
    if raid then return Inst.Find("raid", raid) end
    return Inst.Find("dungeon", key)
end

local function Mine()
    GuildPrideDB.myNeeds = type(GuildPrideDB.myNeeds) == "table" and GuildPrideDB.myNeeds or {}
    local me = Me()
    GuildPrideDB.myNeeds[me] = type(GuildPrideDB.myNeeds[me]) == "table" and GuildPrideDB.myNeeds[me] or {}
    return GuildPrideDB.myNeeds[me]
end
function Needs.IsMine(key) return Mine()[key] == true end

-- Liste als Text ("dm,sfk,r:ony") und zurück; nur bekannte Instanzen
function Needs.Encode(set)
    local keys = {}
    for k in pairs(set) do if Needs.Find(k) then keys[#keys + 1] = k end end
    table.sort(keys)
    return table.concat(keys, ",", 1, math.min(#keys, MAX_KEYS))
end
function Needs.Decode(text)
    local out = {}
    for k in tostring(text or ""):gmatch("[^,]+") do
        if Needs.Find(k) and #out < MAX_KEYS then out[#out + 1] = k end
    end
    return out
end

local function Send(target)
    if not IsInGuild() then return end
    local e = DB()[Me()]
    ns.Queue("DND", target, e and e.ver or GetServerTime(), Needs.Encode(Mine()))
end

local function Store(name, ver, keys)
    local db = DB()
    local old = db[name]
    if type(old) == "table" and (old.ver or 0) >= ver then return false end
    db[name] = { ver = ver, keys = keys }
    return true
end
Needs.Store = Store   -- für Tests

function Needs.Set(key, on)
    if not Needs.Find(key) then return false end
    Mine()[key] = on and true or nil
    local keys = {}
    for k in pairs(Mine()) do keys[#keys + 1] = k end
    table.sort(keys)
    Store(Me(), math.max(GetServerTime(), ((DB()[Me()] or {}).ver or 0) + 1), keys)
    Send()
    if Needs.Refresh then Needs.Refresh() end
    return true
end

ns.On("DND", function(payload, sender)
    if sender == Me() then return end
    local ver, list = strsplit(SEP, payload or "")
    ver = ns.Stamp(ver)
    if ver == 0 or not ns.IsGuildMember(sender) then return end
    if Store(sender, ver, Needs.Decode(list)) and Needs.Refresh then Needs.Refresh() end
end)
ns.On("DNQ", function(_, sender)
    if sender == Me() or not next(Mine()) then return end
    C_Timer.After(1 + math.random() * 6, function() Send() end)
end)

-- Online-Mitglieder: [Name] = { level, class }
local function Online()
    local on = {}
    if not (IsInGuild() and GetNumGuildMembers) then return on end
    for i = 1, GetNumGuildMembers() or 0 do
        local name, _, _, level, _, _, _, _, online, _, class = GetGuildRosterInfo(i)
        if name and online then on[ns.Normalize(name)] = { level = level, class = class } end
    end
    return on
end
Needs.Online = Online

-- Wer braucht diese Instanz: { { name, online, level, class } }, online zuerst
function Needs.Who(key, online)
    online = online or Online()
    local out, me = {}, Me()
    for name, e in pairs(DB()) do
        if type(e) == "table" and (name == me or ns.IsGuildMember(name)) then
            for _, k in ipairs(e.keys or {}) do
                if k == key then
                    local o = online[name]
                    out[#out + 1] = { name = name, online = o ~= nil or name == me, level = o and o.level, class = o and o.class }
                    break
                end
            end
        end
    end
    table.sort(out, function(a, b)
        if a.online ~= b.online then return a.online end
        return a.name < b.name
    end)
    return out
end

-- Alle Instanzen mit mindestens einem Interessenten: { { inst, key, who = { … }, online = n } }
function Needs.Overview()
    local online, list = Online(), {}
    for _, kind in ipairs({ "dungeon", "raid" }) do
        for _, inst in ipairs(Inst.list[kind]) do
            local key = Needs.Key(inst)
            local who = Needs.Who(key, online)
            if #who > 0 then
                local n = 0
                for _, w in ipairs(who) do if w.online then n = n + 1 end end
                list[#list + 1] = { inst = inst, key = key, who = who, online = n }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.online ~= b.online then return a.online > b.online end
        if #a.who ~= #b.who then return #a.who > #b.who end
        return a.inst.name < b.inst.name
    end)
    return list
end

-- Gruppen-Vorschläge: Online-Mitglieder ohne Gruppe, passend zur Stufe des Dungeons und zu den
-- fehlenden Rollen. Wer den Dungeon noch braucht, steht vorn.
-- dungeon = { name, min, max } (aus der Gruppensuche), roles = "TH" (fehlende Rollen) oder ""
local ROLE_CLASSES = {
    T = { WARRIOR = true, PALADIN = true, DRUID = true },
    H = { PRIEST = true, PALADIN = true, DRUID = true, SHAMAN = true },
}
function Needs.Suggest(dungeon, roles, max)
    local out, me = {}, Me()
    local inst = dungeon and Inst.ByZone(dungeon.name)
    local needers = {}
    if inst then for _, w in ipairs(Needs.Who(Needs.Key(inst))) do needers[w.name] = true end end
    local lo = dungeon and (tonumber(dungeon.min) or 0) or 0
    local hi = dungeon and (tonumber(dungeon.max) or 0) or 0
    if hi < lo then hi = lo end
    roles = roles or ""
    for name, o in pairs(Online()) do
        local short = Ambiguate(name, "none")
        local inGroup = UnitInParty and UnitInParty(short) or UnitInRaid and UnitInRaid(short)
        local lvl = tonumber(o.level) or 0
        local fits = lo == 0 or (lvl >= lo - 2 and (hi == 0 or lvl <= hi + 5))
        if name ~= me and not inGroup and fits then
            local role
            for r in roles:gmatch("[TH]") do if ROLE_CLASSES[r][o.class or ""] then role = r; break end end
            if roles == "" or role or roles:find("D", 1, true) then
                out[#out + 1] = { name = name, level = lvl, class = o.class, needs = needers[name] or false, role = role }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.needs ~= b.needs then return a.needs end
        if (a.role ~= nil) ~= (b.role ~= nil) then return a.role ~= nil end
        return a.name < b.name
    end)
    for i = #out, (max or 8) + 1, -1 do out[i] = nil end
    return out
end

function Needs.SuggestText(list)
    local parts = {}
    for _, s in ipairs(list) do
        parts[#parts + 1] = Ambiguate(s.name, "guild") .. " (" .. s.level
            .. (s.role == "T" and (", Tank") or s.role == "H" and (", " .. L["Heiler"]) or "")
            .. (s.needs and (", " .. L["braucht ihn"]) or "") .. ")"
    end
    return table.concat(parts, ", ")
end

local function ClassHex(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return c and c.colorStr and c.colorStr:sub(3) or "f0c88c"
end
function Needs.NamesText(who)
    local parts = {}
    for _, w in ipairs(who) do
        local n = Ambiguate(w.name, "guild")
        parts[#parts + 1] = w.online and ("|cff" .. ClassHex(w.class) .. n .. "|r") or ("|cff777777" .. n .. "|r")
    end
    return table.concat(parts, ", ")
end

-- Nach dem Einloggen: eigene Liste schicken und die der anderen anfragen
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    C_Timer.After(30, function()
        if not IsInGuild() then return end
        if next(Mine()) then Send() end
        ns.Queue("DNQ", nil, "1")
    end)
end)

---------------------------------------------------------------------
-- Seite „Offene Dungeons“ (unter „Planen“)
---------------------------------------------------------------------
if not ns.AddTab then return end
local page = ns.AddTab(L["Offene Dungeons"], 57)

local bMine = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
bMine:SetSize(200, 24); bMine:SetPoint("TOPLEFT", 4, -4); bMine:SetText(L["Was ich noch brauche …"])
local info = page:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
info:SetPoint("LEFT", bMine, "RIGHT", 12, 0); info:SetWidth(400); info:SetJustifyH("LEFT")
info:SetText(L["Wer in der Gilde welchen Dungeon noch braucht (nur Mitglieder mit GuildPride). Klick auf eine Zeile lädt alle ein, die online sind."])

local holder = CreateFrame("Frame", nil, page)
holder:SetPoint("TOPLEFT", 0, -36); holder:SetPoint("BOTTOMRIGHT")
local list = ns.CreateList(holder, 24)
local empty = holder:CreateFontString(nil, "OVERLAY", "GPFont_Muted")
empty:SetPoint("TOP", 0, -60); empty:SetWidth(560)
empty:SetText(L["Noch niemand hat offene Dungeons eingetragen. Fang mit „Was ich noch brauche …“ an."])

local function InviteOnline(entry)
    local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    if not invite then return end
    local me, n = Me(), 0
    for _, w in ipairs(entry.who) do
        local short = Ambiguate(w.name, "none")
        if w.online and w.name ~= me and not (UnitInParty and UnitInParty(short)) then
            pcall(invite, short); n = n + 1
        end
    end
    ns.Print((L["%s: %d Einladungen verschickt."]):format(entry.inst.name, n))
end

function page:Refresh()
    local data = Needs.Overview()
    for i, e in ipairs(data) do
        local row = list:GetRow(i)
        row.left:SetText(("%s |cff999999(%s)|r"):format(e.inst.name, e.inst.level or ""))
        row.mid:ClearAllPoints(); row.mid:SetPoint("LEFT", 260, 0); row.mid:SetWidth(280)
        row.mid:SetJustifyH("LEFT"); row.mid:SetWordWrap(false)
        row.mid:SetText(Needs.NamesText(e.who))
        row.right:SetText(e.online > 0 and ("|cff40ff40" .. (L["%d online"]):format(e.online) .. "|r") or L["offline"])
        row:EnableMouse(true)
        row:SetScript("OnMouseUp", function() if e.online > 0 then InviteOnline(e) end end)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(e.inst.name, 1, 1, 1)
            for _, w in ipairs(e.who) do
                GameTooltip:AddLine(Ambiguate(w.name, "guild") .. (w.level and (" (" .. w.level .. ")") or ""),
                    w.online and 0.4 or 0.5, w.online and 1 or 0.5, w.online and 0.4 or 0.5)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
    end
    list:Finish(#data)
    empty:SetShown(#data == 0)
end
Needs.Refresh = function() if page:IsVisible() then page:Refresh() end end

-- Auswahl der eigenen offenen Instanzen
local pick
local PICK_ROWS = 16
local function PickList()
    local out = {}
    for _, kind in ipairs({ "dungeon", "raid" }) do
        for _, inst in ipairs(Inst.list[kind]) do out[#out + 1] = inst end
    end
    return out
end
local function RefreshPick()
    local all = PickList()
    pick.offset = math.max(0, math.min(pick.offset or 0, #all - PICK_ROWS))
    for i = 1, PICK_ROWS do
        local r, inst = pick.rows[i], all[i + pick.offset]
        r:SetShown(inst ~= nil)
        if inst then
            r.key = Needs.Key(inst)
            r.check:SetChecked(Needs.IsMine(r.key))
            r.label:SetText(inst.name .. (" |cff999999(%s%s)|r"):format(inst.kind == "raid" and "Raid, " or "", inst.level or ""))
        end
    end
end
local function OpenPick()
    if not pick then
        pick = CreateFrame("Frame", "GuildPrideNeedsPick", UIParent, "BackdropTemplate")
        pick:SetSize(320, 90 + PICK_ROWS * 22)
        pick:SetPoint("CENTER", 0, 40)
        pick:SetFrameStrata("DIALOG")
        pick:SetMovable(true); pick:EnableMouse(true); pick:SetClampedToScreen(true)
        pick:RegisterForDrag("LeftButton")
        pick:SetScript("OnDragStart", pick.StartMoving)
        pick:SetScript("OnDragStop", pick.StopMovingOrSizing)
        if ns.SkinDialog then ns.SkinDialog(pick) end
        tinsert(UISpecialFrames, "GuildPrideNeedsPick")
        local close = CreateFrame("Button", nil, pick, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -6, -6)
        if ns.SkinClose then ns.SkinClose(close) end
        close:SetScript("OnClick", function() pick:Hide() end)
        local title = pick:CreateFontString(nil, "OVERLAY", "GPFont_Large")
        title:SetPoint("TOPLEFT", 14, -12); title:SetText(L["Was ich noch brauche"])
        if ns.Paint then ns.Paint(title, "heading") end
        local sub = pick:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
        sub:SetPoint("TOPLEFT", 14, -34); sub:SetPoint("RIGHT", -14, 0); sub:SetJustifyH("LEFT")
        sub:SetText(L["Gilt für diesen Charakter. Die Gilde sieht es sofort."])
        pick.rows = {}
        for i = 1, PICK_ROWS do
            local r = CreateFrame("Button", nil, pick)
            r:SetSize(292, 22)
            r:SetPoint("TOPLEFT", 12, -50 - (i - 1) * 22)
            if ns.Paint and i % 2 == 0 then ns.Paint(r:CreateTexture(nil, "BACKGROUND"), "glow", 0.05):SetAllPoints() end
            r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
            r.check:SetSize(20, 20); r.check:SetPoint("LEFT", 0, 0)
            r.check:SetScript("OnClick", function(cb) Needs.Set(r.key, cb:GetChecked()) end)
            r.label = r:CreateFontString(nil, "OVERLAY", "GPFont_Text")
            r.label:SetPoint("LEFT", 24, 0); r.label:SetPoint("RIGHT", -2, 0)
            r.label:SetJustifyH("LEFT"); r.label:SetWordWrap(false)
            r:SetScript("OnClick", function() Needs.Set(r.key, not Needs.IsMine(r.key)); RefreshPick() end)
            pick.rows[i] = r
        end
        pick:EnableMouseWheel(true)
        pick:SetScript("OnMouseWheel", function(_, delta) pick.offset = (pick.offset or 0) - delta * 3; RefreshPick() end)
        local done = CreateFrame("Button", nil, pick, "UIPanelButtonTemplate")
        if ns.SkinButton then ns.SkinButton(done) end
        done:SetSize(100, 22); done:SetPoint("BOTTOMRIGHT", -14, 12); done:SetText(OKAY or "OK")
        done:SetScript("OnClick", function() pick:Hide() end)
    end
    pick.offset = 0
    pick:Show()
    RefreshPick()
end
bMine:SetScript("OnClick", function() if pick and pick:IsShown() then pick:Hide() else OpenPick() end end)
