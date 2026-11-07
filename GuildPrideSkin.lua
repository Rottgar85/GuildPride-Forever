-- GuildPride: Einheitlicher Look für alle Knöpfe, Eingabefelder und Dialoge
-- Wandelt Blizzard-Standardelemente in den gewählten Style um (GuildPrideTheme.lua).
local ADDON, ns = ...
local MEDIA = "Interface\\AddOns\\GuildPrideForever\\Media\\"
local Paint, PaintEnabled = ns.Paint, ns.PaintEnabled
local skinned = setmetatable({}, { __mode = "k" })

local function HideRegions(obj, ...)
    for i = 1, select("#", ...) do
        local r = obj[select(i, ...)]
        if r and r.SetAlpha then r:SetAlpha(0) end
    end
end

-- Knopf (UIPanelButtonTemplate) -> Kupfer-/Glutknopf
local function SkinButton(btn)
    if skinned[btn] then return end
    skinned[btn] = true
    HideRegions(btn, "Left", "Middle", "Right", "LeftSeparator", "RightSeparator")
    local n = btn:GetNormalTexture(); if n then n:SetAlpha(0) end
    local p = btn:GetPushedTexture(); if p then p:SetAlpha(0) end
    local d = btn:GetDisabledTexture(); if d then d:SetAlpha(0) end

    local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetAllPoints()
    bg:SetTexture(MEDIA .. "nav")
    btn.gpBg = bg
    bg.gpOff = not btn:IsEnabled()
    Paint(bg, "tex")

    local hl = btn:GetHighlightTexture()
    if hl then
        hl:SetTexture(nil)
        Paint(hl, "glow", 0.15)
        hl:ClearAllPoints(); hl:SetPoint("TOPLEFT", 3, -3); hl:SetPoint("BOTTOMRIGHT", -3, 3)
    end

    btn:SetNormalFontObject(GPFont_Button)
    btn:SetHighlightFontObject(GPFont_Button)
    btn:SetDisabledFontObject(GPFont_ButtonOff)

    btn:HookScript("OnMouseDown", function(self) if self:IsEnabled() then bg:SetTexture(MEDIA .. "nav_active") end end)
    btn:HookScript("OnMouseUp", function() bg:SetTexture(MEDIA .. "nav") end)
    hooksecurefunc(btn, "SetEnabled", function(_, on) PaintEnabled(bg, on) end)
    hooksecurefunc(btn, "Disable", function() PaintEnabled(bg, false) end)
    hooksecurefunc(btn, "Enable", function() PaintEnabled(bg, true) end)
end
ns.SkinButton = SkinButton

-- Schließen-Kreuz
local function SkinClose(btn)
    if skinned[btn] then return end
    skinned[btn] = true
    btn:SetSize(22, 22)
    btn:SetNormalTexture(MEDIA .. "close")
    btn:SetPushedTexture(MEDIA .. "close_hover")
    btn:SetHighlightTexture(MEDIA .. "close_hover")
    if btn.SetDisabledTexture then btn:SetDisabledTexture(MEDIA .. "close") end
end
ns.SkinClose = SkinClose

-- Eingabefeld (InputBoxTemplate)
local function SkinEditBox(eb)
    if skinned[eb] then return end
    skinned[eb] = true
    HideRegions(eb, "Left", "Middle", "Right")
    local bg = eb:CreateTexture(nil, "BACKGROUND", nil, -1)
    bg:SetPoint("TOPLEFT", -6, 2)
    bg:SetPoint("BOTTOMRIGHT", 2, -2)
    bg:SetTexture(MEDIA .. "input")
    Paint(bg, "tex")
    eb:SetFontObject(GPFont_Text)
    eb:SetTextInsets(2, 2, 0, 0)
end
ns.SkinEditBox = SkinEditBox

-- Dialogfenster (BackdropTemplate mit Blizzard-Rahmen)
local function SkinDialog(f)
    if skinned[f] or not f.SetBackdrop then return end
    skinned[f] = true
    f:SetBackdrop({
        bgFile = MEDIA .. "bg",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    Paint(f, "accent")
    -- Glut-Leiste oben
    local bar = f:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", 2, -2); bar:SetPoint("TOPRIGHT", -2, -2)
    bar:SetHeight(4)
    Paint(bar, "ember", 0.9)
end
ns.SkinDialog = SkinDialog

---------------------------------------------------------------------
-- Rekursiv alle Elemente eines Fensters umstylen
---------------------------------------------------------------------
local function Walk(obj)
    if not obj or not obj.GetObjectType then return end
    local t = obj:GetObjectType()
    if t == "Button" and obj.Left and obj.Middle and obj.Right then
        SkinButton(obj)
    elseif t == "EditBox" and obj.Left and obj.Middle then
        SkinEditBox(obj)
    end
    -- Blizzard-Schließen-Knopf erkennen
    if t == "Button" and not skinned[obj] then
        local n = obj.GetNormalTexture and obj:GetNormalTexture()
        local tex = n and n.GetAtlas and n:GetAtlas()
        local file = n and n.GetTexture and n:GetTexture()
        if (tex and tex:find("RedButton%-Exit")) or (type(file) == "string" and file:find("UI%-Panel%-MinimizeButton")) then
            SkinClose(obj)
        end
    end
    if obj.GetChildren then
        for _, child in ipairs({ obj:GetChildren() }) do Walk(child) end
    end
end

local function SkinAll()
    Walk(GuildPrideFrame)
    for _, name in ipairs({ "GuildPrideCreateEvent", "GuildPrideMemberToast", "GuildPridePollDialog" }) do
        local f = _G[name]
        if f then SkinDialog(f); Walk(f) end
    end
end
ns.SkinAll = SkinAll

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    SkinAll()
    -- Nachträglich erzeugte Elemente (z. B. Listenzeilen) beim Öffnen mitnehmen
    GuildPrideFrame:HookScript("OnShow", function() C_Timer.After(0, SkinAll) end)
    if GuildPrideCreateEvent then GuildPrideCreateEvent:HookScript("OnShow", function() Walk(GuildPrideCreateEvent) end) end
    if GuildPridePollDialog then GuildPridePollDialog:HookScript("OnShow", function() Walk(GuildPridePollDialog) end) end
end)
