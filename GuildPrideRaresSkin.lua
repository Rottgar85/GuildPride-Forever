-- GuildPride Rares: nutzt direkt den Look von GuildPride (GuildPrideTheme/Skin)
local ADDON, GP = ...
GP.Rares = GP.Rares or {}
local ns = GP.Rares

ns.MEDIA = "Interface\\AddOns\\GuildPrideForever\\Media\\"
ns.Paint = GP.Paint
function ns.Repaint() end   -- GuildPride färbt beim Style-Wechsel selbst alles neu
function ns.SkinButton(btn) GP.SkinButton(btn); return btn end
function ns.SkinDialog(f) GP.SkinDialog(f); return f end
function ns.CloseButton(parent)
    local b = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
    b:SetPoint("TOPRIGHT", -6, -6)
    GP.SkinClose(b)
    b:SetScript("OnClick", function() parent:Hide() end)
    return b
end
