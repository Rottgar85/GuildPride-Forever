-- GuildPride: Punkte auf Weltkarte und Gebietskarte über Blizzards Karten-Pin-System
-- (MapCanvas-Datenanbieter). So sitzen die Punkte richtig, egal ob die Weltkarte groß,
-- klein (z. B. mit Leatrix Maps) oder die Gebietskarte (Umschalt+M) offen ist.
-- Module melden Quellen an: ns.AddMapSource(fn), fn(mapID) gibt eine Liste zurück:
--   { x, y (0 … 1 auf der gezeigten Karte), tex = Datei, color = {r,g,b}, size = 14,
--     glow = true/false, level = Zahl (Reihenfolge), enter = fn(pin), click = fn(pin) }
local ADDON, ns = ...

local TEMPLATE = "GuildPrideMapPinTemplate"
local sources = {}

GuildPrideMapPinMixin = CreateFromMixins(MapCanvasPinMixin)

function GuildPrideMapPinMixin:OnLoad()
    -- Nur Maus-Bewegung (Tooltip), keine Klicks: sonst setzt die Karte beim Erzeugen
    -- SetPassThroughButtons, und das sperrt WoW im Kampf ("Aktion blockiert")
    self:EnableMouse(false)
    self:EnableMouseMotion(true)
    self:UseFrameLevelType("PIN_FRAME_LEVEL_VIGNETTE")
    self:SetScalingLimits(1, 1.0, 1.2)
end

function GuildPrideMapPinMixin:OnAcquired(info)
    self.info = info
    local size = info.size or 14
    self:SetSize(size, size)
    self.Tex:SetTexture(info.tex)
    local c = info.color
    if c then self.Tex:SetVertexColor(c[1], c[2], c[3]) else self.Tex:SetVertexColor(1, 1, 1) end
    self.Tex:SetAlpha(info.alpha or 1)
    self.Ring:SetVertexColor(0, 0, 0, 0.9)
    self.Glow:SetVertexColor(0.2, 1, 0.2)
    self.Ring:SetShown(info.ring and true or false)
    self.Ring:SetSize(size + 4, size + 4)
    self.Glow:SetShown(info.glow and true or false)
    self.Glow:SetSize(size * 2.2, size * 2.2)
    self:SetPosition(info.x, info.y)
end

-- Solange die Maus auf einem Punkt liegt, nicht neu zeichnen (Tooltip bliebe sonst nicht stehen)
local hovering = false
function GuildPrideMapPinMixin:OnMouseEnter()
    hovering = true
    if self.info and self.info.enter then self.info.enter(self) end
end
function GuildPrideMapPinMixin:OnMouseLeave() hovering = false; GameTooltip:Hide() end
-- Maus-Ereignisse leitet die Karte selbst an den Punkt weiter (keine eigenen Skripte am Rahmen)
function GuildPrideMapPinMixin:OnMouseClickAction(button)
    if self.info and self.info.click then self.info.click(self, button) end
end

-- Datenanbieter: holt bei jeder Aktualisierung alle Punkte neu von den Quellen
local Provider = CreateFromMixins(MapCanvasDataProviderMixin)
function Provider:RemoveAllData() self:GetMap():RemoveAllPinsByTemplate(TEMPLATE) end
function Provider:RefreshAllData()
    if InCombatLockdown() then return end   -- im Kampf nichts an der Karte ändern
    local map = self:GetMap()
    map:RemoveAllPinsByTemplate(TEMPLATE)
    hovering = false
    local mapID = map:GetMapID()
    if not mapID then return end
    for _, fn in ipairs(sources) do
        local ok, list = pcall(fn, mapID)
        if ok and type(list) == "table" then
            for _, info in ipairs(list) do map:AcquirePin(TEMPLATE, info) end
        end
    end
end
function Provider:OnMapChanged() self:RefreshAllData() end

local providers = {}   -- [Kartenrahmen] = Anbieter
local function Attach(frame)
    if not frame or providers[frame] or not frame.AddDataProvider then return end
    local p = CreateFromMixins(Provider)
    frame:AddDataProvider(p)
    providers[frame] = p
end

function ns.AddMapSource(fn) sources[#sources + 1] = fn end
function ns.RefreshMapPins(force)
    if (hovering and not force) or InCombatLockdown() then return end
    for frame, p in pairs(providers) do
        if frame:IsShown() then p:RefreshAllData() end
    end
end
function ns.MapPinsAttached(frame) return providers[frame] ~= nil end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, name)
    if event == "PLAYER_LOGIN" or name == "Blizzard_WorldMap" or name == "Blizzard_BattlefieldMap" then
        Attach(WorldMapFrame)
        Attach(BattlefieldMapFrame)
    end
end)
-- Punkte bewegen sich (Mitglieder) oder verfallen (Sichtungen): offene Karten jede Sekunde neu zeichnen
C_Timer.NewTicker(1, function() ns.RefreshMapPins() end)
