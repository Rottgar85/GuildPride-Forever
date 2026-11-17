-- GuildPride: Meilenstein-Popup mit Abzeichen
-- Statt nur einer Textzeile erscheint ein animiertes Banner mit Abzeichen.
local ADDON, ns = ...
local L = ns.L
local MEDIA = "Interface\\AddOns\\GuildPrideForever\\Media\\"
local SHOW_TIME = 6

local function BadgeFor(kind, value)
    local lv = tonumber(value)
    if kind == "LEVEL" and lv then
        local tier = math.min(90, math.floor(lv / 10) * 10)
        if tier >= 10 then return MEDIA .. "badge_" .. tier end
    end
    return MEDIA .. "badge_star"
end
ns.BadgeFor = BadgeFor

---------------------------------------------------------------------
-- Popup-Fenster
---------------------------------------------------------------------
local pop = CreateFrame("Frame", "GuildPrideMilestonePopup", UIParent)
pop:SetSize(460, 115)
pop:SetPoint("TOP", 0, -180)
pop:SetFrameStrata("DIALOG")
pop:Hide()

local bg = pop:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetTexture(MEDIA .. "toast_bg")
ns.Paint(bg, "tex")

local badge = pop:CreateTexture(nil, "ARTWORK")
badge:SetSize(104, 104)
badge:SetPoint("LEFT", 34, 0)

local shine = pop:CreateTexture(nil, "OVERLAY")
shine:SetSize(150, 150)
shine:SetPoint("CENTER", badge)
shine:SetTexture("Interface\\Cooldown\\star4")
shine:SetBlendMode("ADD")
shine:SetVertexColor(1, 0.6, 0.25)
shine:SetAlpha(0)

local head = pop:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
head:SetPoint("TOPLEFT", badge, "TOPRIGHT", 18, -16)
head:SetText(L["MEILENSTEIN ERREICHT"])
ns.Paint(head, "title")

local nameText = pop:CreateFontString(nil, "OVERLAY", "GPFont_Huge")
nameText:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)

local desc = pop:CreateFontString(nil, "OVERLAY", "GPFont_Text")
desc:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -5)

-- Animationen: Einblenden + Abzeichen "aufschlagen" + Glanz
local ag = pop:CreateAnimationGroup()
local fadeIn = ag:CreateAnimation("Alpha"); fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.25)

local badgeAg = badge:GetParent():CreateAnimationGroup()
local bscale = badgeAg:CreateAnimation("Scale")
bscale:SetTarget(badge); bscale:SetScaleFrom(1.8, 1.8); bscale:SetScaleTo(1, 1)
bscale:SetDuration(0.35); bscale:SetSmoothing("OUT")

local shineAg = shine:CreateAnimationGroup()
local s1 = shineAg:CreateAnimation("Alpha"); s1:SetFromAlpha(0); s1:SetToAlpha(0.9); s1:SetDuration(0.2); s1:SetStartDelay(0.3)
local s2 = shineAg:CreateAnimation("Rotation"); s2:SetDegrees(-90); s2:SetDuration(1.2); s2:SetStartDelay(0.3)
local s3 = shineAg:CreateAnimation("Alpha"); s3:SetFromAlpha(0.9); s3:SetToAlpha(0); s3:SetDuration(0.7); s3:SetStartDelay(0.8)

local fadeOutAg = pop:CreateAnimationGroup()
local fo = fadeOutAg:CreateAnimation("Alpha"); fo:SetFromAlpha(1); fo:SetToAlpha(0); fo:SetDuration(0.6)

local queue, showing = {}, false
local Next

fadeOutAg:SetScript("OnFinished", function()
    pop:Hide(); pop:SetAlpha(1); showing = false
    Next()
end)

function Next()
    if showing then return end
    local item = table.remove(queue, 1)
    if not item then return end
    showing = true
    badge:SetTexture(item.badge)
    nameText:SetText(item.who)
    desc:SetText(item.text)
    pop:SetAlpha(1)
    pop:Show()
    ag:Play(); badgeAg:Play(); shineAg:Play()
    C_Timer.After(SHOW_TIME, function() if pop:IsShown() then fadeOutAg:Play() end end)
end

pop:EnableMouse(true)
pop:SetScript("OnMouseUp", function() fadeOutAg:Play() end) -- Klick schließt

-- Meilenstein-Sound, unabhängig vom Popup. Den Legendär-Sound gibt es in den
-- Classic-Clients nicht (bliebe stumm), daher dort die Schlachtzugswarnung.
-- "Master", damit er auch bei leisen Effekt-Sounds zu hören ist.
function ns.PlayMilestoneSound()
    if not GuildPrideDB.sound then return end
    local first = (not ns.IS_CLASSIC and SOUNDKIT.UI_LEGENDARY_LOOT_TOAST) or SOUNDKIT.RAID_WARNING
    if not PlaySound(first, "Master") and first ~= SOUNDKIT.RAID_WARNING then
        PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    end
end

function ns.ShowMilestonePopup(who, text, kind, value)
    table.insert(queue, { who = who, text = text, badge = BadgeFor(kind, value) })
    Next()
end

-- Test: /gp badge 30
local orig = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd, val = (arg or ""):match("^(%S*)%s*(%S*)")
    if cmd:lower() == "badge" then
        local lv = tonumber(val) or 30
        ns.PlayMilestoneSound()
        ns.ShowMilestonePopup(UnitName("player"), (L["hat Level %d erreicht!"]):format(lv), "LEVEL", lv)
    else
        orig(arg)
    end
end
