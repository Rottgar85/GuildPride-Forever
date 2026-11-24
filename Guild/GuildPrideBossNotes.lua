-- GuildPride: Boss-Notizen
-- Offiziere schreiben je Boss eine kurze Taktik; beim Betreten der Instanz geht das Fenster
-- einmal auf (abschaltbar: bossNotes), sonst /gp boss.
--   BOS  id · ver · autor · gelöscht (0/1) · instanz ("dm", "r:ony") · boss · text
--   BOQ  stand   Anfrage nach dem Einloggen mit Prüfwert; es antwortet nur, wer einen anderen Stand
--                hat, Offiziere zuerst, andere nur, wenn sie noch keine Antwort gehört haben (ns.SyncAnswer)
-- Von Offizieren sofort, über andere Mitglieder erst bei zwei gleichen Meldungen.
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP

local B = {}
ns.BossNotes = B
local Inst = ns.Instances
local MAX_NOTES, BOSS_MAX, TEXT_MAX = 120, 40, 600
B.TEMPLATE = L["Tank: \nHeiler: \nSchaden: \nAchtung: "]
-- Zeilen stehen in den Daten als „ // “
function B.Show(text) return (tostring(text or ""):gsub(" // ", "\n")) end
function B.Pack(text) return (tostring(text or ""):gsub("%s*[\r\n]+%s*", " // ")) end

local function DB() return ns.GuildTable("bossnotes") end
local function Me() return ns.Me() end
local function Now() return GetServerTime() end
local function CanManage() return CanEditMOTD and CanEditMOTD() and true or false end
B.CanManage = CanManage
local function Clean(s, max) return strtrim((tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[%c|]", " "))):sub(1, max) end

-- Schlüssel einer Instanz wie bei „Offene Dungeons“: Dungeons "dm", Raids "r:ony"
local function Key(inst) return (inst.kind == "raid" and "r:" or "") .. inst.key end
local function Find(key)
    if type(key) ~= "string" then return nil end
    local raid = key:match("^r:(.+)$")
    if raid then return Inst.Find("raid", raid) end
    return Inst.Find("dungeon", key)
end
B.Key, B.Find = Key, Find

function B.Count()
    local n = 0
    for _, e in pairs(DB()) do if not e.deleted then n = n + 1 end end
    return n
end

function B.For(key)
    local list = {}
    for _, e in pairs(DB()) do if not e.deleted and e.inst == key then list[#list + 1] = e end end
    table.sort(list, function(a, b)
        if a.boss ~= b.boss then return a.boss < b.boss end
        return a.id < b.id
    end)
    return list
end

-- Instanz, in der du gerade bist
function B.Here()
    if not GetInstanceInfo then return nil end
    local name, kind = GetInstanceInfo()
    if issecretvalue and (issecretvalue(name) or issecretvalue(kind)) then return nil end
    if kind ~= "party" and kind ~= "raid" then return nil end
    local inst = Inst.ByZone(name)
    return inst and Key(inst) or nil
end

---------------------------------------------------------------------
-- Senden / Anwenden
---------------------------------------------------------------------
local function Send(e, target)
    ns.Queue("BOS", target, e.id, e.ver, e.author, e.deleted and 1 or 0, e.inst, e.boss, e.text)
end
local function Apply(id, ver, author, deleted, inst, boss, text)
    local e = DB()[id]
    if e and ver <= e.ver then return false end
    if not e and (deleted or B.Count() >= MAX_NOTES) then return false end
    DB()[id] = { id = id, ver = ver, author = author, deleted = deleted or nil, inst = inst, boss = boss, text = text }
    if B.Refresh then B.Refresh() end
    return true
end

ns.On("BOS", function(payload, sender)
    if sender == Me() then return end
    ns.SyncHeard("BOS", sender)
    local a = { strsplit(SEP, payload) }
    local id, ver, author = Clean(a[1], 80), ns.Stamp(a[2]), Clean(a[3], 60)
    if ver == 0 or author == "" or id:match("^(.+)%-%d+%-%d+$") ~= author or not ns.IsOfficerName(author) then return end
    if not ns.IsOfficerName(sender) and not ns.Confirmed("BOS\030" .. payload, sender) then return end
    local boss, text = Clean(a[6], BOSS_MAX), Clean(a[7], TEXT_MAX)
    if not Find(a[5]) or boss == "" or (text == "" and a[4] ~= "1") then return end
    Apply(id, ver, author, a[4] == "1", a[5], boss, text)
end)
ns.On("BOQ", function(payload, sender)
    if sender == Me() or payload == ns.SyncHash(DB()) then return end
    ns.SyncAnswer("BOS", function() for _, e in pairs(DB()) do Send(e, sender) end end)
end)

---------------------------------------------------------------------
-- Aktionen (nur Offiziere)
---------------------------------------------------------------------
-- id = nil: neue Notiz. Rückgabe: true oder false
function B.Save(id, inst, boss, text)
    boss, text = Clean(boss, BOSS_MAX), Clean(B.Pack(text), TEXT_MAX)
    if not CanManage() or not Find(inst) or boss == "" or text == "" then return false end
    local old = id and DB()[id]
    if not old then id = Me() .. "-" .. Now() .. "-" .. math.random(1000, 9999) end
    local author = old and old.author or Me()
    if not Apply(id, math.max(Now(), ((old and old.ver) or 0) + 1), author, false, inst, boss, text) then return false end
    Send(DB()[id])
    return true
end
function B.Delete(id)
    local e = DB()[id]
    if not CanManage() or not e then return false end
    Apply(id, math.max(Now(), e.ver + 1), e.author, true, e.inst, e.boss, e.text)
    Send(DB()[id])
    return true
end

---------------------------------------------------------------------
-- Fenster
---------------------------------------------------------------------
local win, instKey, selected
local function AllInst()
    local out = {}
    for _, kind in ipairs({ "raid", "dungeon" }) do for _, x in ipairs(Inst.list[kind]) do out[#out + 1] = x end end
    return out
end
local function Step(dir)
    local all, at = AllInst(), 1
    for i, x in ipairs(all) do if Key(x) == instKey then at = i end end
    instKey = Key(all[(at - 1 + dir) % #all + 1])
    selected = nil
    B.Refresh()
end

function B.Refresh()
    if not win or not win:IsShown() then return end
    local inst = Find(instKey)
    win.title:SetText(L["Boss-Notizen"] .. (inst and (": " .. inst.name) or ""))
    win.list = B.For(instKey)
    local lines, cur = {}, nil
    for _, e in ipairs(win.list) do
        if e.id == selected then cur = e end
        lines[#lines + 1] = (e.id == selected and "|cffffd100" or "|cffe6e0da") .. e.boss .. "|r  |cff888888" .. e.text .. "|r"
    end
    if not cur and win.list[1] then cur = win.list[1]; selected = cur.id; lines[1] = "|cffffd100" .. cur.boss .. "|r  |cff888888" .. cur.text .. "|r" end
    win:SetLines(lines)
    win.body:SetText(cur and ("|cffffd100" .. cur.boss .. "|r\n" .. B.Show(cur.text) .. "\n|cff888888" .. Ambiguate(cur.author, "guild") .. "|r") or "")
    local edit = CanManage()
    for _, f in ipairs(win.edit) do f:SetShown(edit) end
    win.del:SetEnabled(cur ~= nil)
end

local function Fill(e)
    win.boss:SetText(e and e.boss or "")
    win.text:SetText(e and B.Show(e.text) or "")
    win.editing = e and e.id or nil
end

local function Build()
    win = ns.ListWindow({ name = "GuildPrideBossNotes", title = L["Boss-Notizen"], rows = 7, width = 560, extra = 330,
        sub = L["Klick auf einen Boss zeigt die ganze Notiz. Offiziere schreiben unten."],
        empty = L["Für diese Instanz gibt es noch keine Notizen."] })
    for i, row in ipairs(win.rows) do
        row:EnableMouse(true)
        row:SetScript("OnMouseUp", function()
            local e = win.list and win.list[i + win.offset]
            if e then selected = e.id; Fill(e); B.Refresh() end
        end)
    end
    win.body = win:CreateFontString(nil, "OVERLAY", "GPFont_Text")
    win.body:SetPoint("TOPLEFT", 14, win.bottomY); win.body:SetWidth(530)
    win.body:SetJustifyH("LEFT"); win.body:SetJustifyV("TOP")
    win.edit = {}
    local function Button(label, w, x, y, fn, always)
        local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        if ns.SkinButton then ns.SkinButton(b) end
        b:SetSize(w, 22); b:SetPoint("BOTTOMLEFT", x, y); b:SetText(label)
        b:SetScript("OnClick", fn)
        if not always then win.edit[#win.edit + 1] = b end
        return b
    end
    local function Box(w, x, y, max, hintText)
        local e = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
        e:SetSize(w, 22); e:SetPoint("BOTTOMLEFT", x, y); e:SetAutoFocus(false); e:SetMaxLetters(max)
        if ns.SkinEditBox then ns.SkinEditBox(e) end
        local hint = e:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
        hint:SetPoint("LEFT", 2, 0); hint:SetText(hintText)
        e:SetScript("OnTextChanged", function(self) hint:SetShown(self:GetText() == "") end)
        e:SetScript("OnEscapePressed", e.ClearFocus)
        win.edit[#win.edit + 1] = e
        return e
    end
    win.boss = Box(160, 20, 118, BOSS_MAX, L["Boss"])
    -- Taktik über mehrere Zeilen
    local holder = CreateFrame("Frame", nil, win, "BackdropTemplate")
    holder:SetPoint("BOTTOMLEFT", 192, 44); holder:SetSize(350, 98)
    local hb = holder:CreateTexture(nil, "BACKGROUND")
    hb:SetAllPoints(); hb:SetColorTexture(0, 0, 0, 0.35)
    win.text = CreateFrame("EditBox", nil, holder)
    win.text:SetPoint("TOPLEFT", 6, -6); win.text:SetPoint("BOTTOMRIGHT", -6, 6)
    win.text:SetMultiLine(true); win.text:SetAutoFocus(false); win.text:SetMaxLetters(TEXT_MAX)
    win.text:SetFontObject(GPFont_Text)
    win.text:SetScript("OnEscapePressed", win.text.ClearFocus)
    holder:EnableMouse(true)
    holder:SetScript("OnMouseDown", function() win.text:SetFocus() end)
    win.edit[#win.edit + 1] = holder
    Button(L["Vorlage"], 110, 20, 88, function() if win.text:GetText() == "" then win.text:SetText(B.TEMPLATE) end; win.text:SetFocus() end)
    Button("<", 30, 14, 14, function() Step(-1) end, true)
    Button(">", 30, 48, 14, function() Step(1) end, true)
    Button(L["Speichern"], 110, 194, 14, function()
        if B.Save(win.editing, instKey, win.boss:GetText(), win.text:GetText()) then Fill(nil); B.Refresh()
        else ns.Print(L["Bitte Boss und Taktik eintragen."]) end
    end)
    Button(L["Neu"], 80, 310, 14, function() Fill(nil) end)
    win.del = Button(L["Löschen"], 90, 396, 14, function() if selected and B.Delete(selected) then selected = nil; Fill(nil); B.Refresh() end end)
    win:SetScript("OnShow", function() win.offset = 0; B.Refresh() end)
end

function B.Open(key)
    if not win then Build() end
    instKey = key or B.Here() or instKey or Key(AllInst()[1])
    selected = nil
    win:Show()
    Fill(nil)
    B.Refresh()
end

local shown = {}
local function OnEnter()
    if type(GuildPrideDB) ~= "table" or GuildPrideDB.bossNotes == false or not IsInGuild() then return end
    local key = B.Here()
    if not key or shown[key] or #B.For(key) == 0 then return end
    if InCombatLockdown() then return end
    shown[key] = true
    B.Open(key)
end

local ev, asked = CreateFrame("Frame"), false
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function()
    if not asked then
        asked = true
        C_Timer.After(44 + math.random() * 30, function()
            if not IsInGuild() then return end
            ns.PruneDeleted(DB())
            ns.Queue("BOQ", nil, ns.SyncHash(DB()))
        end)
    end
    C_Timer.After(5, OnEnter)
end)

ns.Command({ "boss", "bosse", "bosses" }, function() B.Open() end)
