-- GuildPride Rares: Alarm-Fenster mit Knopf zum Anvisieren
-- Der Knopf ist ein Blizzard-Knopf (SecureActionButton): Erst dein Klick löst
-- "/targetexact Name" aus. Im Kampf darf er nicht geändert werden – dann wird
-- er nach dem Kampf vorbereitet. Für eine Taste: Makro "/click GPRaresTarget".
local ADDON, GP = ...
-- Rare-Scanner läuft in einem eigenen Unter-Namensraum, damit sich nichts mit GuildPride beißt
GP.Rares = GP.Rares or {}
local ns = GP.Rares

local MEDIA = ns.MEDIA
local function ApplyTargetLater() if ns.ApplyTarget then ns.ApplyTarget() end end
-- Banner wie das Meilenstein-Popup von GuildPride
local alert = CreateFrame("Frame", "GPRaresAlert", UIParent)
alert:SetSize(460, 132)
alert:SetPoint("TOP", 0, -180)
alert:SetFrameStrata("DIALOG")
alert:SetMovable(true); alert:EnableMouse(true); alert:RegisterForDrag("LeftButton")
alert:SetClampedToScreen(true)
alert:SetScript("OnDragStart", function(self)
    if not InCombatLockdown() and GPRaresTarget then GPRaresTarget:Hide() end
    self:StartMoving()
end)
alert:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    ns.DB().alertPos = { p, rp, x, y }
    ApplyTargetLater()
end)
alert:Hide()

local bg = alert:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(); bg:SetTexture(MEDIA .. "toast_bg")
ns.Paint(bg, "tex")

-- Totenkopf als Abzeichen, mit Glanz wie beim Meilenstein
local badge = alert:CreateTexture(nil, "ARTWORK")
badge:SetSize(72, 72); badge:SetPoint("LEFT", 44, 0)
badge:SetTexture("Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
local shine = alert:CreateTexture(nil, "OVERLAY")
shine:SetSize(140, 140); shine:SetPoint("CENTER", badge)
shine:SetTexture("Interface\\Cooldown\\star4"); shine:SetBlendMode("ADD")
shine:SetVertexColor(1, 0.6, 0.25); shine:SetAlpha(0)

alert.head = alert:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
alert.head:SetPoint("TOPLEFT", alert, "TOPLEFT", 140, -18)
ns.Paint(alert.head, "title")
alert.title = alert:CreateFontString(nil, "OVERLAY", "GPFont_Huge")
alert.title:SetPoint("TOPLEFT", alert.head, "BOTTOMLEFT", 0, -3); alert.title:SetPoint("RIGHT", -30, 0)
alert.title:SetJustifyH("LEFT"); alert.title:SetWordWrap(false)
ns.Paint(alert.title, "heading")
alert.sub = alert:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
alert.sub:SetPoint("TOPLEFT", alert.title, "BOTTOMLEFT", 0, -3); alert.sub:SetPoint("RIGHT", -24, 0)
alert.sub:SetJustifyH("LEFT"); alert.sub:SetWordWrap(false)
ns.CloseButton(alert):SetPoint("TOPRIGHT", -14, -12)

-- Einblenden, Abzeichen "aufschlagen", Glanz
local ag = alert:CreateAnimationGroup()
local fadeIn = ag:CreateAnimation("Alpha"); fadeIn:SetFromAlpha(0); fadeIn:SetToAlpha(1); fadeIn:SetDuration(0.25)
local badgeAg = alert:CreateAnimationGroup()
local bs = badgeAg:CreateAnimation("Scale"); bs:SetTarget(badge)
bs:SetScaleFrom(1.8, 1.8); bs:SetScaleTo(1, 1); bs:SetDuration(0.35); bs:SetSmoothing("OUT")
local shineAg = shine:CreateAnimationGroup()
local s1 = shineAg:CreateAnimation("Alpha"); s1:SetFromAlpha(0); s1:SetToAlpha(0.9); s1:SetDuration(0.2); s1:SetStartDelay(0.3)
local s2 = shineAg:CreateAnimation("Rotation"); s2:SetDegrees(-90); s2:SetDuration(1.2); s2:SetStartDelay(0.3)
local s3 = shineAg:CreateAnimation("Alpha"); s3:SetFromAlpha(0.9); s3:SetToAlpha(0); s3:SetDuration(0.7); s3:SetStartDelay(0.8)

-- Platzhalter, über dem der Blizzard-Knopf liegt
alert.slot = CreateFrame("Frame", nil, alert)
alert.slot:SetSize(120, 22); alert.slot:SetPoint("TOPLEFT", alert.sub, "BOTTOMLEFT", 0, -7)
-- Ganz unten: wer den Gegner gefunden hat
alert.finder = alert:CreateFontString(nil, "OVERLAY", "GPFont_TextSmall")
alert.finder:SetPoint("TOPLEFT", alert.slot, "BOTTOMLEFT", 0, -8)
alert.finder:SetPoint("RIGHT", -24, 0)
alert.finder:SetJustifyH("LEFT")
alert.combat = alert:CreateFontString(nil, "OVERLAY", "GPFont_MutedSmall")
alert.combat:SetPoint("LEFT", alert.slot, "LEFT", 0, 0)

local wp = ns.SkinButton(CreateFrame("Button", nil, alert, "UIPanelButtonTemplate"))
wp:SetSize(110, 22); wp:SetPoint("LEFT", alert.slot, "RIGHT", 8, 0); wp:SetText("Wegpunkt")

-- Eigenständiger Knopf (nicht im Alarm-Fenster, damit das Fenster im Kampf
-- frei ein- und ausgeblendet werden darf)
local target = CreateFrame("Button", "GPRaresTarget", UIParent, "SecureActionButtonTemplate,UIPanelButtonTemplate")
ns.SkinButton(target)
target:SetSize(120, 22)
target:SetFrameStrata("FULLSCREEN")
target:RegisterForClicks("AnyUp", "AnyDown")
target:SetAttribute("type", "macro")
target:SetText("Anvisieren")
target:Hide()

local current, pendingName = nil, nil

local function ApplyTarget()
    if InCombatLockdown() then return false end
    target:SetAttribute("macrotext", pendingName and ("/targetexact " .. pendingName) or "")
    -- Geschützte Knöpfe dürfen nicht an normalen Fenstern hängen: Bildschirm-
    -- Position des Platzhalters ausrechnen und am UIParent festmachen
    local l, t = alert.slot:GetLeft(), alert.slot:GetTop()
    target:ClearAllPoints()
    if l and t then
        local k = alert.slot:GetEffectiveScale() / UIParent:GetEffectiveScale()
        target:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l * k, t * k)
    end
    target:SetShown(alert:IsShown() and pendingName ~= nil)
    alert.combat:SetText("")
    return true
end
ns.ApplyTarget = ApplyTarget

ns.Listen("PLAYER_REGEN_ENABLED", function() ApplyTarget() end)
ns.Listen("PLAYER_REGEN_DISABLED", function()
    -- Knopf zeigt evtl. gleich einen alten Namen? Nur Hinweis, nichts ändern
end)

alert:SetScript("OnHide", function()
    if not InCombatLockdown() and GPRaresTarget then GPRaresTarget:Hide() end
end)

wp:SetScript("OnClick", function()
    local e = current and ns.DB().seen[current]
    if not e or not (C_Map.SetUserWaypoint and UiMapPoint) then return end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(e.map, e.x, e.y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
end)

local function Sound()
    if not ns.Opt("sound") then return end
    -- wie der Meilenstein-Sound von GuildPride
    local first = SOUNDKIT.UI_LEGENDARY_LOOT_TOAST or SOUNDKIT.RAID_WARNING
    if not PlaySound(first, "Master") then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
end

function ns.ShowAlert(npcId, how)
    if not ns.Enabled() then return end
    local e = ns.DB().seen[npcId]
    if not e then return end
    current = npcId
    local pos = ns.DB().alertPos
    if pos then alert:ClearAllPoints(); alert:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4]) end
    alert.head:SetText(e.boss and "WELTBOSS GESICHTET" or (e.elite and "RARE-ELITE GESICHTET" or "RARE GESICHTET"))
    alert.title:SetText(e.name)
    badge:SetVertexColor(1, (e.elite or e.boss) and 0.8 or 1, (e.elite or e.boss) and 0.2 or 1)
    ns.Repaint()
    alert.sub:SetText(("%s %.1f / %.1f · %s%s"):format(ns.MapName(e.map), e.x * 100, e.y * 100,
        e.hp and (e.hp .. "% · ") or "", ns.Ago(e.t)))
    alert.finder:SetText("|cffa39d90Gefunden von|r |cffe8c37a" .. tostring(e.by or "?") .. "|r"
        .. (how and how ~= "" and ("  |cff8a857a(" .. how .. ")|r") or ""))
    alert:SetAlpha(1)
    alert:Show()
    ag:Play(); badgeAg:Play(); shineAg:Play()
    pendingName = e.name
    if not ApplyTarget() then
        alert.combat:SetText("Anvisieren nach dem Kampf")
    end
    Sound()
end

-- Karte bis zur Zone hochgehen (Höhlen, Unterkarten zählen zur Zone)
local function ZoneOf(map)
    local guard = 0
    while map and C_Map.GetMapInfo and guard < 8 do
        local info = C_Map.GetMapInfo(map)
        if not info then break end
        if info.mapType and info.mapType <= 3 then return map end
        if not info.parentMapID or info.parentMapID == 0 then break end
        map, guard = info.parentMapID, guard + 1
    end
    return map
end

-- Alarm nur, wenn das Rare in meiner Zone ist
local function InMyZone(e)
    local myMap = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not myMap or ns.Secret(myMap) or not e.map then return false end
    if e.map == myMap then return true end
    return ZoneOf(e.map) == ZoneOf(myMap)
end
ns.RareInMyZone = InMyZone

-- Selbst gefunden
function ns.LocalAlert(npcId, source)
    local e = ns.DB().seen[npcId]
    if not e or not InMyZone(e) then return end
    if ns.DB().fav[npcId] or ns.Opt("alertAll") or (e.boss and ns.Opt("alertBoss")) then
        ns.ShowAlert(npcId, source)
    end
end

-- Von anderen gemeldet: nur neue Sichtungen in meiner Zone
function ns.OnRemoteSighting(npcId, isNew)
    if not isNew then return end
    local e = ns.DB().seen[npcId]
    if not e or not InMyZone(e) then return end
    if ns.DB().fav[npcId] or (e.boss and ns.Opt("alertBoss")) or ns.Opt("alertAll") then
        ns.ShowAlert(npcId, "")
    end
end
