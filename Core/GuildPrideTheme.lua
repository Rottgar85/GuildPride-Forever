-- GuildPride: Styles (Farbschemata) für Fenster, Knöpfe und Popups
-- Elemente melden sich mit ns.Paint(obj, rolle) an. Beim Wechsel des Styles
-- (Einstellungen) werden alle angemeldeten Elemente sofort neu eingefärbt.
local ADDON, ns = ...
local L = ns.L

-- tint:    Texturen werden entsättigt und in dieser Farbe eingefärbt (nil = Originalfarben)
-- accent:  Rahmen und Trennlinien
-- ember:   kräftige Leisten (Kachelkante, Chatkante, Dialogleiste)
-- glow:    Hover-Hervorhebung und Zeilenstreifen
-- heading: Überschriften und Namen
-- button:  Knopftext und aktiver Reiter
-- title:   Seitentitel oben rechts
-- Seit 2.14 gibt es nur noch einen Style: "Gildenhalle" – dunkler Schiefer mit Gold.
-- Die Texturen in Media/ sind schon in diesen Farben gemalt (kein Einfärben: tint = nil).
local HALLE = { key = "halle", name = L["Gildenhalle"], tint = nil,
    accent = { 0.79, 0.64, 0.36 }, ember = { 0.79, 0.64, 0.36 }, glow = { 0.91, 0.76, 0.48 },
    heading = { 0.95, 0.90, 0.81 }, button = { 0.95, 0.86, 0.62 }, title = { 0.91, 0.76, 0.48 } }
local THEMES = { HALLE }
ns.THEMES = THEMES

function ns.Theme()
    return HALLE
end

---------------------------------------------------------------------
-- Einfärben
---------------------------------------------------------------------
local painted = setmetatable({}, { __mode = "k" })   -- obj -> { role, alpha }

local function PaintNow(obj, role, alpha)
    local t = ns.Theme()
    if role == "tex" then
        -- Abgeschaltete Knöpfe (obj.gpOff) bleiben grau und halb durchsichtig
        if t.tint and not obj.gpOff then
            obj:SetDesaturated(true)
            obj:SetVertexColor(t.tint[1], t.tint[2], t.tint[3])
        else
            obj:SetDesaturated(obj.gpOff and true or false)
            obj:SetVertexColor(1, 1, 1)
        end
        obj:SetAlpha(obj.gpOff and 0.5 or 1)
        return
    end
    local c = t[role]
    if not c then return end
    if obj.SetTextColor then
        obj:SetTextColor(c[1], c[2], c[3])
    elseif obj.SetBackdropBorderColor then
        obj:SetBackdropBorderColor(c[1], c[2], c[3], alpha or 1)
    elseif obj.SetColorTexture then
        obj:SetColorTexture(c[1], c[2], c[3], alpha or 1)
    end
end

-- Element anmelden und gleich im aktuellen Style einfärben
function ns.Paint(obj, role, alpha)
    if not obj then return obj end
    painted[obj] = { role, alpha }
    PaintNow(obj, role, alpha)
    return obj
end

-- Knopf-Hintergrund an/aus (grau, wenn abgeschaltet)
function ns.PaintEnabled(tex, on)
    tex.gpOff = not on
    PaintNow(tex, "tex")
end

local FONTS = {
    GPFont_Huge = "heading", GPFont_Large = "heading", GPFont_Normal = "heading", GPFont_ButtonActive = "heading",
    GPFont_TextBold = "heading", GPFont_Button = "button",
}

local listeners = {}
function ns.OnThemeChanged(fn) listeners[#listeners + 1] = fn end

function ns.ApplyTheme(key)
    local t = ns.Theme()   -- nur noch ein Style; key wird ignoriert
    for name, role in pairs(FONTS) do
        local f = _G[name]
        if f then f:SetTextColor(t[role][1], t[role][2], t[role][3]) end
    end
    for obj, spec in pairs(painted) do PaintNow(obj, spec[1], spec[2]) end
    for _, fn in ipairs(listeners) do fn(t) end
end

-- Eigene Farbe wählen (Blizzards Farbwähler); Abbrechen stellt die alte wieder her
function ns.PickCustomColor()
    local old = GuildPrideDB.customColor or { 1.00, 0.45, 0.15 }
    local function Set(r, g, b)
        GuildPrideDB.customColor = { r, g, b }
        ns.ApplyTheme("custom")
    end
    local function Picked()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        Set(r, g, b)
    end
    local function Cancel() Set(old[1], old[2], old[3]) end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({ r = old[1], g = old[2], b = old[3],
            swatchFunc = Picked, cancelFunc = Cancel, hasOpacity = false })
    else
        ColorPickerFrame.func, ColorPickerFrame.cancelFunc = Picked, Cancel
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame:SetColorRGB(old[1], old[2], old[3])
        ColorPickerFrame:Hide(); ColorPickerFrame:Show()
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() ns.ApplyTheme() end)
