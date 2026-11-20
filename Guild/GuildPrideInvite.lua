-- GuildPride: Gildeneinladung auf WoW Forever (Vorbild: das Addon Guildy)
--
-- Forever sperrt die Gildeneinladung für alles, was ein Addon auslöst: direkter Aufruf,
-- /ginvite im Makro, vom Addon geöffnete Dialoge und gefüllte Chatzeilen. Sauber bleibt
-- ein sicherer Klick auf Blizzards eigenen Knopf „Mitglied einladen“
-- (CommunitiesFrame.InviteButton): Blizzard öffnet seinen normalen Einladedialog, und der
-- Spieler tippt den Namen dort selbst ein. GuildPride trägt nichts ein.
--
-- Wichtig dafür: Blizzards Gildenfenster darf nie von Addon-Code geschlossen werden
-- (siehe „parken“ unten), sonst blockiert Forever die Einladung.
--
-- Der sichere Klick: Beim Überfahren legt sich ein unsichtbarer sicherer Knopf über
-- unseren Einladen-Knopf. Er hängt an UIParent und wird absolut platziert, nie an unser
-- Fenster geankert: So bleibt das GuildPride-Fenster ungeschützt und lässt sich im Kampf
-- schließen.
--
-- Blizzards Knopf geht nur, wenn Blizzards Gildenfenster geladen ist und darin die Gilde
-- ausgewählt hat. Das passiert, sobald Blizzard es selbst öffnet (Taste J, Gildenknopf der
-- Mikroleiste). Ist das noch nicht geschehen, klickt der erste Klick sicher den Gildenknopf
-- der Mikroleiste (Blizzard lädt sein Fenster und wählt die Gilde, wir parken es), der
-- zweite Klick öffnet den Einladedialog.
local _, ns = ...
local L = ns.L
if not ns.IS_FOREVER then return end

-- Blizzards Einladeknopf, wenn sein Gildenfenster geladen ist und die Gilde zeigt
local function BlizzardInviteButton()
    local frame = rawget(_G, "CommunitiesFrame")
    local button = frame and frame.InviteButton
    if type(button) ~= "table" or not button.IsEnabled or not button:IsEnabled() then return nil end
    local guildClub = C_Club and C_Club.GetGuildClubId and C_Club.GetGuildClubId()
    if not guildClub or not frame.GetSelectedClubId then return nil end
    local ok, selected = pcall(frame.GetSelectedClubId, frame)
    if not ok or selected ~= guildClub then return nil end
    return button
end

local function Clean(raw)
    if type(raw) ~= "string" then return "" end
    return (raw:gsub("[%c|]", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " "))
end

-- Läuft gerade der Vorbereitungsklick? Dann schaltet der ToggleGuildFrame-Hook
-- (GuildPrideUI.lua) unser Fenster nicht um.
local priming = false
function ns.InvitePriming() return priming end

---------------------------------------------------------------------
-- Blizzards Gildenfenster „parken“ statt schließen (wie Guildy)
--
-- Schließt Addon-Code Blizzards Gildenfenster (HideUIPanel, Hide), laufen dessen
-- OnHide-Teile „verseucht“ (Taint). Danach blockiert Forever die Einladung über
-- Blizzards Dialog mit „nur für Blizzard-Oberfläche“ – auch mit selbst getipptem Namen
-- (im Spiel gesehen 18.11.2026). Guildy öffnet und schließt Blizzards Fenster darum nie
-- selbst. Wir genauso: Öffnet J es, machen wir es unsichtbar und schieben es aus dem
-- Bild (nur Alpha und Position, kein Blizzard-Code läuft). Öffnen und schließen tut
-- es weiter nur Blizzard (J, Gildenknopf, Esc).
---------------------------------------------------------------------
local parked, placing, saved = false, false, nil
local showBlizzard = false      -- Spieler will Blizzards Fenster sehen (bis es wieder zugeht)

local function Host() return rawget(_G, "CommunitiesFrame") end

local function Park()
    local f = Host()
    if not f then return end
    if not parked then
        saved = { alpha = f:GetAlpha(), clamped = f.IsClampedToScreen and f:IsClampedToScreen(), points = {} }
        for i = 1, f:GetNumPoints() do saved.points[i] = { f:GetPoint(i) } end
        parked = true
    end
    placing = true
    pcall(function()
        f:SetAlpha(0)
        if f.SetClampedToScreen then f:SetClampedToScreen(false) end
        f:ClearAllPoints()
        f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", -4000, -4000)
    end)
    placing = false
end

local function Unpark()
    local f = Host()
    if not (f and parked) then return end
    parked = false
    placing = true
    pcall(function()
        f:ClearAllPoints()
        for _, p in ipairs(saved.points) do f:SetPoint(unpack(p)) end
        if #saved.points == 0 then f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116) end
        if f.SetClampedToScreen and saved.clamped ~= nil then f:SetClampedToScreen(saved.clamped) end
        f:SetAlpha(saved.alpha or 1)
    end)
    placing = false
end

-- Blizzards Fenster-Verwaltung setzt die Position neu (andere Fenster gehen auf):
-- dann gleich wieder parken
local hooked = false
local function HookHost()
    local f = Host()
    if hooked or not f then return end
    hooked = true
    hooksecurefunc(f, "SetPoint", function()
        if parked and not placing then C_Timer.After(0, function() if parked then Park() end end) end
    end)
    -- Erscheint Blizzards Fenster, während GuildPride das Gildenfenster ersetzt, sofort parken.
    -- Nötig beim ersten J nach dem Einloggen: Da lädt Blizzard sein Fenster erst und zeigt es
    -- nach unserem ToggleGuildFrame-Haken, sonst stünden beide Fenster offen.
    f:HookScript("OnShow", function()
        if showBlizzard or not (GuildPrideDB and GuildPrideDB.replaceGuildFrame) or not IsInGuild() then return end
        Park()
    end)
    f:HookScript("OnHide", function() showBlizzard = false end)
end
local hostWatch = CreateFrame("Frame")
hostWatch:RegisterEvent("ADDON_LOADED")
hostWatch:RegisterEvent("PLAYER_LOGIN")
hostWatch:SetScript("OnEvent", HookHost)

-- Für GuildPrideUI.lua (ToggleGuildFrame-Hook, „Blizzard-Gildenfenster öffnen“) und den Reiter
function ns.ParkBlizzardGuild() HookHost(); showBlizzard = false; Park() end
function ns.UnparkBlizzardGuild() HookHost(); showBlizzard = true; Unpark() end
function ns.BlizzardGuildParked() return parked end
-- Einstellung „Blizzards Gildenfenster behalten“: ein gerade geparktes Fenster gleich zurückholen
function ns.GuildWindowChoiceChanged()
    if GuildPrideDB and not GuildPrideDB.replaceGuildFrame then Unpark() end
end

-- Hinweis, wenn kein sicherer Klick möglich ist (im Kampf o. Ä.)
function ns.ShowInviteHint(rawName)
    if InCombatLockdown() then
        ns.Print(L["|cffff4040Gildeneinladung geht nicht im Kampf.|r"])
        return
    end
    local name = Clean(rawName)
    if name == "" then name = L["Vor- und Nachname"] end
    ns.Print((L["Gildeneinladung gerade nicht möglich. Im Chat eingeben: |cffffd100/ginvite %s|r"]):format(name))
end

---------------------------------------------------------------------
-- Der unsichtbare sichere Knopf
---------------------------------------------------------------------
local overlay

local function Overlay()
    if overlay then return overlay end
    overlay = CreateFrame("Button", "GuildPrideInviteOverlay", UIParent, "SecureActionButtonTemplate")
    overlay:SetFrameStrata("TOOLTIP")
    -- genau eine Klick-Phase: beim Loslassen, unabhängig von ActionButtonUseKeyDown
    overlay:RegisterForClicks("LeftButtonUp")
    overlay:SetAttribute("useOnKeyDown", false)
    overlay:SetAttribute("type", "click")
    overlay:SetScript("PreClick", function(self)
        if self.before then pcall(self.before) end
    end)
    overlay:SetScript("PostClick", function(self)
        local after = self.after
        if self.owner and self.owner.UnlockHighlight then self.owner:UnlockHighlight() end
        GameTooltip:Hide()
        if not InCombatLockdown() then self:Hide() end
        if after then
            local ok, err = pcall(after)
            if not ok then geterrorhandler()(err) end
        end
    end)
    overlay:SetScript("OnEnter", function(self)
        if self.owner and self.owner.LockHighlight then self.owner:LockHighlight() end
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    overlay:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        if self.owner and self.owner.UnlockHighlight then self.owner:UnlockHighlight() end
        if not InCombatLockdown() then self:Hide() end
    end)
    overlay:Hide()
    return overlay
end

-- Legt den sicheren Knopf über button. action = { click = Blizzard-Knopf, before, after }
local function Lay(button, action, tip)
    if InCombatLockdown() or not (action and action.click) or not button:IsVisible() then return end
    local left, bottom = button:GetLeft(), button:GetBottom()
    if not left or not bottom then return end
    local o = Overlay()
    local scale = button:GetEffectiveScale() / UIParent:GetEffectiveScale()
    o:SetAttribute("clickbutton", action.click)
    o.before, o.after, o.owner, o.tip = action.before, action.after, button, tip
    o:ClearAllPoints()
    o:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale, bottom * scale)
    o:SetSize(button:GetWidth() * scale, button:GetHeight() * scale)
    o:Show()
end

local Arm

-- Was ein Klick gerade tut: Blizzards Einladedialog öffnen oder erst sein Gildenfenster vorbereiten
local function InviteAction(button, onDone)
    local invite = BlizzardInviteButton()
    if invite then
        return { click = invite, after = onDone }
    end
    local primer = rawget(_G, "GuildMicroButton")
    if type(primer) ~= "table" then return nil end
    return { click = primer,
        before = function() priming = true end,
        after = function()
            priming = false
            C_Timer.After(0.2, function()
                if not BlizzardInviteButton() then
                    ns.ShowInviteHint()
                    return
                end
                ns.Print(L["Gildeneinladung ist bereit: bitte noch einmal klicken."])
                -- Maus steht noch auf dem Knopf: gleich wieder scharf machen
                if button:IsVisible() and button:IsMouseOver() then Arm(button, onDone) end
            end)
        end }, L["Erster Klick bereitet Blizzards Gildenfenster vor, der zweite lädt ein."]
end

Arm = function(button, onDone)
    if InCombatLockdown() or not IsInGuild() then return end
    if button.IsEnabled and not button:IsEnabled() then return end
    local action, tip = InviteAction(button, onDone)
    if action then Lay(button, action, tip) end
end

-- Macht einen normalen Knopf zum Gilden-Einladeknopf: ein Klick öffnet Blizzards Einladedialog.
-- active(): nil oder true = Gildeneinladung (false z. B. bei Community-Einladung);
-- onDone(): nach dem Öffnen von Blizzards Dialog.
-- Der normale Klick des Knopfes läuft nur, wenn kein sicherer Klick möglich war.
function ns.AttachGuildInvite(button, active, onDone)
    button:HookScript("OnEnter", function(self)
        if active and not active() then return end
        Arm(self, onDone)
    end)
end

-- Namensfeld neben einem Einladen-Knopf: bei der Gilde braucht es keins (der Name wird in
-- Blizzards Dialog getippt), der Knopf rückt an die Stelle des Feldes. Für Communities
-- bleibt das Feld.
function ns.ArrangeInvite(box, button, guild)
    if not box.gpPoint then
        box.gpPoint = { box:GetPoint(1) }
        button.gpPoint = { button:GetPoint(1) }
        box:HookScript("OnShow", function(self) if self.gpGuild then self:Hide() end end)
    end
    if box.gpGuild == guild then return end
    box.gpGuild = guild
    button:ClearAllPoints()
    if guild then
        box:Hide()
        button:SetPoint(unpack(box.gpPoint))
    else
        button:SetPoint(unpack(button.gpPoint))
        box:SetShown(button:IsShown())
    end
end

---------------------------------------------------------------------
-- /gp einladen Name: ein Slash-Befehl ist kein sicherer Klick, darum fragt ein kleines
-- Fenster nach, dessen Knopf Blizzards Einladedialog öffnet. Der Name steht dort zum
-- Abtippen. (Rechtsklick-Menüs laden nicht mehr in die Gilde ein: Forever blockiert das.)
---------------------------------------------------------------------
local dialog

function ns.GuildInviteDialog(rawName)
    local name = Clean(rawName)
    name = ns.Normalize(name) or name
    if not dialog then
        dialog = CreateFrame("Frame", "GuildPrideInviteDialog", UIParent, "BackdropTemplate")
        dialog:SetFrameStrata("DIALOG")
        dialog:SetSize(340, 104)
        dialog:SetPoint("CENTER", 0, 140)
        dialog:EnableMouse(true)
        dialog:SetMovable(true)
        dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", dialog.StartMoving)
        dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
        dialog.text = dialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        dialog.text:SetPoint("TOPLEFT", 20, -22)
        dialog.text:SetPoint("TOPRIGHT", -20, -22)
        dialog.text:SetJustifyH("CENTER")
        dialog.ok = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        dialog.ok:SetSize(140, 24)
        dialog.ok:SetPoint("BOTTOMRIGHT", dialog, "BOTTOM", -4, 18)
        dialog.ok:SetText(L["In Gilde einladen"])
        dialog.ok:SetScript("OnClick", function() ns.ShowInviteHint(dialog.name) end)
        ns.AttachGuildInvite(dialog.ok, nil, function() dialog:Hide() end)
        dialog.cancel = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        dialog.cancel:SetSize(140, 24)
        dialog.cancel:SetPoint("BOTTOMLEFT", dialog, "BOTTOM", 4, 18)
        dialog.cancel:SetText(L["Abbrechen"])
        dialog.cancel:SetScript("OnClick", function() dialog:Hide() end)
        tinsert(UISpecialFrames, "GuildPrideInviteDialog") -- ESC schließt
        if ns.SkinWindow then pcall(ns.SkinWindow, dialog) end   -- Goldrahmen
    end
    dialog.name = name
    dialog.text:SetText((L["|cffffd100%s|r in die Gilde einladen?"]):format(name))
    dialog:Show()
end
