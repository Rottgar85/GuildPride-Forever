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

---------------------------------------------------------------------
-- Goldrahmen für alle eigenen Fenster und Popups (Vorbild: das Gildenfenster)
-- Gildenhallen-Hintergrund, 2 px Goldlinie rundum, goldene Eck-Ornamente.
-- Nur für Fenster, die GuildPride selbst erzeugt (nie für Blizzard-Fenster).
-- Liegt hier (früh geladen), damit auch Fenster aus früh geladenen Dateien
-- ihn gleich beim Erzeugen nutzen können.
---------------------------------------------------------------------
do
    local MEDIA = "Interface\\AddOns\\GuildPrideForever\\Media\\"
    -- Teile von Blizzards BasicFrameTemplate(WithInset): grauer Rahmen und Titelleiste
    local PARTS = { "Bg", "TitleBg", "NineSlice", "TopTileStreaks", "TopLeftCorner", "TopRightCorner",
        "TopBorder", "BotLeftCorner", "BotRightCorner", "BottomBorder", "LeftBorder", "RightBorder" }
    local CORNERS = {
        { "TOPLEFT",     0, 1, 0, 1 },
        { "TOPRIGHT",    1, 0, 0, 1 },
        { "BOTTOMLEFT",  0, 1, 1, 0 },
        { "BOTTOMRIGHT", 1, 0, 1, 0 },
    }
    local done = setmetatable({}, { __mode = "k" })

    -- Graue Vorlage eines eigenen Fensters ausblenden (nur die eigenen Teile des Fensters)
    local function HideTemplate(f)
        for _, k in ipairs(PARTS) do
            local r = rawget(f, k)
            if r and r.Hide then r:Hide() end
        end
        local inset = rawget(f, "Inset")
        if inset and inset.GetRegions then
            if inset.NineSlice then inset.NineSlice:Hide() end
            for _, r in ipairs({ inset:GetRegions() }) do
                if r.GetObjectType and r:GetObjectType() == "Texture" then r:Hide() end
            end
        end
        -- Der Titel saß in Blizzards Titelleiste (TOP, -5): jetzt in Gold-Schrift
        for _, r in ipairs({ f:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" then
                local p, rel, rp, x, y = r:GetPoint(1)
                if p == "TOP" and (rel == nil or rel == f) and rp == "TOP" and x == 0 and y == -5 then
                    r:SetPoint("TOP", f, "TOP", 0, -9)
                    if GPFont_Normal then r:SetFontObject(GPFont_Normal) end
                end
            end
        end
        local close = rawget(f, "CloseButton")
        if close and close.ClearAllPoints then
            close:ClearAllPoints()
            close:SetPoint("TOPRIGHT", -4, -4)
        end
    end

    function ns.GoldFrame(f)
        if not f or done[f] then return f end
        done[f] = true
        -- fremden Rahmen ablegen (eigener Backdrop oder Blizzard-Vorlage)
        if f.SetBackdrop then f:SetBackdrop(nil) end
        if rawget(f, "CloseButton") then HideTemplate(f) end

        local bg = f:CreateTexture(nil, "BACKGROUND", nil, -8)
        bg:SetAllPoints()
        bg:SetTexture(MEDIA .. "bg")
        ns.Paint(bg, "tex")

        local lines = {}
        local function Line(p1, p2, vertical)
            local t = f:CreateTexture(nil, "BORDER")
            ns.Paint(t, "accent")
            t:SetPoint(p1); t:SetPoint(p2)
            if vertical then t:SetWidth(2) else t:SetHeight(2) end
            lines[#lines + 1] = t
        end
        Line("TOPLEFT", "TOPRIGHT")
        Line("BOTTOMLEFT", "BOTTOMRIGHT")
        Line("TOPLEFT", "BOTTOMLEFT", true)
        Line("TOPRIGHT", "BOTTOMRIGHT", true)

        -- Ecken wie im Gildenfenster (40 px), bei kleinen Fenstern kleiner
        local w, h = tonumber(f:GetWidth()) or 0, tonumber(f:GetHeight()) or 0
        local size = math.floor(math.min(w, h) * 0.2)
        if size > 40 then size = 40 elseif size < 18 then size = 18 end
        local off = math.floor(size * 0.15 + 0.5)
        local corners = {}
        for _, c in ipairs(CORNERS) do
            -- ARTWORK statt OVERLAY: Titel und Texte des Fensters bleiben darüber lesbar
            local t = f:CreateTexture(nil, "ARTWORK", nil, 7)
            t:SetSize(size, size)
            t:SetPoint(c[1], c[1]:find("LEFT") and -off or off, c[1]:find("TOP") and off or -off)
            t:SetTexture(MEDIA .. "corner")
            t:SetTexCoord(c[2], c[3], c[4], c[5])
            ns.Paint(t, "tex")
            corners[#corners + 1] = t
        end
        f.gpGold = { bg = bg, lines = lines, corners = corners }
        return f
    end
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
