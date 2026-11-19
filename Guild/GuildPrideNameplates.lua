-- GuildPride: eigene Farben für Namensplaketten
-- Jeder Spieler färbt die Namensplaketten über den Köpfen anderer Spieler für
-- sich selbst ein (nur lokal, wird mit niemandem geteilt):
--   * eine Farbe für alle Gildenmitglieder (optional)
--   * eine eigene Farbe je Spieler (geht vor)
--   * optional auch den Lebensbalken färben
-- Gespeichert in GuildPrideDB.plateColorMap["Name-Realm"] = { r, g, b }
-- und GuildPrideDB.plateGuildColor = { r, g, b } (nil = aus).
-- Blizzards Plaketten werden nur nachträglich eingefärbt (hooksecurefunc),
-- gesperrte Plaketten (z. B. befreundete in Instanzen) werden nicht angefasst.
local ADDON, ns = ...
local L = ns.L

local Plates = {}
ns.Plates = Plates

local function DB()
    GuildPrideDB.plateColorMap = GuildPrideDB.plateColorMap or {}
    return GuildPrideDB.plateColorMap
end
local function On() return GuildPrideDB and GuildPrideDB.plateColors ~= false end

-- Gleiche Namensform wie ns.Me() (Forever: Vor- und Nachname)
local function UnitKey(unit)
    if not unit or not UnitIsPlayer(unit) then return nil end
    local name, realm = UnitFullName(unit)
    if not name or name == "" then return nil end
    return ns.Normalize((realm and realm ~= "") and (name .. "-" .. realm) or name)
end
Plates.UnitKey = UnitKey

-- Farbe für eine Person: eigene Farbe, sonst Gildenfarbe (nur Mitglieder)
local function ColorFor(key)
    if not key then return nil end
    local c = DB()[key]
    if c then return c end
    local g = GuildPrideDB.plateGuildColor
    if g and ns.IsGuildMember(key) then return g end
    return nil
end
Plates.ColorFor = ColorFor

local function IsPlate(frame)
    if not frame or not frame.unit or frame:IsForbidden() then return false end
    return frame.unit:find("^nameplate") ~= nil
end

local function PaintName(frame)
    if not On() or not IsPlate(frame) or not frame.name then return end
    local c = ColorFor(UnitKey(frame.unit))
    if c then frame.name:SetTextColor(c[1], c[2], c[3]) end
end

local function PaintBar(frame)
    if not On() or not GuildPrideDB.plateColorBar or not IsPlate(frame) or not frame.healthBar then return end
    local c = ColorFor(UnitKey(frame.unit))
    if c then frame.healthBar:SetStatusBarColor(c[1], c[2], c[3]) end
end

local function Paint(frame) PaintName(frame); PaintBar(frame) end

if CompactUnitFrame_UpdateName then hooksecurefunc("CompactUnitFrame_UpdateName", PaintName) end
if CompactUnitFrame_UpdateHealthColor then hooksecurefunc("CompactUnitFrame_UpdateHealthColor", PaintBar) end

-- Alle sichtbaren Plaketten neu zeichnen (nach einer Änderung)
function Plates.RefreshAll()
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local f = plate.UnitFrame
        if f and not f:IsForbidden() then
            -- erst Blizzards Farbe wiederherstellen (falls Farbe entfernt), dann eigene
            if CompactUnitFrame_UpdateName then pcall(CompactUnitFrame_UpdateName, f) end
            if CompactUnitFrame_UpdateHealthColor then pcall(CompactUnitFrame_UpdateHealthColor, f) end
            Paint(f)
        end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("NAME_PLATE_UNIT_ADDED")
ev:SetScript("OnEvent", function(_, _, unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if plate and plate.UnitFrame then Paint(plate.UnitFrame) end
end)

---------------------------------------------------------------------
-- Farbe setzen / entfernen
---------------------------------------------------------------------
function Plates.Set(key, r, g, b)
    if not key then return end
    DB()[key] = r and { r, g, b } or nil
    Plates.RefreshAll()
    if Plates.RefreshWindow then Plates.RefreshWindow() end
end

-- Blizzards Farbwähler (neue und alte Schnittstelle)
local function PickColor(start, onPick)
    local r, g, b = start and start[1] or 1, start and start[2] or 1, start and start[3] or 1
    local function cur() return ColorPickerFrame:GetColorRGB() end
    local function apply() onPick(cur()) end
    local function cancel(prev)
        if type(prev) == "table" then onPick(prev.r or prev[1], prev.g or prev[2], prev.b or prev[3])
        else onPick(r, g, b) end
    end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = apply, cancelFunc = cancel })
    else
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.previousValues = { r, g, b }
        ColorPickerFrame.func, ColorPickerFrame.cancelFunc = apply, cancel
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide(); ColorPickerFrame:Show()
    end
end
Plates.PickColor = PickColor

function Plates.PickFor(key)
    if not key then return end
    PickColor(DB()[key] or GuildPrideDB.plateGuildColor, function(r, g, b) Plates.Set(key, r, g, b) end)
end

---------------------------------------------------------------------
-- Fenster: Gildenfarbe, Ziel einfärben, Liste der eigenen Farben, Suche
---------------------------------------------------------------------
local win
local ROW_H, ROWS = 24, 12

local function Swatch(parent)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(18, 18)
    s.border = s:CreateTexture(nil, "BACKGROUND"); s.border:SetAllPoints(); s.border:SetColorTexture(0, 0, 0, 1)
    s.tex = s:CreateTexture(nil, "ARTWORK"); s.tex:SetPoint("TOPLEFT", 2, -2); s.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    function s:SetColor(c)
        if c then self.tex:SetColorTexture(c[1], c[2], c[3], 1) else self.tex:SetColorTexture(0.25, 0.25, 0.25, 1) end
    end
    return s
end

local function Btn(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22); b:SetText(text)
    return b
end

-- Treffer: Personen mit eigener Farbe, dazu Gildenmitglieder passend zur Suche
local function Entries(filter)
    local seen, out = {}, {}
    filter = (filter or ""):lower()
    for key in pairs(DB()) do
        if filter == "" or key:lower():find(filter, 1, true) then
            seen[key] = true; out[#out + 1] = key
        end
    end
    if filter ~= "" and IsInGuild() then
        for i = 1, GetNumGuildMembers() do
            local name = GetGuildRosterInfo(i)
            local key = name and ns.Normalize(name)
            if key and not seen[key] and key:lower():find(filter, 1, true) then
                seen[key] = true; out[#out + 1] = key
                if #out >= 60 then break end
            end
        end
    end
    table.sort(out, function(a, b)
        local ca, cb = DB()[a] ~= nil, DB()[b] ~= nil
        if ca ~= cb then return ca end
        return a < b
    end)
    return out
end

local function Build()
    win = CreateFrame("Frame", "GuildPridePlatesFrame", UIParent, "BasicFrameTemplateWithInset")
    win:SetSize(440, 470); win:SetPoint("CENTER", 0, 40); win:SetFrameStrata("DIALOG")
    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving); win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "GuildPridePlatesFrame")
    local title = win:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -5); title:SetText(L["Farben der Namensplaketten"])

    local hint = win:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    hint:SetPoint("TOPLEFT", 16, -32); hint:SetWidth(408); hint:SetJustifyH("LEFT")
    hint:SetText(L["Nur für dich: andere sehen deine Farben nicht. Eigene Farbe je Spieler geht vor der Gildenfarbe."])

    -- Gildenfarbe
    win.guildCb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    win.guildCb:SetSize(24, 24); win.guildCb:SetPoint("TOPLEFT", 12, -62)
    local gl = win:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    gl:SetPoint("LEFT", win.guildCb, "RIGHT", 2, 0); gl:SetText(L["Alle Gildenmitglieder färben"])
    win.guildSw = Swatch(win); win.guildSw:SetPoint("LEFT", gl, "RIGHT", 10, 0)
    local function pickGuild()
        PickColor(GuildPrideDB.plateGuildColor or { 0.25, 1, 0.25 }, function(r, g, b)
            GuildPrideDB.plateGuildColor = { r, g, b }
            Plates.RefreshAll(); Plates.RefreshWindow()
        end)
    end
    win.guildSw:SetScript("OnClick", pickGuild)
    win.guildCb:SetScript("OnClick", function(self)
        if self:GetChecked() then pickGuild()
        else GuildPrideDB.plateGuildColor = nil; Plates.RefreshAll(); Plates.RefreshWindow() end
    end)

    -- Lebensbalken
    win.barCb = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
    win.barCb:SetSize(24, 24); win.barCb:SetPoint("TOPLEFT", 12, -88)
    local bl = win:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    bl:SetPoint("LEFT", win.barCb, "RIGHT", 2, 0); bl:SetText(L["Auch den Lebensbalken färben"])
    win.barCb:SetScript("OnClick", function(self)
        GuildPrideDB.plateColorBar = self:GetChecked() and true or false
        Plates.RefreshAll()
    end)

    -- Ziel einfärben
    local tb = Btn(win, L["Mein Ziel einfärben …"], 180); tb:SetPoint("TOPLEFT", 16, -120)
    tb:SetScript("OnClick", function()
        local key = UnitKey("target")
        if not key then ns.Print(L["Bitte erst einen Spieler ins Ziel nehmen."]) return end
        Plates.PickFor(key)
    end)

    -- Suche
    local sl = win:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
    sl:SetPoint("TOPLEFT", 16, -154); sl:SetText(L["Gildenmitglied suchen:"])
    win.search = CreateFrame("EditBox", nil, win, "InputBoxTemplate")
    win.search:SetSize(200, 22); win.search:SetPoint("LEFT", sl, "RIGHT", 10, 0)
    win.search:SetAutoFocus(false)
    win.search:SetScript("OnTextChanged", function() Plates.RefreshWindow() end)
    win.search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Liste (feste Zeilen + Mausrad-Blättern)
    win.offset = 0
    win.rows = {}
    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, win)
        r:SetSize(404, ROW_H); r:SetPoint("TOPLEFT", 16, -180 - (i - 1) * ROW_H)
        r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints()
        r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0)
        r.sw = Swatch(r); r.sw:SetPoint("LEFT", 4, 0)
        r.name = r:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
        r.name:SetPoint("LEFT", r.sw, "RIGHT", 8, 0); r.name:SetWidth(220); r.name:SetJustifyH("LEFT")
        r.pick = Btn(r, L["Farbe …"], 70); r.pick:SetPoint("RIGHT", -84, 0)
        r.reset = Btn(r, L["Zurücksetzen"], 80); r.reset:SetPoint("RIGHT", -2, 0)
        r.sw:SetScript("OnClick", function() Plates.PickFor(r.key) end)
        r.pick:SetScript("OnClick", function() Plates.PickFor(r.key) end)
        r.reset:SetScript("OnClick", function() Plates.Set(r.key, nil) end)
        win.rows[i] = r
    end
    win:EnableMouseWheel(true)
    win:SetScript("OnMouseWheel", function(_, d)
        win.offset = math.max(0, win.offset - d * 3); Plates.RefreshWindow()
    end)
    win.empty = win:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
    win.empty:SetPoint("TOPLEFT", 20, -186); win.empty:SetWidth(400); win.empty:SetJustifyH("LEFT")
    win.empty:SetText(L["Noch keine eigenen Farben. Nimm einen Spieler ins Ziel oder such oben ein Gildenmitglied."])
    if ns.SkinWindow then pcall(ns.SkinWindow, win) end
end

function Plates.RefreshWindow()
    if not win or not win:IsShown() then return end
    win.guildCb:SetChecked(GuildPrideDB.plateGuildColor ~= nil)
    win.guildSw:SetColor(GuildPrideDB.plateGuildColor)
    win.barCb:SetChecked(GuildPrideDB.plateColorBar and true or false)
    local list = Entries(win.search:GetText())
    win.offset = math.min(win.offset, math.max(0, #list - ROWS))
    for i, r in ipairs(win.rows) do
        local key = list[i + win.offset]
        r.key = key
        if key then
            local c = DB()[key]
            r.sw:SetColor(c or ColorFor(key))
            r.name:SetText(Ambiguate(key, "guild"))
            if c then r.name:SetTextColor(c[1], c[2], c[3]) else r.name:SetTextColor(0.8, 0.8, 0.8) end
            r.reset:SetShown(c ~= nil)
            r:Show()
        else
            r:Hide()
        end
    end
    win.empty:SetShown(#list == 0)
end

function Plates.Toggle()
    if not win then Build() end
    if win:IsShown() then win:Hide() return end
    win:Show(); Plates.RefreshWindow()
end

local slash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd = strtrim(arg or ""):lower()
    if cmd == "plaketten" or cmd == "farben" or cmd == "nameplates" then Plates.Toggle() return end
    return slash(arg)
end
