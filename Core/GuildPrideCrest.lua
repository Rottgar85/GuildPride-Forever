-- GuildPride: oben in der Seitenleiste wahlweise das Gildenwappen statt des Fraktionslogos
-- (Einstellung „crestGuild“). Gezeichnet mit Blizzards SetLargeGuildTabardTextures
-- (Hintergrund, Wappen, Rand), wie im Addon Guildy. Ohne Gilde, ohne Wappen oder ohne
-- diese Blizzard-Funktion bleibt das Fraktionslogo.
--
-- Das Wappen liegt genau über dem Fraktionslogo (factionLogo aus GuildPrideUI.lua) und
-- übernimmt dessen Größe, Position und Sichtbarkeit; das Layout (GuildPrideLayout.lua)
-- steuert also beide. Das Fraktionslogo wird dafür nur durchsichtig gemacht.
local _, ns = ...

local P = ns.UIParts
if not (P and P.factionLogo and P.frame) then return end
local logo = P.factionLogo

local holder = CreateFrame("Frame", nil, P.frame)
holder:SetPoint("CENTER", logo, "CENTER", 0, 0)
holder:SetFrameLevel(P.frame:GetFrameLevel() + 5)
holder.Background = holder:CreateTexture(nil, "ARTWORK", nil, 1)
holder.Background:SetTexture("Interface\\GuildFrame\\GuildFrame")
holder.Background:SetTexCoord(0.63183594, 0.69238281, 0.61914063, 0.74023438)
holder.Background:SetAllPoints()
holder.Emblem = holder:CreateTexture(nil, "ARTWORK", nil, 2)
holder.Border = holder:CreateTexture(nil, "ARTWORK", nil, 3)
holder.Border:SetTexture("Interface\\GuildFrame\\GuildFrame")
holder.Border:SetTexCoord(0.63183594, 0.69238281, 0.74414063, 0.86523438)
local mask = holder.CreateMaskTexture and holder:CreateMaskTexture()
if mask then
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints()
    for _, t in ipairs({ holder.Background, holder.Emblem, holder.Border }) do t:AddMaskTexture(mask) end
end
holder:Hide()

-- Teile nach der Größe des Logos ausrichten (Verhältnisse wie bei Guildy)
local function Fit()
    local size = logo:GetWidth() or 0
    if size <= 0 then size = 104 end
    holder:SetSize(size, size)
    holder.Emblem:ClearAllPoints()
    holder.Emblem:SetSize(size * 56 / 60, size * 64 / 60)
    holder.Emblem:SetPoint("CENTER", holder, "TOPLEFT", size * 30 / 60, -size * 31 / 60)
    holder.Border:ClearAllPoints()
    holder.Border:SetPoint("TOPLEFT", 0, -1)
    holder.Border:SetSize(size, size * 59 / 60)
end

-- Wappen zeigen, wenn eingeschaltet und möglich; sonst das Fraktionslogo
local function Update()
    Fit()
    local want = GuildPrideDB and GuildPrideDB.crestGuild
    local set = rawget(_G, "SetLargeGuildTabardTextures")
    local ok = want and set ~= nil and IsInGuild()
        and (pcall(set, "player", holder.Emblem, holder.Background, holder.Border)) or false
    holder.ok = ok
    holder:SetShown(ok and logo:IsShown())
    logo:SetAlpha(ok and 0 or 1)
end
ns.UpdateCrestChoice = Update

-- Das Layout blendet das Logo ein/aus und ändert seine Größe: Wappen folgt
hooksecurefunc(logo, "SetShown", function() holder:SetShown(holder.ok and logo:IsShown()) end)
hooksecurefunc(logo, "Show", function() holder:SetShown(holder.ok) end)
hooksecurefunc(logo, "Hide", function() holder:Hide() end)
hooksecurefunc(logo, "SetSize", Fit)

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "PLAYER_GUILD_UPDATE", "GUILDTABARD_UPDATE" }) do
    pcall(ev.RegisterEvent, ev, e)   -- unbekannte Events werfen in manchen Clients einen Fehler
end
ev:SetScript("OnEvent", function() C_Timer.After(0, Update) end)
