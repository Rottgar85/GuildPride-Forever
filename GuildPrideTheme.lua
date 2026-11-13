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
local THEMES = {
    { key = "forge", name = L["Schmiede"], tint = nil,
      accent = { 0.80, 0.55, 0.27 }, ember = { 1.00, 0.45, 0.15 }, glow = { 1.00, 0.50, 0.20 },
      heading = { 0.94, 0.78, 0.55 }, button = { 1.00, 0.82, 0.55 }, title = { 1.00, 0.55, 0.25 } },
    { key = "frost", name = L["Frost"], tint = { 0.62, 0.82, 1.00 },
      accent = { 0.45, 0.65, 0.88 }, ember = { 0.35, 0.75, 1.00 }, glow = { 0.45, 0.80, 1.00 },
      heading = { 0.76, 0.88, 1.00 }, button = { 0.82, 0.92, 1.00 }, title = { 0.45, 0.80, 1.00 } },
    { key = "emerald", name = L["Smaragd"], tint = { 0.62, 1.00, 0.66 },
      accent = { 0.36, 0.72, 0.42 }, ember = { 0.30, 0.90, 0.45 }, glow = { 0.35, 0.95, 0.50 },
      heading = { 0.74, 0.95, 0.74 }, button = { 0.82, 1.00, 0.82 }, title = { 0.35, 0.95, 0.50 } },
    { key = "arcane", name = L["Arkan"], tint = { 0.84, 0.64, 1.00 },
      accent = { 0.62, 0.46, 0.88 }, ember = { 0.76, 0.45, 1.00 }, glow = { 0.78, 0.50, 1.00 },
      heading = { 0.87, 0.78, 1.00 }, button = { 0.92, 0.84, 1.00 }, title = { 0.80, 0.55, 1.00 } },
    { key = "night", name = L["Nacht"], tint = { 0.70, 0.70, 0.74 },
      accent = { 0.50, 0.50, 0.56 }, ember = { 0.82, 0.82, 0.88 }, glow = { 0.80, 0.80, 0.90 },
      heading = { 0.90, 0.90, 0.93 }, button = { 0.95, 0.95, 0.97 }, title = { 0.85, 0.85, 0.92 } },
}
-- Eigener Style: alle Farben aus einer selbst gewählten Farbe abgeleitet
local function Mix(c, w) return { c[1] + (1 - c[1]) * w, c[2] + (1 - c[2]) * w, c[3] + (1 - c[3]) * w } end
local custom = { key = "custom", name = L["Eigene"] }
local function BuildCustom()
    local s = GuildPrideDB and GuildPrideDB.customColor or { 1.00, 0.45, 0.15 }
    local c = { s[1], s[2], s[3] }
    custom.tint = Mix(c, 0.35)
    custom.accent = { c[1] * 0.8, c[2] * 0.8, c[3] * 0.8 }
    custom.ember, custom.glow, custom.title = c, c, Mix(c, 0.15)
    custom.heading, custom.button = Mix(c, 0.6), Mix(c, 0.7)
end
BuildCustom()
THEMES[#THEMES + 1] = custom
ns.THEMES = THEMES

local byKey = {}
for _, t in ipairs(THEMES) do byKey[t.key] = t end

function ns.Theme()
    return byKey[GuildPrideDB and GuildPrideDB.theme or "forge"] or THEMES[1]
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
    if key and byKey[key] then GuildPrideDB.theme = key end
    BuildCustom()
    local t = ns.Theme()
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
