-- GuildPride: Layer wechseln mit Hilfe anderer GuildPride-Spieler (serverweit)
--
-- Ablauf:
--  1. "Layer wechseln" fragt im offenen GuildPride-Kanal: LYQ (Spielversion, Karte, eigener Layer)
--  2. Wer hilft (Einstellung an), in derselben Zone auf einem ANDEREN Layer steht und
--     einladen kann, antwortet per Flüstern: LYA (Karte, Layer)
--  3. Nach ein paar Sekunden wird ein Helfer gewählt und gebeten: LYR (Flüstern)
--  4. Der Helfer bekommt eine Abfrage mit "Einladen" (Klick = Einladung)
--  5. Nach dem Beitritt wechselt das Spiel den Layer. Sobald eine Kreatur in der Nähe
--     den neuen Layer verrät, verlässt das Addon die Gruppe wieder.
--
-- Der Layer steckt in der GUID von Kreaturen ("Creature-0-Server-Instanz-ZONE-npc-spawn").
-- Die Zahl gilt nur innerhalb einer Zone; verglichen wird daher nur bei gleicher Karte.
local ADDON, ns = ...
local L = ns.L
local SEP = ns.SEP or "\031"

local Layer = { id = nil, map = nil }
ns.Layer = Layer

---------------------------------------------------------------------
-- Eigenen Layer erkennen
---------------------------------------------------------------------
local function Secret(v) return issecretvalue and issecretvalue(v) or false end

local function MapId()
    return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
end

local function Observe(unit)
    if IsInInstance() or not UnitExists(unit) or UnitIsPlayer(unit) then return end
    local guid = UnitGUID(unit)
    if type(guid) ~= "string" or Secret(guid) then return end
    local kind, _, _, _, zoneUID = strsplit("-", guid)
    if (kind ~= "Creature" and kind ~= "Vehicle") or not zoneUID or zoneUID == "" or zoneUID == "0" then return end
    -- Begleiter und Wächter von Spielern verraten nichts Verlässliches
    if UnitPlayerControlled and UnitPlayerControlled(unit) then return end
    local map, changed = MapId(), Layer.id ~= zoneUID
    Layer.id, Layer.map, Layer.at = zoneUID, map, GetTime()
    if changed and Layer.OnChange then Layer.OnChange() end
end

local watch = CreateFrame("Frame")
ns.RegisterEvents(watch, "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
    "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PARTY_INVITE_REQUEST")
watch:SetScript("OnEvent", function(_, event, unit)
    if event == "PARTY_INVITE_REQUEST" then
        if Layer.OnInvite then Layer.OnInvite(unit) end
    elseif event == "PLAYER_TARGET_CHANGED" then Observe("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then Observe("mouseover")
    elseif event == "NAME_PLATE_UNIT_ADDED" then Observe(unit)
    elseif event == "GROUP_ROSTER_UPDATE" then
        if Layer.OnGroup then Layer.OnGroup() end
    else
        -- neue Zone: alte Layer-Zahl gilt dort nicht mehr
        Layer.id, Layer.map = nil, nil
    end
end)

function Layer.Text()
    if not Layer.id then return L["unbekannt"] end
    return Layer.id
end

---------------------------------------------------------------------
-- Nachrichten (offener Kanal + Flüstern, auch von Nicht-Mitgliedern)
---------------------------------------------------------------------
local function Available()
    return ns.IS_FOREVER and ns.PublicChannelId and ns.PublicChannelId() and not ns.PUBLIC_VIA_CHAT
end

local function Send(kind, to, ...)
    if to then ns.QueuePublicTo(to, kind, ...) else ns.Queue(kind, "@PUBLIC", ...) end
end

-- Laufende Anfrage (ich will wechseln)
local req          -- { started, map, from, offers = { [name] = layer }, asked, joinedAt }
-- Wem ich als Helfer geantwortet habe: [Name] = Zeit
local answered = {}
local lastAsk = 0

local function Reset(msg)
    if msg then ns.Print(msg) end
    req = nil
end

local function CanHelp()
    if not (GuildPrideDB and GuildPrideDB.layerHelp) or not Layer.id or InCombatLockdown() or IsInInstance() then return false end
    if Layer.map ~= MapId() then return false end
    if IsInGroup() then
        if not UnitIsGroupLeader("player") then return false end
        if GetNumGroupMembers() >= (IsInRaid() and 40 or 5) then return false end
    end
    return true
end

StaticPopupDialogs["GUILDPRIDE_LAYER_INVITE"] = {
    text = L["%s (GuildPride) möchte auf deinen Layer wechseln. Einladen? Die Person verlässt die Gruppe danach von selbst."],
    button1 = L["Einladen"], button2 = L["Nein"],
    OnAccept = function(_, name)
        local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
        if invite then invite(Ambiguate(name, "none")) end
    end,
    timeout = 30, whileDead = true, hideOnEscape = true,
}

-- Automatisch einladen bzw. annehmen. Sperrt WoW das (ADDON_ACTION_BLOCKED kommt
-- noch während des Aufrufs), fällt das Addon für diese Sitzung auf einen Klick zurück.
local trying, gotBlocked = false, false
local noAuto = {}   -- ["invite"] / ["accept"] = true: in dieser Sitzung gesperrt
local blockWatch = CreateFrame("Frame")
blockWatch:RegisterEvent("ADDON_ACTION_BLOCKED")
blockWatch:RegisterEvent("ADDON_ACTION_FORBIDDEN")
blockWatch:SetScript("OnEvent", function(_, _, addon) if trying and addon == ADDON then gotBlocked = true end end)
local function Try(key, fn, ...)
    if noAuto[key] or not fn then return false end
    trying, gotBlocked = true, false
    local ok = pcall(fn, ...)
    trying = false
    if not ok or gotBlocked then noAuto[key] = true; return false end
    return true
end
local InviteFn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit

function ns.OnLayerMessage(message, sender, whisper)
    if not ns.IS_FOREVER or sender == ns.Me() then return end
    local kind, value = message:match("^(LY%u):(.*)$")
    if not kind then return end
    local f = { strsplit(SEP, value) }
    if f[1] ~= ns.CLIENT_TAG then return end
    local map = tonumber(f[2])

    if kind == "LYQ" and not whisper then
        -- Jemand sucht einen anderen Layer: nur antworten, wenn ich wirklich helfen kann
        if not CanHelp() or map ~= Layer.map or (f[3] ~= "" and f[3] == Layer.id) then return end
        if (answered[sender] or 0) > GetTime() - 30 then return end
        answered[sender] = GetTime()
        C_Timer.After(0.5 + math.random() * 2.5, function()
            if CanHelp() then Send("LYA", sender, ns.CLIENT_TAG, Layer.map, Layer.id) end
        end)
    elseif kind == "LYA" and whisper then
        if not req or req.asked or map ~= req.map then return end
        local layer = f[3]
        if layer == "" or layer == req.from then return end
        req.offers[sender] = layer
    elseif kind == "LYR" and whisper then
        -- Bitte um Einladung: nur, wenn ich dem Fragenden vorher angeboten habe
        if (answered[sender] or 0) < GetTime() - 90 or not CanHelp() then return end
        answered[sender] = nil
        local short = Ambiguate(sender, "none")
        if Try("invite", InviteFn, short) then
            ns.Print((L["Layer-Hilfe: %s automatisch eingeladen – die Person wechselt auf deinen Layer und verlässt die Gruppe danach von selbst."]):format(short))
        else
            -- WoW lässt das automatische Einladen nicht zu: ein Klick genügt
            StaticPopup_Show("GUILDPRIDE_LAYER_INVITE", short, nil, sender)
            if GuildPrideDB.sound then PlaySound(SOUNDKIT.TELL_MESSAGE) end
        end
    end
end

---------------------------------------------------------------------
-- Anfrage stellen
---------------------------------------------------------------------
local function PickHelper()
    if not req then return end
    req.asked = true
    -- Ein Layer, der sich vom eigenen unterscheidet; bei mehreren Helfern zufällig
    local names = {}
    for name in pairs(req.offers) do names[#names + 1] = name end
    if #names == 0 then
        return Reset(L["Layer wechseln: Niemand mit GuildPride in dieser Zone kann gerade helfen. Später noch einmal versuchen."])
    end
    local layers = {}
    for _, layer in pairs(req.offers) do layers[layer] = true end
    local count = 0
    for _ in pairs(layers) do count = count + 1 end
    local helper = names[math.random(#names)]
    req.helper, req.target = helper, req.offers[helper]
    Send("LYR", helper, ns.CLIENT_TAG, req.map)
    ns.Print((L["Layer wechseln: %d Helfer auf %d anderen Layer(n) gefunden. %s lädt dich ein, der Rest läuft automatisch."])
        :format(#names, count, Ambiguate(helper, "none")))
    C_Timer.After(45, function()
        if req and not req.joinedAt then
            Reset(L["Layer wechseln: Keine Einladung angenommen – abgebrochen. Einfach noch einmal versuchen."])
        end
    end)
end

function Layer.Request()
    if not ns.IS_FOREVER then ns.Print(L["Layer wechseln gibt es nur in WoW Forever."]); return end
    if not Available() then
        ns.Print(L["Layer wechseln braucht den serverweiten GuildPride-Kanal: Einstellungen > Serverweite Gruppensuche einschalten."])
        return
    end
    if IsInInstance() then ns.Print(L["In einer Instanz gibt es keine Layer."]); return end
    if IsInGroup() then ns.Print(L["Zum Layer-Wechsel bitte zuerst die Gruppe verlassen."]); return end
    if req then ns.Print(L["Layer wechseln läuft schon …"]); return end
    if GetTime() - lastAsk < 20 then ns.Print(L["Bitte kurz warten, bevor du erneut fragst."]); return end
    local map = MapId()
    if not map then return end
    lastAsk = GetTime()
    local from = (Layer.map == map) and Layer.id or nil
    req = { started = GetTime(), map = map, from = from, offers = {} }
    Send("LYQ", nil, ns.CLIENT_TAG, map, from or "")
    ns.Print(from and (L["Layer wechseln: Suche Helfer (dein Layer: %s) …"]):format(from)
        or L["Layer wechseln: Suche Helfer … (Tipp: vorher eine Kreatur anvisieren, dann wird dein Layer erkannt)"])
    -- Antworten sammeln (Kanaltakt 2 s + Zufallsverzögerung der Helfer)
    C_Timer.After(8, PickHelper)
end

-- Einladung vom gewählten Helfer: automatisch annehmen (sonst klickt man selbst)
function Layer.OnInvite(inviter)
    if not req or not req.helper or type(inviter) ~= "string" or Secret(inviter) then return end
    if ns.Normalize(inviter) ~= req.helper and Ambiguate(inviter, "none") ~= Ambiguate(req.helper, "none") then return end
    if Try("accept", AcceptGroup) then
        StaticPopup_Hide("PARTY_INVITE")
        C_Timer.After(0, function() StaticPopup_Hide("PARTY_INVITE") end)
    else
        ns.Print(L["Layer wechseln: Bitte die Einladung annehmen."])
    end
end

-- Beitritt erkannt -> auf den neuen Layer warten, dann wieder austreten
function Layer.OnGroup()
    if not req or not req.helper then return end
    if IsInGroup() and not req.joinedAt then
        req.joinedAt = GetTime()
        ns.Print(L["Layer wechseln: In der Gruppe. Warte auf den Wechsel – eine Kreatur anvisieren hilft beim Erkennen."])
        C_Timer.After(120, function()
            if req and req.joinedAt and IsInGroup() then
                Reset(L["Layer wechseln: Kein Wechsel erkannt. Du bist noch in der Gruppe – verlassen mit /gp layer raus."])
            end
        end)
    elseif not IsInGroup() and req.joinedAt then
        Reset()
    end
end

local function LeaveGroup()
    local leave = (C_PartyInfo and C_PartyInfo.LeaveParty) or LeaveParty
    if leave then leave() end
end

function Layer.OnChange()
    if not req or not req.joinedAt or not IsInGroup() then return end
    -- Ziel ist der Layer des Helfers (die eigene alte Zahl ist evtl. unbekannt)
    if Layer.map ~= req.map or Layer.id ~= req.target then return end
    ns.Print((L["Layer gewechselt (jetzt %s). Gruppe wird verlassen – danke an %s!"]):format(Layer.id, Ambiguate(req.helper, "none")))
    req = nil
    C_Timer.After(1.5, function() if IsInGroup() then LeaveGroup() end end)
end

---------------------------------------------------------------------
-- Knopf in der Gruppensuche und /gp layer
---------------------------------------------------------------------
if ns.IS_FOREVER and ns.GroupPage then
    local b = CreateFrame("Button", nil, ns.GroupPage, "UIPanelButtonTemplate")
    if ns.SkinButton then ns.SkinButton(b) end
    b:SetSize(140, 24)
    -- an der Seite verankert, nicht am sicheren Dungeonbrowser-Knopf (der wird im Kampf geparkt)
    b:SetPoint("TOPRIGHT", -(2 + (ns.GroupBrowserWidth and ns.GroupBrowserWidth + 6 or 0)), -52)
    b:SetText(L["Layer wechseln"])
    b:SetScript("OnClick", function() Layer.Request() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Layer wechseln"], 1, 1, 1)
        GameTooltip:AddLine((L["Dein Layer: %s"]):format(Layer.Text()), 0.9, 0.8, 0.5)
        GameTooltip:AddLine(L["Fragt alle mit GuildPride in deiner Zone. Jemand auf einem anderen Layer lädt dich ein, nach dem Wechsel verlässt du die Gruppe automatisch."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
end

-- Knopf in der Seitenleiste des Gildenfensters, direkt über „Einstellungen“.
-- Er hängt am Einstellungen-Reiter und wandert mit, wenn das Layout wechselt.
local parts = ns.UIParts
local setTab = parts and ns.SettingsPage and parts.tabs and parts.tabs[ns.SettingsPage.tabId]
if ns.IS_FOREVER and setTab then
    local b = CreateFrame("Button", nil, parts.frame, "UIPanelButtonTemplate")
    if ns.SkinButton then ns.SkinButton(b) end
    b:SetHeight(24)
    b:SetPoint("BOTTOMLEFT", setTab, "TOPLEFT", 0, 6)
    b:SetPoint("BOTTOMRIGHT", setTab, "TOPRIGHT", 0, 6)
    b:SetText(L["Layer wechseln"])
    b:SetScript("OnSizeChanged", function() if ns.LayerUpdateDisplay then ns.LayerUpdateDisplay() end end)
    b:SetScript("OnClick", function() Layer.Request() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Layer wechseln"], 1, 1, 1)
        GameTooltip:AddLine((L["Dein Layer: %s"]):format(Layer.Text()), 0.9, 0.8, 0.5)
        GameTooltip:AddLine(L["Klick: Ein anderer GuildPride-Spieler lädt dich automatisch ein, nach dem Wechsel verlässt du die Gruppe von selbst."], 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    Layer.sideButton = b
end

---------------------------------------------------------------------
-- Layer-Anzeige: kleine Zeile unter der Minimap (verschiebbar, abschaltbar)
---------------------------------------------------------------------
local display
local function DisplayText()
    if Layer.id then return ("|cff40ff40%s|r"):format(Layer.id) end
    return "|cff999999?|r"
end

local function UpdateDisplay()
    local sb = Layer.sideButton
    if sb then
        local w = sb:GetWidth() or 0
        sb:SetText(w < 100 and L["Layer"] or (Layer.id and ("%s (%s)"):format(L["Layer wechseln"], Layer.id) or L["Layer wechseln"]))
    end
    if display and display:IsShown() then
        display.text:SetText(("%s %s"):format(L["Layer:"], DisplayText()))
        display:SetWidth(display.text:GetStringWidth() + 12)
    end
end
ns.LayerUpdateDisplay = UpdateDisplay

local function PlaceDisplay()
    if not display or not GuildPrideDB then return end
    display:ClearAllPoints()
    local pos = GuildPrideDB.layerShowPos
    if pos then display:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
    else display:SetPoint("TOP", Minimap, "BOTTOM", 0, -22) end
    display:SetShown(GuildPrideDB.layerShow ~= false)
    UpdateDisplay()
end
ns.LayerShowChanged = PlaceDisplay

if ns.IS_FOREVER then
    display = CreateFrame("Button", "GuildPrideLayerDisplay", UIParent)
    display:SetSize(80, 18)
    display:SetFrameStrata("MEDIUM")
    display:SetMovable(true); display:SetClampedToScreen(true)
    display:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    display:RegisterForDrag("LeftButton")
    local bg = display:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.45)
    display.text = display:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    display.text:SetPoint("CENTER")
    display:Hide()
    display:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
    display:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, _, x, y = self:GetPoint()
        GuildPrideDB.layerShowPos = { point, x, y }
    end)
    display:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            GuildPrideDB.layerShow = false
            PlaceDisplay()
            ns.Print(L["Layer-Anzeige ausgeblendet. Wieder einblenden mit /gp layer anzeige oder in den Einstellungen."])
        else
            Layer.Request()
        end
    end)
    display:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText((L["Dein Layer: %s"]):format(Layer.Text()), 1, 1, 1)
        GameTooltip:AddLine(L["Die Zahl kommt vom Server: gleiche Zahl = gleicher Layer (nur innerhalb einer Zone vergleichbar). Erkannt über Kreaturen in der Nähe – eine Kreatur anvisieren aktualisiert sie."], 0.8, 0.8, 0.8, true)
        GameTooltip:AddLine(L["Klick: Layer wechseln"], 1, 1, 1)
        GameTooltip:AddLine(L["Umschalt+Ziehen: verschieben"], 0.7, 0.7, 0.7)
        GameTooltip:AddLine(L["Rechtsklick: ausblenden"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    display:SetScript("OnLeave", GameTooltip_Hide)
    local login = CreateFrame("Frame")
    login:RegisterEvent("PLAYER_LOGIN")
    login:SetScript("OnEvent", function()
        PlaceDisplay()
        -- Layer ändert sich durch Zielwechsel, Zonenwechsel usw.: einmal pro Sekunde nachziehen
        C_Timer.NewTicker(1, UpdateDisplay)
    end)
end

local slash = SlashCmdList.GUILDPRIDE
SlashCmdList.GUILDPRIDE = function(arg)
    local cmd, rest = strtrim(arg or ""):lower():match("^(%S*)%s*(.-)$")
    if cmd ~= "layer" then return slash(arg) end
    if rest == "" or rest == "wechseln" or rest == "switch" then
        Layer.Request()
    elseif rest == "anzeige" or rest == "display" then
        GuildPrideDB.layerShow = GuildPrideDB.layerShow == false
        ns.LayerShowChanged()
        ns.Print(GuildPrideDB.layerShow and L["Layer-Anzeige eingeblendet (unter der Minimap, Umschalt+Ziehen zum Verschieben)."]
            or L["Layer-Anzeige ausgeblendet. Wieder einblenden mit /gp layer anzeige oder in den Einstellungen."])
    elseif rest == "raus" or rest == "leave" then
        req = nil
        LeaveGroup()
    elseif rest == "an" or rest == "on" or rest == "aus" or rest == "off" then
        GuildPrideDB.layerHelp = rest == "an" or rest == "on"
        ns.Print(GuildPrideDB.layerHelp and L["Du hilfst anderen beim Layer-Wechsel (lädt automatisch ein)."]
            or L["Du hilfst anderen nicht mehr beim Layer-Wechsel."])
    else
        ns.Print((L["Dein Layer: %s"]):format(Layer.Text()))
        ns.Print(L["/gp layer – wechseln · /gp layer anzeige – Anzeige ein/aus · /gp layer raus – Gruppe verlassen · /gp layer an|aus – anderen helfen"])
    end
end
