-- GuildPride Rares: Punkte für frische Sichtungen auf Weltkarte und Gebietskarte
local ADDON, GP = ...
-- Rare-Scanner läuft in einem eigenen Unter-Namensraum, damit sich nichts mit GuildPride beißt
GP.Rares = GP.Rares or {}
local ns = GP.Rares

local maps = {}   -- [Kartenrahmen] = { frame, overlay, pins, size }

local function Translate(map, x, y, shown)
    if map == shown then return x, y end
    if not (C_Map.GetWorldPosFromMapPos and C_Map.GetMapPosFromWorldPos and CreateVector2D) then return end
    local ok, cont, world = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
    if not ok or not cont or not world then return end
    local ok2, _, pos = pcall(C_Map.GetMapPosFromWorldPos, cont, world, shown)
    if not ok2 or not pos then return end
    local px, py = pos:GetXY()
    if not px or px < 0 or px > 1 or py < 0 or py > 1 then return end
    return px, py
end

-- Tooltip: aktive Sichtung oder bekannter Fundort
local function PinEnter(pin)
    local db = ns.DB()
    local e, s = db.seen[pin.npc], db.spawns[pin.npc]
    GameTooltip:SetOwner(pin, "ANCHOR_RIGHT")
    local info = ns.StaticInfo(pin.npc)
    local name = (e and e.name) or (s and s.name) or (info and info[1]) or "?"
    local elite = (e and e.elite) or (s and s.elite) or (s and s.boss) or (info and info[2] == 1)
    if info and info[3] > 0 then name = name .. ("  (Stufe %d%s)"):format(info[3], info[2] == 1 and ", Elite" or "") end
    GameTooltip:AddLine(name, 1, elite and 0.6 or 0.82, elite and 0.1 or 0)
    if pin.active then
        GameTooltip:AddLine(("|cff40ff40Gerade gesehen|r · %s · %s"):format(ns.Ago(e.t), e.hp and (e.hp .. "% Leben") or "Leben unbekannt"), 1, 1, 1)
        local n = ns.Confirmations(e)
        GameTooltip:AddLine(("Gemeldet von %s%s"):format(tostring(e.by), n >= ns.CONFIRM and (" · |cff40ff40bestätigt (" .. n .. ")|r") or ""), 0.8, 0.8, 0.8)
    else
        GameTooltip:AddLine("Bekannter Fundort", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Zuletzt gesehen: " .. ns.Ago(e and e.t), 0.8, 0.8, 0.8)
        GameTooltip:AddLine("Zuletzt getötet: " .. ns.Ago(db.killed[pin.npc]), 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end

local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
-- Punkte für die gerade gezeigte Karte (über GuildPrideMapPins.lua gezeichnet)
local function RarePins(shown)
    local list, now, db = {}, GetServerTime(), ns.DB()
    -- gold: Rare-Elite und Weltboss, weiß: normales Rare, grün leuchtend: gerade gesehen
    local function Add(npc, x, y, active, gold)
        list[#list + 1] = { x = x, y = y, tex = SKULL, size = active and 20 or 14, glow = active,
            alpha = active and 1 or 0.85, color = gold and { 1, 0.8, 0.2 } or nil,
            enter = function(pin) pin.npc, pin.active = npc, active; PinEnter(pin) end,
            click = function() if active then ns.ShowAlert(npc, "") end end }
    end
    if db and ns.Enabled() and ns.Opt("pins") and shown then
        local activeAt = {}
        -- 1. gerade gesehen (groß, leuchtend)
        for npc, e in pairs(db.seen) do
            if e.t and now - e.t <= ns.FRESH and not (e.dead and e.dead >= e.t) then
                local x, y = Translate(e.map, e.x, e.y, shown)
                if x then
                    Add(npc, x, y, true, e.elite or e.boss)
                    activeAt[npc] = true
                end
            end
        end
        -- 2. bekannte Fundorte (klein); auf großen Karten (Kontinent) nur ein Punkt je Gegner
        local zoomedOut = C_Map.GetMapInfo(shown) and C_Map.GetMapInfo(shown).mapType
            and C_Map.GetMapInfo(shown).mapType < (Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3)
        local static = ns.StaticPoints()
        local function Draw(npc, pts, gold)
            if activeAt[npc] then return end
            for _, p in ipairs(pts) do
                local x, y = Translate(p[1], p[2], p[3], shown)
                if x then
                    Add(npc, x, y, false, gold)
                    if zoomedOut then activeAt[npc] = true; return end
                end
            end
        end
        for npc, pts in pairs(static) do
            local info = ns.StaticInfo(npc)
            Draw(npc, pts, info[2] == 1 or ns.WORLD_BOSSES[npc])
        end
        for npc, s in pairs(db.spawns) do
            if not activeAt[npc] and not static[npc] then
                for _, p in ipairs(s.pts) do
                    local x, y = Translate(p[1], p[2], p[3], shown)
                    if x then
                        Add(npc, x, y, false, s.elite or s.boss)
                        if zoomedOut then break end
                    end
                end
            end
        end
    end
    return list
end
if GP.AddMapSource then GP.AddMapSource(RarePins) end

local function Setup(frame)
    if frame then maps[frame] = true end
end

-- Kleiner Knopf oben rechts auf der Weltkarte: Rare-Scanner an/aus
local toggle
local function UpdateToggle()
    if not toggle then return end
    local on = ns.Enabled()
    toggle.icon:SetDesaturated(not on)
    toggle.icon:SetAlpha(on and 1 or 0.45)
end
local function MakeToggle()
    if toggle or not WorldMapFrame or not WorldMapFrame.ScrollContainer then return end
    toggle = CreateFrame("Button", "GPRaresMapToggle", WorldMapFrame.ScrollContainer)
    toggle:SetSize(28, 28)
    toggle:SetPoint("TOPLEFT", WorldMapFrame.ScrollContainer, "TOPLEFT", 8, -8)
    toggle:SetFrameLevel(WorldMapFrame.ScrollContainer:GetFrameLevel() + 2000)
    local bg = toggle:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetTexture(ns.MEDIA .. "nav"); ns.Paint(bg, "tex")
    local edge = CreateFrame("Frame", nil, toggle, "BackdropTemplate")
    edge:SetAllPoints(); edge:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    ns.Paint(edge, "accent")
    toggle.icon = toggle:CreateTexture(nil, "ARTWORK")
    toggle.icon:SetPoint("TOPLEFT", 3, -3); toggle.icon:SetPoint("BOTTOMRIGHT", -3, 3)
    toggle.icon:SetTexture(SKULL)
    toggle:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    toggle:SetScript("OnClick", function()
        ns.SetEnabled(not ns.Enabled())
        ns.Print(ns.Enabled() and "Rare-Scanner |cff40ff40an|r" or "Rare-Scanner |cffff6060aus|r – Zeichen auf der Karte ausgeblendet")
    end)
    toggle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("GuildPride Rares", 1, 0.82, 0)
        GameTooltip:AddLine(ns.Enabled() and "Scanner ist an – Klick schaltet aus" or "Scanner ist aus – Klick schaltet an", 1, 1, 1)
        GameTooltip:Show()
    end)
    toggle:SetScript("OnLeave", GameTooltip_Hide)
    UpdateToggle()
end
ns.UpdateMapToggle = UpdateToggle

-- Eintrag im Kartenfilter (Lupe/Filter oben rechts auf der Weltkarte)
local function SetEnabled(on)
    ns.DB().opts.enabled = on
    UpdateToggle()
    ns.RefreshMaps()
    if ns.RefreshUI then ns.RefreshUI() end
end
ns.SetEnabled = SetEnabled

local menuHooked = false
local function HookFilterMenu()
    if menuHooked or not (Menu and Menu.ModifyMenu) then return end
    menuHooked = true
    Menu.ModifyMenu("MENU_WORLD_MAP_TRACKING", function(_, root)
        ns.filterMenuSeen = true
        root:CreateDivider()
        root:CreateTitle("GuildPride Rares")
        root:CreateCheckbox("Rare-Scanner", function() return ns.Enabled() end,
            function() SetEnabled(not ns.Enabled()) end)
        root:CreateCheckbox("Fundorte auf der Karte", function() return ns.Opt("pins") and true or false end,
            function() ns.DB().opts.pins = not ns.Opt("pins"); ns.RefreshMaps() end)
    end)
end

-- Eigener Knopf nur, wenn man ihn will (/gpr knopf) oder das Filtermenü fehlt
local function UpdateToggleShown()
    if toggle then toggle:SetShown(ns.Opt("mapButton") or not (Menu and Menu.ModifyMenu)) end
end
ns.UpdateToggleShown = UpdateToggleShown

local function SetupAll()
    Setup(WorldMapFrame, 20)
    Setup(BattlefieldMapFrame, 16)
    MakeToggle()
    HookFilterMenu()
    UpdateToggleShown()
end
ns.RefreshMaps = function() if GP.RefreshMapPins then GP.RefreshMapPins() end end
ns.Listen("PLAYER_LOGIN", SetupAll)
ns.Listen("ADDON_LOADED", function(name)
    if name == "Blizzard_WorldMap" or name == "Blizzard_BattlefieldMap" then SetupAll() end
end)
