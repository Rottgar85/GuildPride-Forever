-- GuildPride: "Tinte" für helles Papier (Layout Gildenbuch)
-- Das Addon schreibt an vielen Stellen helle oder farbige Texte (auch mit
-- |cffRRGGBB-Codes). Auf hellem Pergament wären die kaum lesbar. Ist die Tinte
-- an, wird jede Schrift im Hauptfenster in einen dunklen Ton desselben
-- Farbtons umgerechnet und ihr Schatten entfernt. Aus = alles wie vorher.
--   - Gemerkt wird je Schrift der Originaltext und die Originalfarbe; neue
--     Texte (SetText/SetTextColor) laufen über Hooks.
--   - Ausgenommen: Bereiche mit gpNoInk (dunkle Einlagen wie der Chat),
--     Schrift auf Knöpfen mit eigenem Hintergrund, Eingabefelder.
--   - Dunkle, halbdurchsichtige Kästen (ns.DarkBg) werden auf Papier zu
--     einem hellen Braunton.
local ADDON, ns = ...

local Ink = { on = false }
ns.Ink = Ink
local hooked = setmetatable({}, { __mode = "k" })
local darkBgs = setmetatable({}, { __mode = "k" })

---------------------------------------------------------------------
-- Farben umrechnen
---------------------------------------------------------------------
local function ToHSL(r, g, b)
    local max, min = math.max(r, g, b), math.min(r, g, b)
    local l = (max + min) / 2
    if max == min then return 0, 0, l end
    local d = max - min
    local s = l > 0.5 and d / (2 - max - min) or d / (max + min)
    local h
    if max == r then h = (g - b) / d + (g < b and 6 or 0)
    elseif max == g then h = (b - r) / d + 2
    else h = (r - g) / d + 4 end
    return h / 6, s, l
end

local function Hue(p, q, t)
    if t < 0 then t = t + 1 end
    if t > 1 then t = t - 1 end
    if t < 1 / 6 then return p + (q - p) * 6 * t end
    if t < 1 / 2 then return q end
    if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
    return p
end

local function FromHSL(h, s, l)
    if s == 0 then return l, l, l end
    local q = l < 0.5 and l * (1 + s) or l + s - l * s
    local p = 2 * l - q
    return Hue(p, q, h + 1 / 3), Hue(p, q, h), Hue(p, q, h - 1 / 3)
end

-- Helle Farbe -> dunkle Tinte im selben Farbton; dunkle Farben bleiben
function Ink.Color(r, g, b)
    if not Ink.on or type(r) ~= "number" then return r, g, b end
    if 0.299 * r + 0.587 * g + 0.114 * b < 0.40 then return r, g, b end
    local h, s, l = ToHSL(r, g, b)
    if s < 0.22 then
        -- neutral: Haupttext fast schwarzbraun, gedämpfter Text heller
        if l > 0.72 then return 0.15, 0.10, 0.06 end
        return 0.27, 0.20, 0.13
    end
    return FromHSL(h, math.min(s, 0.85), 0.23)
end

local function MapHex(hex)
    local r, g, b = tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
    r, g, b = Ink.Color(r, g, b)
    return ("%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

function Ink.Text(t)
    if not Ink.on or type(t) ~= "string" or not t:find("|c", 1, true) then return t end
    return (t:gsub("|c(%x%x)(%x%x%x%x%x%x)", function(a, hex) return "|c" .. a .. MapHex(hex) end))
end

---------------------------------------------------------------------
-- Schriften erfassen
---------------------------------------------------------------------
local function Apply(fs)
    fs.gpInkBusy = true
    local t = fs.gpRawText
    if t ~= nil then fs:SetText(Ink.on and Ink.Text(t) or t) end
    local c = fs.gpRawColor
    if Ink.on then
        local r, g, b = Ink.Color(c[1], c[2], c[3])
        fs:SetTextColor(r, g, b, c[4] or 1)
        fs:SetShadowOffset(0, 0)
    else
        if fs.gpInherited and fs.GetFontObject and fs:GetFontObject() then
            -- wieder der Schriftart folgen (Style-Wechsel färbt sie dann mit)
            fs:SetFontObject(fs:GetFontObject())
            if t ~= nil then fs:SetText(t) end
        else
            fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        end
        fs:SetShadowOffset(fs.gpRawShadow[1], fs.gpRawShadow[2])
    end
    fs.gpInkBusy = false
end

local function Install(fs)
    if hooked[fs] then return end
    hooked[fs] = true
    local r, g, b, a = fs:GetTextColor()
    fs.gpRawColor = { r, g, b, a }
    local fo = fs.GetFontObject and fs:GetFontObject()
    if fo and fo.GetTextColor then
        local fr, fg, fb = fo:GetTextColor()
        fs.gpInherited = math.abs(r - fr) + math.abs(g - fg) + math.abs(b - fb) < 0.01
    end
    fs.gpRawText = fs:GetText()
    fs.gpRawShadow = { fs:GetShadowOffset() }
    hooksecurefunc(fs, "SetText", function(self, t)
        if self.gpInkBusy then return end
        self.gpRawText = t
        if Ink.on then
            local m = Ink.Text(t)
            if m ~= t then self.gpInkBusy = true; self:SetText(m); self.gpInkBusy = false end
        end
    end)
    hooksecurefunc(fs, "SetTextColor", function(self, nr, ng, nb, na)
        if self.gpInkBusy then return end
        self.gpRawColor = { nr, ng, nb, na }
        self.gpInherited = false
        if Ink.on then
            local ir, ig, ib = Ink.Color(nr, ng, nb)
            self.gpInkBusy = true; self:SetTextColor(ir, ig, ib, na or 1); self.gpInkBusy = false
        end
    end)
    if Ink.on then Apply(fs) end
end

-- Schrift auf einem Knopf mit eigenem (dunklem) Hintergrund bleibt hell
local function OnDarkButton(fs)
    local p = fs:GetParent()
    if not p or not p.IsObjectType or not p:IsObjectType("Button") or p:IsObjectType("CheckButton") then return false end
    return p.gpBg ~= nil or (p.GetNormalTexture and p:GetNormalTexture() ~= nil)
end

local function Walk(f)
    if f.gpNoInk then return end
    for _, r in ipairs({ f:GetRegions() }) do
        if r:IsObjectType("FontString") and not r.gpNoInk and not OnDarkButton(r) then Install(r) end
    end
    for _, c in ipairs({ f:GetChildren() }) do Walk(c) end
end

function Ink.Walk()
    if ns.GuildFrame then Walk(ns.GuildFrame) end
end

-- Kurz nach einer Änderung (neue Zeilen in Listen) erfassen
local walkPending = false
function Ink.Soon()
    if not Ink.on or walkPending then return end
    walkPending = true
    C_Timer.After(0, function() walkPending = false; if Ink.on then Ink.Walk() end end)
end

---------------------------------------------------------------------
-- Dunkle Kästen
---------------------------------------------------------------------
function ns.DarkBg(tex, alpha)
    darkBgs[tex] = alpha or 0.45
    if Ink.on then tex:SetColorTexture(0.45, 0.31, 0.16, 0.14) else tex:SetColorTexture(0, 0, 0, darkBgs[tex]) end
    return tex
end

---------------------------------------------------------------------
-- An/aus
---------------------------------------------------------------------
function Ink.Set(on)
    on = on and true or false
    if Ink.on == on then
        if on then Ink.Walk() end
        return
    end
    Ink.on = on
    if on then Ink.Walk() end
    for fs in pairs(hooked) do Apply(fs) end
    for tex, a in pairs(darkBgs) do
        if on then tex:SetColorTexture(0.45, 0.31, 0.16, 0.14) else tex:SetColorTexture(0, 0, 0, a) end
    end
end

-- Jede Sekunde neue Schriften erfassen (Ink.Soon nach Aktualisierungen: GuildPrideLayout.lua)
local ticker = CreateFrame("Frame")
local acc = 0
ticker:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 1 then return end
    acc = 0
    if Ink.on and ns.GuildFrame and ns.GuildFrame:IsShown() then Ink.Walk() end
end)
