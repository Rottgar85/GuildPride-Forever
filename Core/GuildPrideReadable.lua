-- GuildPride: besser lesbar (größere Schrift, heller) und Farben für Farbenblinde
--   easyRead   Schriften von GuildPride zwei Punkte größer, graue Texte heller
--   colorSafe  in Listenfenstern Blau/Orange statt Grün/Rot
local ADDON, ns = ...

local FONTS = { "GPFont_Text", "GPFont_TextSmall", "GPFont_TextBold", "GPFont_Muted", "GPFont_MutedSmall", "GPFont_Normal", "GPFont_Button" }
local MUTED = { GPFont_Muted = true, GPFont_MutedSmall = true }
local base = {}   -- [Schrift] = { Datei, Größe, Stil, r, g, b }

function ns.ApplyReadable()
    local on = type(GuildPrideDB) == "table" and GuildPrideDB.easyRead == true
    for _, name in ipairs(FONTS) do
        local f = _G[name]
        if f and f.GetFont then
            if not base[name] then
                local file, size, flags = f:GetFont()
                local r, g, b = f:GetTextColor()
                if type(size) == "number" and type(r) == "number" then base[name] = { file, size, flags or "", r, g, b } end
            end
            local o = base[name]
            if o and o[1] then
                f:SetFont(o[1], o[2] + (on and 2 or 0), o[3])
                if MUTED[name] then
                    if on then f:SetTextColor(0.85, 0.83, 0.80) else f:SetTextColor(o[4], o[5], o[6]) end
                end
            end
        end
    end
end

-- Grün -> Blau, Rot -> Orange (nach Okabe/Ito unterscheidbar bei Rot-Grün-Schwäche)
local SAFE = { ["40ff40"] = "56b4e9", ["60d060"] = "56b4e9", ["ff6060"] = "e69f00", ["ff4040"] = "e69f00", ["ff8060"] = "e69f00" }
function ns.ColorSafe(text)
    if type(text) ~= "string" or type(GuildPrideDB) ~= "table" or GuildPrideDB.colorSafe ~= true then return text end
    return (text:gsub("|cff(%x%x%x%x%x%x)", function(c) local s = SAFE[c:lower()]; return s and ("|cff" .. s) or nil end))
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function() ns.ApplyReadable() end)
